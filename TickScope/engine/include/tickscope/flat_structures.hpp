#pragma once

// Allocation-free building blocks for OrderBookV2.

#include <algorithm>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <utility>
#include <vector>

#include "tickscope/types.hpp"

namespace tickscope::detail {

inline constexpr std::uint32_t kNil = std::numeric_limits<std::uint32_t>::max();

// OrderId -> node index. Open addressing with linear probing in one flat array.
//
// std::unordered_map allocates a node per entry and chains through pointers; here a lookup
// is a multiply-shift hash and a short forward scan over contiguous 16-byte slots, usually
// within one or two cache lines. Load factor is kept <= 0.5 so probe chains stay short.
// Deletion uses backward shift (no tombstones), so long add/cancel sequences never degrade.
class IdMap {
 public:
  explicit IdMap(std::size_t initialCapacity = 1 << 16) {
    rehash(std::bit_ceil(std::max<std::size_t>(initialCapacity, 16)));
  }

  // Returns kNil if absent.
  [[nodiscard]] std::uint32_t find(OrderId key) const {
    for (std::size_t i = home(key);; i = (i + 1) & mask_) {
      const Slot& s = slots_[i];
      if (s.val == kNil) return kNil;
      if (s.key == key) return s.val;
    }
  }

  // `key` must not be present.
  void insert(OrderId key, std::uint32_t val) {
    if ((size_ + 1) * 2 > slots_.size()) rehash(slots_.size() * 2);
    place(key, val);
    ++size_;
  }

  bool erase(OrderId key) {
    std::size_t hole = home(key);
    for (;; hole = (hole + 1) & mask_) {
      if (slots_[hole].val == kNil) return false;
      if (slots_[hole].key == key) break;
    }
    // Backward shift: walk the rest of the probe run; any entry whose home slot is not
    // cyclically within (hole, j] can move back into the hole without becoming unreachable.
    for (std::size_t j = (hole + 1) & mask_; slots_[j].val != kNil; j = (j + 1) & mask_) {
      const std::size_t h = home(slots_[j].key);
      const bool reachableFromHole = hole <= j ? (hole < h && h <= j) : (hole < h || h <= j);
      if (!reachableFromHole) {
        slots_[hole] = slots_[j];
        hole = j;
      }
    }
    slots_[hole].val = kNil;
    --size_;
    return true;
  }

  [[nodiscard]] std::size_t size() const { return size_; }
  [[nodiscard]] std::size_t capacity() const { return slots_.size(); }

 private:
  struct Slot {
    OrderId key = 0;
    std::uint32_t val = kNil;  // kNil marks an empty slot, so every key value is usable
  };

  // Fibonacci hashing: multiply by 2^64/phi and keep the top bits. Spreads sequential ids.
  [[nodiscard]] std::size_t home(OrderId key) const {
    return static_cast<std::size_t>((key * 0x9E3779B97F4A7C15ULL) >> shift_);
  }

  void place(OrderId key, std::uint32_t val) {
    std::size_t i = home(key);
    while (slots_[i].val != kNil) i = (i + 1) & mask_;
    slots_[i] = Slot{key, val};
  }

  void rehash(std::size_t capacity) {
    std::vector<Slot> old = std::move(slots_);
    slots_.assign(capacity, Slot{});
    mask_ = capacity - 1;
    shift_ = 64 - std::countr_zero(capacity);
    for (const Slot& s : old) {
      if (s.val != kNil) place(s.key, s.val);
    }
  }

  std::vector<Slot> slots_;
  std::size_t mask_ = 0;
  int shift_ = 64;
  std::size_t size_ = 0;
};

// Two-level bitmap over N slots: one bit per price level, plus one summary bit per 64-bit
// word. Finding the lowest/highest set bit scans at most N/4096 summary words and then
// reads one word: e.g. 16 + 1 words for N = 65,536, using count-leading/trailing-zeros.
class LevelBitmap {
 public:
  explicit LevelBitmap(std::size_t n) : words_(n / 64), summary_((n / 64 + 63) / 64) {
    if (n == 0 || n % 64 != 0) throw std::invalid_argument("LevelBitmap size must be a positive multiple of 64");
  }

  void set(std::size_t i) {
    words_[i >> 6] |= bit(i);
    summary_[i >> 12] |= bit(i >> 6);
  }

  void clear(std::size_t i) {
    std::uint64_t& w = words_[i >> 6];
    w &= ~bit(i);
    if (w == 0) summary_[i >> 12] &= ~bit(i >> 6);
  }

  [[nodiscard]] bool test(std::size_t i) const { return (words_[i >> 6] & bit(i)) != 0; }

  // -1 if empty.
  [[nodiscard]] std::int64_t lowest() const {
    for (std::size_t s = 0; s < summary_.size(); ++s) {
      if (summary_[s] != 0) {
        const std::size_t w = s * 64 + static_cast<std::size_t>(std::countr_zero(summary_[s]));
        return static_cast<std::int64_t>(w * 64 + static_cast<std::size_t>(std::countr_zero(words_[w])));
      }
    }
    return -1;
  }

  [[nodiscard]] std::int64_t highest() const {
    for (std::size_t s = summary_.size(); s-- > 0;) {
      if (summary_[s] != 0) {
        const std::size_t w = s * 64 + 63 - static_cast<std::size_t>(std::countl_zero(summary_[s]));
        return static_cast<std::int64_t>(w * 64 + 63 - static_cast<std::size_t>(std::countl_zero(words_[w])));
      }
    }
    return -1;
  }

  // Calls f(index) for every set bit, in increasing order.
  template <class F>
  void forEach(F&& f) const {
    for (std::size_t w = 0; w < words_.size(); ++w) {
      for (std::uint64_t bits = words_[w]; bits != 0; bits &= bits - 1) {
        f(w * 64 + static_cast<std::size_t>(std::countr_zero(bits)));
      }
    }
  }

 private:
  static constexpr std::uint64_t bit(std::size_t i) { return std::uint64_t{1} << (i & 63); }

  std::vector<std::uint64_t> words_;
  std::vector<std::uint64_t> summary_;
};

}  // namespace tickscope::detail

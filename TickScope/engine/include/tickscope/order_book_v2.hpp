#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <type_traits>
#include <utility>
#include <vector>

#include "tickscope/flat_structures.hpp"
#include "tickscope/order.hpp"

namespace tickscope {

namespace detail {

// One price level: an intrusive FIFO of pool indices.
struct LevelV2 {
  std::uint32_t head = kNil;
  std::uint32_t tail = kNil;
  std::uint32_t count = 0;
  QtyLots total = 0;
};

// One side of the book. Levels inside a band of `band` ticks live in a flat array indexed
// by (price - base); a bitmap marks non-empty levels. Levels outside the band live in a
// fallback std::map. When an out-of-band order would become the best price on its side,
// the band recenters on it, moving levels between the array and the map.
template <bool IsBid>
class Ladder {
 public:
  using Level = LevelV2;

  explicit Ladder(std::size_t band) : band_(band), levels_(band), bits_(band) {}

  // "a is a better price than b" for this side.
  static constexpr bool better(PriceTicks a, PriceTicks b) { return IsBid ? a > b : a < b; }

  struct Best {
    PriceTicks price;
    Level* level;
  };

  // O(band / 4096) bitmap words + O(1) fallback check.
  [[nodiscard]] std::optional<Best> best() {
    std::optional<Best> out;
    const std::int64_t i = IsBid ? bits_.highest() : bits_.lowest();
    if (i >= 0) out = Best{base_ + i, &levels_[static_cast<std::size_t>(i)]};
    if (!fallback_.empty()) {
      auto& [price, level] = *fallback_.begin();
      if (!out || better(price, out->price)) out = Best{price, &level};
    }
    return out;
  }

  [[nodiscard]] Level* find(PriceTicks price) {
    if (inBand(price)) {
      const auto i = index(price);
      return bits_.test(i) ? &levels_[i] : nullptr;
    }
    const auto it = fallback_.find(price);
    return it == fallback_.end() ? nullptr : &it->second;
  }

  // Level to rest a new order at `price`, created if needed.
  Level& levelForRest(PriceTicks price) {
    if (!initialized_) {
      base_ = price - static_cast<PriceTicks>(band_ / 2);
      initialized_ = true;
    } else if (!inBand(price)) {
      const auto b = best();
      if (!b || better(price, b->price)) recenter(price);
    }
    if (inBand(price)) {
      const auto i = index(price);
      if (!bits_.test(i)) {
        bits_.set(i);
        ++bandLevels_;
      }
      return levels_[i];
    }
    return fallback_[price];
  }

  // `price` must hold an empty level.
  void eraseLevel(PriceTicks price) {
    if (inBand(price)) {
      const auto i = index(price);
      bits_.clear(i);
      levels_[i] = Level{};
      --bandLevels_;
    } else {
      fallback_.erase(price);
    }
  }

  [[nodiscard]] std::size_t levelCount() const { return bandLevels_ + fallback_.size(); }
  [[nodiscard]] std::size_t fallbackLevels() const { return fallback_.size(); }
  [[nodiscard]] std::uint64_t recenters() const { return recenters_; }

 private:
  using Compare = std::conditional_t<IsBid, std::greater<>, std::less<>>;

  [[nodiscard]] bool inBand(PriceTicks price) const {
    return initialized_ && price >= base_ && price - base_ < static_cast<PriceTicks>(band_);
  }
  [[nodiscard]] std::size_t index(PriceTicks price) const { return static_cast<std::size_t>(price - base_); }

  // Center the band on `price`. Cost: O(levels in old band + fallback levels in new band).
  // Levels are moved by value; orders reference pool indices, never level addresses, so
  // nothing else needs updating.
  void recenter(PriceTicks price) {
    ++recenters_;
    std::vector<std::pair<PriceTicks, Level>> moving;
    moving.reserve(bandLevels_);
    bits_.forEach([&](std::size_t i) {
      moving.emplace_back(base_ + static_cast<PriceTicks>(i), levels_[i]);
      levels_[i] = Level{};
    });
    for (const auto& m : moving) bits_.clear(index(m.first));
    bandLevels_ = 0;

    base_ = price - static_cast<PriceTicks>(band_ / 2);

    for (const auto& [p, level] : moving) {
      if (inBand(p)) {
        adopt(p, level);
      } else {
        fallback_.emplace(p, level);
      }
    }
    // Pull fallback levels that now fall inside the band into the array.
    for (auto it = fallback_.begin(); it != fallback_.end();) {
      if (inBand(it->first)) {
        adopt(it->first, it->second);
        it = fallback_.erase(it);
      } else {
        ++it;
      }
    }
  }

  void adopt(PriceTicks p, const Level& level) {
    const auto i = index(p);
    levels_[i] = level;
    bits_.set(i);
    ++bandLevels_;
  }

  std::size_t band_;
  std::vector<Level> levels_;
  LevelBitmap bits_;
  std::map<PriceTicks, Level, Compare> fallback_;
  PriceTicks base_ = 0;
  bool initialized_ = false;
  std::size_t bandLevels_ = 0;
  std::uint64_t recenters_ = 0;
};

}  // namespace detail

// v2 order book: same interface and identical matching results as OrderBook (v1), with
// cache-friendly, allocation-free data structures on the hot path:
//   - price levels: flat array + two-level bitmap (fallback std::map outside the band)
//   - orders: preallocated pool of 48-byte nodes, recycled through a free list
//   - per-level FIFO: intrusive doubly linked list of pool indices (no list nodes)
//   - id -> order: open-addressing hash map (no per-entry allocation)
class OrderBookV2 {
 public:
  // bandTicks: width of the array-backed price window per side (multiple of 64).
  // initialOrders: pool and hash-map capacity reserved up front.
  explicit OrderBookV2(std::size_t bandTicks = 1 << 16, std::size_t initialOrders = 1 << 16);

  ExecReport addLimit(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                      std::vector<Fill>& fills);
  ExecReport addMarket(OrderId id, Side side, QtyLots qty, TimestampUs ts, std::vector<Fill>& fills);
  ExecReport addIoc(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills);
  bool cancel(OrderId id);
  ExecReport amend(OrderId id, PriceTicks newPrice, QtyLots newQty, TimestampUs ts, std::vector<Fill>& fills);

  [[nodiscard]] std::optional<PriceTicks> bestBid();
  [[nodiscard]] std::optional<PriceTicks> bestAsk();
  [[nodiscard]] QtyLots volumeAt(Side side, PriceTicks price);
  [[nodiscard]] std::size_t ordersAt(Side side, PriceTicks price);
  [[nodiscard]] std::size_t levelCount(Side side) const;
  [[nodiscard]] std::size_t orderCount() const { return index_.size(); }

  // Introspection for tests and benchmark reports.
  [[nodiscard]] std::size_t poolSize() const { return nodes_.size(); }
  [[nodiscard]] std::size_t fallbackLevels(Side side) const;
  [[nodiscard]] std::uint64_t recenters() const { return bids_.recenters() + asks_.recenters(); }

 private:
  struct Node {
    OrderId id;
    TimestampUs ts;
    PriceTicks price;
    QtyLots qty;
    std::uint32_t prev;
    std::uint32_t next;
    Side side;
  };

  enum class Kind : std::uint8_t { Limit, Market, Ioc };

  ExecReport submit(Kind kind, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills);

  template <class Ladder>
  QtyLots match(Ladder& opposite, OrderId takerId, Side takerSide, PriceTicks takerPrice, QtyLots& qty,
                TimestampUs ts, std::vector<Fill>& fills);

  template <class Ladder>
  void rest(Ladder& own, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts);

  template <class Ladder>
  void removeResting(Ladder& own, std::uint32_t node);

  std::uint32_t allocNode();
  void freeNode(std::uint32_t i);
  void pushBack(detail::LevelV2& level, std::uint32_t i);
  void unlink(detail::LevelV2& level, std::uint32_t i);
  detail::LevelV2* findLevel(Side side, PriceTicks price);

  std::vector<Node> nodes_;
  std::uint32_t freeHead_ = detail::kNil;
  detail::IdMap index_;
  detail::Ladder<true> bids_;
  detail::Ladder<false> asks_;
};

}  // namespace tickscope

#pragma once

#include <atomic>
#include <bit>
#include <cstddef>
#include <memory>
#include <stdexcept>
#include <type_traits>

namespace tickscope {

// Padding unit for data written by different threads. Apple M-series cores use 128-byte
// cache lines (sysctl hw.cachelinesize = 128); x86 uses 64. Padding to 128 is correct on
// both, at the cost of a few unused bytes.
inline constexpr std::size_t kCacheLine = 128;

// Bounded single-producer / single-consumer lock-free ring buffer.
//
// Exactly one thread may call the producer side (tryPush) and exactly one thread the consumer
// side (tryPop, popBatch). Indices increase forever (64-bit, never wrap in practice) and are
// masked into a power-of-two buffer, so "full" is tail - head == capacity and "empty" is
// tail == head, with no wasted slot.
//
// Memory ordering:
//   producer: write slot, then tail.store(release)  — publishes the slot contents
//   consumer: tail.load(acquire), then read slot     — sees everything published before
//   consumer: read slot, then head.store(release)    — hands the slot back
//   producer: head.load(acquire), then reuse slot    — never overwrites unread data
// Each side also keeps a cached copy of the other side's index and only reloads it (a
// cross-core cache miss) when the cached value says full/empty.
template <class T>
class SpscQueue {
  static_assert(std::is_nothrow_copy_assignable_v<T> || std::is_nothrow_move_assignable_v<T>);

 public:
  explicit SpscQueue(std::size_t capacity)
      : capacity_(capacity), mask_(capacity - 1), buffer_(std::make_unique<T[]>(capacity)) {
    if (capacity < 2 || !std::has_single_bit(capacity)) {
      throw std::invalid_argument("SpscQueue capacity must be a power of two >= 2");
    }
  }

  SpscQueue(const SpscQueue&) = delete;
  SpscQueue& operator=(const SpscQueue&) = delete;

  // Producer only. Returns false if full.
  bool tryPush(const T& value) noexcept {
    const std::size_t tail = producer_.tail.load(std::memory_order_relaxed);  // only we write it
    if (tail - producer_.cachedHead == capacity_) {
      producer_.cachedHead = consumer_.head.load(std::memory_order_acquire);
      if (tail - producer_.cachedHead == capacity_) return false;
    }
    buffer_[tail & mask_] = value;
    producer_.tail.store(tail + 1, std::memory_order_release);
    return true;
  }

  // Consumer only. Returns false if empty.
  bool tryPop(T& out) noexcept {
    const std::size_t head = consumer_.head.load(std::memory_order_relaxed);  // only we write it
    if (head == consumer_.cachedTail) {
      consumer_.cachedTail = producer_.tail.load(std::memory_order_acquire);
      if (head == consumer_.cachedTail) return false;
    }
    out = std::move(buffer_[head & mask_]);
    consumer_.head.store(head + 1, std::memory_order_release);
    return true;
  }

  // Consumer only. Pops up to `max` items into `out`; one release store for the whole batch,
  // so the producer sees one cache-line transfer per batch instead of per item.
  std::size_t popBatch(T* out, std::size_t max) noexcept {
    const std::size_t head = consumer_.head.load(std::memory_order_relaxed);
    if (head == consumer_.cachedTail) {
      consumer_.cachedTail = producer_.tail.load(std::memory_order_acquire);
      if (head == consumer_.cachedTail) return 0;
    }
    const std::size_t available = consumer_.cachedTail - head;
    const std::size_t n = available < max ? available : max;
    for (std::size_t i = 0; i < n; ++i) out[i] = std::move(buffer_[(head + i) & mask_]);
    consumer_.head.store(head + n, std::memory_order_release);
    return n;
  }

  [[nodiscard]] std::size_t capacity() const noexcept { return capacity_; }

 private:
  // Written by the producer, read by the consumer. Own cache line(s).
  struct alignas(kCacheLine) ProducerSide {
    std::atomic<std::size_t> tail{0};
    std::size_t cachedHead = 0;  // producer-private copy of consumer_.head
  };
  // Written by the consumer, read by the producer. Own cache line(s).
  struct alignas(kCacheLine) ConsumerSide {
    std::atomic<std::size_t> head{0};
    std::size_t cachedTail = 0;  // consumer-private copy of producer_.tail
  };

  // Read-only after construction; shared freely.
  const std::size_t capacity_;
  const std::size_t mask_;
  const std::unique_ptr<T[]> buffer_;

  ProducerSide producer_;
  ConsumerSide consumer_;
};

}  // namespace tickscope

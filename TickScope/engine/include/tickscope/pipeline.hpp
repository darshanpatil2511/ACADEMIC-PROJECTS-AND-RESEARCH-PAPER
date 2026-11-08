#pragma once

// Two-thread pipeline: a producer thread feeds events through a queue to the engine thread.
// Used by tickscope_replay --pipeline to compare an SPSC lock-free queue (per-item and batched
// pops) against a mutex-protected queue and against the plain single-thread replay.

#include <atomic>
#include <chrono>
#include <cstddef>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/replay.hpp"
#include "tickscope/spsc_queue.hpp"

#if defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#endif

namespace tickscope {

// Spin-wait hint: tells the core we are busy-waiting (saves power, frees pipeline resources
// for a sibling hyper-thread) without giving up the time slice like yield() would.
inline void cpuRelax() noexcept {
#if defined(__x86_64__) || defined(_M_X64)
  _mm_pause();
#elif defined(__aarch64__)
  asm volatile("yield" ::: "memory");
#endif
}

// Baseline: the same bounded ring, but every push and pop takes a mutex.
template <class T>
class MutexQueue {
 public:
  explicit MutexQueue(std::size_t capacity) : buf_(capacity), cap_(capacity) {}
  bool tryPush(const T& v) {
    std::lock_guard<std::mutex> lock(m_);
    if (tail_ - head_ == cap_) return false;
    buf_[tail_++ % cap_] = v;
    return true;
  }
  bool tryPop(T& out) {
    std::lock_guard<std::mutex> lock(m_);
    if (head_ == tail_) return false;
    out = buf_[head_++ % cap_];
    return true;
  }

 private:
  std::mutex m_;
  std::vector<T> buf_;
  std::size_t cap_;
  std::size_t head_ = 0, tail_ = 0;
};

struct PipelineResult {
  double seconds = 0;
  std::uint64_t fills = 0;
};

// Producer thread pushes every event; the calling thread pops and applies them to `Book`.
// batch == 1 uses tryPop; batch > 1 uses popBatch (SPSC only).
template <class Book, class Queue>
PipelineResult runPipeline(const std::vector<Event>& events, std::size_t capacity, std::size_t batch) {
  Queue q(capacity);
  auto book = std::make_unique<Book>();
  std::vector<Fill> fills;
  fills.reserve(4096);
  std::vector<Event> local(batch);
  std::atomic<bool> go{false};

  std::thread producer([&] {
    while (!go.load(std::memory_order_acquire)) cpuRelax();
    for (const Event& ev : events) {
      while (!q.tryPush(ev)) cpuRelax();
    }
  });

  PipelineResult res;
  const auto start = std::chrono::steady_clock::now();
  go.store(true, std::memory_order_release);
  std::size_t done = 0;
  while (done < events.size()) {
    std::size_t n = 0;
    if constexpr (requires { q.popBatch(local.data(), batch); }) {
      n = batch > 1 ? q.popBatch(local.data(), batch) : (q.tryPop(local[0]) ? 1 : 0);
    } else {
      n = q.tryPop(local[0]) ? 1 : 0;
    }
    if (n == 0) {
      cpuRelax();
      continue;
    }
    for (std::size_t i = 0; i < n; ++i) {
      fills.clear();
      apply(*book, local[i], fills);
      res.fills += fills.size();
    }
    done += n;
  }
  res.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
  producer.join();
  return res;
}

}  // namespace tickscope

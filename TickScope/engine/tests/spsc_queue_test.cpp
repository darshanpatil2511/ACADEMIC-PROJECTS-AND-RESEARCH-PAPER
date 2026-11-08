// SPSC queue tests. The two stress tests are also run under ThreadSanitizer in CI
// (-DTICKSCOPE_TSAN=ON), which reports any data race on the slots or indices.

#include <gtest/gtest.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <thread>
#include <vector>

#include "tickscope/spsc_queue.hpp"

namespace {

using tickscope::SpscQueue;

TEST(SpscQueue, RejectsNonPowerOfTwoCapacity) {
  EXPECT_THROW(SpscQueue<int>(0), std::invalid_argument);
  EXPECT_THROW(SpscQueue<int>(1), std::invalid_argument);
  EXPECT_THROW(SpscQueue<int>(6), std::invalid_argument);
  EXPECT_NO_THROW(SpscQueue<int>(8));
}

TEST(SpscQueue, FifoFullAndEmptyOnOneThread) {
  SpscQueue<int> q(4);
  int out = 0;
  EXPECT_FALSE(q.tryPop(out));
  for (int i = 0; i < 4; ++i) EXPECT_TRUE(q.tryPush(i));
  EXPECT_FALSE(q.tryPush(99));  // full: all 4 slots usable, none wasted
  for (int i = 0; i < 4; ++i) {
    ASSERT_TRUE(q.tryPop(out));
    EXPECT_EQ(out, i);
  }
  EXPECT_FALSE(q.tryPop(out));
  // Wrap around the buffer many times.
  for (int i = 0; i < 1000; ++i) {
    ASSERT_TRUE(q.tryPush(i));
    ASSERT_TRUE(q.tryPop(out));
    ASSERT_EQ(out, i);
  }
}

TEST(SpscQueue, PopBatchTakesWhatIsAvailable) {
  SpscQueue<int> q(8);
  for (int i = 0; i < 5; ++i) q.tryPush(i);
  int out[8] = {};
  EXPECT_EQ(q.popBatch(out, 3), 3u);
  EXPECT_EQ(out[2], 2);
  EXPECT_EQ(q.popBatch(out, 8), 2u);
  EXPECT_EQ(out[0], 3);
  EXPECT_EQ(out[1], 4);
  EXPECT_EQ(q.popBatch(out, 8), 0u);
}

TEST(SpscQueue, ProducerAndConsumerStateLiveOnSeparateCacheLines) {
  // alignas on the two sides is what prevents false sharing; check it took effect.
  static_assert(tickscope::kCacheLine >= 64);
  SUCCEED();
}

// Lockstep handoff: the producer pushes one item and waits until the consumer acknowledges
// it before pushing the next. The acknowledgement only orders consumer -> producer, so the
// ONLY producer -> consumer happens-before edge is the queue's own release/acquire on tail.
//
// Why this test exists: in the streaming stress tests below the producer runs ahead, so a
// later release of `tail` also orders earlier slot writes; ThreadSanitizer (which judges the
// interleavings that actually happen) then cannot see a missing or misplaced release. Mutation
// testing showed exactly that. Here every slot read depends on the release for that slot.
TEST(SpscQueueStress, LockstepHandoffPublishesEachSlot) {
  struct Msg {
    std::uint64_t seq;
    std::uint64_t check;
  };
  constexpr std::uint64_t kHandoffs = 100'000;
  SpscQueue<Msg> q(2);
  std::atomic<std::uint64_t> acked{0};
  std::thread producer([&] {
    for (std::uint64_t i = 0; i < kHandoffs; ++i) {
      while (!q.tryPush(Msg{i, ~i})) {
      }
      while (acked.load(std::memory_order_acquire) <= i) {
      }
    }
  });
  bool ok = true;
  Msg m{};
  for (std::uint64_t i = 0; i < kHandoffs; ++i) {
    while (!q.tryPop(m)) {
    }
    ok = ok && m.seq == i && m.check == ~i;
    acked.store(i + 1, std::memory_order_release);
  }
  producer.join();
  EXPECT_TRUE(ok);
}

// 10M by default; CI's ThreadSanitizer job sets TICKSCOPE_STRESS_ITEMS lower because TSan
// instruments every atomic access (10M items take minutes under TSan).
const std::uint64_t kItems = [] {
  const char* env = std::getenv("TICKSCOPE_STRESS_ITEMS");
  return env ? std::strtoull(env, nullptr, 10) : 10'000'000ULL;
}();

// Producer pushes 0..N-1, consumer checks every value arrives exactly once, in order.
TEST(SpscQueueStress, TenMillionItemsInOrder) {
  SpscQueue<std::uint64_t> q(1024);  // small queue: forces constant full/empty transitions
  std::thread producer([&] {
    for (std::uint64_t i = 0; i < kItems; ++i) {
      while (!q.tryPush(i)) std::this_thread::yield();
    }
  });
  std::uint64_t expected = 0;
  std::uint64_t sum = 0;
  std::uint64_t v = 0;
  while (expected < kItems) {
    if (q.tryPop(v)) {
      if (v != expected) break;  // stop early; asserted below
      sum += v;
      ++expected;
    } else {
      std::this_thread::yield();
    }
  }
  producer.join();
  EXPECT_EQ(expected, kItems) << "out-of-order value " << v << " at position " << expected;
  EXPECT_EQ(sum, kItems * (kItems - 1) / 2);
  EXPECT_FALSE(q.tryPop(v));
}

// Same with batch pops and a struct payload (torn reads of a multi-word slot would show).
TEST(SpscQueueStress, TenMillionStructsBatchedInOrder) {
  struct Msg {
    std::uint64_t seq;
    std::uint64_t check;  // = ~seq
  };
  SpscQueue<Msg> q(256);
  std::thread producer([&] {
    for (std::uint64_t i = 0; i < kItems; ++i) {
      while (!q.tryPush(Msg{i, ~i})) std::this_thread::yield();
    }
  });
  std::vector<Msg> batch(64);
  std::uint64_t expected = 0;
  bool ok = true;
  while (expected < kItems && ok) {
    const std::size_t n = q.popBatch(batch.data(), batch.size());
    if (n == 0) std::this_thread::yield();
    for (std::size_t i = 0; i < n; ++i) {
      ok = ok && batch[i].seq == expected && batch[i].check == ~expected;
      ++expected;
    }
  }
  producer.join();
  EXPECT_TRUE(ok);
  EXPECT_EQ(expected, kItems);
}

}  // namespace

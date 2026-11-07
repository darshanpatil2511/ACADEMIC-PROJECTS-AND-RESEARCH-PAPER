// Differential tests: drive a real book and the naive reference book with the same seeded
// random stream; every report, fill and best price must match exactly. v2 also runs with a
// tiny price band on a drifting price, which forces constant recentering and heavy use of
// the out-of-band fallback map.

#include <gtest/gtest.h>

#include <cstdint>
#include <vector>

#include "reference_book.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/order_book_v2.hpp"
#include "tickscope/rng.hpp"

namespace {

using namespace tickscope;
using tickscope::testing::ReferenceBook;

struct StreamShape {
  std::int64_t halfWidth;  // orders priced within center +/- halfWidth
  std::int64_t drift;      // center moves by up to +/- drift per op
};

template <class Book>
void runStream(Book& book, std::uint64_t seed, int ops, StreamShape shape) {
  ReferenceBook ref;
  std::vector<Fill> fillsBook;
  std::vector<Fill> fillsRef;
  Rng rng(seed);

  OrderId nextId = 1;
  PriceTicks center = 100'000;
  for (int i = 0; i < ops; ++i) {
    const auto ts = static_cast<TimestampUs>(i);
    center += rng.uniformInt(-shape.drift, shape.drift);
    const Side side = rng.bernoulli(0.5) ? Side::Buy : Side::Sell;
    const PriceTicks px = center + rng.uniformInt(-shape.halfWidth, shape.halfWidth);
    const QtyLots qty = rng.uniformInt(1, 20);
    const std::int64_t action = rng.uniformInt(0, 99);

    ExecReport a;
    ExecReport b;
    if (action < 55) {
      const OrderId id = nextId++;
      a = book.addLimit(id, side, px, qty, ts, fillsBook);
      b = ref.addLimit(id, side, px, qty, ts, fillsRef);
    } else if (action < 63) {
      const OrderId id = nextId++;
      a = book.addMarket(id, side, qty, ts, fillsBook);
      b = ref.addMarket(id, side, qty, ts, fillsRef);
    } else if (action < 71) {
      const OrderId id = nextId++;
      a = book.addIoc(id, side, px, qty, ts, fillsBook);
      b = ref.addIoc(id, side, px, qty, ts, fillsRef);
    } else if (action < 90) {
      // Random past id: often still resting, sometimes filled or already cancelled.
      const auto id = static_cast<OrderId>(rng.uniformInt(1, static_cast<std::int64_t>(nextId)));
      ASSERT_EQ(book.cancel(id), ref.cancel(id)) << "op " << i;
    } else {
      const auto id = static_cast<OrderId>(rng.uniformInt(1, static_cast<std::int64_t>(nextId)));
      a = book.amend(id, px, qty, ts, fillsBook);
      b = ref.amend(id, px, qty, ts, fillsRef);
    }

    ASSERT_EQ(a, b) << "op " << i;
    ASSERT_EQ(fillsBook.size(), fillsRef.size()) << "op " << i;
    ASSERT_EQ(book.bestBid(), ref.best(Side::Buy)) << "op " << i;
    ASSERT_EQ(book.bestAsk(), ref.best(Side::Sell)) << "op " << i;
    ASSERT_EQ(book.orderCount(), ref.orderCount()) << "op " << i;
    if (book.bestBid() && book.bestAsk()) {
      ASSERT_LT(*book.bestBid(), *book.bestAsk()) << "crossed book at op " << i;
    }
  }
  EXPECT_EQ(fillsBook, fillsRef);
  EXPECT_GT(fillsBook.size(), static_cast<std::size_t>(ops / 10));  // the stream really trades
}

constexpr StreamShape kNarrow{.halfWidth = 8, .drift = 0};
constexpr StreamShape kDrifting{.halfWidth = 40, .drift = 3};

TEST(Differential, V1MatchesReference) {
  for (const std::uint64_t seed : {1ULL, 2ULL, 0xC0FFEEULL}) {
    OrderBook book;
    runStream(book, seed, 20'000, kNarrow);
  }
  OrderBook drifting;
  runStream(drifting, 4, 20'000, kDrifting);
}

TEST(Differential, V2MatchesReference) {
  for (const std::uint64_t seed : {1ULL, 2ULL, 0xC0FFEEULL}) {
    OrderBookV2 book;
    runStream(book, seed, 20'000, kNarrow);
  }
}

TEST(Differential, V2TinyBandDriftingPriceMatchesReference) {
  // 64-tick band, prices spread over +/-40 ticks around a random walk: most operations touch
  // the band edge, the fallback map, or trigger a recenter.
  for (const std::uint64_t seed : {4ULL, 5ULL, 6ULL}) {
    OrderBookV2 book(/*bandTicks=*/64, /*initialOrders=*/16);
    runStream(book, seed, 20'000, kDrifting);
    EXPECT_GT(book.recenters(), 100u) << "seed " << seed;
  }
}

}  // namespace

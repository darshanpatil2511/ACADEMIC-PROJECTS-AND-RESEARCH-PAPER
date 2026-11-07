// Differential test: drive the real book and the naive reference book with the same
// seeded random stream; every report, fill and best price must match exactly.

#include <gtest/gtest.h>

#include <cstdint>
#include <random>
#include <vector>

#include "reference_book.hpp"
#include "tickscope/order_book.hpp"

namespace {

using namespace tickscope;
using tickscope::testing::ReferenceBook;

void runStream(std::uint64_t seed, int ops) {
  OrderBook book;
  ReferenceBook ref;
  std::vector<Fill> fillsBook;
  std::vector<Fill> fillsRef;

  std::mt19937_64 rng(seed);
  auto uniform = [&rng](std::int64_t lo, std::int64_t hi) {
    return std::uniform_int_distribution<std::int64_t>(lo, hi)(rng);
  };

  OrderId nextId = 1;
  for (int i = 0; i < ops; ++i) {
    const auto ts = static_cast<TimestampUs>(i);
    const Side side = uniform(0, 1) == 0 ? Side::Buy : Side::Sell;
    // Narrow band around 1000 so orders cross often and levels hold several orders.
    const PriceTicks px = 1000 + uniform(-8, 8);
    const QtyLots qty = uniform(1, 20);
    const std::int64_t action = uniform(0, 99);

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
      const auto id = static_cast<OrderId>(uniform(1, static_cast<std::int64_t>(nextId)));
      ASSERT_EQ(book.cancel(id), ref.cancel(id)) << "op " << i;
    } else {
      const auto id = static_cast<OrderId>(uniform(1, static_cast<std::int64_t>(nextId)));
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

TEST(Differential, MatchesReferenceSeed1) { runStream(1, 20'000); }
TEST(Differential, MatchesReferenceSeed2) { runStream(2, 20'000); }
TEST(Differential, MatchesReferenceSeed3) { runStream(0xC0FFEE, 20'000); }

}  // namespace

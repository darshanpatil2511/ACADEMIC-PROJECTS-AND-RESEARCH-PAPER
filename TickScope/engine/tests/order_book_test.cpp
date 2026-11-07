#include <gtest/gtest.h>

#include <vector>

#include "tickscope/order_book.hpp"
#include "tickscope/order_book_v2.hpp"

namespace {

using namespace tickscope;

// Every test runs against both implementations: v1 (std::map + std::list) and v2 (flat
// array + pool). They must behave identically.
template <class Book>
class OrderBookTest : public ::testing::Test {
 protected:
  Book book;
  std::vector<Fill> fills;

  ExecReport buy(OrderId id, PriceTicks px, QtyLots qty, TimestampUs ts = 0) {
    return book.addLimit(id, Side::Buy, px, qty, ts, fills);
  }
  ExecReport sell(OrderId id, PriceTicks px, QtyLots qty, TimestampUs ts = 0) {
    return book.addLimit(id, Side::Sell, px, qty, ts, fills);
  }
  static Fill fill(OrderId maker, OrderId taker, Side takerSide, PriceTicks px, QtyLots qty, TimestampUs ts = 0) {
    return Fill{.ts = ts, .makerId = maker, .takerId = taker, .takerSide = takerSide, .price = px, .qty = qty};
  }
};

using BookTypes = ::testing::Types<OrderBook, OrderBookV2>;
TYPED_TEST_SUITE(OrderBookTest, BookTypes);

TYPED_TEST(OrderBookTest, EmptyBookHasNoBestPrices) {
  EXPECT_FALSE(this->book.bestBid().has_value());
  EXPECT_FALSE(this->book.bestAsk().has_value());
  EXPECT_EQ(this->book.orderCount(), 0u);
}

TYPED_TEST(OrderBookTest, NonCrossingOrdersRest) {
  EXPECT_EQ(this->buy(1, 99, 5), (ExecReport{.rested = 5}));
  EXPECT_EQ(this->sell(2, 101, 7), (ExecReport{.rested = 7}));
  this->buy(3, 98, 1);
  this->sell(4, 102, 1);
  EXPECT_EQ(this->book.bestBid(), 99);
  EXPECT_EQ(this->book.bestAsk(), 101);
  EXPECT_EQ(this->book.levelCount(Side::Buy), 2u);
  EXPECT_EQ(this->book.levelCount(Side::Sell), 2u);
  EXPECT_TRUE(this->fills.empty());
}

TYPED_TEST(OrderBookTest, PartialFillLeavesMakerRemainder) {
  this->sell(1, 100, 10);
  const auto r = this->buy(2, 100, 4, /*ts=*/42);
  EXPECT_EQ(r, (ExecReport{.filled = 4}));
  ASSERT_EQ(this->fills.size(), 1u);
  EXPECT_EQ(this->fills[0], this->fill(1, 2, Side::Buy, 100, 4, 42));
  EXPECT_EQ(this->book.volumeAt(Side::Sell, 100), 6);
  EXPECT_EQ(this->book.orderCount(), 1u);
  EXPECT_FALSE(this->book.bestBid().has_value());
}

TYPED_TEST(OrderBookTest, TakerRemainderRestsAtItsLimit) {
  this->sell(1, 100, 3);
  const auto r = this->buy(2, 101, 10);
  EXPECT_EQ(r, (ExecReport{.filled = 3, .rested = 7}));
  EXPECT_EQ(this->book.bestBid(), 101);
  EXPECT_FALSE(this->book.bestAsk().has_value());
}

TYPED_TEST(OrderBookTest, FillsAtMakerPriceNotTakerPrice) {
  this->sell(1, 100, 5);
  this->buy(2, 105, 5);
  ASSERT_EQ(this->fills.size(), 1u);
  EXPECT_EQ(this->fills[0].price, 100);
}

TYPED_TEST(OrderBookTest, SweepsThreeLevels) {
  this->sell(1, 100, 5);
  this->sell(2, 101, 5);
  this->sell(3, 102, 5);
  const auto r = this->buy(4, 102, 12);
  EXPECT_EQ(r, (ExecReport{.filled = 12}));
  const std::vector<Fill> expected{this->fill(1, 4, Side::Buy, 100, 5), this->fill(2, 4, Side::Buy, 101, 5),
                                   this->fill(3, 4, Side::Buy, 102, 2)};
  EXPECT_EQ(this->fills, expected);
  EXPECT_EQ(this->book.bestAsk(), 102);
  EXPECT_EQ(this->book.volumeAt(Side::Sell, 102), 3);
  EXPECT_EQ(this->book.levelCount(Side::Sell), 1u);
}

TYPED_TEST(OrderBookTest, SweepStopsAtLimitPrice) {
  this->sell(1, 100, 5);
  this->sell(2, 101, 5);
  this->sell(3, 102, 5);
  const auto r = this->buy(4, 101, 20);
  EXPECT_EQ(r, (ExecReport{.filled = 10, .rested = 10}));
  EXPECT_EQ(this->book.bestBid(), 101);
  EXPECT_EQ(this->book.bestAsk(), 102);
}

TYPED_TEST(OrderBookTest, SellTakerSweepsBidsHighestFirst) {
  this->buy(1, 98, 5);
  this->buy(2, 100, 5);
  this->buy(3, 99, 5);
  this->book.addLimit(4, Side::Sell, 99, 8, 0, this->fills);
  const std::vector<Fill> expected{this->fill(2, 4, Side::Sell, 100, 5), this->fill(3, 4, Side::Sell, 99, 3)};
  EXPECT_EQ(this->fills, expected);
  EXPECT_EQ(this->book.bestBid(), 99);
}

TYPED_TEST(OrderBookTest, FifoWithinALevel) {
  this->sell(1, 100, 3);
  this->sell(2, 100, 3);
  this->sell(3, 100, 3);
  this->buy(4, 100, 7);
  const std::vector<Fill> expected{this->fill(1, 4, Side::Buy, 100, 3), this->fill(2, 4, Side::Buy, 100, 3),
                                   this->fill(3, 4, Side::Buy, 100, 1)};
  EXPECT_EQ(this->fills, expected);
  EXPECT_EQ(this->book.ordersAt(Side::Sell, 100), 1u);
  EXPECT_EQ(this->book.volumeAt(Side::Sell, 100), 2);
}

TYPED_TEST(OrderBookTest, CancelAfterPartialFill) {
  this->sell(1, 100, 10);
  this->buy(2, 100, 4);
  EXPECT_TRUE(this->book.cancel(1));
  EXPECT_FALSE(this->book.bestAsk().has_value());
  EXPECT_EQ(this->book.levelCount(Side::Sell), 0u);
  EXPECT_EQ(this->book.orderCount(), 0u);
  EXPECT_FALSE(this->book.cancel(1));  // second cancel is a no-op
}

TYPED_TEST(OrderBookTest, CancelMiddleOrderKeepsQueueOrder) {
  this->sell(1, 100, 1);
  this->sell(2, 100, 1);
  this->sell(3, 100, 1);
  EXPECT_TRUE(this->book.cancel(2));
  EXPECT_EQ(this->book.volumeAt(Side::Sell, 100), 2);
  this->buy(4, 100, 2);
  const std::vector<Fill> expected{this->fill(1, 4, Side::Buy, 100, 1), this->fill(3, 4, Side::Buy, 100, 1)};
  EXPECT_EQ(this->fills, expected);
}

TYPED_TEST(OrderBookTest, CancelUnknownOrFilledIdFails) {
  EXPECT_FALSE(this->book.cancel(99));
  this->sell(1, 100, 1);
  this->buy(2, 100, 1);  // fully this->fills id 1
  EXPECT_FALSE(this->book.cancel(1));
}

TYPED_TEST(OrderBookTest, MarketOrderOnEmptySideIsDiscarded) {
  const auto r = this->book.addMarket(1, Side::Buy, 10, 0, this->fills);
  EXPECT_EQ(r, (ExecReport{.discarded = 10}));
  EXPECT_TRUE(this->fills.empty());
  EXPECT_EQ(this->book.orderCount(), 0u);
  EXPECT_FALSE(this->book.bestBid().has_value());
}

TYPED_TEST(OrderBookTest, MarketOrderExceedingLiquidityDiscardsRemainder) {
  this->sell(1, 100, 3);
  this->sell(2, 200, 4);
  const auto r = this->book.addMarket(3, Side::Buy, 10, 0, this->fills);
  EXPECT_EQ(r, (ExecReport{.filled = 7, .discarded = 3}));
  EXPECT_EQ(this->fills.size(), 2u);
  EXPECT_FALSE(this->book.bestAsk().has_value());
  EXPECT_FALSE(this->book.bestBid().has_value());  // never rests
}

TYPED_TEST(OrderBookTest, IocFillsToLimitAndDiscardsRest) {
  this->sell(1, 100, 3);
  this->sell(2, 101, 3);
  const auto r = this->book.addIoc(3, Side::Buy, 100, 5, 0, this->fills);
  EXPECT_EQ(r, (ExecReport{.filled = 3, .discarded = 2}));
  EXPECT_FALSE(this->book.bestBid().has_value());
  EXPECT_EQ(this->book.bestAsk(), 101);
}

TYPED_TEST(OrderBookTest, AmendDownKeepsPriority) {
  this->sell(1, 100, 5);
  this->sell(2, 100, 5);
  EXPECT_EQ(this->book.amend(1, 100, 3, 0, this->fills), (ExecReport{.rested = 3}));
  EXPECT_EQ(this->book.volumeAt(Side::Sell, 100), 8);
  this->buy(3, 100, 3);
  ASSERT_EQ(this->fills.size(), 1u);
  EXPECT_EQ(this->fills[0].makerId, 1u);
}

TYPED_TEST(OrderBookTest, AmendUpLosesPriority) {
  this->sell(1, 100, 5);
  this->sell(2, 100, 5);
  this->book.amend(1, 100, 8, 0, this->fills);
  this->buy(3, 100, 5);
  ASSERT_EQ(this->fills.size(), 1u);
  EXPECT_EQ(this->fills[0].makerId, 2u);
}

TYPED_TEST(OrderBookTest, AmendPriceMovesLevelAndCanCross) {
  this->sell(1, 105, 5);
  this->buy(2, 100, 5);
  const auto r = this->book.amend(2, 105, 5, 7, this->fills);
  EXPECT_EQ(r, (ExecReport{.filled = 5}));
  ASSERT_EQ(this->fills.size(), 1u);
  EXPECT_EQ(this->fills[0], this->fill(1, 2, Side::Buy, 105, 5, 7));
  EXPECT_EQ(this->book.orderCount(), 0u);
}

TYPED_TEST(OrderBookTest, AmendUnknownIdFails) {
  EXPECT_EQ(this->book.amend(9, 100, 1, 0, this->fills).status, Status::UnknownId);
}

TYPED_TEST(OrderBookTest, RejectsInvalidInput) {
  EXPECT_EQ(this->buy(1, 100, 0).status, Status::InvalidQty);
  EXPECT_EQ(this->buy(1, 0, 5).status, Status::InvalidPrice);
  EXPECT_EQ(this->book.addIoc(1, Side::Sell, -1, 5, 0, this->fills).status, Status::InvalidPrice);
  EXPECT_EQ(this->book.addMarket(1, Side::Sell, -2, 0, this->fills).status, Status::InvalidQty);
  this->buy(1, 100, 5);
  EXPECT_EQ(this->sell(1, 101, 5).status, Status::DuplicateId);
  this->sell(2, 101, 5);
  EXPECT_EQ(this->book.amend(2, 101, 0, 0, this->fills).status, Status::InvalidQty);
  EXPECT_EQ(this->book.orderCount(), 2u);
}

TYPED_TEST(OrderBookTest, IdCanBeReusedAfterOrderLeavesBook) {
  this->sell(1, 100, 1);
  this->buy(2, 100, 1);
  EXPECT_EQ(this->sell(1, 100, 1).status, Status::Ok);
}

}  // namespace

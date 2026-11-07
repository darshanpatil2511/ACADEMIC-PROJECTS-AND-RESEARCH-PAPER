#include <gtest/gtest.h>

#include <vector>

#include "tickscope/order_book.hpp"

namespace {

using namespace tickscope;

class OrderBookTest : public ::testing::Test {
 protected:
  OrderBook book;
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

TEST_F(OrderBookTest, EmptyBookHasNoBestPrices) {
  EXPECT_FALSE(book.bestBid().has_value());
  EXPECT_FALSE(book.bestAsk().has_value());
  EXPECT_EQ(book.orderCount(), 0u);
}

TEST_F(OrderBookTest, NonCrossingOrdersRest) {
  EXPECT_EQ(buy(1, 99, 5), (ExecReport{.rested = 5}));
  EXPECT_EQ(sell(2, 101, 7), (ExecReport{.rested = 7}));
  buy(3, 98, 1);
  sell(4, 102, 1);
  EXPECT_EQ(book.bestBid(), 99);
  EXPECT_EQ(book.bestAsk(), 101);
  EXPECT_EQ(book.levelCount(Side::Buy), 2u);
  EXPECT_EQ(book.levelCount(Side::Sell), 2u);
  EXPECT_TRUE(fills.empty());
}

TEST_F(OrderBookTest, PartialFillLeavesMakerRemainder) {
  sell(1, 100, 10);
  const auto r = buy(2, 100, 4, /*ts=*/42);
  EXPECT_EQ(r, (ExecReport{.filled = 4}));
  ASSERT_EQ(fills.size(), 1u);
  EXPECT_EQ(fills[0], fill(1, 2, Side::Buy, 100, 4, 42));
  EXPECT_EQ(book.volumeAt(Side::Sell, 100), 6);
  EXPECT_EQ(book.orderCount(), 1u);
  EXPECT_FALSE(book.bestBid().has_value());
}

TEST_F(OrderBookTest, TakerRemainderRestsAtItsLimit) {
  sell(1, 100, 3);
  const auto r = buy(2, 101, 10);
  EXPECT_EQ(r, (ExecReport{.filled = 3, .rested = 7}));
  EXPECT_EQ(book.bestBid(), 101);
  EXPECT_FALSE(book.bestAsk().has_value());
}

TEST_F(OrderBookTest, FillsAtMakerPriceNotTakerPrice) {
  sell(1, 100, 5);
  buy(2, 105, 5);
  ASSERT_EQ(fills.size(), 1u);
  EXPECT_EQ(fills[0].price, 100);
}

TEST_F(OrderBookTest, SweepsThreeLevels) {
  sell(1, 100, 5);
  sell(2, 101, 5);
  sell(3, 102, 5);
  const auto r = buy(4, 102, 12);
  EXPECT_EQ(r, (ExecReport{.filled = 12}));
  const std::vector<Fill> expected{fill(1, 4, Side::Buy, 100, 5), fill(2, 4, Side::Buy, 101, 5),
                                   fill(3, 4, Side::Buy, 102, 2)};
  EXPECT_EQ(fills, expected);
  EXPECT_EQ(book.bestAsk(), 102);
  EXPECT_EQ(book.volumeAt(Side::Sell, 102), 3);
  EXPECT_EQ(book.levelCount(Side::Sell), 1u);
}

TEST_F(OrderBookTest, SweepStopsAtLimitPrice) {
  sell(1, 100, 5);
  sell(2, 101, 5);
  sell(3, 102, 5);
  const auto r = buy(4, 101, 20);
  EXPECT_EQ(r, (ExecReport{.filled = 10, .rested = 10}));
  EXPECT_EQ(book.bestBid(), 101);
  EXPECT_EQ(book.bestAsk(), 102);
}

TEST_F(OrderBookTest, SellTakerSweepsBidsHighestFirst) {
  buy(1, 98, 5);
  buy(2, 100, 5);
  buy(3, 99, 5);
  book.addLimit(4, Side::Sell, 99, 8, 0, fills);
  const std::vector<Fill> expected{fill(2, 4, Side::Sell, 100, 5), fill(3, 4, Side::Sell, 99, 3)};
  EXPECT_EQ(fills, expected);
  EXPECT_EQ(book.bestBid(), 99);
}

TEST_F(OrderBookTest, FifoWithinALevel) {
  sell(1, 100, 3);
  sell(2, 100, 3);
  sell(3, 100, 3);
  buy(4, 100, 7);
  const std::vector<Fill> expected{fill(1, 4, Side::Buy, 100, 3), fill(2, 4, Side::Buy, 100, 3),
                                   fill(3, 4, Side::Buy, 100, 1)};
  EXPECT_EQ(fills, expected);
  EXPECT_EQ(book.ordersAt(Side::Sell, 100), 1u);
  EXPECT_EQ(book.volumeAt(Side::Sell, 100), 2);
}

TEST_F(OrderBookTest, CancelAfterPartialFill) {
  sell(1, 100, 10);
  buy(2, 100, 4);
  EXPECT_TRUE(book.cancel(1));
  EXPECT_FALSE(book.bestAsk().has_value());
  EXPECT_EQ(book.levelCount(Side::Sell), 0u);
  EXPECT_EQ(book.orderCount(), 0u);
  EXPECT_FALSE(book.cancel(1));  // second cancel is a no-op
}

TEST_F(OrderBookTest, CancelMiddleOrderKeepsQueueOrder) {
  sell(1, 100, 1);
  sell(2, 100, 1);
  sell(3, 100, 1);
  EXPECT_TRUE(book.cancel(2));
  EXPECT_EQ(book.volumeAt(Side::Sell, 100), 2);
  buy(4, 100, 2);
  const std::vector<Fill> expected{fill(1, 4, Side::Buy, 100, 1), fill(3, 4, Side::Buy, 100, 1)};
  EXPECT_EQ(fills, expected);
}

TEST_F(OrderBookTest, CancelUnknownOrFilledIdFails) {
  EXPECT_FALSE(book.cancel(99));
  sell(1, 100, 1);
  buy(2, 100, 1);  // fully fills id 1
  EXPECT_FALSE(book.cancel(1));
}

TEST_F(OrderBookTest, MarketOrderOnEmptySideIsDiscarded) {
  const auto r = book.addMarket(1, Side::Buy, 10, 0, fills);
  EXPECT_EQ(r, (ExecReport{.discarded = 10}));
  EXPECT_TRUE(fills.empty());
  EXPECT_EQ(book.orderCount(), 0u);
  EXPECT_FALSE(book.bestBid().has_value());
}

TEST_F(OrderBookTest, MarketOrderExceedingLiquidityDiscardsRemainder) {
  sell(1, 100, 3);
  sell(2, 200, 4);
  const auto r = book.addMarket(3, Side::Buy, 10, 0, fills);
  EXPECT_EQ(r, (ExecReport{.filled = 7, .discarded = 3}));
  EXPECT_EQ(fills.size(), 2u);
  EXPECT_FALSE(book.bestAsk().has_value());
  EXPECT_FALSE(book.bestBid().has_value());  // never rests
}

TEST_F(OrderBookTest, IocFillsToLimitAndDiscardsRest) {
  sell(1, 100, 3);
  sell(2, 101, 3);
  const auto r = book.addIoc(3, Side::Buy, 100, 5, 0, fills);
  EXPECT_EQ(r, (ExecReport{.filled = 3, .discarded = 2}));
  EXPECT_FALSE(book.bestBid().has_value());
  EXPECT_EQ(book.bestAsk(), 101);
}

TEST_F(OrderBookTest, AmendDownKeepsPriority) {
  sell(1, 100, 5);
  sell(2, 100, 5);
  EXPECT_EQ(book.amend(1, 100, 3, 0, fills), (ExecReport{.rested = 3}));
  EXPECT_EQ(book.volumeAt(Side::Sell, 100), 8);
  buy(3, 100, 3);
  ASSERT_EQ(fills.size(), 1u);
  EXPECT_EQ(fills[0].makerId, 1u);
}

TEST_F(OrderBookTest, AmendUpLosesPriority) {
  sell(1, 100, 5);
  sell(2, 100, 5);
  book.amend(1, 100, 8, 0, fills);
  buy(3, 100, 5);
  ASSERT_EQ(fills.size(), 1u);
  EXPECT_EQ(fills[0].makerId, 2u);
}

TEST_F(OrderBookTest, AmendPriceMovesLevelAndCanCross) {
  sell(1, 105, 5);
  buy(2, 100, 5);
  const auto r = book.amend(2, 105, 5, 7, fills);
  EXPECT_EQ(r, (ExecReport{.filled = 5}));
  ASSERT_EQ(fills.size(), 1u);
  EXPECT_EQ(fills[0], fill(1, 2, Side::Buy, 105, 5, 7));
  EXPECT_EQ(book.orderCount(), 0u);
}

TEST_F(OrderBookTest, AmendUnknownIdFails) {
  EXPECT_EQ(book.amend(9, 100, 1, 0, fills).status, Status::UnknownId);
}

TEST_F(OrderBookTest, RejectsInvalidInput) {
  EXPECT_EQ(buy(1, 100, 0).status, Status::InvalidQty);
  EXPECT_EQ(buy(1, 0, 5).status, Status::InvalidPrice);
  EXPECT_EQ(book.addIoc(1, Side::Sell, -1, 5, 0, fills).status, Status::InvalidPrice);
  EXPECT_EQ(book.addMarket(1, Side::Sell, -2, 0, fills).status, Status::InvalidQty);
  buy(1, 100, 5);
  EXPECT_EQ(sell(1, 101, 5).status, Status::DuplicateId);
  sell(2, 101, 5);
  EXPECT_EQ(book.amend(2, 101, 0, 0, fills).status, Status::InvalidQty);
  EXPECT_EQ(book.orderCount(), 2u);
}

TEST_F(OrderBookTest, IdCanBeReusedAfterOrderLeavesBook) {
  sell(1, 100, 1);
  buy(2, 100, 1);
  EXPECT_EQ(sell(1, 100, 1).status, Status::Ok);
}

}  // namespace

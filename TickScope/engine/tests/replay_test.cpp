#include <gtest/gtest.h>

#include <algorithm>
#include <cmath>
#include <set>
#include <stdexcept>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/market_data.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/replay.hpp"
#include "tickscope/rng.hpp"

namespace {

using namespace tickscope;

// ---- CSV parsing -----------------------------------------------------------------------

TEST(MarketData, ParsesPricesAndTrades) {
  const auto prices = parsePrices("tsSec,priceTicks\n100,7600000\n101,7600123\n");
  ASSERT_EQ(prices.size(), 2u);
  EXPECT_EQ(prices[1].tsSec, 101);
  EXPECT_EQ(prices[1].price, 7600123);

  const auto trades = parseTrades("tradeId,tsUs,side,priceTicks,qtyLots\r\n7,1000,B,8050401,29\r\n8,1001,S,8050400,5");
  ASSERT_EQ(trades.size(), 2u);
  EXPECT_EQ(trades[0].tradeId, 7u);
  EXPECT_EQ(trades[0].side, Side::Buy);
  EXPECT_EQ(trades[1].side, Side::Sell);
  EXPECT_EQ(trades[1].qty, 5);
}

TEST(MarketData, RejectsMalformedRowsWithLineNumber) {
  try {
    parseTrades("h\n1,2,B,3,4\n1,2,X,3,4\n");
    FAIL() << "expected throw";
  } catch (const std::runtime_error& e) {
    EXPECT_NE(std::string(e.what()).find("line 3"), std::string::npos);
  }
  EXPECT_THROW(parsePrices("h\n1,abc\n"), std::runtime_error);
  EXPECT_THROW(parsePrices("h\n1,2,3\n"), std::runtime_error);
  EXPECT_THROW(parsePrices("h\n1\n"), std::runtime_error);
}

// ---- RNG -------------------------------------------------------------------------------

TEST(Rng, DeterministicAndRoughlyCorrectMoments) {
  Rng a(5), b(5);
  for (int i = 0; i < 100; ++i) ASSERT_EQ(a.next(), b.next());

  Rng r(9);
  const int n = 200'000;
  double sumU = 0, sumN = 0, sumN2 = 0, sumG = 0;
  std::vector<double> logn;
  for (int i = 0; i < n; ++i) {
    sumU += r.uniform01();
    const double z = r.normal();
    sumN += z;
    sumN2 += z * z;
    sumG += static_cast<double>(r.geometric(0.25));
    logn.push_back(r.lognormal(std::log(200.0), 1.5));
  }
  EXPECT_NEAR(sumU / n, 0.5, 0.01);
  EXPECT_NEAR(sumN / n, 0.0, 0.01);
  EXPECT_NEAR(sumN2 / n, 1.0, 0.02);
  EXPECT_NEAR(sumG / n, 3.0, 0.05);  // (1 - p) / p
  std::nth_element(logn.begin(), logn.begin() + n / 2, logn.end());
  EXPECT_NEAR(logn[n / 2], 200.0, 5.0);  // lognormal median = exp(mu)
}

// ---- Generator -------------------------------------------------------------------------

struct Fixture {
  std::vector<PricePoint> prices;
  std::vector<TakerTrade> trades;
};

Fixture smallMarket() {
  Fixture f;
  for (std::int64_t s = 999; s <= 1'010; ++s) f.prices.push_back({s, 7'600'000 + (s - 999) * 3});
  std::uint64_t id = 500;
  for (std::int64_t s = 1'000; s <= 1'009; ++s) {
    for (int k = 0; k < 5; ++k) {
      f.trades.push_back({id++, s * 1'000'000 + k * 1'000, k % 2 ? Side::Sell : Side::Buy, 7'600'000, 10 + k});
    }
  }
  return f;
}

TEST(Generator, SameSeedSameStreamDifferentSeedDifferent) {
  const auto m = smallMarket();
  GeneratorConfig cfg;
  const auto a = buildStream(m.prices, m.trades, cfg);
  const auto b = buildStream(m.prices, m.trades, cfg);
  cfg.seed = 43;
  const auto c = buildStream(m.prices, m.trades, cfg);
  ASSERT_EQ(a.size(), b.size());
  for (std::size_t i = 0; i < a.size(); ++i) {
    ASSERT_EQ(a[i].id, b[i].id);
    ASSERT_EQ(a[i].ts, b[i].ts);
    ASSERT_EQ(a[i].price, b[i].price);
    ASSERT_EQ(a[i].qty, b[i].qty);
  }
  bool differs = a.size() != c.size();
  for (std::size_t i = 0; !differs && i < a.size(); ++i) differs = a[i].ts != c[i].ts || a[i].qty != c[i].qty;
  EXPECT_TRUE(differs);
}

TEST(Generator, StreamIsTimeOrderedAndContainsEveryRealTradeOnce) {
  const auto m = smallMarket();
  const auto ev = buildStream(m.prices, m.trades, GeneratorConfig{});
  EXPECT_TRUE(std::is_sorted(ev.begin(), ev.end(), [](const Event& a, const Event& b) { return a.ts < b.ts; }));

  std::vector<std::uint64_t> real;
  for (const Event& e : ev) {
    if (e.source == Source::Real) {
      EXPECT_TRUE(e.type == EventType::Market || e.type == EventType::Ioc);
      EXPECT_NE(e.id & kRealIdBit, 0u);
      real.push_back(e.id & ~kRealIdBit);
    }
  }
  std::vector<std::uint64_t> expected;
  for (const auto& t : m.trades) expected.push_back(t.tradeId);
  EXPECT_EQ(real, expected);  // all present, once, in exchange order
}

TEST(Generator, MakersQuoteAroundPreviousSecondPrice) {
  const auto m = smallMarket();
  const auto ev = buildStream(m.prices, m.trades, GeneratorConfig{});
  for (const Event& e : ev) {
    if (e.type != EventType::Limit) continue;
    const std::int64_t sec = e.ts / 1'000'000;
    const PriceTicks ref = 7'600'000 + (sec - 1 - 999) * 3;
    if (e.side == Side::Buy) {
      EXPECT_LT(e.price, ref);
    } else {
      EXPECT_GT(e.price, ref);
    }
    EXPECT_GE(e.qty, 1);
  }
}

// ---- Replay ----------------------------------------------------------------------------

TEST(Replay, QuantityIsConservedAndFillsMatchReports) {
  const auto m = smallMarket();
  const auto ev = buildStream(m.prices, m.trades, GeneratorConfig{});
  OrderBook book;
  QtyLots fillQty = 0;
  std::size_t fillCount = 0;
  std::set<OrderId> cancelled;
  const ReplayStats s = replay(book, ev, [&](const Event& e, const std::vector<Fill>& fills) {
    for (const Fill& f : fills) {
      EXPECT_EQ(f.takerId, e.id);
      EXPECT_EQ(f.ts, e.ts);
      fillQty += f.qty;
    }
    fillCount += fills.size();
  });

  EXPECT_EQ(s.events, ev.size());
  EXPECT_EQ(s.fills, fillCount);
  EXPECT_EQ(s.rejects, 0u);
  const FlowStats* flows[] = {&s.synthLimit, &s.realMarket, &s.realIoc};
  QtyLots takerFilled = 0;
  for (const FlowStats* f : flows) {
    EXPECT_EQ(f->submitted, f->filled + f->rested + f->discarded);
    takerFilled += f->filled;
  }
  EXPECT_EQ(takerFilled, fillQty);
  EXPECT_EQ(s.realMarket.rested + s.realIoc.rested, 0);  // real takers never rest
  EXPECT_GT(fillCount, 0u);
}

}  // namespace

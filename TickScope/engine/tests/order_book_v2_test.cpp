// Tests specific to v2's data structures: the flat id map, the level bitmap, the order
// pool, band recentering and the out-of-band fallback. Shared matching behaviour is
// covered by the typed tests in order_book_test.cpp and the differential tests.

#include <gtest/gtest.h>

#include <set>
#include <unordered_map>
#include <vector>

#include "tickscope/flat_structures.hpp"
#include "tickscope/generator.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/order_book_v2.hpp"
#include "tickscope/replay.hpp"
#include "tickscope/rng.hpp"

namespace {

using namespace tickscope;
using detail::IdMap;
using detail::kNil;
using detail::LevelBitmap;

TEST(IdMap, MatchesUnorderedMapUnderRandomInsertErase) {
  IdMap map(16);  // tiny start: forces many rehashes and long probe runs
  std::unordered_map<OrderId, std::uint32_t> truth;
  Rng rng(3);
  for (int i = 0; i < 200'000; ++i) {
    // Small key space -> lots of collisions, re-inserts and erases of absent keys.
    const auto key = static_cast<OrderId>(rng.uniformInt(0, 5'000)) * 1'000'003ULL;
    if (rng.bernoulli(0.55)) {
      if (!truth.contains(key)) {
        const auto v = static_cast<std::uint32_t>(i);
        map.insert(key, v);
        truth[key] = v;
      }
    } else {
      ASSERT_EQ(map.erase(key), truth.erase(key) == 1) << "op " << i;
    }
    if (i % 997 == 0) {
      for (const auto& [k, v] : truth) ASSERT_EQ(map.find(k), v);
    }
    ASSERT_EQ(map.size(), truth.size());
  }
  for (const auto& [k, v] : truth) EXPECT_EQ(map.find(k), v);
  EXPECT_EQ(map.find(123), kNil);
  EXPECT_LE(map.size() * 2, map.capacity());  // load factor <= 0.5
}

TEST(IdMap, ZeroAndMaxKeysAreOrdinaryKeys) {
  IdMap map;
  map.insert(0, 7);
  map.insert(~OrderId{0}, 9);
  EXPECT_EQ(map.find(0), 7u);
  EXPECT_EQ(map.find(~OrderId{0}), 9u);
  EXPECT_TRUE(map.erase(0));
  EXPECT_EQ(map.find(0), kNil);
}

TEST(LevelBitmap, LowestHighestAndForEachMatchASet) {
  LevelBitmap bits(1 << 14);
  std::set<std::size_t> truth;
  Rng rng(11);
  EXPECT_EQ(bits.lowest(), -1);
  EXPECT_EQ(bits.highest(), -1);
  for (int i = 0; i < 50'000; ++i) {
    const auto k = static_cast<std::size_t>(rng.uniformInt(0, (1 << 14) - 1));
    if (rng.bernoulli(0.5)) {
      bits.set(k);
      truth.insert(k);
    } else {
      bits.clear(k);
      truth.erase(k);
    }
    ASSERT_EQ(bits.lowest(), truth.empty() ? -1 : static_cast<std::int64_t>(*truth.begin()));
    ASSERT_EQ(bits.highest(), truth.empty() ? -1 : static_cast<std::int64_t>(*truth.rbegin()));
  }
  std::vector<std::size_t> seen;
  bits.forEach([&](std::size_t i) { seen.push_back(i); });
  EXPECT_EQ(seen, std::vector<std::size_t>(truth.begin(), truth.end()));
}

TEST(OrderBookV2, PoolRecyclesNodesInsteadOfGrowing) {
  OrderBookV2 book;
  std::vector<Fill> fills;
  for (OrderId id = 1; id <= 100'000; ++id) {
    book.addLimit(id, Side::Buy, 1'000 + static_cast<PriceTicks>(id % 50), 5, 0, fills);
    ASSERT_TRUE(book.cancel(id));
  }
  EXPECT_EQ(book.poolSize(), 1u);  // one node, reused 100k times
  EXPECT_EQ(book.orderCount(), 0u);
  EXPECT_EQ(book.levelCount(Side::Buy), 0u);
}

TEST(OrderBookV2, OutOfBandOrdersUseFallbackAndStillMatch) {
  OrderBookV2 book(/*bandTicks=*/64);
  std::vector<Fill> fills;
  book.addLimit(1, Side::Sell, 10'000, 5, 0, fills);  // initializes the band around 10,000
  book.addLimit(2, Side::Sell, 50'000, 5, 0, fills);  // far away and not the best: fallback
  EXPECT_EQ(book.fallbackLevels(Side::Sell), 1u);
  EXPECT_EQ(book.recenters(), 0u);

  const auto r = book.addMarket(3, Side::Buy, 8, 1, fills);  // sweeps band level then fallback
  EXPECT_EQ(r.filled, 8);
  ASSERT_EQ(fills.size(), 2u);
  EXPECT_EQ(fills[0].price, 10'000);
  EXPECT_EQ(fills[1].price, 50'000);
  EXPECT_EQ(book.volumeAt(Side::Sell, 50'000), 2);
}

TEST(OrderBookV2, NewBestPriceOutsideBandRecentersAndMovesLevels) {
  OrderBookV2 book(/*bandTicks=*/64);
  std::vector<Fill> fills;
  book.addLimit(1, Side::Buy, 10'000, 1, 0, fills);
  book.addLimit(2, Side::Buy, 10'010, 1, 0, fills);
  book.addLimit(3, Side::Buy, 20'000, 1, 0, fills);  // better bid far above the band
  EXPECT_EQ(book.recenters(), 1u);
  EXPECT_EQ(book.bestBid(), 20'000);
  EXPECT_EQ(book.fallbackLevels(Side::Buy), 2u);  // old levels moved out to the map
  EXPECT_TRUE(book.cancel(1));
  EXPECT_EQ(book.fallbackLevels(Side::Buy), 1u);

  book.addLimit(4, Side::Buy, 10'005, 1, 0, fills);  // worse than best: no recenter
  EXPECT_EQ(book.recenters(), 1u);
  book.addLimit(5, Side::Sell, 10'000, 3, 1, fills);  // sweeps 20,000 then 10,010 then 10,005
  const std::vector<PriceTicks> prices{fills[0].price, fills[1].price, fills[2].price};
  EXPECT_EQ(prices, (std::vector<PriceTicks>{20'000, 10'010, 10'005}));
  EXPECT_EQ(book.orderCount(), 0u);
}

// Found by mutation testing: the random differential streams never emptied a side's band
// while fallback levels sat just outside it, so recentering never had to pull fallback
// levels back into the array. This pins that path down.
TEST(OrderBookV2, RecenterAdoptsFallbackLevelsThatFallInsideNewBand) {
  OrderBookV2 book(/*bandTicks=*/64);  // first order at 10,000 -> band [9,968, 10,032)
  std::vector<Fill> fills;
  book.addLimit(1, Side::Buy, 10'000, 1, 0, fills);
  book.addLimit(2, Side::Buy, 9'900, 2, 0, fills);  // below band, not best: fallback
  book.addLimit(3, Side::Buy, 9'890, 3, 0, fills);  // fallback
  EXPECT_EQ(book.fallbackLevels(Side::Buy), 2u);

  book.addLimit(4, Side::Sell, 10'000, 1, 1, fills);  // fills id 1: the band side is now empty
  EXPECT_EQ(book.bestBid(), 9'900);                   // best now comes from the fallback

  book.addLimit(5, Side::Buy, 9'905, 4, 2, fills);  // new best, out of band -> recenter on 9,905
  EXPECT_EQ(book.recenters(), 1u);
  EXPECT_EQ(book.fallbackLevels(Side::Buy), 0u);  // 9,900 and 9,890 adopted into the band
  EXPECT_EQ(book.levelCount(Side::Buy), 3u);
  EXPECT_EQ(book.volumeAt(Side::Buy, 9'900), 2);

  EXPECT_TRUE(book.cancel(2));  // must find the adopted level
  EXPECT_EQ(book.levelCount(Side::Buy), 2u);
  fills.clear();
  book.addMarket(6, Side::Sell, 7, 3, fills);
  ASSERT_EQ(fills.size(), 2u);
  EXPECT_EQ(fills[0].price, 9'905);
  EXPECT_EQ(fills[1].price, 9'890);
  EXPECT_EQ(book.orderCount(), 0u);
  EXPECT_EQ(book.levelCount(Side::Buy), 0u);
}

TEST(OrderBookV2, IdenticalFillsToV1OnGeneratedStream) {
  // A generated stream with a price path drifting far beyond a small band.
  std::vector<PricePoint> prices;
  std::vector<TakerTrade> trades;
  Rng rng(21);
  PriceTicks px = 7'600'000;
  for (std::int64_t sec = 0; sec < 600; ++sec) {
    px += rng.uniformInt(-60, 60);
    prices.push_back({sec, px});
    for (int k = 0; k < 40; ++k) {
      trades.push_back({static_cast<std::uint64_t>(trades.size() + 1), sec * 1'000'000 + k * 20'000,
                        rng.bernoulli(0.5) ? Side::Buy : Side::Sell, px, rng.uniformInt(1, 800)});
    }
  }
  const auto events = buildStream(prices, trades, GeneratorConfig{});

  auto collect = [&](auto& book) {
    std::vector<Fill> all;
    const ReplayStats s = replay(book, events, [&](const Event&, const ExecReport&, const std::vector<Fill>& f) {
      all.insert(all.end(), f.begin(), f.end());
    });
    return std::make_pair(all, s.cancelHits);
  };
  OrderBook v1;
  OrderBookV2 v2(/*bandTicks=*/256, /*initialOrders=*/64);
  const auto [fills1, hits1] = collect(v1);
  const auto [fills2, hits2] = collect(v2);
  EXPECT_GT(fills1.size(), 1'000u);
  EXPECT_EQ(fills1, fills2);
  EXPECT_EQ(hits1, hits2);
  EXPECT_GT(v2.recenters(), 0u);
}

}  // namespace

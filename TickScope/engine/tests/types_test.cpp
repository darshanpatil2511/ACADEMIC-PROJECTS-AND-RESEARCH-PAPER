#include <gtest/gtest.h>

#include <type_traits>

#include "tickscope/types.hpp"

namespace ts = tickscope;

TEST(Types, PriceAndQtyAreSigned64BitIntegers) {
  static_assert(std::is_same_v<ts::PriceTicks, std::int64_t>);
  static_assert(std::is_same_v<ts::QtyLots, std::int64_t>);
  SUCCEED();
}

TEST(Types, TickAndLotScales) {
  // 100,000.00 USDT -> 10,000,000 ticks; 0.00001 BTC -> 1 lot.
  EXPECT_EQ(100'000 * ts::kTicksPerUsdt, 10'000'000);
  EXPECT_EQ(ts::kLotsPerBtc, 100'000);
}

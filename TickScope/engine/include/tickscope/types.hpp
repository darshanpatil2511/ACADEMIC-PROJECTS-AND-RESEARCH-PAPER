#pragma once

#include <cstdint>

namespace tickscope {

// Prices are integer ticks of 0.01 USDT; quantities are integer lots of 1e-5 BTC.
// Integers keep matching exact: no rounding drift, no dust left on "filled" orders.
using PriceTicks = std::int64_t;
using QtyLots = std::int64_t;
using OrderId = std::uint64_t;
using TimestampUs = std::int64_t;  // microseconds since Unix epoch

inline constexpr std::int64_t kTicksPerUsdt = 100;      // tick size 0.01
inline constexpr std::int64_t kLotsPerBtc = 100'000;    // lot size 1e-5

enum class Side : std::uint8_t { Buy, Sell };

}  // namespace tickscope

#pragma once

#include <cstdint>
#include <vector>

#include "tickscope/market_data.hpp"
#include "tickscope/order.hpp"

namespace tickscope {

enum class EventType : std::uint8_t { Limit, Market, Ioc, Cancel };
enum class Source : std::uint8_t { Synthetic, Real };

// One order-entry message for the engine. 40 bytes; a day is ~10M events.
struct Event {
  OrderId id;
  TimestampUs ts;
  PriceTicks price;  // unused for Market and Cancel
  QtyLots qty;       // unused for Cancel
  EventType type;
  Side side;
  Source source;
};

// Real trades get ids with the top bit set so they never collide with synthetic ids.
inline constexpr OrderId kRealIdBit = OrderId{1} << 63;

// Synthetic market makers: every second, post limit orders on both sides around the
// previous second's real price, and cancel a share of earlier orders. Real taker flow is
// replayed as market orders (share `marketShare`) or IOC orders priced at the real trade
// price plus a tolerance.
struct GeneratorConfig {
  std::uint64_t seed = 42;
  double addsPerSidePerSec = 25.0;   // synthetic limit orders per side per second
  double sizeMedianLots = 200.0;     // lognormal size: median 0.002 BTC
  double sizeSigma = 1.5;            // ... heavy right tail (mean ~3x median)
  double offsetMeanTicks = 5.0;      // distance from reference price: 1 + geometric
  double lifetimeSec = 30.0;         // each second, cancel live/lifetime orders at random
  double marketShare = 0.2;          // share of real trades sent as market orders
  PriceTicks iocToleranceTicks = 50; // IOC limit = real price +/- 0.50 USDT
};

// Builds the full, time-ordered event stream. Pure function of its inputs and the seed:
// the same inputs give the same stream on every platform.
std::vector<Event> buildStream(const std::vector<PricePoint>& prices, const std::vector<TakerTrade>& trades,
                               const GeneratorConfig& config);

}  // namespace tickscope

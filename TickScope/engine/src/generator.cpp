#include "tickscope/generator.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

#include "tickscope/rng.hpp"

namespace tickscope {
namespace {

constexpr TimestampUs kUsPerSec = 1'000'000;

// Rate r per second -> floor(r) events plus one more with probability frac(r).
std::int64_t drawCount(Rng& rng, double rate) {
  const double whole = std::floor(rate);
  return static_cast<std::int64_t>(whole) + (rng.bernoulli(rate - whole) ? 1 : 0);
}

}  // namespace

std::vector<Event> buildStream(const std::vector<PricePoint>& prices, const std::vector<TakerTrade>& trades,
                               const GeneratorConfig& cfg) {
  if (trades.empty()) return {};
  if (prices.empty()) throw std::invalid_argument("buildStream: empty price path");

  Rng rng(cfg.seed);
  const double sizeMu = std::log(cfg.sizeMedianLots);
  const double offsetP = 1.0 / cfg.offsetMeanTicks;

  // prices.csv is one row per second with no gaps, so a second maps to an index.
  const std::int64_t firstPriceSec = prices.front().tsSec;
  auto priceAt = [&](std::int64_t sec) {
    const std::int64_t i = std::clamp<std::int64_t>(sec - firstPriceSec, 0,
                                                    static_cast<std::int64_t>(prices.size()) - 1);
    return prices[static_cast<std::size_t>(i)].price;
  };

  const std::int64_t firstSec = trades.front().ts / kUsPerSec;
  const std::int64_t lastSec = trades.back().ts / kUsPerSec;
  const auto seconds = static_cast<std::size_t>(lastSec - firstSec + 1);

  std::vector<Event> events;
  events.reserve(trades.size() + seconds * static_cast<std::size_t>(4.5 * cfg.addsPerSidePerSec + 1));
  std::vector<Event> batch;
  std::vector<OrderId> live;  // synthetic ids the generator believes are resting
  OrderId nextId = 1;
  std::size_t ti = 0;

  for (std::int64_t sec = firstSec; sec <= lastSec; ++sec) {
    batch.clear();
    const TimestampUs secStart = sec * kUsPerSec;
    // Reference = previous second's last price: makers never see the future.
    const PriceTicks ref = priceAt(sec - 1);
    auto randomTs = [&] { return secStart + rng.uniformInt(0, kUsPerSec - 1); };

    // Cancels: the generator does not know about fills, so some cancels target orders that
    // already traded — the engine reports those as misses, like a real cancel/fill race.
    const std::int64_t cancels = drawCount(rng, static_cast<double>(live.size()) / cfg.lifetimeSec);
    for (std::int64_t k = 0; k < cancels && !live.empty(); ++k) {
      const auto j = static_cast<std::size_t>(rng.uniformInt(0, static_cast<std::int64_t>(live.size()) - 1));
      const OrderId id = live[j];
      live[j] = live.back();
      live.pop_back();
      batch.push_back({.id = id, .ts = randomTs(), .price = 0, .qty = 0, .type = EventType::Cancel,
                       .side = Side::Buy, .source = Source::Synthetic});
    }

    for (const Side side : {Side::Buy, Side::Sell}) {
      const std::int64_t adds = drawCount(rng, cfg.addsPerSidePerSec);
      for (std::int64_t k = 0; k < adds; ++k) {
        const PriceTicks offset = 1 + rng.geometric(offsetP);
        const PriceTicks price = side == Side::Buy ? ref - offset : ref + offset;
        const auto qty = std::max<QtyLots>(1, std::llround(rng.lognormal(sizeMu, cfg.sizeSigma)));
        const OrderId id = nextId++;
        live.push_back(id);
        batch.push_back({.id = id, .ts = randomTs(), .price = price, .qty = qty, .type = EventType::Limit,
                         .side = side, .source = Source::Synthetic});
      }
    }

    for (; ti < trades.size() && trades[ti].ts / kUsPerSec <= sec; ++ti) {
      const TakerTrade& t = trades[ti];
      const bool market = rng.bernoulli(cfg.marketShare);
      const PriceTicks limit =
          t.side == Side::Buy ? t.price + cfg.iocToleranceTicks : t.price - cfg.iocToleranceTicks;
      batch.push_back({.id = kRealIdBit | t.tradeId, .ts = t.ts, .price = market ? 0 : limit, .qty = t.qty,
                       .type = market ? EventType::Market : EventType::Ioc, .side = t.side,
                       .source = Source::Real});
    }

    // Stable: real trades keep their exchange order when they share a timestamp.
    std::stable_sort(batch.begin(), batch.end(), [](const Event& a, const Event& b) { return a.ts < b.ts; });
    events.insert(events.end(), batch.begin(), batch.end());
  }
  return events;
}

}  // namespace tickscope

#pragma once

#include <string>
#include <string_view>
#include <vector>

#include "tickscope/types.hpp"

namespace tickscope {

// One row of data/prices.csv: last traded price of a second (gaps forward-filled).
struct PricePoint {
  std::int64_t tsSec;
  PriceTicks price;
};

// One row of data/trades.csv: a real trade seen from the aggressor's side.
struct TakerTrade {
  std::uint64_t tradeId;
  TimestampUs ts;
  Side side;  // taker side
  PriceTicks price;
  QtyLots qty;
};

// Parsers for the CSVs written by the Spark jobs (header row first). Throw
// std::runtime_error naming the line on malformed input.
std::vector<PricePoint> parsePrices(std::string_view csv);
std::vector<TakerTrade> parseTrades(std::string_view csv);

std::string readFile(const std::string& path);

}  // namespace tickscope

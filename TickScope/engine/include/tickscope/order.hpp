#pragma once

#include <cstdint>

#include "tickscope/types.hpp"

namespace tickscope {

constexpr Side opposite(Side s) noexcept { return s == Side::Buy ? Side::Sell : Side::Buy; }

// A resting order. `qty` is the remaining (unfilled) quantity.
struct Order {
  OrderId id;
  Side side;
  PriceTicks price;
  QtyLots qty;
  TimestampUs ts;
};

// One execution between a resting (maker) and an incoming (taker) order.
// Trades at the maker's price; `ts` is the taker's timestamp.
struct Fill {
  TimestampUs ts;
  OrderId makerId;
  OrderId takerId;
  Side takerSide;
  PriceTicks price;
  QtyLots qty;

  bool operator==(const Fill&) const = default;
};

enum class Status : std::uint8_t {
  Ok,
  InvalidQty,    // qty <= 0
  InvalidPrice,  // price <= 0 on a priced order
  DuplicateId,   // id already resting in the book
  UnknownId,     // cancel/amend of an id that is not resting
};

// Outcome of one submit/amend. For an accepted order:
// original qty == filled + rested + discarded.
struct ExecReport {
  Status status = Status::Ok;
  QtyLots filled = 0;     // matched against resting orders
  QtyLots rested = 0;     // left in the book (limit orders only)
  QtyLots discarded = 0;  // unfilled remainder of market/IOC orders

  bool operator==(const ExecReport&) const = default;
};

}  // namespace tickscope

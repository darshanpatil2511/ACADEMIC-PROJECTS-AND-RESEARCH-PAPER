#pragma once

#include <cstddef>
#include <functional>
#include <list>
#include <map>
#include <optional>
#include <unordered_map>
#include <utility>
#include <vector>

#include "tickscope/order.hpp"

namespace tickscope {

// Single-instrument limit order book with price-time priority (v1: node-based containers).
//
// Complexity (L = price levels on a side, F = fills generated):
//   addLimit / addIoc / addMarket   O(F + log L) — match from the best level, rest if needed
//   cancel                          O(1) average; + O(log L) only when the level empties
//   amend (qty down, same price)    O(1) average, keeps queue priority
//   amend (price change or qty up)  cancel + addLimit, loses queue priority
//   bestBid / bestAsk               O(1) — begin() of each map
//
// Fills are appended to a caller-owned vector so the hot path does not allocate a new
// container per order.
class OrderBook {
 public:
  ExecReport addLimit(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                      std::vector<Fill>& fills);

  // Matches at any price; any remainder is discarded, never rested.
  ExecReport addMarket(OrderId id, Side side, QtyLots qty, TimestampUs ts, std::vector<Fill>& fills);

  // Immediate-or-cancel: matches up to `price`; any remainder is discarded.
  ExecReport addIoc(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills);

  // Returns false if `id` is not resting (never existed, already filled or cancelled).
  bool cancel(OrderId id);

  // Same price and newQty <= remaining: reduce in place, keep priority.
  // Otherwise: cancel and re-submit as a limit order at `ts` (may match immediately).
  ExecReport amend(OrderId id, PriceTicks newPrice, QtyLots newQty, TimestampUs ts,
                   std::vector<Fill>& fills);

  [[nodiscard]] std::optional<PriceTicks> bestBid() const;
  [[nodiscard]] std::optional<PriceTicks> bestAsk() const;

  [[nodiscard]] QtyLots volumeAt(Side side, PriceTicks price) const;
  [[nodiscard]] std::size_t ordersAt(Side side, PriceTicks price) const;
  [[nodiscard]] std::size_t levelCount(Side side) const;
  [[nodiscard]] std::size_t orderCount() const { return index_.size(); }

  // Best `n` price levels on a side, best first: (price, total quantity). O(n).
  [[nodiscard]] std::vector<std::pair<PriceTicks, QtyLots>> depth(Side side, std::size_t n) const;

 private:
  struct Level {
    std::list<Order> orders;  // FIFO: front has time priority
    QtyLots total = 0;        // sum of orders[i].qty, kept in O(1)
  };

  // Bids: highest price first. Asks: lowest price first. So begin() is always the best.
  using Bids = std::map<PriceTicks, Level, std::greater<>>;
  using Asks = std::map<PriceTicks, Level, std::less<>>;

  // std::list iterators and std::map node addresses stay valid until that element is
  // erased, so both can be stored for O(1) access.
  struct Locator {
    std::list<Order>::iterator order;
    Level* level;
  };

  enum class Kind : std::uint8_t { Limit, Market, Ioc };

  ExecReport submit(Kind kind, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills);

  template <class Ladder>
  QtyLots match(Ladder& opposite, Order& taker, std::vector<Fill>& fills);

  template <class Ladder>
  void rest(Ladder& own, const Order& order);

  template <class Ladder>
  void remove(Ladder& own, const Locator& loc);

  Bids bids_;
  Asks asks_;
  std::unordered_map<OrderId, Locator> index_;
};

}  // namespace tickscope

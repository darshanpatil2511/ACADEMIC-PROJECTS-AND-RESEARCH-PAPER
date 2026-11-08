#include "tickscope/order_book.hpp"

#include <algorithm>
#include <limits>

namespace tickscope {

ExecReport OrderBook::addLimit(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                               std::vector<Fill>& fills) {
  return submit(Kind::Limit, id, side, price, qty, ts, fills);
}

ExecReport OrderBook::addMarket(OrderId id, Side side, QtyLots qty, TimestampUs ts,
                                std::vector<Fill>& fills) {
  // A market order is a limit order at the most aggressive possible price that never rests.
  const PriceTicks any = side == Side::Buy ? std::numeric_limits<PriceTicks>::max()
                                           : std::numeric_limits<PriceTicks>::min();
  return submit(Kind::Market, id, side, any, qty, ts, fills);
}

ExecReport OrderBook::addIoc(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                             std::vector<Fill>& fills) {
  return submit(Kind::Ioc, id, side, price, qty, ts, fills);
}

ExecReport OrderBook::submit(Kind kind, OrderId id, Side side, PriceTicks price, QtyLots qty,
                             TimestampUs ts, std::vector<Fill>& fills) {
  if (qty <= 0) return {.status = Status::InvalidQty};
  if (kind != Kind::Market && price <= 0) return {.status = Status::InvalidPrice};
  if (index_.contains(id)) return {.status = Status::DuplicateId};

  Order taker{.id = id, .side = side, .price = price, .qty = qty, .ts = ts};
  ExecReport report;
  report.filled = side == Side::Buy ? match(asks_, taker, fills) : match(bids_, taker, fills);

  if (taker.qty > 0) {
    if (kind == Kind::Limit) {
      if (side == Side::Buy) {
        rest(bids_, taker);
      } else {
        rest(asks_, taker);
      }
      report.rested = taker.qty;
    } else {
      report.discarded = taker.qty;
    }
  }
  return report;
}

// Walk the opposite side from its best level while the taker still has quantity and the
// level price crosses the taker's limit. Within a level, fill strictly in arrival order.
template <class Ladder>
QtyLots OrderBook::match(Ladder& opposite, Order& taker, std::vector<Fill>& fills) {
  // The ladder's comparator orders levels best-first, so "level is at least as good as
  // the taker's limit" is exactly !comp(takerPrice, levelPrice):
  //   asks (less):    levelPrice <= taker.price
  //   bids (greater): levelPrice >= taker.price
  const auto comp = opposite.key_comp();
  QtyLots filled = 0;

  while (taker.qty > 0 && !opposite.empty()) {
    auto levelIt = opposite.begin();
    const PriceTicks levelPrice = levelIt->first;
    if (comp(taker.price, levelPrice)) break;  // best level no longer crosses

    Level& level = levelIt->second;
    while (taker.qty > 0 && !level.orders.empty()) {
      Order& maker = level.orders.front();
      const QtyLots qty = std::min(taker.qty, maker.qty);

      fills.push_back(Fill{.ts = taker.ts,
                           .makerId = maker.id,
                           .takerId = taker.id,
                           .takerSide = taker.side,
                           .price = levelPrice,
                           .qty = qty});
      maker.qty -= qty;
      taker.qty -= qty;
      level.total -= qty;
      filled += qty;

      if (maker.qty == 0) {
        index_.erase(maker.id);
        level.orders.pop_front();
      }
    }
    if (level.orders.empty()) opposite.erase(levelIt);
  }
  return filled;
}

template <class Ladder>
void OrderBook::rest(Ladder& own, const Order& order) {
  Level& level = own[order.price];  // creates the level if absent: O(log L)
  level.orders.push_back(order);
  level.total += order.qty;
  index_.emplace(order.id, Locator{.order = std::prev(level.orders.end()), .level = &level});
}

template <class Ladder>
void OrderBook::remove(Ladder& own, const Locator& loc) {
  const PriceTicks price = loc.order->price;
  loc.level->total -= loc.order->qty;
  loc.level->orders.erase(loc.order);  // O(1): unlink one node, no other iterator invalidated
  if (loc.level->orders.empty()) own.erase(price);
}

bool OrderBook::cancel(OrderId id) {
  const auto it = index_.find(id);
  if (it == index_.end()) return false;

  const Locator loc = it->second;
  index_.erase(it);
  if (loc.order->side == Side::Buy) {
    remove(bids_, loc);
  } else {
    remove(asks_, loc);
  }
  return true;
}

ExecReport OrderBook::amend(OrderId id, PriceTicks newPrice, QtyLots newQty, TimestampUs ts,
                            std::vector<Fill>& fills) {
  const auto it = index_.find(id);
  if (it == index_.end()) return {.status = Status::UnknownId};
  if (newQty <= 0) return {.status = Status::InvalidQty};
  if (newPrice <= 0) return {.status = Status::InvalidPrice};

  Order& order = *it->second.order;
  if (newPrice == order.price && newQty <= order.qty) {
    // Reducing size does not disadvantage anyone queued behind, so priority is kept.
    it->second.level->total -= order.qty - newQty;
    order.qty = newQty;
    return {.rested = newQty};
  }

  // A price change or a size increase is a new order: it goes to the back of the queue.
  const Side side = order.side;
  cancel(id);
  return addLimit(id, side, newPrice, newQty, ts, fills);
}

std::optional<PriceTicks> OrderBook::bestBid() const {
  if (bids_.empty()) return std::nullopt;
  return bids_.begin()->first;
}

std::optional<PriceTicks> OrderBook::bestAsk() const {
  if (asks_.empty()) return std::nullopt;
  return asks_.begin()->first;
}

QtyLots OrderBook::volumeAt(Side side, PriceTicks price) const {
  if (side == Side::Buy) {
    const auto it = bids_.find(price);
    return it == bids_.end() ? 0 : it->second.total;
  }
  const auto it = asks_.find(price);
  return it == asks_.end() ? 0 : it->second.total;
}

std::size_t OrderBook::ordersAt(Side side, PriceTicks price) const {
  if (side == Side::Buy) {
    const auto it = bids_.find(price);
    return it == bids_.end() ? 0 : it->second.orders.size();
  }
  const auto it = asks_.find(price);
  return it == asks_.end() ? 0 : it->second.orders.size();
}

std::vector<std::pair<PriceTicks, QtyLots>> OrderBook::depth(Side side, std::size_t n) const {
  std::vector<std::pair<PriceTicks, QtyLots>> out;
  out.reserve(n);
  auto take = [&](const auto& ladder) {
    for (auto it = ladder.begin(); it != ladder.end() && out.size() < n; ++it) out.emplace_back(it->first, it->second.total);
  };
  if (side == Side::Buy) {
    take(bids_);
  } else {
    take(asks_);
  }
  return out;
}

std::size_t OrderBook::levelCount(Side side) const {
  return side == Side::Buy ? bids_.size() : asks_.size();
}

}  // namespace tickscope

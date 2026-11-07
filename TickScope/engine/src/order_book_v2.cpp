#include "tickscope/order_book_v2.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>

namespace tickscope {

using detail::kNil;
using detail::LevelV2;

OrderBookV2::OrderBookV2(std::size_t bandTicks, std::size_t initialOrders)
    : index_(initialOrders * 2), bids_(bandTicks), asks_(bandTicks) {
  if (initialOrders >= kNil) throw std::invalid_argument("initialOrders too large for 32-bit node indices");
  nodes_.reserve(initialOrders);
}

// ---- Pool and intrusive list --------------------------------------------------------

std::uint32_t OrderBookV2::allocNode() {
  if (freeHead_ != kNil) {
    const std::uint32_t i = freeHead_;
    freeHead_ = nodes_[i].next;
    return i;
  }
  if (nodes_.size() >= kNil) throw std::length_error("order pool exhausted");
  nodes_.emplace_back();  // only when every pooled node is live; amortized O(1)
  return static_cast<std::uint32_t>(nodes_.size() - 1);
}

void OrderBookV2::freeNode(std::uint32_t i) {
  nodes_[i].next = freeHead_;  // the free list threads through the same `next` field
  freeHead_ = i;
}

void OrderBookV2::pushBack(LevelV2& level, std::uint32_t i) {
  Node& n = nodes_[i];
  n.prev = level.tail;
  n.next = kNil;
  if (level.tail != kNil) {
    nodes_[level.tail].next = i;
  } else {
    level.head = i;
  }
  level.tail = i;
  ++level.count;
  level.total += n.qty;
}

void OrderBookV2::unlink(LevelV2& level, std::uint32_t i) {
  const Node& n = nodes_[i];
  if (n.prev != kNil) {
    nodes_[n.prev].next = n.next;
  } else {
    level.head = n.next;
  }
  if (n.next != kNil) {
    nodes_[n.next].prev = n.prev;
  } else {
    level.tail = n.prev;
  }
  --level.count;
  level.total -= n.qty;
}

LevelV2* OrderBookV2::findLevel(Side side, PriceTicks price) {
  return side == Side::Buy ? bids_.find(price) : asks_.find(price);
}

// ---- Order entry --------------------------------------------------------------------

ExecReport OrderBookV2::addLimit(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                                 std::vector<Fill>& fills) {
  return submit(Kind::Limit, id, side, price, qty, ts, fills);
}

ExecReport OrderBookV2::addMarket(OrderId id, Side side, QtyLots qty, TimestampUs ts, std::vector<Fill>& fills) {
  const PriceTicks any = side == Side::Buy ? std::numeric_limits<PriceTicks>::max()
                                           : std::numeric_limits<PriceTicks>::min();
  return submit(Kind::Market, id, side, any, qty, ts, fills);
}

ExecReport OrderBookV2::addIoc(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                               std::vector<Fill>& fills) {
  return submit(Kind::Ioc, id, side, price, qty, ts, fills);
}

ExecReport OrderBookV2::submit(Kind kind, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                               std::vector<Fill>& fills) {
  if (qty <= 0) return {.status = Status::InvalidQty};
  if (kind != Kind::Market && price <= 0) return {.status = Status::InvalidPrice};
  if (index_.find(id) != kNil) return {.status = Status::DuplicateId};

  ExecReport report;
  QtyLots remaining = qty;
  report.filled = side == Side::Buy ? match(asks_, id, side, price, remaining, ts, fills)
                                    : match(bids_, id, side, price, remaining, ts, fills);
  if (remaining > 0) {
    if (kind == Kind::Limit) {
      if (side == Side::Buy) {
        rest(bids_, id, side, price, remaining, ts);
      } else {
        rest(asks_, id, side, price, remaining, ts);
      }
      report.rested = remaining;
    } else {
      report.discarded = remaining;
    }
  }
  return report;
}

template <class Ladder>
QtyLots OrderBookV2::match(Ladder& opposite, OrderId takerId, Side takerSide, PriceTicks takerPrice, QtyLots& qty,
                           TimestampUs ts, std::vector<Fill>& fills) {
  QtyLots filled = 0;
  while (qty > 0) {
    const auto best = opposite.best();
    // Same crossing rule as v1: the level crosses unless the taker's limit is strictly
    // better (from the opposite side's point of view) than the level price.
    if (!best || Ladder::better(takerPrice, best->price)) break;

    LevelV2& level = *best->level;
    while (qty > 0 && level.head != kNil) {
      const std::uint32_t mi = level.head;
      Node& maker = nodes_[mi];
      const QtyLots q = std::min(qty, maker.qty);
      fills.push_back(Fill{.ts = ts, .makerId = maker.id, .takerId = takerId, .takerSide = takerSide,
                           .price = best->price, .qty = q});
      maker.qty -= q;
      level.total -= q;
      qty -= q;
      filled += q;
      if (maker.qty == 0) {
        index_.erase(maker.id);
        unlink(level, mi);  // maker.qty is 0, so total is unchanged
        freeNode(mi);
      }
    }
    if (level.head == kNil) opposite.eraseLevel(best->price);
  }
  return filled;
}

template <class Ladder>
void OrderBookV2::rest(Ladder& own, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts) {
  LevelV2& level = own.levelForRest(price);
  const std::uint32_t i = allocNode();
  nodes_[i] = Node{.id = id, .ts = ts, .price = price, .qty = qty, .prev = kNil, .next = kNil, .side = side};
  pushBack(level, i);
  index_.insert(id, i);
}

template <class Ladder>
void OrderBookV2::removeResting(Ladder& own, std::uint32_t i) {
  const PriceTicks price = nodes_[i].price;
  LevelV2* level = own.find(price);
  unlink(*level, i);
  if (level->head == kNil) own.eraseLevel(price);
  freeNode(i);
}

bool OrderBookV2::cancel(OrderId id) {
  const std::uint32_t i = index_.find(id);
  if (i == kNil) return false;
  index_.erase(id);
  if (nodes_[i].side == Side::Buy) {
    removeResting(bids_, i);
  } else {
    removeResting(asks_, i);
  }
  return true;
}

ExecReport OrderBookV2::amend(OrderId id, PriceTicks newPrice, QtyLots newQty, TimestampUs ts,
                              std::vector<Fill>& fills) {
  const std::uint32_t i = index_.find(id);
  if (i == kNil) return {.status = Status::UnknownId};
  if (newQty <= 0) return {.status = Status::InvalidQty};
  if (newPrice <= 0) return {.status = Status::InvalidPrice};

  Node& n = nodes_[i];
  if (newPrice == n.price && newQty <= n.qty) {
    findLevel(n.side, n.price)->total -= n.qty - newQty;
    n.qty = newQty;
    return {.rested = newQty};
  }
  const Side side = n.side;
  cancel(id);
  return addLimit(id, side, newPrice, newQty, ts, fills);
}

// ---- Queries ------------------------------------------------------------------------

std::optional<PriceTicks> OrderBookV2::bestBid() {
  const auto b = bids_.best();
  return b ? std::optional<PriceTicks>(b->price) : std::nullopt;
}

std::optional<PriceTicks> OrderBookV2::bestAsk() {
  const auto b = asks_.best();
  return b ? std::optional<PriceTicks>(b->price) : std::nullopt;
}

QtyLots OrderBookV2::volumeAt(Side side, PriceTicks price) {
  const LevelV2* l = findLevel(side, price);
  return l ? l->total : 0;
}

std::size_t OrderBookV2::ordersAt(Side side, PriceTicks price) {
  const LevelV2* l = findLevel(side, price);
  return l ? l->count : 0;
}

std::size_t OrderBookV2::levelCount(Side side) const {
  return side == Side::Buy ? bids_.levelCount() : asks_.levelCount();
}

std::size_t OrderBookV2::fallbackLevels(Side side) const {
  return side == Side::Buy ? bids_.fallbackLevels() : asks_.fallbackLevels();
}

}  // namespace tickscope

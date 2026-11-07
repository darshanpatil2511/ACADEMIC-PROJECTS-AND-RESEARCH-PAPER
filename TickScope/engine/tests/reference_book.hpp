#pragma once

// Deliberately naive order book used only as a test oracle: a flat vector of resting
// orders, linear scans for everything. Too slow for real use, but simple enough to trust
// by inspection. The real books must produce exactly the same fills and reports.

#include <algorithm>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

#include "tickscope/order.hpp"

namespace tickscope::testing {

class ReferenceBook {
 public:
  ExecReport addLimit(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                      std::vector<Fill>& fills) {
    return submit(true, id, side, price, qty, ts, fills);
  }

  ExecReport addMarket(OrderId id, Side side, QtyLots qty, TimestampUs ts, std::vector<Fill>& fills) {
    const PriceTicks any = side == Side::Buy ? std::numeric_limits<PriceTicks>::max()
                                             : std::numeric_limits<PriceTicks>::min();
    if (qty <= 0) return {.status = Status::InvalidQty};
    return submit(false, id, side, any, qty, ts, fills, /*checkPrice=*/false);
  }

  ExecReport addIoc(OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills) {
    return submit(false, id, side, price, qty, ts, fills);
  }

  bool cancel(OrderId id) {
    const auto it = find(id);
    if (it == resting_.end()) return false;
    resting_.erase(it);
    return true;
  }

  ExecReport amend(OrderId id, PriceTicks newPrice, QtyLots newQty, TimestampUs ts,
                   std::vector<Fill>& fills) {
    const auto it = find(id);
    if (it == resting_.end()) return {.status = Status::UnknownId};
    if (newQty <= 0) return {.status = Status::InvalidQty};
    if (newPrice <= 0) return {.status = Status::InvalidPrice};
    if (newPrice == it->order.price && newQty <= it->order.qty) {
      it->order.qty = newQty;
      return {.rested = newQty};
    }
    const Side side = it->order.side;
    resting_.erase(it);
    return addLimit(id, side, newPrice, newQty, ts, fills);
  }

  [[nodiscard]] std::optional<PriceTicks> best(Side side) const {
    std::optional<PriceTicks> out;
    for (const auto& r : resting_) {
      if (r.order.side != side) continue;
      if (!out || (side == Side::Buy ? r.order.price > *out : r.order.price < *out)) out = r.order.price;
    }
    return out;
  }

  [[nodiscard]] std::size_t orderCount() const { return resting_.size(); }

 private:
  struct Resting {
    Order order;
    std::uint64_t seq;  // arrival order for time priority
  };

  std::vector<Resting>::iterator find(OrderId id) {
    return std::find_if(resting_.begin(), resting_.end(), [id](const Resting& r) { return r.order.id == id; });
  }

  ExecReport submit(bool rests, OrderId id, Side side, PriceTicks price, QtyLots qty, TimestampUs ts,
                    std::vector<Fill>& fills, bool checkPrice = true) {
    if (qty <= 0) return {.status = Status::InvalidQty};
    if (checkPrice && price <= 0) return {.status = Status::InvalidPrice};
    if (find(id) != resting_.end()) return {.status = Status::DuplicateId};

    ExecReport report;
    while (qty > 0) {
      // Best maker: best price for the taker, then earliest arrival.
      auto best = resting_.end();
      for (auto it = resting_.begin(); it != resting_.end(); ++it) {
        if (it->order.side == side) continue;
        const bool crosses = side == Side::Buy ? it->order.price <= price : it->order.price >= price;
        if (!crosses) continue;
        if (best == resting_.end()) {
          best = it;
          continue;
        }
        const bool better = side == Side::Buy ? it->order.price < best->order.price
                                              : it->order.price > best->order.price;
        if (better || (it->order.price == best->order.price && it->seq < best->seq)) best = it;
      }
      if (best == resting_.end()) break;

      const QtyLots q = std::min(qty, best->order.qty);
      fills.push_back(Fill{.ts = ts,
                           .makerId = best->order.id,
                           .takerId = id,
                           .takerSide = side,
                           .price = best->order.price,
                           .qty = q});
      qty -= q;
      best->order.qty -= q;
      report.filled += q;
      if (best->order.qty == 0) resting_.erase(best);
    }

    if (qty > 0) {
      if (rests) {
        resting_.push_back({Order{.id = id, .side = side, .price = price, .qty = qty, .ts = ts}, nextSeq_++});
        report.rested = qty;
      } else {
        report.discarded = qty;
      }
    }
    return report;
  }

  std::vector<Resting> resting_;
  std::uint64_t nextSeq_ = 0;
};

}  // namespace tickscope::testing

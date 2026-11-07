#pragma once

#include <cstdint>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/order.hpp"

namespace tickscope {

// Applies one event to any book with the OrderBook interface (v1 now, v2 in Phase 6).
template <class Book>
inline ExecReport apply(Book& book, const Event& ev, std::vector<Fill>& fills) {
  switch (ev.type) {
    case EventType::Limit:
      return book.addLimit(ev.id, ev.side, ev.price, ev.qty, ev.ts, fills);
    case EventType::Market:
      return book.addMarket(ev.id, ev.side, ev.qty, ev.ts, fills);
    case EventType::Ioc:
      return book.addIoc(ev.id, ev.side, ev.price, ev.qty, ev.ts, fills);
    case EventType::Cancel:
      return {.status = book.cancel(ev.id) ? Status::Ok : Status::UnknownId};
  }
  return {.status = Status::UnknownId};  // unreachable
}

struct FlowStats {
  std::uint64_t orders = 0;
  QtyLots submitted = 0;
  QtyLots filled = 0;
  QtyLots rested = 0;
  QtyLots discarded = 0;
};

struct ReplayStats {
  std::uint64_t events = 0;
  std::uint64_t fills = 0;
  std::uint64_t cancels = 0;
  std::uint64_t cancelHits = 0;  // cancel found a resting order
  std::uint64_t rejects = 0;     // orders refused by validation
  FlowStats synthLimit;          // synthetic makers (can also take when prices move)
  FlowStats realMarket;
  FlowStats realIoc;
};

// Replays `events` through `book`, calling onFills(event, fills) after each event.
// Pass a no-op callback for benchmarking: it inlines away.
template <class Book, class OnFills>
ReplayStats replay(Book& book, const std::vector<Event>& events, OnFills&& onFills) {
  ReplayStats s;
  std::vector<Fill> fills;
  fills.reserve(4096);
  for (const Event& ev : events) {
    fills.clear();
    const ExecReport r = apply(book, ev, fills);
    ++s.events;
    s.fills += fills.size();
    if (ev.type == EventType::Cancel) {
      ++s.cancels;
      s.cancelHits += r.status == Status::Ok ? 1 : 0;
    } else if (r.status != Status::Ok) {
      ++s.rejects;
    } else {
      FlowStats& f = ev.type == EventType::Limit ? s.synthLimit
                     : ev.type == EventType::Market ? s.realMarket
                                                    : s.realIoc;
      ++f.orders;
      f.submitted += ev.qty;
      f.filled += r.filled;
      f.rested += r.rested;
      f.discarded += r.discarded;
    }
    onFills(ev, fills);
  }
  return s;
}

}  // namespace tickscope

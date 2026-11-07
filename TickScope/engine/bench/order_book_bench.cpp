// Microbenchmarks for single book operations. Templated on the book type so v2 (Phase 6)
// runs the exact same code. End-to-end throughput/latency on real flow is in tickscope_replay.

#include <benchmark/benchmark.h>

#include <memory>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/order_book_v2.hpp"
#include "tickscope/replay.hpp"
#include "tickscope/rng.hpp"

namespace {

using namespace tickscope;

constexpr PriceTicks kMid = 7'600'000;  // ~76,000 USDT

// Book with `levels` price levels per side, 4 orders each, away from the touch.
template <class Book>
void prefill(Book& book, std::int64_t levels, OrderId& nextId, std::vector<Fill>& fills) {
  for (std::int64_t l = 1; l <= levels; ++l) {
    for (int k = 0; k < 4; ++k) {
      book.addLimit(nextId++, Side::Buy, kMid - 10 - l, 100, 0, fills);
      book.addLimit(nextId++, Side::Sell, kMid + 10 + l, 100, 0, fills);
    }
  }
}

// Add a non-crossing limit inside the existing depth, then cancel it.
template <class Book>
void BM_AddCancel(benchmark::State& state) {
  Book book;
  std::vector<Fill> fills;
  OrderId id = 1;
  prefill(book, state.range(0), id, fills);
  Rng rng(1);
  for (auto _ : state) {
    const PriceTicks px = kMid - 10 - rng.uniformInt(1, state.range(0));
    const OrderId oid = id++;
    benchmark::DoNotOptimize(book.addLimit(oid, Side::Buy, px, 100, 0, fills));
    benchmark::DoNotOptimize(book.cancel(oid));
  }
  state.SetItemsProcessed(state.iterations() * 2);
}

// Rest one order at the touch, then take it with a market order (one full fill).
template <class Book>
void BM_AddAndFill(benchmark::State& state) {
  Book book;
  std::vector<Fill> fills;
  fills.reserve(64);
  OrderId id = 1;
  prefill(book, state.range(0), id, fills);
  for (auto _ : state) {
    fills.clear();
    book.addLimit(id++, Side::Sell, kMid, 100, 0, fills);
    benchmark::DoNotOptimize(book.addMarket(id++, Side::Buy, 100, 0, fills));
  }
  state.SetItemsProcessed(state.iterations() * 2);
}

// Synthetic end-to-end stream (random-walk price, random takers): replay throughput.
std::vector<Event> syntheticStream() {
  Rng rng(7);
  std::vector<PricePoint> prices;
  std::vector<TakerTrade> trades;
  PriceTicks px = kMid;
  for (std::int64_t sec = 0; sec < 3'600; ++sec) {
    px += rng.uniformInt(-20, 20);
    prices.push_back({sec, px});
    for (int k = 0; k < 50; ++k) {
      const Side side = rng.bernoulli(0.5) ? Side::Buy : Side::Sell;
      trades.push_back({static_cast<std::uint64_t>(trades.size() + 1), sec * 1'000'000 + k * 10'000, side, px,
                        static_cast<QtyLots>(rng.uniformInt(1, 500))});
    }
  }
  return buildStream(prices, trades, GeneratorConfig{});
}

template <class Book>
void BM_ReplaySynthetic(benchmark::State& state) {
  static const std::vector<Event> events = syntheticStream();
  for (auto _ : state) {
    state.PauseTiming();  // book construction/destruction is not what we measure
    auto book = std::make_unique<Book>();
    state.ResumeTiming();
    auto s = replay(*book, events, [](const Event&, const std::vector<Fill>&) {});
    benchmark::DoNotOptimize(s.fills);
    state.PauseTiming();
    book.reset();
    state.ResumeTiming();
  }
  state.SetItemsProcessed(state.iterations() * static_cast<std::int64_t>(events.size()));
}

BENCHMARK(BM_AddCancel<OrderBook>)->Name("v1/AddCancel")->Arg(10)->Arg(1000);
BENCHMARK(BM_AddCancel<OrderBookV2>)->Name("v2/AddCancel")->Arg(10)->Arg(1000);
BENCHMARK(BM_AddAndFill<OrderBook>)->Name("v1/AddAndFill")->Arg(10)->Arg(1000);
BENCHMARK(BM_AddAndFill<OrderBookV2>)->Name("v2/AddAndFill")->Arg(10)->Arg(1000);
BENCHMARK(BM_ReplaySynthetic<OrderBook>)->Name("v1/ReplaySynthetic")->Unit(benchmark::kMillisecond);
BENCHMARK(BM_ReplaySynthetic<OrderBookV2>)->Name("v2/ReplaySynthetic")->Unit(benchmark::kMillisecond);

}  // namespace

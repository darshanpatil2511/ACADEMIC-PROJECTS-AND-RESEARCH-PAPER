// Placeholder so the benchmark target builds in Phase 0.
// Real order-book benchmarks replace this in Phase 5.
#include <benchmark/benchmark.h>

#include "tickscope/types.hpp"

static void BM_TickConversion(benchmark::State& state) {
  tickscope::PriceTicks p = 0;
  for (auto _ : state) {
    p += 100 * tickscope::kTicksPerUsdt;
    benchmark::DoNotOptimize(p);
  }
}
BENCHMARK(BM_TickConversion);

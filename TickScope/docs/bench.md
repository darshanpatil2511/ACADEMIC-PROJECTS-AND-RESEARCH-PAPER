# TickScope — Benchmark log

Every number here was printed by a real run. Raw JSON for each run is in `results/`.
Resume and README figures are copied from this file, never rounded up.

## Machine
- Apple M2 (8 cores: 4 performance + 4 efficiency), 8 GB RAM, macOS 27.0.1
- Apple clang 21.0.0, Release build (`-O3 -DNDEBUG`, CMake default), no `-mcpu=native`
- Laptop on power; other apps (VS Code) open — load average 2.3–5.4 during runs
- No core pinning: macOS does not allow it (Google Benchmark warns "Failed to set thread affinity")

---

## 2026-11-07 — Engine v1 (`std::map` + `std::list`), end-to-end replay

**Input:** Binance BTCUSDT 2026-11-05: 4,929,786 real taker trades replayed as market
(20%) / IOC (80%, limit = real price ± 0.50 USDT) orders, plus seeded synthetic makers
(seed 42, 25 limit orders per side per second, lognormal sizes median 0.002 BTC,
1 + geometric offset with mean 5 ticks, random cancels with 30 s mean lifetime).

**Stream:** 13,568,286 events — limit 31.8%, market 7.3%, IOC 29.1%, cancel 31.8%.

**Method:** load and build the stream once; 1 warm-up replay; 5 throughput runs (no
per-op timing, fresh book each run, book destruction outside the timed region); 5 latency
runs (each op timed with `steady_clock`); medians reported.

Command: `./build-rel/tickscope_replay --prices data/prices.csv --trades data/trades.csv --reps 5 --json results/bench_v1.json`

### Throughput
| Run | Seconds | Events/s |
|---|---|---|
| 1 | 0.459 | 29,569,866 |
| 2 | 0.460 | 29,525,816 |
| 3 | 0.483 | 28,106,914 |
| 4 | 0.476 | 28,500,110 |
| 5 | 0.461 | 29,456,249 |
| **Median** | | **29,456,249** (~34 ns/event average) |

### Per-operation latency (ns, median across 5 runs)

**Read this first:** on Apple Silicon `steady_clock` ticks every **41 ns** (24 MHz
counter); measured resolution 41.0 ns, back-to-back `now()` pair p50 0 ns. Any value
below ~41 ns is "under one tick", so **p50 is not measurable here** — the 0/41/42 values
are quantization. p99 and above are meaningful. Values include up to one tick of timer
error.

| Op | Count | p50 | p99 | p99.9 | Max |
|---|---|---|---|---|---|
| limit_rest (no fill) | 3,450,456 | <41 | 125 | 167 | 67,500 |
| limit_cross (fills) | 869,544 | <41 | 417 | 1,083 | 63,042 |
| market | 984,430 | <41 | 375 | 1,791 | 46,583 |
| ioc | 3,945,356 | <41 | 208 | 1,083 | 64,292 |
| cancel_hit | 1,242,509 | <41 | 125 | 166 | 32,958 |
| cancel_miss | 3,075,991 | <41 | 42 | 42 | 49,292 |

Max values (33–68 µs) are single outliers consistent with OS preemption/page faults on a
non-isolated laptop core; not representative of the engine.

### Microbenchmarks (Google Benchmark, 5 repetitions, median)
Command: `./build-rel/bench/tickscope_bench --benchmark_repetitions=5 --benchmark_report_aggregates_only=true`

| Benchmark | Time/iter | Items/s |
|---|---|---|
| AddCancel, 10 levels/side | 61.6 ns (add + cancel) | 32.5M ops/s |
| AddCancel, 1,000 levels/side | 83.8 ns | 23.9M ops/s |
| AddAndFill, 10 levels/side | 83.8 ns (add + market fill) | 23.9M ops/s |
| AddAndFill, 1,000 levels/side | 82.9 ns | 24.1M ops/s |
| ReplaySynthetic (1 h random walk, ~537k events) | 22.0 ms | 24.4M events/s |

AddCancel slows from 61.6 to 83.8 ns as depth grows from 10 to 1,000 levels: the
O(log L) `std::map` lookup on insert is the depth-sensitive part.

### Simulation outcome (same stream, `--fills data/fills.csv`)
6,406,577 fills (403 MB CSV). Fill rate by quantity: real market orders 53.38%, real
IOC 27.60%, synthetic limits (as takers) 19.13%. Cancels found a resting order 28.8% of
the time (the rest raced a fill). 385 orders resting at end of day (72 bid levels, 47 ask
levels): the synthetic book is thin relative to the heavy-tailed real flow (p99 trade
13,127 lots, max 7,190,419 lots = 71.9 BTC), so large orders sweep it.

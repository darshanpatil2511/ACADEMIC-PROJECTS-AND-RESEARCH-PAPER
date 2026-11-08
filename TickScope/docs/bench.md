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

---

## 2026-11-07 — Engine v1 vs v2 (flat array + pool), same stream, same machine

v2 = flat price-level array over a 65,536-tick band with a two-level bitmap, out-of-band
fallback `std::map` with recentering, preallocated order pool with free list, intrusive
per-level FIFO, open-addressing id map. Same build (`-O3 -DNDEBUG`), same seeded stream,
same method as above (1 warm-up, 5 throughput + 5 latency runs per engine, medians).

**Correctness gate before timing:** both engines replay the full stream untimed and every
fill is hashed (FNV-1a over all fields, in order). Both scenarios: **identical** fill
streams (shallow: 6,406,577 fills, hash `5814cc944bcf593f`; deep: 11,230,290 fills, hash
`d1e1038c4610b475`).

### Scenario "shallow-default" (generator defaults, as in the v1 run above)
`--engine both --reps 5 --scenario shallow-default` → `results/bench_v1_v2_shallow.json`
Stream 13,568,286 events; book depth avg 385 orders / 91 levels (max 1,473 / 212).

| Engine | Throughput runs (events/s) | Median |
|---|---|---|
| v1 | 29,501,167 · 29,530,239 · 29,542,809 · 26,554,599 · 29,521,474 | 29,521,474 |
| v2 | 52,020,833 · 52,025,562 · 51,888,405 · 51,928,842 · 52,153,395 | **52,020,833** |
| | | **v2/v1 = 1.76×** |

### Scenario "deep" (`--adds-per-sec 50 --lifetime 600 --offset-mean 50`)
→ `results/bench_v1_v2_deep.json`. Stream 22,149,786 events; book depth avg 5,723 orders
/ 2,215 levels (max 22,626 / 4,335).

| Engine | Throughput runs (events/s) | Median |
|---|---|---|
| v1 | 22,286,167 · 22,410,346 · 22,523,029 · 22,441,247 · 22,262,666 | 22,410,346 |
| v2 | 49,800,409 · 49,798,534 · 49,373,969 · 49,375,758 · 49,090,230 | **49,375,758** |
| | | **v2/v1 = 2.20×** |

v1 loses 24% throughput going from the shallow to the deep book; v2 loses 5%.

### p99 latency (ns; 41 ns timer resolution — see the note in the v1 section)
| Op | v1 shallow | v2 shallow | v1 deep | v2 deep |
|---|---|---|---|---|
| limit_rest | 125 | 42 | 167 | 83 |
| limit_cross | 417 | 167 | 583 | 250 |
| market | 375 | 167 | 708 | 250 |
| ioc | 208 | 84 | 291 | 125 |
| cancel_hit | 125 | 42 | 209 | 125 |
| cancel_miss | 42 | 42 | 42 | 42 |

p99.9 (deep): market 3,208 → 1,208; limit_cross 1,625 → 625; ioc 1,833 → 667.
p50 is below timer resolution for both engines (reported as <41 ns).

### Microbenchmarks (Google Benchmark, 5 repetitions, median) → `results/microbench_v1_v2.json`
| Benchmark | v1 | v2 | Speedup |
|---|---|---|---|
| AddCancel, 10 levels/side | 61.3 ns | 18.5 ns | 3.3× |
| AddCancel, 1,000 levels/side | 84.7 ns | 19.0 ns | 4.5× |
| AddAndFill, 10 levels/side | 84.4 ns | 27.0 ns | 3.1× |
| AddAndFill, 1,000 levels/side | 84.2 ns | 27.5 ns | 3.1× |
| ReplaySynthetic (~537k events) | 21.9 ms | 11.9 ms | 1.8× |

v1 add+cancel cost grows with depth (61 → 85 ns, the O(log L) tree insert); v2 is flat
(18.5 → 19.0 ns): the level is an array index.

---

## 2026-11-07 — Two-thread pipeline (Phase 8): SPSC queue vs mutex vs single thread

Producer thread pushes the pre-built 13,568,286-event stream (Nov 5, defaults) into a
4,096-slot queue; the engine thread (v2) pops and matches. Busy-wait with a CPU pause hint
on both sides. 1 warm-up + 5 runs per mode. Every mode produced the same 6,406,577 fills.
Command: `./build-rel/tickscope_replay --engine v2 --pipeline 5 --pipeline-json results/pipeline.json`

| Mode | Runs (events/s) | Median |
|---|---|---|
| single thread (no queue) | 53,229,160 · 53,192,590 · 52,932,230 · 53,092,569 · 53,144,011 | 53,144,011 |
| SPSC lock-free, pop 1 | 37,011,882 · 36,923,964 · 36,848,818 · 36,936,835 · 37,244,891 | 36,936,835 |
| SPSC lock-free, batch pop 64 | 50,707,873 · 50,725,606 · 50,693,349 · 50,734,845 · 50,752,732 | 50,725,606 |
| mutex-protected ring, pop 1 | 6,749,097 · 6,739,722 · 6,856,645 · 6,857,976 · 7,080,739 | 6,856,645 |

- SPSC (pop 1) is **5.4×** the mutex queue; SPSC batch-64 is **7.4×**.
- Batching recovers the pipeline to **95%** of single-thread throughput.
- The pipeline does **not** beat one thread here: the producer only copies a pre-built
  event, so the queue hand-off is pure overhead. A second thread pays off when the producer
  does real work (network I/O, parsing) that would otherwise sit on the matching thread.

## 2026-11-07 — ThreadSanitizer and mutation results for the SPSC queue

- Correct code: all SPSC tests pass under TSan, 3 repeats at 10M items (local, Apple
  clang 21) and 3 repeats at 1M items in CI (Linux).
- Planted "publish index before writing slot": **caught** by the lockstep handoff test
  (stale slot read), after the 10M streaming tests had **missed** it (a later release of
  the index orders the earlier write, so TSan saw no race in that interleaving).
- Planted `release`→`relaxed` on the producer's publish, or `acquire`→`relaxed` on the
  consumer's load: **not caught** by the tests or by TSan on this toolchain. Memory-order
  weakening needs a model checker (e.g. GenMC, CDSChecker) to prove; documented as a limit.

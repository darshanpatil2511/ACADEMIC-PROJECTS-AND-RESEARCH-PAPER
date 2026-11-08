# TickScope — Design notes and interview prep

One section per phase: what was built, why, complexity, and the questions to expect.

## Phase 0 — Bootstrap and CI

**What exists:** a CMake project for the engine (GoogleTest + Google Benchmark via
FetchContent), an sbt project for analytics (Spark 3.5, ScalaTest), and a path-filtered
GitHub Actions workflow.

**Decisions to be able to explain**

1. **Why prices and quantities are int64, not double.**
   0.1 + 0.2 ≠ 0.3 in binary floating point. In a matching engine, a "fully filled" order
   left with 1e-17 BTC never leaves the book, and two prices that should be equal compare
   unequal, which breaks price-level lookup. Ticks (0.01 USDT) and lots (1e-5 BTC) are
   exact, compare in one instruction, and hash cleanly. int64 has headroom: 100,000 USDT is
   10M ticks; int64 holds 9.2e18.

2. **Why FetchContent with pinned release tarballs.**
   Anyone can clone and build with only CMake and a compiler; versions are pinned, so builds
   are reproducible. Tarballs download faster than git clones, and CI caches `_deps`.

3. **Why sanitizers in Debug and in CI.**
   ASan catches use-after-free and out-of-bounds (the classic risk with stored list
   iterators and pools). UBSan catches signed overflow and misaligned access. Running them
   on every push means memory bugs fail the build instead of corrupting benchmarks.
   Sanitizer flags apply only to project targets, not to third-party code.

4. **Why Spark needs `--add-opens` on Java 17.**
   Java 9+ modules block reflective access to JDK internals; Spark 3.5 uses that access
   (e.g. for off-heap memory via `sun.nio.ch`). Tests fork a JVM so the flags apply.

5. **Why benchmarks don't run in CI.**
   Shared runners have noisy neighbours and variable CPUs, so timings are not comparable
   run to run. CI only checks the benchmark binary compiles.

**Likely questions:** int vs double for prices; what ASan/UBSan/TSan each catch and why
ASan and TSan can't be combined; how path filters keep a monorepo's CI fast.

## Phase 1 — Download, ingest, clean

**What exists**
- `scripts/download.sh N [END_DATE]`: fetches N days of BTCUSDT spot trades, verifies each
  zip's SHA-256 against Binance's `.CHECKSUM`, stores the CSV re-compressed as `.csv.gz`,
  skips days already present, and writes via a temp name so a killed run leaves no
  truncated file.
- `IngestJob`: raw CSVs → `data/clean/date=YYYY-MM-DD/*.parquet` + `_ingest_report.json`.
- `ExportTrades`: cleaned Parquet → `data/trades.csv` (tradeId, tsUs, taker side,
  priceTicks, qtyLots) for the C++ replay driver.

**First real run** (Apple M2, 8 GB, 7 days 2026-10-30 → 2026-11-05, single run):
22,520,393 trades read, 22,520,393 kept, 0 dropped for every reason; 240.9 s;
153 MB gzip in → 287 MB Parquet out. Binance's published files are already clean; the
fixture test is what proves each rule works.

**Decisions to be able to explain**

1. **Explicit schema, decimals for price/qty.** Schema inference reads the data twice and
   guesses types. Reading `price`/`qty` as `Decimal(20,8)` makes `price × 100` exact, so
   `priceTicks` is exact; converting through double could turn 80000.01 into 8000000.999…
   and truncate to the wrong tick.

2. **Timestamp units.** Files carry 16-digit microsecond timestamps; older files used
   13-digit milliseconds. Anything below 1e14 is treated as ms and multiplied by 1000
   (ms values today are ~1.7e12, µs ~1.7e15, so there is no overlap).

3. **Rejection order and why each stage runs on the survivors.** Row-local checks first
   (no shuffle), then duplicates, then timestamp order. Checking order only on unique,
   valid rows means one bad row is counted once, under its first reason.

4. **Which steps shuffle.** Row checks: none (narrow). Duplicates: `row_number` over
   `partitionBy(tradeId)` → hash shuffle by tradeId. Backwards timestamps: `lag` over
   `partitionBy(date).orderBy(tradeId)` → shuffle by date + sort within each date. Writing
   `partitionBy("date")` does not shuffle; each task writes the dates it holds. The window
   is per date, not global, to avoid a single-partition global sort.

5. **"Backwards" means strictly earlier.** Many trades share a timestamp (one aggressive
   order filling several resting orders), so equal timestamps are normal. Limitation:
   comparing with the previous row means a single far-future timestamp makes the *next*
   row look backwards instead of itself. Fine for this data (0 cases); a robust version
   would compare with a rolling median.

6. **Why persist the raw scan.** The classification unions three branches that all start
   from the raw rows; without `persist`, Spark would decompress and parse the gzip files
   three times. The classified frame is persisted too because two actions use it (counts
   and the Parquet write).

7. **Why gzip, and its cost.** Disk is limited (raw CSV is ~357 MB/day; gzip ~35 MB).
   Gzip is not splittable, so each day file is read by exactly one task: parallelism of
   the first stage = number of days. This is one reason Phase 9 compares CSV against
   Parquet (splittable, columnar, compressed per column).

8. **Taker side.** `isBuyerMaker = true` means the resting order was the buy, so the
   aggressor sold: side `S`. This is what turns real trades into replayable taker orders.

**Likely questions:** why not `dropDuplicates` (it keeps an arbitrary row; `row_number`
ordered by time is deterministic); narrow vs wide transformations; why gzip limits
parallelism; how `partitionBy` on write lays out directories and enables pruning later.

## Phase 4 — Order book v1

**What exists:** `OrderBook` (`include/tickscope/order_book.hpp`, `src/order_book.cpp`) with
`addLimit`, `addMarket`, `addIoc`, `cancel`, `amend`, `bestBid`, `bestAsk`; 21 unit tests (each now run on both books)
and a differential test against a naive reference book (3 seeds × 20,000 random ops,
every report, fill and best price compared after each op). All pass under ASan + UBSan.
A deliberately planted FIFO bug was caught by the differential test within 33–42 ops.

**Data structures and memory layout**
```
bids_: std::map<price, Level, greater>   asks_: std::map<price, Level, less>
          │ red-black tree node per price level (heap-allocated)
          ▼
Level { std::list<Order> orders; int64 total; }
          │ doubly linked list node per order (heap-allocated)
          ▼
Order { id, side, price, qty, ts }

index_: std::unordered_map<OrderId, Locator{list iterator, Level*}>
```
Every level and every order is a separate heap node, so walking the book is pointer
chasing with poor cache locality. That is the cost Phase 6 removes.

**Complexity** (L = levels on a side, F = fills produced)

| Operation | Cost | Why |
|---|---|---|
| bestBid / bestAsk | O(1) | `begin()` of a map (cached leftmost node) |
| addLimit, no cross | O(log L) | map lookup/insert of the level; list push_back O(1) |
| addLimit / IOC / market that trades | O(F + log L) | each fill O(1); emptied levels erased O(1) amortized from begin() |
| cancel | O(1) avg | hash lookup + list unlink; + O(log L) only if the level empties |
| amend, qty down same price | O(1) avg | edit in place, keep priority |
| amend, price change / qty up | cancel + addLimit | loses priority |

**Decisions to be able to explain**

1. **Why `std::map` for levels.** Sorted, so the best price is `begin()`, and a sweep walks
   levels in price order. Insert/erase of a level is O(log L). A sorted vector would give
   better locality but O(L) inserts in the middle.

2. **Why `std::list` per level and storing its iterator.** Price-time priority needs FIFO
   at each price plus removal from the middle (cancels). A list gives O(1) push_back,
   pop_front and erase-by-iterator, and its iterators stay valid until *that* node is
   erased — inserting or erasing other nodes never invalidates them. A `std::vector` or
   `std::deque` would invalidate stored positions on erase.

3. **Why `Level*` is safe to store.** `std::map` is node-based: inserting or erasing other
   levels never moves an existing node, so a pointer to a level's value stays valid until
   that level is erased. The book erases a level only when it is empty, and an empty level
   has no orders in `index_` pointing at it.

4. **One matching loop for both sides.** `match` is a template over the ladder type; the
   ladder's own comparator answers "does this level cross?" as `!comp(takerPrice, level)`
   (asks: level ≤ limit; bids: level ≥ limit). A market order is a limit at INT64_MAX
   (buy) or INT64_MIN (sell) that never rests. No duplicated buy/sell code.

5. **Fills at the maker's price.** The resting order set the price; an aggressive buyer
   at 105 against an ask at 100 trades at 100 (price improvement for the taker).

6. **Amend rules.** Reducing size keeps queue priority (it cannot hurt anyone queued
   behind). Increasing size or changing price is treated as a new order and goes to the
   back of the queue — otherwise traders could reserve a queue spot with a tiny order and
   enlarge it later. A price amend can cross and trade immediately.

7. **What happens when a market order exceeds liquidity.** It sweeps every level on the
   opposite side, then the remainder is discarded and reported (`discarded`), never
   rested — a resting market order would have no price. Real venues often add price
   protection bands; listed as a limitation.

8. **Fills into a caller-owned vector.** Avoids allocating a new container per order on
   the hot path; the caller can `clear()` and reuse capacity.

9. **Differential testing.** A 150-line brute-force book (linear scans, explicit sequence
   numbers for time priority) is easy to verify by reading. Random streams in a narrow
   price band force crosses, partials, multi-level sweeps, cancels of filled ids and
   amends. Any divergence fails with the exact op number. Phase 6 reuses it for v2.

**Limitations:** single instrument; no FOK, stop or iceberg orders; no self-trade
prevention; ids may be reused once an order leaves the book; no price bands.

**Likely questions:** why cancel is O(1) and when it is not (level empties → map erase);
what invalidates `std::list` iterators (only erasing that node); why `std::map` iterators
and node pointers survive other inserts; what a crossed book is and why it can never
persist here (an incoming order matches until it no longer crosses, and only then rests).

## Phase 2 — Feature engine

**What exists:** `Bars.compute(trades, intervalSec, volWindow)` (1m and 5m bars: OHLCV,
VWAP, trade count, buy/sell volume, imbalance, log return, rolling realized volatility),
`Prices.lastPricePerSecond` (1-second path, gaps forward-filled), and `FeatureJob` which
writes `data/features/bars_{1m,5m}` (Parquet by date) and `data/prices.csv`. 8
known-answer tests on a hand-built tape; the job also checks invariants on every run.

**First real run** (7 days, single run, 20.3 s): 10,080 1m bars (= 7 × 1,440, no missing
minute), 2,016 5m bars; all 22,520,393 trades accounted for; VWAP inside [low, high] for
every bar; 604,800 rows in `prices.csv`.

**Decisions to be able to explain**

1. **Bar bucketing.** `floor(tsUs / width) * width` gives the bar start; integer maths on
   microseconds, no timestamp/timezone conversions on the hot column.

2. **Open/close by `tradeId`, not timestamp.** Many trades share a microsecond (one taker
   filling several makers), so "first by time" is ambiguous. `min_by(price, tradeId)` /
   `max_by(price, tradeId)` use the exchange's sequence, which is a total order. The test
   tape has two same-timestamp pairs to pin this down.

3. **VWAP = Σ(price·qty) / Σqty**, the average price paid per unit traded. It always lies
   within [low, high] (checked on every run). Benchmarks for execution quality (Phase 7)
   are measured against it.

4. **Imbalance = (buyVol − sellVol) / (buyVol + sellVol)**, using the *taker* side, in
   [−1, 1]. Taker side comes from `isBuyerMaker` (true → taker sold).

5. **Which steps shuffle.**
   - `groupBy(barStart).agg(...)`: one hash shuffle by bar. Spark first aggregates within
     each partition (partial aggregation), so each partition sends one row per bar, not
     one row per trade — 22.5M trades shrink to ~10k rows before the network.
   - `lag` and the rolling window run *on the bars*. Their window has no partition key,
     so all bars move to one partition (Spark warns about this). Acceptable on 10k rows;
     it would be a bug on raw trades. Partitioning by date would avoid it but would lose
     the return across midnight.
   - The price path joins every second in range to the per-second last price, then
     forward-fills with `last(..., ignoreNulls)` — again on small data (86,400 rows/day).
   - `cache()` on the trades: three outputs (1m, 5m, prices) read the same input.

6. **Log returns and realized volatility.** Log returns add over time
   (r₁ + r₂ = ln(P₂/P₀)), so multi-bar returns are sums. Realized volatility over a window
   is √Σr², the standard estimator when the mean return is ≈ 0 at short horizons; null
   until the window is full. Not annualized (multiply by √(bars per year) to annualize).

7. **Missing bars.** A minute with no trades produces no bar; the next bar's return spans
   the gap. On this data there were none (10,080 = 7 × 1,440). The price path, by
   contrast, forward-fills so the C++ replay always has a reference price.

8. **Doubles here, integers in the engine.** Research maths (logs, ratios) needs floating
   point; exact matching does not. The price path is exported in integer ticks.

**Likely questions:** what partial aggregation does to shuffle size; why a window without
`partitionBy` is dangerous on big data; VWAP vs TWAP; why log returns and not simple
returns; what realized volatility estimates.

## Phase 5 — Replay driver, fills, benchmark v1

**What exists**
- `Rng` (`rng.hpp`): xoshiro256** + hand-written uniform/normal/lognormal/geometric.
- `parsePrices` / `parseTrades` (`market_data.cpp`): `std::from_chars` CSV parsing with
  line-numbered errors.
- `buildStream` (`generator.cpp`): real taker flow + seeded synthetic makers → one
  time-ordered vector of 40-byte `Event`s.
- `replay` / `apply` (`replay.hpp`): templates over the book type, so v2 reuses them.
- `tickscope_replay`: writes `data/fills.csv`, prints flow stats, runs the benchmark.
- `tickscope_bench`: Google Benchmark microbenchmarks (add+cancel, add+fill, synthetic replay).
- 7 new tests (parsing, RNG moments, generator determinism/ordering/pricing, quantity
  conservation in replay). Results in `docs/bench.md`.

**Headline (v1, Nov 5 flow, 13.6M events):** 29.5M events/s median throughput; p99
125 ns to rest a limit or cancel, 208–417 ns for orders that trade.

**Decisions to be able to explain**

1. **Replay model.** Real trades are the aggressive side: `isBuyerMaker` gives the taker
   side, so each trade becomes a market order (20%) or an IOC limited to the real price
   ± 0.50 USDT (80%). Makers are synthetic: each second they quote around the *previous*
   second's price (no look-ahead) with random sizes and distances, and cancel at random.
   So the results describe "a simulated book absorbing real order flow".

2. **Open-loop generator.** The stream is built before the replay and does not react to
   fills. That makes it identical for v1 and v2 (fair benchmark) and separates generation
   cost from engine cost. Consequence: some cancels target already-filled orders (71% on
   this run) — the engine reports a miss, like a real cancel/fill race.

3. **Own RNG and distributions.** `std::*_distribution` algorithms are implementation-
   defined, so the same seed gives different streams on macOS (libc++) and Linux
   (libstdc++). Writing them by hand (Box-Muller, inverse-CDF geometric) makes the seeded
   stream identical everywhere.

4. **Throughput vs latency runs are separate.** Timing every op adds two clock reads per
   op and perturbs the thing measured; throughput runs time only the whole replay.
   Fresh book per run, destroyed outside the timed region; one warm-up run first.

5. **Timer resolution.** Apple Silicon's `steady_clock` is a 24 MHz counter: 41.67 ns per
   tick. Most ops finish within one tick, so p50 reads 0 or 41 — quantization, not a
   measurement. We report it as "<41 ns" and rely on p99/p99.9. On x86 Linux, `rdtsc` or
   `clock_gettime` gives ~ns resolution; batched timing (time N ops, divide) is the other
   fix, but it averages away tail latency.

6. **Percentiles, not means.** Latency distributions are skewed; the mean hides the tail
   that matters for a trading system. p99.9 and max show preemption outliers (33–68 µs
   max on a non-isolated laptop core).

7. **Fills into a reused vector, CSV via `to_chars`.** No allocation per event on the hot
   path; output formatting avoids `printf` format parsing per field. Writing 6.4M fills
   costs ~0.75 s on top of the ~0.46 s replay.

8. **What the microbenchmarks show.** Add+cancel goes from 61.6 ns at 10 levels to 83.8 ns
   at 1,000 levels per side: `std::map` insert is O(log L) and each tree level is a
   pointer dereference into a separately allocated node (cache miss risk). That is the
   target for Phase 6.

**Simulation outcome:** market orders filled 53.4% by quantity, IOC 27.6%; the book is thin
(385 orders at end of day) relative to heavy-tailed real flow (max trade 71.9 BTC). The
generator parameters are CLI flags (`--adds-per-sec`, `--size-median`, `--lifetime`, ...)
for sensitivity runs.

**Likely questions:** why the stream is pre-generated; how you measured latency and what
the timer resolution means; why p99 not mean; what "29.5M events/s" includes (matching,
cancels, fill vector writes; not parsing or I/O); what a cancel/fill race is.

## Phase 6 — Order book v2 (optimization pass)

**What exists:** `OrderBookV2` (`order_book_v2.hpp/.cpp`) with the same interface and
identical results as v1; `IdMap` and `LevelBitmap` (`flat_structures.hpp`). The 21 book
tests are now typed tests run on both books; differential tests run v2 against the
reference (normal and tiny-band/drifting modes); v2-specific tests cover the id map
(vs `std::unordered_map`), the bitmap (vs `std::set`), pool reuse, the fallback and
recentering; the replay binary refuses to report a speedup unless v1 and v2 fill streams
hash identically. 62 tests total, all under ASan/UBSan.

**Headline:** 52.0M vs 29.5M events/s (**1.76×**) on the default stream; **2.20×** on a
deep book (avg 2,215 levels), where v1 drops 24% and v2 only 5%. Add+cancel 61–85 ns → 19 ns.

**Memory layout, v1 vs v2**
```
v1: map node ─► Level ─► list node ─► list node ─► ...    (every box: separate malloc)
    unordered_map bucket ─► node {id, list iterator}       (another malloc per order)

v2: levels_[price - base]   contiguous array, 24 B per level, 65,536 per side
    bitmap words_ + summary_ one bit per level, one bit per 64 levels
    nodes_[i]               contiguous pool, 48 B per order; prev/next are uint32 indices
    IdMap slots_[]          contiguous, 16 B per slot, load factor <= 0.5
```

**Where v1 spent its time and what v2 changed**

1. **Allocation per order.** v1 does a `malloc` for each list node and each hash node, and
   a `free` when it leaves. v2 takes nodes from a preallocated pool and returns them to a
   free list threaded through the same `next` field: two loads and a store. Test: 100k
   add/cancel cycles use exactly one pool node.

2. **Pointer chasing.** Reaching a level in v1 walks a red-black tree: ~log2(L)
   dependent loads to scattered nodes, each a likely cache miss (11 levels deep at 2,000
   levels). In v2 it is `levels_[price - base]`: one address computation. That is why
   v1's add+cancel grows with depth (61 → 85 ns) and v2's does not (18.5 → 19.0 ns).

3. **Finding the next best level.** v1: `begin()` of the map (cached, O(1)), but erasing
   the emptied level rebalances the tree. v2: the bitmap; `highest()`/`lowest()` read at
   most N/4096 summary words (16 for N = 65,536) and one word, using `countl_zero` /
   `countr_zero` (single instructions). Erasing a level is clearing a bit.

4. **Hash map.** `std::unordered_map` is a vector of buckets pointing to linked nodes.
   `IdMap` is one array; lookup = multiply-shift hash + short linear scan, usually in one
   cache line. Deletion by backward shift keeps probe runs short forever (tombstones would
   accumulate under add/cancel churn).

5. **Indices instead of pointers.** 32-bit indices halve link size versus pointers and stay
   valid if the pool vector grows (pointers would dangle on reallocation).

**The bounded band, and the two edge cases interviewers ask about**

- BTC is ~7.6M ticks from zero, and moved ~440k ticks on 2026-11-05, so one array cannot
  cover every price. The band is 65,536 ticks ($655) per side; outside it, levels live in
  a fallback `std::map`.
- **Out-of-band orders** go to the fallback. Matching takes the better of "best in band"
  and "best in fallback", so they trade in correct price-time order.
- **Recentering:** when an out-of-band order would become the best price on its side (the
  market has moved), the band recenters on it: band levels move to the fallback if they
  fall outside, fallback levels move into the array if they fall inside. Levels are moved
  by value; orders point to pool indices, never to level addresses, so nothing else
  changes. Cost O(levels moved), rare (BTC needs to move $327 from the centre).

**Testing story (good to tell):** mutation testing found a gap. Breaking "pull fallback
levels into the band on recenter" left all 61 tests green: the random streams never
emptied a band side while fallback levels sat just outside it. A targeted test for that
sequence now fails (UBSan null-reference) when the bug is planted. Lesson: random
differential testing is strong but not exhaustive; mutation testing shows what it misses.

**Trade-offs and limitations**
- Fixed memory per side: 65,536 × 24 B = 1.5 MB of levels + 8 KB bitmap, whether used or
  not. Fine for one instrument; for thousands of instruments you would size bands per
  instrument or use a sparse structure.
- A pathological market that oscillates across the band edge would recenter often; a
  hysteresis margin would fix it.
- The pool still grows (vector doubling) if more orders rest than were reserved; growth
  is amortized and indices stay valid.

**Likely questions:** what exactly made v2 faster (allocations, pointer chasing, cache
lines); why indices not pointers; how the bitmap finds the best level; how you handle
prices outside the array; how you proved v2 is correct (typed tests, differential vs
reference, identical-fill hash on 13.6M and 22.1M real events, mutation testing).

## Phase 3 — Statistics report

**What exists:** `Stats` (moments, autocorrelation, predictive regression with naive and
Newey-West t-stats) and `StatsJob` → `reports/stats.md` + `results/stats.json`. Spark
aggregates and `lag`/`lead` windows only; the only collected rows are single aggregate
rows and the 7-row daily table. 5 tests check every Spark number against a plain-array
reference implementation (to 1e-9).

**Findings on 2026-10-30 → 2026-11-05 (10,079 one-minute returns):**
- Std dev of 1m log returns 5.59e-4 (~5.6 bp); skew −0.06; **excess kurtosis 11.47**;
  82 moves beyond 4σ where a normal distribution predicts ~0.6.
- Return autocorrelation lags 1–5: all within ±0.0195 except lag 2 (−0.0219, marginal;
  ~0.25 false positives expected from 5 tests). Absolute-return autocorrelation 0.31–0.36
  at every lag: **volatility clustering**.
- Imbalance(t) → return(t+1): r = 0.0208 (0.04% of variance), slope 0.24 bp per unit of
  imbalance, naive t = 2.09, **HAC t = 2.47 (11 lags)**: significant at 5%, economically tiny.

**Decisions to be able to explain**

1. **Fat tails / kurtosis.** Kurtosis measures tail weight relative to a normal. 11.47
   excess means extreme minutes happen orders of magnitude more often than a Gaussian
   model says (82 vs 0.6 beyond 4σ). VaR from a normal model understates risk; use
   empirical quantiles, Student-t, or EVT.

2. **Why the ±1.96/√n band.** Under no autocorrelation, the sample autocorrelation is
   approximately N(0, 1/n). Testing 5 lags at 5% each expects 0.25 false positives, so
   one marginal exceedance is weak evidence (multiple-testing caveat).

3. **Volatility clustering.** Returns are nearly uncorrelated, |returns| strongly
   correlated: direction is unpredictable, magnitude is predictable (the basis of GARCH).

4. **Why HAC (Newey-West).** OLS standard errors assume independent, equal-variance
   errors. Volatility clusters, so errors are heteroskedastic and possibly
   autocorrelated, and naive t-stats can be wrong in either direction. Newey-West
   estimates the long-run variance of (x − x̄)·e with Bartlett weights 1 − l/(L+1),
   L = ⌊4(n/100)^(2/9)⌋ = 11. Here HAC t (2.47) > naive t (2.09): the correction is not
   always conservative.

5. **Significant vs useful.** r² = 0.04% and 0.24 bp per unit imbalance is far below
   trading costs (BTC spread ~0.01 USDT ≈ 0.001 bp, but fees ~1–10 bp). Statistically
   detectable, not tradable at this horizon.

6. **No collect of the series.** `agg(...)` returns one row; `lag` windows run on
   ~10k bars (single partition, acceptable at bar level, not at trade level).

**Likely questions:** what kurtosis says about tail risk; what the imbalance correlation
showed and whether it was significant (yes at 5% with HAC, but tiny); why HAC; why ACF
of |r| differs from ACF of r.

## Phase 7 — Fill analytics

**What exists:** the replay writes `data/orders.csv` (one row per order with
filled/rested/discarded) next to `data/fills.csv`; `FillAnalytics` + `FillJob` compute fill
rates, slippage vs 1m VWAP, slippage vs the real Binance print, effective/realized spread
and price impact at 5 s and 60 s, and the fill-size distribution → section 5 of
`reports/stats.md` (replaced on each run) and `results/fills.json`. 6 tests on
hand-computed fixtures. 24.6 s on 6.4M fills / 9.2M orders.

**Cross-check:** Spark's fill rates (IOC 27.60%, market 53.38%, synthetic 19.13%) equal the
C++ engine's own counters — two independent implementations agree.

**Findings (simulated book vs real 2026-11-05 flow)**
- Market orders: 86.3% fully filled, 13.3% got nothing (book swept/empty).
- Slippage vs real print: IOC p99 0.015 bp (bounded by the ±0.50 USDT limit); market
  orders p99 6.9 bp — large orders walk the thin synthetic book.
- IOC and synthetic takers show *negative* effective spread and positive impact: makers
  quoting around the previous second's price get picked off when the price moves —
  adverse selection, the core risk a market maker manages.
- Fill sizes: median 24 lots (0.00024 BTC) but 100–9,999-lot fills carry 90% of volume.

**Decisions to be able to explain**

1. **Definitions.** d = +1 taker buy, −1 sell. Effective spread 2d(P − M0)/M0: what the
   taker paid versus the pre-trade reference. Realized spread 2d(P − Mh)/M0: what the maker
   kept after h seconds. Price impact = effective − realized: how far the price moved
   against the maker — information in the flow. Market makers care because realized
   spread minus fees is their P&L per unit traded.

2. **Reference price.** No quote (bid/ask) data in this dataset, so the mid is approximated
   by the last-trade price path, using the *previous* second to avoid look-ahead. Stated in
   the report as a limitation.

3. **Which joins shuffle.**
   - Fills/executions ⨝ 1m bars (10k rows) and ⨝ price path (605k rows, ~10 MB): broadcast
     joins — the small side is copied to every task, the 6.4M fills never move.
   - Executions ⨝ real trades on tradeId: both sides are millions of rows → sort-merge join
     (shuffle both by tradeId). The date filter on the partitioned Parquet prunes it to one
     day's directory before reading.
   - `groupBy(takerId)` to build per-order executions: hash shuffle by taker id.

4. **Ids above Long.MaxValue.** Real order ids have the top bit set, so they are read as
   `Decimal(20,0)` and the Binance tradeId is recovered by subtracting 2^63.

5. **Approximate quantiles.** `percentile_approx` (Greenwald-Khanna-style sketch) with
   accuracy 10,000 → relative rank error 1e-4; exact quantiles would need a full sort.

**Likely questions:** what slippage and realized spread measure and why a market maker
cares; broadcast vs sort-merge join and when Spark picks each; why the synthetic makers lost
money and how a real one would protect itself (faster requotes, wider spreads, skewing).

## Phase 8 — SPSC lock-free ring buffer and two-thread pipeline

**What exists:** `SpscQueue<T>` (`spsc_queue.hpp`), `MutexQueue<T>` baseline and
`runPipeline` (`pipeline.hpp`), `--pipeline` mode in `tickscope_replay`; 7 tests including
two 10M-item stress tests and a lockstep handoff test; a CI job running them under TSan.

**Headline:** SPSC is 5.4× a mutex queue (7.4× with batch pops); batch-64 pipeline reaches
95% of single-thread throughput; single thread still wins because the producer does no work.

**Design to be able to explain**

1. **Indices never wrap, buffer is a power of two.** `head`/`tail` are 64-bit counters
   that only increase; slot = index & (capacity − 1). Full is `tail − head == capacity`,
   empty is `tail == head`, so no slot is wasted and there is no modulo division.

2. **Acquire/release, exactly where needed.**
   - Producer: write slot → `tail.store(release)`. Release guarantees the slot write is
     visible to any thread that acquires that tail value.
   - Consumer: `tail.load(acquire)` → read slot. Acquire guarantees it sees the write.
   - Consumer: read slot → `head.store(release)`; producer: `head.load(acquire)` before
     reusing a slot, so it never overwrites data still being read.
   - Each thread reads its *own* index with `relaxed`: no other thread writes it.
   No `seq_cst` fences: on ARM, acquire/release compile to `ldar`/`stlr`, cheaper than full
   barriers.

3. **Cached opposite index.** The producer keeps a private copy of `head` and only reloads
   the shared one when its copy says "full" (consumer symmetric with `tail`). Most pushes
   then touch only producer-owned cache lines — fewer cross-core cache misses.

4. **False sharing and the 128-byte line.** Producer state and consumer state are on
   separate `alignas(128)` blocks. If `head` and `tail` shared a line, every push would
   invalidate the consumer's copy and vice versa (the line "ping-pongs" between cores)
   even though they never touch the same variable. Apple M-series lines are 128 bytes
   (`sysctl hw.cachelinesize`), x86 is 64 — padding to 64 would not be enough here.

5. **Batch pop.** `popBatch` reads up to N slots and publishes `head` once: one cache-line
   transfer per batch instead of per item. That is the 36.9M → 50.7M events/s jump.

6. **Busy-wait with a pause hint.** `yield` on ARM / `_mm_pause` on x86 inside spin loops:
   lower power, frees resources for a sibling hyper-thread, no context switch. Burns a core
   — acceptable for a latency-critical dedicated thread, not for a shared machine.

**Testing story (good to tell):** the streaming 10M stress tests passed even with a planted
"publish before writing the slot" bug — the producer runs ahead, and the *next* release of
`tail` happens to order the buggy write, so neither the value checks nor TSan saw a problem.
A lockstep handoff test (one item in flight, acknowledgement only consumer→producer) makes
each slot depend on its own release, and catches it. Weakening a single `release` or
`acquire` to `relaxed` was not caught by tests or TSan: memory-order bugs can hide from
dynamic tools; proving them needs model checking (GenMC/CDSChecker) or careful reasoning.

**Likely questions:** explain acquire/release on this queue line by line; what false sharing
is and how padding fixes it; why SPSC needs no CAS (each index has exactly one writer);
why the pipeline did not beat one thread; how you would extend to MPSC (CAS on tail, or
per-producer queues).

## Phase 9 — Spark benchmark, incremental ingestion, README

**What exists:** `SparkBench` (5 variants × 3 runs, scan metrics from Spark's own SQL
metrics, physical plans in `docs/spark-plans.md`), per-day incremental `IngestJob`, the
README. 30 days ingested: 84,744,597 trades, 0 dropped, 843 s, 1.0 GB Parquet.

**Headline:** partition-pruned Parquet is ≥31× faster than naive gzip CSV on the same
workload (31.1× and 52.2× in two sessions; the CSV baseline is the noisy side).

**Decisions to be able to explain**

1. **Why Parquet beats CSV.** Columnar: reads only the columns a query uses. Binary typed
   encoding: no text parsing per value. Per-column compression and encodings (dictionary,
   RLE). Splittable files with row groups; gzip CSV is one non-splittable stream per file.
   Footer statistics (min/max per row group) allow predicate pushdown.

2. **Partition pruning vs predicate pushdown.** Data is laid out as `date=YYYY-MM-DD/`
   directories. A filter on `date` becomes a `PartitionFilter`: resolved against directory
   names at planning time, so 23 of 30 directories are never listed or opened (7 files read).
   A filter on `tsUs` is a `PushedFilter`: Parquet must open every file's footer to check
   row-group statistics (30 files read). Both are visible in `docs/spark-plans.md`.

3. **Why caching made it slower.** `cache()` is lazy; the first action builds an in-memory
   columnar copy (~4 s here). It pays off only if that cost is amortized over many reuses,
   or if the source is expensive (remote storage, CSV parsing). Two queries over 7 local,
   compact Parquet files are faster read directly by the vectorized reader.

4. **Why `shuffle.partitions` did nothing.** Spark 3.x Adaptive Query Execution looks at
   real shuffle sizes after each stage and coalesces small partitions: the 200 configured
   partitions became 1 (metric: `AQEShuffleReadExec.partitionSpecs`). Manual tuning
   mattered before AQE was on by default (Spark 3.2).

5. **Incremental ingestion (a real failure).** The first 30-day ingest persisted all raw
   and classified rows at once and filled the laptop's disk with spill ("No space left on
   device"). Fix: process one day file per batch with dynamic partition overwrite
   (`partitionOverwriteMode=dynamic` replaces only that day's directory), serialized
   storage for the persisted frames. Peak resource use is now bounded by one day; reruns are
   idempotent per day; `--skip-existing` makes it incremental. Valid because Binance daily
   files do not overlap, so per-day duplicate/order checks lose nothing.

6. **Benchmark hygiene.** Same data and query for every variant; fresh SparkSession per
   run; `noop` sink so output I/O is not timed; medians of 3; scan facts from engine
   metrics, not from `inputFiles` (which lists every file in the table — an early version of
   the harness reported "30 files" for the pruned scan because of that, and was fixed).

**Likely questions:** which steps shuffle and how you reduced it; how partition pruning works
on this layout; why Parquet beats CSV; Dataset vs DataFrame (typed case classes for the
pipeline stages, untyped DataFrame operations where Spark functions like `min_by` and window
functions are clearer); what you would change on a cluster (S3 paths, `provided` Spark
dependency, executor sizing, more partitions per day).

## Phase 10 — Results dashboard

**What exists:** `dashboard/` (static HTML/CSS/JS, Chart.js 4.4.1 from a pinned CDN URL) that
loads every number from `results/*.json` at runtime; `DashboardExport` (5-minute bars and
the standardized return histogram), `tickscope_replay --snapshot` (engine depth ladder every
250 ms for the busiest minute of 2026-11-05, plus fills and the real price path);
`tickscope-pages.yml` deploys `dashboard/` + `results/` to GitHub Pages from `main`.

**Decisions to be able to explain**
1. **No numbers in the page source.** The page is a view over the JSON written by the
   engine and Spark jobs, so it cannot drift from the recorded runs (the one exception, the
   earlier-session Spark figure, is labelled as such).
2. **Static site, no build step.** Nothing to install or break; GitHub Pages serves files.
3. **Chart choices.** v1 drawn in gray and v2 in the accent color ("highlight one, gray the
   rest"); one y-axis per chart (price and volume are two charts, not a dual axis); log
   scales where values span orders of magnitude (Spark runtimes, histogram tails); the
   ±1.96/√n band as hairlines. Palette checked with a colour-vision-deficiency validator in
   light and dark mode.
4. **Replay from engine state, not a re-implementation.** The browser does not re-run the
   matcher; it plays frames the C++ engine recorded, so what you see is exactly what the
   engine did (including 33 frames where real flow swept one side of the synthetic book).
5. **Checked by rendering.** Headless Chrome screenshots at 1280 px (light and dark) and an
   emulated 390 px phone viewport (no page-level horizontal overflow); the Play button was
   clicked programmatically and the replay clock advanced with no page errors.

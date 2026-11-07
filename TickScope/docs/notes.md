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

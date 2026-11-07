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
`addLimit`, `addMarket`, `addIoc`, `cancel`, `amend`, `bestBid`, `bestAsk`; 23 unit tests
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

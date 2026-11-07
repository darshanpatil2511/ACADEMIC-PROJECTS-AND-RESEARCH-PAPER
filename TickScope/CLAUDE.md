# TickScope — rules for Claude Code

## Project
C++20 limit order book + matching engine (`engine/`) and Scala 2.13 / Spark 3.5
market-data analytics (`analytics/`), plus a static results dashboard (`dashboard/`).
Data: Binance BTCUSDT spot trade CSVs from data.binance.vision.
Full plan: `docs/PLAN.md`. Interview notes: `docs/notes.md`. Benchmarks: `docs/bench.md`.

## Repo
- TickScope lives inside the monorepo `ACADEMIC-PROJECTS-AND-RESEARCH-PAPER/`.
  Run git from the monorepo root; stage only `TickScope/` and
  `.github/workflows/tickscope-ci.yml`.
- Work on branch `tickscope`; merge to `main` at milestones.
- Never add AI co-author or attribution lines to commits or PRs.
- Keep everything company-neutral: no employer or target-company names anywhere.

## How we work
- Plan first, one phase at a time, stop after each phase for review.
- Claude writes all code, including the core (order book, matching, cancel,
  SPSC queue, bar/VWAP logic).
- After each phase, append to `docs/notes.md`: what was built, Big-O of each
  operation, memory layout, edge cases, and likely interview questions.
- Never invent numbers. Benchmarks, stats and dashboard data come only from
  real runs, recorded with date, machine, flags and data size.

## C++ conventions
- C++20, `-Wall -Wextra -Wpedantic -Werror` on project targets.
- Debug builds use ASan + UBSan (`-DTICKSCOPE_SANITIZE=ON`); TSan for concurrency.
- Benchmarks: Release `-O2`; `-O3 -mcpu=native` reported separately (Apple Silicon).
- No raw `new`/`delete`; RAII everywhere.
- Prices are int64 ticks (0.01 USDT), quantities are int64 lots (1e-5 BTC). Never double.
- Header-only templates live in `include/tickscope/`.

## Scala conventions
- Typed Datasets with case classes; no `var`s; small pure functions.
- Spark local mode; config via SparkSession builder and CLI args, no hardcoded paths.
- Tests and `run` fork a JVM with the `--add-opens` flags Spark needs on Java 17.

## Commands (run from TickScope/)
- Engine:  `cmake -S engine -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DTICKSCOPE_SANITIZE=ON && cmake --build build && ctest --test-dir build --output-on-failure`
- Bench:   `cmake -S engine -B build-rel -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-rel && ./build-rel/bench/tickscope_bench --benchmark_repetitions=5`
- Spark:   `cd analytics && sbt test` (forked JVM auto-uses Java 17: `$TICKSCOPE_JAVA_HOME` or Homebrew openjdk@17)

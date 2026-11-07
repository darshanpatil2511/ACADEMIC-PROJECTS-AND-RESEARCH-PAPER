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

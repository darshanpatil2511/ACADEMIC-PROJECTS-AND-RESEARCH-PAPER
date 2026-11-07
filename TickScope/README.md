# TickScope

A C++20 limit order book and matching engine replaying real Binance BTCUSDT trade flow,
plus a Scala/Apache Spark pipeline for market-data research.

> Work in progress. See [docs/PLAN.md](docs/PLAN.md) for the roadmap. Benchmarks and
> findings will appear here only once they come from real runs.

## Layout
| Path | What |
|---|---|
| `engine/` | C++20 order book, matching engine, tests (GoogleTest), benchmarks (Google Benchmark) |
| `analytics/` | Scala 2.13 / Spark 3.5 ingestion, features, statistics, fill analytics |
| `scripts/` | Data download |
| `docs/` | Plan, design notes, benchmark records |

## Quickstart

Requirements: CMake ≥ 3.24, Ninja, a C++20 compiler, Java 17, sbt.

```bash
# Engine: debug build with ASan/UBSan, run tests
cmake -S engine -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DTICKSCOPE_SANITIZE=ON
cmake --build build && ctest --test-dir build --output-on-failure

# Analytics
cd analytics && sbt test
```

## License
MIT

// tickscope_replay: replay real taker flow against a synthetic resting book.
//
//   tickscope_replay --prices data/prices.csv --trades data/trades.csv
//                    [--engine v1|v2|both] [--fills data/fills.csv] [--seed 42]
//                    [--reps 5] [--json out.json] [--scenario name]
//                    [--adds-per-sec 25] [--size-median 200] [--size-sigma 1.5]
//                    [--offset-mean 5] [--lifetime 30] [--market-share 0.2] [--ioc-tol 50]
//
// 1. Loads the price path and taker flow, builds the seeded event stream (once).
// 2. Verification: replays the stream through each selected engine and hashes every fill;
//    with --engine both the hashes must match. Prints flow and book-depth statistics.
// 3. With --fills: writes every fill (from the first selected engine) to CSV.
// 4. With --reps N, per engine: one warm-up, then N throughput runs (no per-op timing) and
//    N latency runs (each op timed with steady_clock), each on a fresh book; medians.

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/market_data.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/order_book_v2.hpp"
#include "tickscope/replay.hpp"

#ifndef TICKSCOPE_BUILD_INFO
#define TICKSCOPE_BUILD_INFO "unknown"
#endif

namespace {

using namespace tickscope;
using Clock = std::chrono::steady_clock;

double secondsSince(Clock::time_point t0) { return std::chrono::duration<double>(Clock::now() - t0).count(); }

std::map<std::string, std::string> parseArgs(int argc, char** argv) {
  std::map<std::string, std::string> out;
  for (int i = 1; i < argc; i += 2) {
    const std::string key = argv[i];
    if (key.rfind("--", 0) != 0 || i + 1 >= argc) throw std::invalid_argument("expected --key value pairs");
    out[key.substr(2)] = argv[i + 1];
  }
  return out;
}

const char* takerType(EventType t) {
  switch (t) {
    case EventType::Limit: return "synthetic_limit";
    case EventType::Market: return "real_market";
    case EventType::Ioc: return "real_ioc";
    case EventType::Cancel: return "cancel";
  }
  return "?";
}

// Buffered CSV writer for fills; to_chars avoids printf parsing per field.
class FillWriter {
 public:
  explicit FillWriter(const std::string& path) : f_(std::fopen(path.c_str(), "wb")) {
    if (!f_) throw std::runtime_error("cannot write " + path);
    buf_ = "tsUs,makerId,takerId,takerSide,priceTicks,qtyLots,takerType\n";
  }
  ~FillWriter() {
    flush();
    std::fclose(f_);
  }
  FillWriter(const FillWriter&) = delete;
  FillWriter& operator=(const FillWriter&) = delete;

  void write(const Event& ev, const std::vector<Fill>& fills) {
    for (const Fill& f : fills) {
      num(f.ts);
      num(f.makerId);
      num(f.takerId);
      buf_ += f.takerSide == Side::Buy ? "B," : "S,";
      num(f.price);
      num(f.qty);
      buf_ += takerType(ev.type);
      buf_ += '\n';
    }
    if (buf_.size() > (1 << 20)) flush();
  }

 private:
  template <class Int>
  void num(Int v) {
    std::array<char, 24> tmp{};
    const auto res = std::to_chars(tmp.data(), tmp.data() + tmp.size(), v);
    buf_.append(tmp.data(), res.ptr);
    buf_ += ',';
  }
  void flush() {
    std::fwrite(buf_.data(), 1, buf_.size(), f_);
    buf_.clear();
  }

  std::FILE* f_;
  std::string buf_;
};

void printFlow(const char* name, const FlowStats& f) {
  const double fillPct = f.submitted ? 100.0 * static_cast<double>(f.filled) / static_cast<double>(f.submitted) : 0;
  std::printf("    %-16s orders %10llu  qty %14lld  filled %6.2f%%  rested %14lld  discarded %14lld\n", name,
              static_cast<unsigned long long>(f.orders), static_cast<long long>(f.submitted), fillPct,
              static_cast<long long>(f.rested), static_cast<long long>(f.discarded));
}

// ---- Verification pass ----------------------------------------------------------------

struct Verification {
  std::uint64_t fillHash = 0;
  ReplayStats stats;
  double avgOrders = 0, avgLevels = 0;  // sampled every 1,000 events
  std::size_t maxOrders = 0, maxLevels = 0;
};

// FNV-1a over every field of every fill, in order.
template <class Book>
Verification verify(const std::vector<Event>& events, FillWriter* writer) {
  auto book = std::make_unique<Book>();
  Verification v;
  std::uint64_t h = 1469598103934665603ULL;
  auto mix = [&h](std::uint64_t x) {
    h ^= x;
    h *= 1099511628211ULL;
  };
  double sumOrders = 0, sumLevels = 0;
  std::size_t samples = 0, n = 0;
  v.stats = replay(*book, events, [&](const Event& ev, const std::vector<Fill>& fills) {
    for (const Fill& f : fills) {
      mix(static_cast<std::uint64_t>(f.ts));
      mix(f.makerId);
      mix(f.takerId);
      mix(static_cast<std::uint64_t>(f.takerSide));
      mix(static_cast<std::uint64_t>(f.price));
      mix(static_cast<std::uint64_t>(f.qty));
    }
    if (writer) writer->write(ev, fills);
    if (++n % 1000 == 0) {
      const std::size_t orders = book->orderCount();
      const std::size_t levels = book->levelCount(Side::Buy) + book->levelCount(Side::Sell);
      sumOrders += static_cast<double>(orders);
      sumLevels += static_cast<double>(levels);
      v.maxOrders = std::max(v.maxOrders, orders);
      v.maxLevels = std::max(v.maxLevels, levels);
      ++samples;
    }
  });
  v.fillHash = h;
  v.avgOrders = samples ? sumOrders / static_cast<double>(samples) : 0;
  v.avgLevels = samples ? sumLevels / static_cast<double>(samples) : 0;
  return v;
}

// ---- Benchmark ------------------------------------------------------------------------

enum Category : std::size_t { kLimitRest, kLimitCross, kMarket, kIoc, kCancelHit, kCancelMiss, kCategories };
constexpr std::array<const char*, kCategories> kCategoryNames{"limit_rest", "limit_cross", "market",
                                                              "ioc",        "cancel_hit",  "cancel_miss"};

struct Percentiles {
  double p50 = 0, p99 = 0, p999 = 0, max = 0;
  std::size_t n = 0;
};

Percentiles percentiles(std::vector<std::uint32_t>& v) {
  Percentiles p;
  p.n = v.size();
  if (v.empty()) return p;
  auto at = [&](double q) {
    const auto k = static_cast<std::size_t>(q * static_cast<double>(v.size() - 1));
    std::nth_element(v.begin(), v.begin() + static_cast<std::ptrdiff_t>(k), v.end());
    return static_cast<double>(v[k]);
  };
  p.p50 = at(0.50);
  p.p99 = at(0.99);
  p.p999 = at(0.999);
  p.max = static_cast<double>(*std::max_element(v.begin(), v.end()));
  return p;
}

double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

template <class Book>
std::array<Percentiles, kCategories> latencyRun(const std::vector<Event>& events) {
  std::array<std::vector<std::uint32_t>, kCategories> samples;
  for (auto& s : samples) s.reserve(events.size() / 2);
  auto book = std::make_unique<Book>();
  std::vector<Fill> fills;
  fills.reserve(4096);

  for (const Event& ev : events) {
    fills.clear();
    const auto t0 = Clock::now();
    const ExecReport r = apply(*book, ev, fills);
    const auto t1 = Clock::now();
    const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();

    Category c;
    switch (ev.type) {
      case EventType::Limit: c = fills.empty() ? kLimitRest : kLimitCross; break;
      case EventType::Market: c = kMarket; break;
      case EventType::Ioc: c = kIoc; break;
      default: c = r.status == Status::Ok ? kCancelHit : kCancelMiss; break;
    }
    samples[c].push_back(static_cast<std::uint32_t>(std::min<long long>(ns, UINT32_MAX)));
  }
  std::array<Percentiles, kCategories> out;
  for (std::size_t c = 0; c < kCategories; ++c) out[c] = percentiles(samples[c]);
  return out;
}

struct BenchResult {
  std::vector<double> throughput;
  std::array<Percentiles, kCategories> latency{};  // median across runs per field
};

template <class Book>
BenchResult bench(const char* name, const std::vector<Event>& events, int reps) {
  BenchResult res;
  auto noop = [](const Event&, const std::vector<Fill>&) {};
  {  // warm-up: page in the event array, let the allocator settle
    auto book = std::make_unique<Book>();
    replay(*book, events, noop);
  }
  for (int r = 0; r < reps; ++r) {
    auto book = std::make_unique<Book>();  // construction outside the timed region
    const auto start = Clock::now();
    const ReplayStats s = replay(*book, events, noop);
    const double secs = secondsSince(start);
    res.throughput.push_back(static_cast<double>(s.events) / secs);
    std::printf("  %s throughput run %d: %.3f s, %.0f events/s\n", name, r + 1, secs, res.throughput.back());
  }  // destruction outside the timed region

  std::vector<std::array<Percentiles, kCategories>> runs;
  for (int r = 0; r < reps; ++r) runs.push_back(latencyRun<Book>(events));
  for (std::size_t c = 0; c < kCategories; ++c) {
    auto med = [&](double Percentiles::*field) {
      std::vector<double> v;
      for (const auto& run : runs) v.push_back(run[c].*field);
      return median(v);
    };
    res.latency[c] = {med(&Percentiles::p50), med(&Percentiles::p99), med(&Percentiles::p999),
                      med(&Percentiles::max), runs[0][c].n};
  }
  return res;
}

// Cost and granularity of the timer itself, so per-op numbers can be read honestly.
std::pair<double, double> timerOverheadAndResolution() {
  std::vector<std::uint32_t> d(1'000'000);
  long long resolution = 0;
  for (auto& x : d) {
    const auto t0 = Clock::now();
    const auto t1 = Clock::now();
    const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
    x = static_cast<std::uint32_t>(ns);
    if (ns > 0 && (resolution == 0 || ns < resolution)) resolution = ns;
  }
  return {percentiles(d).p50, static_cast<double>(resolution)};
}

std::string num(double x) {
  char buf[64];
  std::snprintf(buf, sizeof buf, "%.1f", x);
  return buf;
}

}  // namespace

int main(int argc, char** argv) try {
  const auto args = parseArgs(argc, argv);
  auto get = [&](const std::string& k, const std::string& def) {
    const auto it = args.find(k);
    return it == args.end() ? def : it->second;
  };
  GeneratorConfig cfg;
  cfg.seed = std::stoull(get("seed", std::to_string(cfg.seed)));
  cfg.addsPerSidePerSec = std::stod(get("adds-per-sec", std::to_string(cfg.addsPerSidePerSec)));
  cfg.sizeMedianLots = std::stod(get("size-median", std::to_string(cfg.sizeMedianLots)));
  cfg.sizeSigma = std::stod(get("size-sigma", std::to_string(cfg.sizeSigma)));
  cfg.offsetMeanTicks = std::stod(get("offset-mean", std::to_string(cfg.offsetMeanTicks)));
  cfg.lifetimeSec = std::stod(get("lifetime", std::to_string(cfg.lifetimeSec)));
  cfg.marketShare = std::stod(get("market-share", std::to_string(cfg.marketShare)));
  cfg.iocToleranceTicks = std::stoll(get("ioc-tol", std::to_string(cfg.iocToleranceTicks)));
  const int reps = std::stoi(get("reps", "0"));
  const std::string engine = get("engine", "v1");
  const std::string scenario = get("scenario", "default");
  const bool runV1 = engine == "v1" || engine == "both";
  const bool runV2 = engine == "v2" || engine == "both";
  if (!runV1 && !runV2) throw std::invalid_argument("--engine must be v1, v2 or both");

  auto t0 = Clock::now();
  std::vector<Event> events;
  std::size_t realTrades = 0;
  {
    const auto prices = parsePrices(readFile(get("prices", "data/prices.csv")));
    const auto trades = parseTrades(readFile(get("trades", "data/trades.csv")));
    realTrades = trades.size();
    std::printf("loaded %zu prices, %zu trades in %.2f s\n", prices.size(), trades.size(), secondsSince(t0));
    t0 = Clock::now();
    events = buildStream(prices, trades, cfg);
  }
  std::array<std::size_t, 4> mix{};
  for (const Event& e : events) ++mix[static_cast<std::size_t>(e.type)];
  const auto pct = [&](std::size_t n) { return 100.0 * static_cast<double>(n) / static_cast<double>(events.size()); };
  std::printf("built %zu events in %.2f s (seed %llu): limit %.1f%%  market %.1f%%  ioc %.1f%%  cancel %.1f%%\n",
              events.size(), secondsSince(t0), static_cast<unsigned long long>(cfg.seed), pct(mix[0]), pct(mix[1]),
              pct(mix[2]), pct(mix[3]));

  // ---- Verification (and optional fills output) ----
  std::unique_ptr<FillWriter> writer;
  if (args.contains("fills")) writer = std::make_unique<FillWriter>(args.at("fills"));
  std::vector<std::pair<std::string, Verification>> verified;
  if (runV1) verified.emplace_back("v1", verify<OrderBook>(events, writer.get()));
  if (runV2) verified.emplace_back("v2", verify<OrderBookV2>(events, runV1 ? nullptr : writer.get()));
  writer.reset();
  for (const auto& [name, v] : verified) {
    std::printf("  %s: %llu fills, hash %016llx, book depth avg %.0f orders / %.0f levels (max %zu / %zu)\n",
                name.c_str(), static_cast<unsigned long long>(v.stats.fills),
                static_cast<unsigned long long>(v.fillHash), v.avgOrders, v.avgLevels, v.maxOrders, v.maxLevels);
  }
  const Verification& v0 = verified.front().second;
  printFlow("synthetic_limit", v0.stats.synthLimit);
  printFlow("real_market", v0.stats.realMarket);
  printFlow("real_ioc", v0.stats.realIoc);
  std::printf("    cancels %llu (hit %.1f%%)  rejects %llu\n", static_cast<unsigned long long>(v0.stats.cancels),
              v0.stats.cancels ? 100.0 * static_cast<double>(v0.stats.cancelHits) / static_cast<double>(v0.stats.cancels)
                               : 0.0,
              static_cast<unsigned long long>(v0.stats.rejects));
  if (verified.size() == 2) {
    const bool same = verified[0].second.fillHash == verified[1].second.fillHash &&
                      verified[0].second.stats.fills == verified[1].second.stats.fills;
    std::printf("  v1 vs v2 fill streams identical: %s\n", same ? "YES" : "NO");
    if (!same) return 2;
  }
  if (args.contains("fills")) std::printf("  wrote %s\n", args.at("fills").c_str());
  if (reps <= 0) return 0;

  // ---- Benchmarks ----
  std::vector<std::pair<std::string, BenchResult>> results;
  if (runV1) results.emplace_back("v1", bench<OrderBook>("v1", events, reps));
  if (runV2) results.emplace_back("v2", bench<OrderBookV2>("v2", events, reps));
  const auto [timerNs, timerRes] = timerOverheadAndResolution();

  std::printf("\ntimer: steady_clock now() pair overhead p50 %.0f ns, resolution %.1f ns\n", timerNs, timerRes);
  for (const auto& [name, r] : results) {
    std::printf("\n%s throughput (median of %d): %.0f events/s\n", name.c_str(), reps, median(r.throughput));
    std::printf("%s latency ns, median across %d runs (includes timer overhead):\n", name.c_str(), reps);
    std::printf("  %-12s %10s %8s %8s %8s %10s\n", "op", "count", "p50", "p99", "p99.9", "max");
    for (std::size_t c = 0; c < kCategories; ++c) {
      const Percentiles& p = r.latency[c];
      std::printf("  %-12s %10zu %8.0f %8.0f %8.0f %10.0f\n", kCategoryNames[c], p.n, p.p50, p.p99, p.p999, p.max);
    }
  }
  if (results.size() == 2) {
    std::printf("\nv2 / v1 throughput: %.2fx\n", median(results[1].second.throughput) / median(results[0].second.throughput));
  }

  if (args.contains("json")) {
    std::string json = "{\n  \"scenario\": \"" + scenario + "\",\n  \"build\": \"" TICKSCOPE_BUILD_INFO "\",\n";
    json += "  \"seed\": " + std::to_string(cfg.seed) + ",\n  \"generator\": {\"addsPerSidePerSec\": " +
            num(cfg.addsPerSidePerSec) + ", \"sizeMedianLots\": " + num(cfg.sizeMedianLots) +
            ", \"offsetMeanTicks\": " + num(cfg.offsetMeanTicks) + ", \"lifetimeSec\": " + num(cfg.lifetimeSec) +
            ", \"marketShare\": " + num(cfg.marketShare) + "},\n";
    json += "  \"events\": " + std::to_string(events.size()) + ",\n  \"realTrades\": " + std::to_string(realTrades) +
            ",\n  \"fills\": " + std::to_string(v0.stats.fills) + ",\n  \"avgRestingOrders\": " + num(v0.avgOrders) +
            ",\n  \"avgLevels\": " + num(v0.avgLevels) + ",\n  \"reps\": " + std::to_string(reps) +
            ",\n  \"timerOverheadNs\": " + num(timerNs) + ",\n  \"timerResolutionNs\": " + num(timerRes) +
            ",\n  \"engines\": {";
    for (std::size_t e = 0; e < results.size(); ++e) {
      const auto& [name, r] = results[e];
      json += std::string(e ? "," : "") + "\n    \"" + name + "\": {\n      \"throughputEventsPerSec\": " +
              num(median(r.throughput)) + ",\n      \"throughputRuns\": [";
      for (std::size_t i = 0; i < r.throughput.size(); ++i) json += (i ? ", " : "") + num(r.throughput[i]);
      json += "],\n      \"latencyNs\": {";
      for (std::size_t c = 0; c < kCategories; ++c) {
        const Percentiles& p = r.latency[c];
        json += std::string(c ? "," : "") + "\n        \"" + kCategoryNames[c] + "\": {\"count\": " +
                std::to_string(p.n) + ", \"p50\": " + num(p.p50) + ", \"p99\": " + num(p.p99) +
                ", \"p999\": " + num(p.p999) + ", \"max\": " + num(p.max) + "}";
      }
      json += "\n      }\n    }";
    }
    json += "\n  }\n}\n";
    std::FILE* f = std::fopen(args.at("json").c_str(), "wb");
    if (!f) throw std::runtime_error("cannot write " + args.at("json"));
    std::fwrite(json.data(), 1, json.size(), f);
    std::fclose(f);
    std::printf("wrote %s\n", args.at("json").c_str());
  }
  return 0;
} catch (const std::exception& e) {
  std::fprintf(stderr, "error: %s\n", e.what());
  return 1;
}

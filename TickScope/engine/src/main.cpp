// tickscope_replay: replay real taker flow against a synthetic resting book.
//
//   tickscope_replay --prices data/prices.csv --trades data/trades.csv
//                    [--fills data/fills.csv] [--seed 42] [--reps 5] [--json out.json]
//                    [--adds-per-sec 25] [--size-median 200] [--size-sigma 1.5]
//                    [--offset-mean 5] [--lifetime 30] [--market-share 0.2] [--ioc-tol 50]
//
// 1. Loads the price path and taker flow, builds the seeded event stream.
// 2. With --fills: one replay that writes every fill to CSV and prints flow statistics.
// 3. With --reps N: one warm-up, then N throughput runs (no per-op timing) and N latency
//    runs (each op timed with steady_clock), each on a fresh book; reports medians.

#include <algorithm>
#include <array>
#include <charconv>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "tickscope/generator.hpp"
#include "tickscope/market_data.hpp"
#include "tickscope/order_book.hpp"
#include "tickscope/replay.hpp"

#ifndef TICKSCOPE_BUILD_INFO
#define TICKSCOPE_BUILD_INFO "unknown"
#endif

namespace {

using namespace tickscope;
using Clock = std::chrono::steady_clock;

double secondsSince(Clock::time_point t0) {
  return std::chrono::duration<double>(Clock::now() - t0).count();
}

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
  std::printf("  %-16s orders %10llu  qty %14lld  filled %6.2f%%  rested %14lld  discarded %14lld\n", name,
              static_cast<unsigned long long>(f.orders), static_cast<long long>(f.submitted), fillPct,
              static_cast<long long>(f.rested), static_cast<long long>(f.discarded));
}

// ---- Latency measurement --------------------------------------------------------------

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

std::array<Percentiles, kCategories> latencyRun(const std::vector<Event>& events) {
  std::array<std::vector<std::uint32_t>, kCategories> samples;
  for (auto& s : samples) s.reserve(events.size() / 2);
  auto book = std::make_unique<OrderBook>();
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

double median(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

}  // namespace

int main(int argc, char** argv) try {
  const auto args = parseArgs(argc, argv);
  auto get = [&](const std::string& k, const std::string& def) {
    const auto it = args.find(k);
    return it == args.end() ? def : it->second;
  };
  const std::string pricesPath = get("prices", "data/prices.csv");
  const std::string tradesPath = get("trades", "data/trades.csv");
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

  auto t0 = Clock::now();
  std::vector<Event> events;
  std::size_t realTrades = 0;
  {
    const auto prices = parsePrices(readFile(pricesPath));
    const auto trades = parseTrades(readFile(tradesPath));
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

  if (args.contains("fills")) {
    t0 = Clock::now();
    OrderBook book;
    ReplayStats s;
    {
      FillWriter writer(args.at("fills"));
      s = replay(book, events, [&](const Event& ev, const std::vector<Fill>& f) { writer.write(ev, f); });
    }
    std::printf("replayed %llu events -> %llu fills in %.2f s (with CSV output) -> %s\n",
                static_cast<unsigned long long>(s.events), static_cast<unsigned long long>(s.fills),
                secondsSince(t0), args.at("fills").c_str());
    printFlow("synthetic_limit", s.synthLimit);
    printFlow("real_market", s.realMarket);
    printFlow("real_ioc", s.realIoc);
    std::printf("  cancels %llu (hit %.1f%%)  rejects %llu  resting at end %zu (bid levels %zu, ask levels %zu)\n",
                static_cast<unsigned long long>(s.cancels),
                s.cancels ? 100.0 * static_cast<double>(s.cancelHits) / static_cast<double>(s.cancels) : 0.0,
                static_cast<unsigned long long>(s.rejects), book.orderCount(), book.levelCount(Side::Buy),
                book.levelCount(Side::Sell));
  }

  if (reps > 0) {
    auto noop = [](const Event&, const std::vector<Fill>&) {};
    {  // warm-up: page in the event array, let the allocator settle
      auto book = std::make_unique<OrderBook>();
      replay(*book, events, noop);
    }

    std::vector<double> throughput;
    for (int r = 0; r < reps; ++r) {
      auto book = std::make_unique<OrderBook>();
      const auto start = Clock::now();
      const ReplayStats s = replay(*book, events, noop);
      const double secs = secondsSince(start);
      throughput.push_back(static_cast<double>(s.events) / secs);
      std::printf("  throughput run %d: %.3f s, %.0f events/s\n", r + 1, secs, throughput.back());
    }  // book destroyed outside the timed region

    const auto [timerNs, timerRes] = timerOverheadAndResolution();
    std::vector<std::array<Percentiles, kCategories>> runs;
    for (int r = 0; r < reps; ++r) runs.push_back(latencyRun(events));

    std::printf("\nthroughput (median of %d): %.0f events/s\n", reps, median(throughput));
    std::printf("timer: steady_clock now() pair overhead p50 %.0f ns, resolution %.1f ns\n", timerNs, timerRes);
    std::printf("latency ns, median across %d runs (includes timer overhead):\n", reps);
    std::printf("  %-12s %10s %8s %8s %8s %10s\n", "op", "count", "p50", "p99", "p99.9", "max");

    std::string json = "{\n  \"engine\": \"v1-std-map\",\n  \"build\": \"" TICKSCOPE_BUILD_INFO "\",\n";
    json += "  \"seed\": " + std::to_string(cfg.seed) + ",\n  \"events\": " + std::to_string(events.size()) +
            ",\n  \"realTrades\": " + std::to_string(realTrades) + ",\n  \"reps\": " + std::to_string(reps) +
            ",\n  \"throughputEventsPerSec\": " + std::to_string(median(throughput)) +
            ",\n  \"timerOverheadNs\": " + std::to_string(timerNs) + ",\n  \"timerResolutionNs\": " +
            std::to_string(timerRes) + ",\n  \"latencyNs\": {";
    for (std::size_t c = 0; c < kCategories; ++c) {
      auto med = [&](auto field) {
        std::vector<double> v;
        for (const auto& run : runs) v.push_back(run[c].*field);
        return median(v);
      };
      const double p50 = med(&Percentiles::p50), p99 = med(&Percentiles::p99), p999 = med(&Percentiles::p999),
                   mx = med(&Percentiles::max);
      std::printf("  %-12s %10zu %8.0f %8.0f %8.0f %10.0f\n", kCategoryNames[c], runs[0][c].n, p50, p99, p999, mx);
      json += std::string(c ? "," : "") + "\n    \"" + kCategoryNames[c] + "\": {\"count\": " +
              std::to_string(runs[0][c].n) + ", \"p50\": " + std::to_string(p50) + ", \"p99\": " +
              std::to_string(p99) + ", \"p999\": " + std::to_string(p999) + ", \"max\": " + std::to_string(mx) +
              "}";
    }
    json += "\n  }\n}\n";
    if (args.contains("json")) {
      std::FILE* f = std::fopen(args.at("json").c_str(), "wb");
      if (!f) throw std::runtime_error("cannot write " + args.at("json"));
      std::fwrite(json.data(), 1, json.size(), f);
      std::fclose(f);
      std::printf("wrote %s\n", args.at("json").c_str());
    }
  }
  return 0;
} catch (const std::exception& e) {
  std::fprintf(stderr, "error: %s\n", e.what());
  return 1;
}

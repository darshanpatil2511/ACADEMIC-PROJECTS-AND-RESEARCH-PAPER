#pragma once

#include <cmath>
#include <cstdint>
#include <numbers>

namespace tickscope {

// xoshiro256** seeded through splitmix64, with hand-written distributions.
//
// std::uniform_int_distribution, std::lognormal_distribution etc. are implementation-defined:
// the same seed gives different streams on libc++ (macOS) and libstdc++ (Linux). Writing the
// distributions ourselves makes a seeded order stream identical on every platform, which is
// what makes v1-vs-v2 benchmarks and CI results reproducible.
class Rng {
 public:
  explicit Rng(std::uint64_t seed) noexcept {
    std::uint64_t x = seed;
    for (auto& s : s_) s = splitmix64(x);
  }

  std::uint64_t next() noexcept {
    const std::uint64_t result = rotl(s_[1] * 5, 7) * 9;
    const std::uint64_t t = s_[1] << 17;
    s_[2] ^= s_[0];
    s_[3] ^= s_[1];
    s_[1] ^= s_[2];
    s_[0] ^= s_[3];
    s_[2] ^= t;
    s_[3] = rotl(s_[3], 45);
    return result;
  }

  // Uniform in [0, 1) with 53 random bits.
  double uniform01() noexcept { return static_cast<double>(next() >> 11) * 0x1.0p-53; }

  // Uniform integer in [lo, hi]. Modulo bias is < 2^-40 for the small ranges used here.
  std::int64_t uniformInt(std::int64_t lo, std::int64_t hi) noexcept {
    const auto span = static_cast<std::uint64_t>(hi - lo) + 1;
    return lo + static_cast<std::int64_t>(next() % span);
  }

  bool bernoulli(double p) noexcept { return uniform01() < p; }

  // Standard normal via Box-Muller.
  double normal() noexcept {
    const double u1 = 1.0 - uniform01();  // (0, 1], so log(u1) is finite
    const double u2 = uniform01();
    return std::sqrt(-2.0 * std::log(u1)) * std::cos(2.0 * std::numbers::pi * u2);
  }

  // exp(N(mu, sigma)); median = exp(mu).
  double lognormal(double mu, double sigma) noexcept { return std::exp(mu + sigma * normal()); }

  // Failures before the first success, success probability p in (0, 1]; mean (1 - p) / p.
  std::int64_t geometric(double p) noexcept {
    if (p >= 1.0) return 0;
    const double u = 1.0 - uniform01();
    return static_cast<std::int64_t>(std::floor(std::log(u) / std::log1p(-p)));
  }

 private:
  static std::uint64_t rotl(std::uint64_t x, int k) noexcept { return (x << k) | (x >> (64 - k)); }

  static std::uint64_t splitmix64(std::uint64_t& x) noexcept {
    std::uint64_t z = (x += 0x9E3779B97F4A7C15ULL);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
  }

  std::uint64_t s_[4]{};
};

}  // namespace tickscope

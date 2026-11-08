#include "tickscope/market_data.hpp"

#include <charconv>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace tickscope {
namespace {

// Splits `csv` into lines (skipping the header) and hands each to `parseLine` together with
// a cursor over its comma-separated fields.
class FieldCursor {
 public:
  FieldCursor(std::string_view line, std::size_t lineNo) : rest_(line), lineNo_(lineNo) {}

  std::string_view next() {
    if (done_) fail("too few fields");
    const auto comma = rest_.find(',');
    std::string_view field = rest_.substr(0, comma);
    if (comma == std::string_view::npos) {
      done_ = true;
    } else {
      rest_.remove_prefix(comma + 1);
    }
    return field;
  }

  template <class Int>
  Int nextInt() {
    const std::string_view f = next();
    Int value{};
    const auto [ptr, ec] = std::from_chars(f.data(), f.data() + f.size(), value);
    if (ec != std::errc{} || ptr != f.data() + f.size()) fail("bad integer '" + std::string(f) + "'");
    return value;
  }

  void expectEnd() const {
    if (!done_) fail("too many fields");
  }

  [[noreturn]] void fail(const std::string& what) const {
    throw std::runtime_error("line " + std::to_string(lineNo_) + ": " + what);
  }

 private:
  std::string_view rest_;
  std::size_t lineNo_;
  bool done_ = false;
};

template <class Row, class ParseLine>
std::vector<Row> parseCsv(std::string_view csv, ParseLine parseLine) {
  std::vector<Row> rows;
  rows.reserve(csv.size() / 40);
  std::size_t lineNo = 0;
  while (!csv.empty()) {
    const auto nl = csv.find('\n');
    std::string_view line = csv.substr(0, nl);
    csv.remove_prefix(nl == std::string_view::npos ? csv.size() : nl + 1);
    ++lineNo;
    if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
    if (lineNo == 1 || line.empty()) continue;  // header / trailing newline
    FieldCursor cursor(line, lineNo);
    rows.push_back(parseLine(cursor));
    cursor.expectEnd();
  }
  return rows;
}

}  // namespace

std::vector<PricePoint> parsePrices(std::string_view csv) {
  return parseCsv<PricePoint>(csv, [](FieldCursor& c) {
    PricePoint p{};
    p.tsSec = c.nextInt<std::int64_t>();
    p.price = c.nextInt<PriceTicks>();
    return p;
  });
}

std::vector<TakerTrade> parseTrades(std::string_view csv) {
  return parseCsv<TakerTrade>(csv, [](FieldCursor& c) {
    TakerTrade t{};
    t.tradeId = c.nextInt<std::uint64_t>();
    t.ts = c.nextInt<TimestampUs>();
    const std::string_view side = c.next();
    if (side == "B") {
      t.side = Side::Buy;
    } else if (side == "S") {
      t.side = Side::Sell;
    } else {
      c.fail("bad side '" + std::string(side) + "'");
    }
    t.price = c.nextInt<PriceTicks>();
    t.qty = c.nextInt<QtyLots>();
    return t;
  });
}

std::string readFile(const std::string& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("cannot open " + path);
  std::ostringstream ss;
  ss << in.rdbuf();
  return std::move(ss).str();
}

}  // namespace tickscope

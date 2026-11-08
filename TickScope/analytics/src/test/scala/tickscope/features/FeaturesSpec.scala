package tickscope.features

import java.sql.Date

import org.scalatest.funsuite.AnyFunSuite
import tickscope.SparkTestSession
import tickscope.ingest.Trade

/** Known-answer tests on a hand-built tape (T0 = 2026-11-05 00:00:00 UTC).
  *
  *   id  t(s)  price qty  taker
  *   1     1   100   1    buy
  *   2    10   102   2    sell   (same timestamp as id 3)
  *   3    10    99   1    buy
  *   4    50   101   4    sell
  *   5    60   103   1    buy    (same timestamp as id 6)
  *   6    60   104   1    buy
  *   7   119   105   2    sell
  *   8   185   100   1    buy    (no trades in 120–179 s: a missing bar)
  *
  * 1m bar @0s:   O 100 H 102 L 99 C 101, V 8, VWAP 807/8 = 100.875, buy 2 sell 6, imb -0.5
  * 1m bar @60s:  O 103 H 105 L 103 C 105, V 4, VWAP 417/4 = 104.25, buy 2 sell 2, imb 0,
  *               r = ln(105/101)
  * 1m bar @180s: O=H=L=C 100, V 1, VWAP 100, imb +1, r = ln(100/105)
  *               realizedVol (window 2) = sqrt(ln(105/101)^2 + ln(100/105)^2)
  */
class FeaturesSpec extends AnyFunSuite with SparkTestSession {
  import spark.implicits._

  private val T0 = 1793836800000000L
  private val day = Date.valueOf("2026-11-05")

  private def trade(id: Long, sec: Long, price: Double, qty: Double, takerBuy: Boolean): Trade =
    Trade(id, price, qty, price * qty, math.round(price * 100), math.round(qty * 100000), T0 + sec * 1000000L,
      isBuyerMaker = !takerBuy, day)

  private lazy val tape = Seq(
    trade(1, 1, 100, 1, takerBuy = true),
    trade(2, 10, 102, 2, takerBuy = false),
    trade(3, 10, 99, 1, takerBuy = true),
    trade(4, 50, 101, 4, takerBuy = false),
    trade(5, 60, 103, 1, takerBuy = true),
    trade(6, 60, 104, 1, takerBuy = true),
    trade(7, 119, 105, 2, takerBuy = false),
    trade(8, 185, 100, 1, takerBuy = true)
  ).toDS()

  private lazy val bars1m = Bars.compute(tape, 60, volWindow = 2).collect().sortBy(_.barStartUs)

  private val eps = 1e-12

  test("1m bars: one per minute that traded, missing minute skipped") {
    assert(bars1m.map(b => (b.barStartUs - T0) / 1000000L).toSeq == Seq(0L, 60L, 180L))
    assert(bars1m.forall(b => b.intervalSec == 60 && b.date == day))
  }

  test("OHLCV and trade count; open/close by trade sequence on equal timestamps") {
    val b = bars1m(0)
    assert((b.open, b.high, b.low, b.close) == ((100.0, 102.0, 99.0, 101.0)))
    assert(b.volume == 8.0 && b.tradeCount == 4L && b.quoteVolume == 807.0)
    val b1 = bars1m(1)
    assert((b1.open, b1.high, b1.low, b1.close) == ((103.0, 105.0, 103.0, 105.0))) // id 5 before id 6
  }

  test("VWAP") {
    assert(math.abs(bars1m(0).vwap - 100.875) < eps)
    assert(math.abs(bars1m(1).vwap - 104.25) < eps)
    assert(bars1m(2).vwap == 100.0)
  }

  test("buy/sell volume and imbalance") {
    assert((bars1m(0).buyVolume, bars1m(0).sellVolume) == ((2.0, 6.0)))
    assert(bars1m.map(_.imbalance).toSeq == Seq(-0.5, 0.0, 1.0))
  }

  test("log returns and rolling realized volatility") {
    val r1 = math.log(105.0 / 101.0)
    val r2 = math.log(100.0 / 105.0)
    assert(bars1m(0).logReturn.isEmpty)
    assert(math.abs(bars1m(1).logReturn.get - r1) < eps)
    assert(math.abs(bars1m(2).logReturn.get - r2) < eps)
    assert(bars1m(0).realizedVol.isEmpty && bars1m(1).realizedVol.isEmpty) // window not full yet
    assert(math.abs(bars1m(2).realizedVol.get - math.sqrt(r1 * r1 + r2 * r2)) < eps)
  }

  test("5m bar aggregates the whole tape") {
    val bars = Bars.compute(tape, 300, volWindow = 2).collect()
    assert(bars.length == 1)
    val b = bars.head
    assert((b.open, b.high, b.low, b.close, b.volume) == ((100.0, 105.0, 99.0, 100.0, 13.0)))
    assert(b.logReturn.isEmpty)
  }

  test("1-second price path: last trade by sequence, gaps forward-filled") {
    val path = Prices.lastPricePerSecond(tape).collect().map(p => (p.tsSec - T0 / 1000000L) -> p.priceTicks).toMap
    assert(path.size == 185)              // seconds 1..185 inclusive
    assert(path(1) == 10000L)
    assert(path(10) == 9900L)             // ids 2 and 3 share the second; id 3 is last
    assert(path(11) == 9900L)             // no trade: carried forward
    assert(path(60) == 10400L)
    assert(path(150) == 10500L)
    assert(path(185) == 10000L)
  }

  test("barStart floors to the interval") {
    val df = Seq(T0 + 59999999L, T0 + 60000000L).toDF("ts").select(Bars.barStart($"ts", 60).as("b"))
    assert(df.as[Long].collect().toSeq == Seq(T0, T0 + 60000000L))
  }
}

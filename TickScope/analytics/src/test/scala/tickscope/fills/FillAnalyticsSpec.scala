package tickscope.fills

import org.scalatest.funsuite.AnyFunSuite
import tickscope.SparkTestSession

/** Hand-computed fixtures (prices in ticks; 10,000 ticks = 100.00 USDT). */
class FillAnalyticsSpec extends AnyFunSuite with SparkTestSession {
  import spark.implicits._

  private val T0 = 1793836800000000L // a minute boundary
  private val bit = BigDecimal(FillAnalytics.RealIdBit)
  private val tol = 1e-9

  // Order A: real market BUY, tradeId 7, fills 1 lot @ 10,000 and 3 lots @ 10,010
  //   avg = (10,000 + 30,030) / 4 = 10,007.5 ticks
  // Order B: real market SELL, tradeId 8, fills 2 lots @ 9,990 -> avg 9,990
  private lazy val fills = Seq(
    (T0 + 1000000L, BigDecimal(1), bit + 7, "B", 10000L, 1L, "real_market"),
    (T0 + 1000000L, BigDecimal(2), bit + 7, "B", 10010L, 3L, "real_market"),
    (T0 + 5000000L, BigDecimal(3), bit + 8, "S", 9990L, 2L, "real_market")
  ).toDF("tsUs", "makerId", "takerId", "takerSide", "priceTicks", "qtyLots", "takerType")
    .select($"tsUs", $"makerId".cast("decimal(20,0)"), $"takerId".cast("decimal(20,0)"), $"takerSide",
      $"priceTicks", $"qtyLots", $"takerType")

  private lazy val bars = Seq((T0, 100.0)).toDF("barStartUs", "vwap")

  test("execution price is the quantity-weighted average of an order's fills") {
    val ex = FillAnalytics.executions(fills).as[(BigDecimal, String, String, Long, Double, Long, Long)].collect()
      .map(r => r._1 -> r).toMap
    assert(math.abs(ex(bit + 7)._5 - 10007.5) < tol)
    assert(ex(bit + 7)._6 == 4L && ex(bit + 7)._7 == 2L)
    assert(ex(bit + 8)._5 == 9990.0)
  }

  test("slippage vs VWAP is signed so positive means worse for the taker") {
    val s = FillAnalytics
      .slippageVsVwap(FillAnalytics.executions(fills), bars)
      .select($"takerId", $"slippageBp")
      .as[(BigDecimal, Double)]
      .collect()
      .toMap
    // Buy paid 10,007.5 vs VWAP 10,000: +7.5 bp. Sell received 9,990 vs 10,000: +10 bp cost.
    assert(math.abs(s(bit + 7) - 7.5) < tol)
    assert(math.abs(s(bit + 8) - 10.0) < tol)
  }

  test("slippage vs the real print joins on tradeId recovered from the id bit") {
    val trades = Seq((7L, 10005L), (8L, 9990L)).toDF("tradeId", "priceTicks")
    val s = FillAnalytics
      .slippageVsPrint(FillAnalytics.executions(fills), trades)
      .select($"tradeId", $"slippageBp")
      .as[(Long, Double)]
      .collect()
      .toMap
    assert(math.abs(s(7L) - 2.5 / 10005 * 1e4) < tol) // paid 2.5 ticks more than the print
    assert(math.abs(s(8L)) < tol)                     // same price as the print
  }

  test("effective spread, realized spread and impact") {
    // Single buy fill at 10,010 at second 101; M0 (second 100) = 10,000; M at 101+5 = 10,004.
    val one = Seq((101000000L, "B", 10010L, 1L, "real_market")).toDF("tsUs", "takerSide", "priceTicks", "qtyLots", "takerType")
    val prices = Seq((100L, 10000L), (106L, 10004L)).toDF("tsSec", "priceTicks")
    val r = FillAnalytics.spreads(one, prices, horizonSec = 5).select("effectiveBp", "realizedBp", "impactBp").as[(Double, Double, Double)].head()
    assert(math.abs(r._1 - 20.0) < tol) // 2 * 10 / 10,000
    assert(math.abs(r._2 - 12.0) < tol) // 2 * 6 / 10,000
    assert(math.abs(r._3 - 8.0) < tol)
  }

  test("fill rates per order type") {
    val orders = Seq(
      ("real_market", 10L, 10L, 0L, 0L),
      ("real_market", 10L, 4L, 0L, 6L),
      ("real_ioc", 5L, 0L, 0L, 5L)
    ).toDF("type", "qtyLots", "filled", "rested", "discarded")
    val m = FillAnalytics.fillRates(orders).collect().map(r => r.getString(0) -> r).toMap
    assert(m("real_market").getAs[Double]("fillRate") == 0.7)
    assert(m("real_market").getAs[Double]("fullyFilledShare") == 0.5)
    assert(m("real_ioc").getAs[Double]("unfilledShare") == 1.0)
  }

  test("size histogram buckets by decade") {
    val h = FillAnalytics.sizeHistogram(Seq(1L, 9L, 10L, 250L).toDF("qtyLots")).as[(Int, Long, Long)].collect().toSeq
    assert(h == Seq((0, 2L, 10L), (1, 1L, 10L), (2, 1L, 250L)))
  }
}

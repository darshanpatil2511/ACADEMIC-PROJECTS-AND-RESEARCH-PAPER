package tickscope.fills

import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.{Column, DataFrame, SparkSession}

/** Execution-quality analytics on the C++ engine's output (fills.csv, orders.csv).
  *
  * Conventions: d = +1 for a taker buy, -1 for a taker sell. Costs are in basis points and
  * signed so that positive = worse for the taker. Prices are in ticks (0.01 USDT).
  */
object FillAnalytics {

  /** Real orders carry the Binance tradeId with the top bit set (kRealIdBit in the engine). */
  val RealIdBit: java.math.BigDecimal = new java.math.BigDecimal("9223372036854775808")

  // Ids can exceed Long.MaxValue (top bit set), so they are read as Decimal(20,0).
  val fillSchema: StructType = StructType(
    Seq(
      StructField("tsUs", LongType),
      StructField("makerId", DecimalType(20, 0)),
      StructField("takerId", DecimalType(20, 0)),
      StructField("takerSide", StringType),
      StructField("priceTicks", LongType),
      StructField("qtyLots", LongType),
      StructField("takerType", StringType)
    )
  )

  val orderSchema: StructType = StructType(
    Seq(
      StructField("orderId", DecimalType(20, 0)),
      StructField("tsUs", LongType),
      StructField("type", StringType),
      StructField("side", StringType),
      StructField("priceTicks", LongType),
      StructField("qtyLots", LongType),
      StructField("filled", LongType),
      StructField("rested", LongType),
      StructField("discarded", LongType)
    )
  )

  val priceSchema: StructType = StructType(Seq(StructField("tsSec", LongType), StructField("priceTicks", LongType)))

  def readCsv(spark: SparkSession, path: String, schema: StructType): DataFrame =
    spark.read.option("header", "true").schema(schema).csv(path)

  private def direction(side: Column): Column = when(side === "B", lit(1.0)).otherwise(lit(-1.0))

  /** Per order type: how much of the submitted quantity traded. */
  def fillRates(orders: DataFrame): DataFrame =
    orders
      .groupBy(col("type"))
      .agg(
        count(lit(1)).as("orders"),
        sum("qtyLots").as("qtyLots"),
        sum("filled").as("filledLots"),
        sum("rested").as("restedLots"),
        sum("discarded").as("discardedLots"),
        avg(when(col("filled") === col("qtyLots"), 1.0).otherwise(0.0)).as("fullyFilledShare"),
        avg(when(col("filled") === 0, 1.0).otherwise(0.0)).as("unfilledShare")
      )
      .withColumn("fillRate", col("filledLots") / col("qtyLots"))
      .orderBy("type")

  /** One row per taker order that traded: arrival time and average execution price. */
  def executions(fills: DataFrame): DataFrame =
    fills
      .groupBy("takerId", "takerType", "takerSide")
      .agg(
        min("tsUs").as("tsUs"),
        (sum(col("priceTicks") * col("qtyLots")) / sum("qtyLots")).as("avgPxTicks"),
        sum("qtyLots").as("execLots"),
        count(lit(1)).as("fills")
      )

  /** Slippage of each execution vs the VWAP of the 1-minute bar it arrived in.
    *
    * `bars` is ~10k rows, so Spark broadcasts it to every task (no shuffle of the
    * executions); the hint makes that explicit.
    */
  def slippageVsVwap(execs: DataFrame, bars: DataFrame): DataFrame = {
    val vwap = bars.select(col("barStartUs"), (col("vwap") * 100).as("vwapTicks"))
    execs
      .withColumn("barStartUs", floor(col("tsUs") / 60000000L).cast("long") * 60000000L)
      .join(broadcast(vwap), Seq("barStartUs"))
      .withColumn(
        "slippageBp",
        direction(col("takerSide")) * (col("avgPxTicks") - col("vwapTicks")) / col("vwapTicks") * 1e4
      )
  }

  /** Slippage of each real execution vs the price Binance actually printed for that trade.
    * `trades` (tradeId, priceTicks) is large, so this is a shuffle (sort-merge) join on
    * tradeId; partition pruning on the date keeps the input to the one replayed day.
    */
  def slippageVsPrint(execs: DataFrame, trades: DataFrame): DataFrame =
    execs
      .filter(col("takerType") =!= "synthetic_limit")
      .withColumn("tradeId", (col("takerId") - lit(RealIdBit)).cast(LongType))
      .join(trades.select(col("tradeId"), col("priceTicks").as("printTicks")), Seq("tradeId"))
      .withColumn(
        "slippageBp",
        direction(col("takerSide")) * (col("avgPxTicks") - col("printTicks")) / col("printTicks") * 1e4
      )

  /** Effective and realized spread per fill (taker's perspective; the maker earns it).
    *
    *   M0 = reference price before the fill (last price of the previous second)
    *   Mh = reference price `horizonSec` later
    *   effective = 2 d (P - M0) / M0,  realized = 2 d (P - Mh) / M0,  impact = effective - realized
    * Uses the last-trade price path as the reference (no quote data), noted in the report.
    */
  def spreads(fills: DataFrame, prices: DataFrame, horizonSec: Int): DataFrame = {
    val p0 = prices.select(col("tsSec").as("s0"), col("priceTicks").as("m0"))
    val ph = prices.select(col("tsSec").as("sh"), col("priceTicks").as("mh"))
    fills
      .withColumn("sec", floor(col("tsUs") / 1000000L).cast("long"))
      .join(broadcast(p0), col("s0") === col("sec") - 1)
      .join(broadcast(ph), col("sh") === col("sec") + horizonSec)
      .withColumn("d", direction(col("takerSide")))
      .withColumn("effectiveBp", lit(2.0) * col("d") * (col("priceTicks") - col("m0")) / col("m0") * 1e4)
      .withColumn("realizedBp", lit(2.0) * col("d") * (col("priceTicks") - col("mh")) / col("m0") * 1e4)
      .withColumn("impactBp", col("effectiveBp") - col("realizedBp"))
  }

  /** Quantity-weighted mean of `c` by `group`. */
  def weightedMean(df: DataFrame, group: String, c: String, weight: String): DataFrame =
    df.groupBy(group).agg((sum(col(c) * col(weight)) / sum(weight)).as(c), count(lit(1)).as("n"))

  /** Distribution summary: count, mean and approximate quantiles (relative error 1e-4). */
  def summary(df: DataFrame, group: String, c: String): DataFrame =
    df.groupBy(group)
      .agg(
        count(lit(1)).as("n"),
        avg(c).as("mean"),
        percentile_approx(col(c), array(lit(0.1), lit(0.5), lit(0.9), lit(0.99)), lit(10000)).as("q")
      )
      .orderBy(group)

  /** Fill sizes by decade of lots: 1-9, 10-99, ... */
  def sizeHistogram(fills: DataFrame): DataFrame =
    fills
      .withColumn("decade", floor(log10(col("qtyLots"))).cast("int"))
      .groupBy("decade")
      .agg(count(lit(1)).as("fills"), sum("qtyLots").as("lots"))
      .orderBy("decade")
}

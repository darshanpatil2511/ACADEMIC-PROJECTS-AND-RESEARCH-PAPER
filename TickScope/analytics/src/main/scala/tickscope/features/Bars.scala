package tickscope.features

import java.sql.Date

import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.functions._
import org.apache.spark.sql.{Column, Dataset}
import tickscope.ingest.Trade

/** One time bar. Prices are USDT, volumes BTC. `logReturn` and `realizedVol` are null for
  * the first bar(s) where the previous bar / a full window does not exist yet.
  */
final case class Bar(
    barStartUs: Long,
    date: Date,
    intervalSec: Int,
    open: Double,
    high: Double,
    low: Double,
    close: Double,
    volume: Double,
    quoteVolume: Double,
    vwap: Double,
    tradeCount: Long,
    buyVolume: Double,
    sellVolume: Double,
    imbalance: Double,
    logReturn: Option[Double],
    realizedVol: Option[Double]
)

object Bars {

  /** Start of the bar containing `tsUs`: floor to a multiple of the interval. */
  def barStart(tsUs: Column, intervalSec: Int): Column = {
    val width = intervalSec.toLong * 1000000L
    floor(tsUs / width).cast("long") * width
  }

  /** Trades -> bars of `intervalSec`, with log returns and rolling realized volatility.
    *
    * Stage 1 (wide): groupBy bar start -> one shuffle; partial aggregates are combined
    * map-side first, so only one row per bar per partition crosses the network.
    * Stage 2 (on the bars, which are few: 1,440/day at 1m): lag and a rolling window in
    * time order. That window has no partition key, so Spark moves all bars to a single
    * partition — fine for ~10k rows, never done on raw trades.
    *
    * realizedVol = sqrt(sum of squared log returns over the last `volWindow` bars),
    * i.e. per-window volatility, not annualized.
    */
  def compute(trades: Dataset[Trade], intervalSec: Int, volWindow: Int): Dataset[Bar] = {
    require(intervalSec > 0 && volWindow > 0)
    import trades.sparkSession.implicits._

    // Taker side: isBuyerMaker = true means the aggressor sold.
    val takerBuy = !col("isBuyerMaker")

    val agg = trades
      .withColumn("barStartUs", barStart(col("tsUs"), intervalSec))
      .groupBy("barStartUs")
      .agg(
        // open/close by trade sequence, not by timestamp: many trades share a timestamp.
        min_by(col("price"), col("tradeId")).as("open"),
        max(col("price")).as("high"),
        min(col("price")).as("low"),
        max_by(col("price"), col("tradeId")).as("close"),
        sum(col("qty")).as("volume"),
        sum(col("quoteQty")).as("quoteVolume"),
        sum(col("price") * col("qty")).as("pxQty"),
        count(lit(1)).as("tradeCount"),
        sum(when(takerBuy, col("qty")).otherwise(0.0)).as("buyVolume"),
        sum(when(!takerBuy, col("qty")).otherwise(0.0)).as("sellVolume")
      )
      .withColumn("vwap", col("pxQty") / col("volume"))
      .withColumn("imbalance", (col("buyVolume") - col("sellVolume")) / (col("buyVolume") + col("sellVolume")))
      .withColumn("date", to_date(timestamp_micros(col("barStartUs"))))
      .withColumn("intervalSec", lit(intervalSec))
      .drop("pxQty")

    val inTime = Window.orderBy("barStartUs")
    val trailing = inTime.rowsBetween(-(volWindow - 1), Window.currentRow)

    agg
      .withColumn("logReturn", log(col("close") / lag(col("close"), 1).over(inTime)))
      .withColumn("_n", count(col("logReturn")).over(trailing))
      .withColumn(
        "realizedVol",
        when(col("_n") === volWindow, sqrt(sum(col("logReturn") * col("logReturn")).over(trailing)))
      )
      .drop("_n")
      .as[Bar]
  }
}

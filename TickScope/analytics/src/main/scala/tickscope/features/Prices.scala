package tickscope.features

import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.functions._
import org.apache.spark.sql.Dataset
import tickscope.ingest.Trade

/** Last traded price of each second, in ticks. */
final case class PricePoint(tsSec: Long, priceTicks: Long)

object Prices {

  /** One row per second from the first to the last trade. A second with no trades carries
    * the previous second's price forward, so the C++ replay always has a reference price.
    */
  def lastPricePerSecond(trades: Dataset[Trade]): Dataset[PricePoint] = {
    val spark = trades.sparkSession
    import spark.implicits._

    val traded = trades
      .withColumn("tsSec", floor(col("tsUs") / 1000000L).cast("long"))
      .groupBy("tsSec")
      .agg(max_by(col("priceTicks"), col("tradeId")).as("priceTicks"))

    val bounds = traded.agg(min("tsSec"), max("tsSec")).head()
    if (bounds.isNullAt(0)) spark.emptyDataset[PricePoint]
    else {
      // Every second in range, then forward-fill gaps. ~86,400 rows/day: small enough for
      // an unpartitioned window.
      val allSeconds = spark.range(bounds.getLong(0), bounds.getLong(1) + 1).withColumnRenamed("id", "tsSec")
      val upToNow = Window.orderBy("tsSec").rowsBetween(Window.unboundedPreceding, Window.currentRow)
      allSeconds
        .join(traded, Seq("tsSec"), "left")
        .withColumn("priceTicks", last(col("priceTicks"), ignoreNulls = true).over(upToNow))
        .as[PricePoint]
    }
  }
}

package tickscope.ingest

import org.apache.spark.sql.functions._
import org.apache.spark.sql.{DataFrame, Dataset}
import tickscope.{Args, Io, Spark}

/** Cleaned Parquet -> one CSV of taker flow for the C++ replay driver.
  *
  * Columns: tradeId, tsUs, side (taker side: B or S), priceTicks, qtyLots; sorted by tradeId.
  *
  * sbt "runMain tickscope.ingest.ExportTrades --clean ../data/clean --out ../data/trades.csv
  *      [--from 2026-11-01] [--to 2026-11-05]"
  */
object ExportTrades {

  /** Binance's isBuyerMaker = true means the buyer rested, so the aggressor (taker) sold. */
  def toTakerFlow(trades: Dataset[Trade]): DataFrame =
    trades.select(
      col("tradeId"),
      col("tsUs"),
      when(col("isBuyerMaker"), lit("S")).otherwise(lit("B")).as("side"),
      col("priceTicks"),
      col("qtyLots")
    )

  def main(argv: Array[String]): Unit = {
    val opts = Args.parse(argv.toSeq)
    val cleanPath = Args.required(opts, "clean")
    val outFile = Args.required(opts, "out")
    val spark = Spark.local("tickscope-export-trades")
    import spark.implicits._

    try {
      val all = spark.read.parquet(cleanPath).as[Trade]
      // Filters on the partition column prune whole date directories before any read.
      val from = opts.get("from").fold(all)(d => all.filter(col("date") >= lit(d).cast("date")))
      val inRange = opts.get("to").fold(from)(d => from.filter(col("date") <= lit(d).cast("date")))

      Io.writeSingleCsv(toTakerFlow(inRange), outFile, "tradeId")
      println(s"wrote $outFile")
    } finally spark.stop()
  }
}

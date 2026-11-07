package tickscope.features

import org.apache.spark.sql.SaveMode
import tickscope.ingest.Trade
import tickscope.{Args, Io, Spark}

/** Cleaned trades -> 1m and 5m bars (Parquet by date) and the 1-second price path (CSV).
  *
  * sbt "runMain tickscope.features.FeatureJob --clean ../data/clean --out ../data/features
  *      --prices ../data/prices.csv [--vol-window 30]"
  */
object FeatureJob {
  def main(argv: Array[String]): Unit = {
    val opts = Args.parse(argv.toSeq)
    val cleanPath = Args.required(opts, "clean")
    val outPath = Args.required(opts, "out")
    val pricesFile = Args.required(opts, "prices")
    val volWindow = opts.get("vol-window").fold(30)(_.toInt)
    val spark = Spark.local("tickscope-features")
    import spark.implicits._

    try {
      val started = System.nanoTime()
      // Read once, reused by the 1m bars, the 5m bars and the price path.
      val trades = spark.read.parquet(cleanPath).as[Trade].cache()

      val tradeCount = trades.count()
      for (interval <- Seq(60, 300)) {
        val target = s"$outPath/bars_${interval / 60}m"
        Bars
          .compute(trades, interval, volWindow)
          .write
          .mode(SaveMode.Overwrite)
          .partitionBy("date")
          .parquet(target)
        println(s"wrote $target")
        checkBars(spark.read.parquet(target).as[Bar].collect().toSeq, tradeCount, target)
      }

      Io.writeSingleCsv(Prices.lastPricePerSecond(trades).toDF(), pricesFile, "tsSec")
      println(s"wrote $pricesFile")
      println(f"elapsed ${(System.nanoTime() - started) / 1e9}%.1f s")
      trades.unpersist()
    } finally spark.stop()
  }

  /** Invariants on the written bars (they are small: ~10k rows/week at 1m), so collect is fine. */
  def checkBars(bars: Seq[Bar], tradeCount: Long, label: String): Unit = {
    val tol = 1e-9
    val tradesInBars = bars.map(_.tradeCount).sum
    val vwapOutside = bars.count(b => b.vwap < b.low - tol || b.vwap > b.high + tol)
    val ohlcBad = bars.count(b => b.high < math.max(b.open, b.close) || b.low > math.min(b.open, b.close))
    val imbBad = bars.count(b => b.imbalance < -1 - tol || b.imbalance > 1 + tol)
    println(
      f"  ${bars.size}%,d bars, $tradesInBars%,d trades (input $tradeCount%,d), " +
        s"vwap outside [low,high]: $vwapOutside, bad OHLC: $ohlcBad, imbalance out of [-1,1]: $imbBad"
    )
    require(tradesInBars == tradeCount && vwapOutside == 0 && ohlcBad == 0 && imbBad == 0, s"$label failed checks")
  }
}

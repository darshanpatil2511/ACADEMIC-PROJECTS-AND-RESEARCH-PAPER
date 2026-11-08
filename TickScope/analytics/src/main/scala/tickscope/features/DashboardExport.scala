package tickscope.features

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import org.apache.spark.sql.functions._
import tickscope.{Args, Spark}

/** Small JSON extracts for the static dashboard (everything else comes from the JSON files in results/).
  *
  *  - market_5m.json: 5-minute bars for a date window (close, VWAP, volume, buy volume)
  *  - returns_hist.json: histogram of 1-minute log returns in units of their std dev, with the
  *    count a normal distribution would put in each bin
  *
  * sbt "runMain tickscope.features.DashboardExport --features ../data/features
  *      --from 2026-10-30 --to 2026-11-05 --out ../results"
  */
object DashboardExport {

  /** Standard normal CDF via the Abramowitz-Stegun erf approximation (|error| < 1.5e-7). */
  def normalCdf(z: Double): Double = {
    val x = math.abs(z) / math.sqrt(2)
    val t = 1 / (1 + 0.3275911 * x)
    val erf = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
    0.5 * (1 + math.signum(z) * erf)
  }

  def main(argv: Array[String]): Unit = {
    val o = Args.parse(argv.toSeq)
    val features = Args.required(o, "features")
    val (from, to) = (Args.required(o, "from"), Args.required(o, "to"))
    val out = Paths.get(Args.required(o, "out"))
    val spark = Spark.local("tickscope-dashboard-export")
    try {
      val window = col("date").between(lit(from).cast("date"), lit(to).cast("date"))

      // Bars are small (288/day at 5m), so collecting them is fine.
      val bars = spark.read
        .parquet(s"$features/bars_5m")
        .filter(window)
        .select("barStartUs", "open", "high", "low", "close", "vwap", "volume", "buyVolume")
        .orderBy("barStartUs")
        .collect()
      val barJson = bars
        .map(r =>
          f"[${r.getLong(0) / 1000000L},${r.getDouble(1)}%.2f,${r.getDouble(2)}%.2f,${r.getDouble(3)}%.2f,${r.getDouble(4)}%.2f,${r.getDouble(5)}%.2f,${r.getDouble(6)}%.4f,${r.getDouble(7)}%.4f]"
        )
        .mkString(",\n    ")
      Files.write(
        out.resolve("market_5m.json"),
        s"""{\n  "from": "$from", "to": "$to",\n  "columns": ["tsSec", "open", "high", "low", "close", "vwap", "volumeBtc", "takerBuyVolumeBtc"],\n  "bars": [\n    $barJson\n  ]\n}\n"""
          .getBytes(StandardCharsets.UTF_8)
      )

      // Histogram of standardized 1m returns; aggregation in Spark, only the bins come back.
      val r1m = spark.read.parquet(s"$features/bars_1m").filter(window && col("logReturn").isNotNull)
      val stats = r1m.agg(avg("logReturn"), stddev_samp("logReturn"), count(lit(1))).head()
      val (mu, sd, n) = (stats.getDouble(0), stats.getDouble(1), stats.getLong(2))
      val width = 0.5
      val limit = 8.0 // bins cover [-8, 8) sigma; anything beyond is clamped into the edge bins
      val bins = r1m
        .select(((col("logReturn") - mu) / sd).as("z"))
        .withColumn("bin", floor(greatest(least(col("z"), lit(limit - 1e-9)), lit(-limit)) / width).cast("int"))
        .groupBy("bin")
        .count()
        .collect()
        .map(r => r.getInt(0) -> r.getLong(1))
        .toMap
      val lo = (-limit / width).toInt
      val hi = (limit / width).toInt - 1
      val rows = (lo to hi).map { b =>
        val (a, z) = (b * width, (b + 1) * width)
        val expected = n * (normalCdf(z) - normalCdf(a))
        f"""{"lo": $a%.1f, "hi": $z%.1f, "observed": ${bins.getOrElse(b, 0L)}, "normal": $expected%.3f}"""
      }
      Files.write(
        out.resolve("returns_hist.json"),
        s"""{\n  "from": "$from", "to": "$to", "n": $n, "mean": $mu, "std": $sd, "binWidthSigma": $width,\n  "note": "bins clamp at +/-$limit sigma",\n  "bins": [\n    ${rows.mkString(",\n    ")}\n  ]\n}\n"""
          .getBytes(StandardCharsets.UTF_8)
      )
      println(s"wrote ${out.resolve("market_5m.json")} (${bars.length} bars) and ${out.resolve("returns_hist.json")} ($n returns)")
    } finally spark.stop()
  }
}

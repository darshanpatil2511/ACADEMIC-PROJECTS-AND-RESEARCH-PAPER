package tickscope.bench

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import org.apache.spark.sql.execution.FileSourceScanExec
import org.apache.spark.sql.execution.adaptive.{AQEShuffleReadExec, AdaptiveSparkPlanHelper}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.{DataFrame, SparkSession}
import tickscope.ingest.Cleaning
import tickscope.{Args, Spark}

/** Times the same research workload under five storage/execution variants.
  *
  * Workload (one "run"): over a date window, (Q1) 1-minute OHLCV + VWAP bars and (Q2) a daily
  * summary. Both are written to Spark's `noop` sink, so the full plan executes but no output
  * I/O is timed. Each run uses a fresh SparkSession (session start-up not timed); the OS page
  * cache stays warm across runs, which favours the CSV variant if anything.
  *
  * sbt "runMain tickscope.bench.SparkBench --raw ../data/raw --clean ../data/clean
  *      --from 2026-10-30 --to 2026-11-05 --runs 3 --json ../results/spark_bench.json
  *      --plans ../docs/spark-plans.md"
  */
object SparkBench extends AdaptiveSparkPlanHelper {

  final case class Variant(name: String, description: String, shufflePartitions: Int, cache: Boolean,
                           load: SparkSession => DataFrame)

  /** One timed run: total = cache build (if any) + Q1 + Q2. */
  final case class Run(totalSec: Double, cacheBuildSec: Double, queriesSec: Double)

  /** What the scan really did, from Spark's own SQL metrics after executing Q2. */
  final case class ScanStats(filesRead: Long, partitionsRead: Long, shufflePartitionsAfterAqe: Long, rows: Long)

  final case class Result(variant: Variant, runs: Seq[Run], scan: ScanStats) {
    private def med(xs: Seq[Double]) = xs.sorted.apply(xs.size / 2)
    def median: Double = med(runs.map(_.totalSec))
    def medianCacheBuild: Double = med(runs.map(_.cacheBuildSec))
    def medianQueries: Double = med(runs.map(_.queriesSec))
  }

  /** Q1: 1-minute bars. Shuffle: hash-partition by bar start. */
  def q1Bars(df: DataFrame): DataFrame =
    df.groupBy((floor(col("tsUs") / 60000000L) * 60000000L).as("barStartUs"))
      .agg(
        min_by(col("price"), col("tradeId")).as("open"),
        max("price").as("high"),
        min("price").as("low"),
        max_by(col("price"), col("tradeId")).as("close"),
        sum("qty").as("volume"),
        (sum(col("price") * col("qty")) / sum("qty")).as("vwap"),
        count(lit(1)).as("trades")
      )

  /** Q2: daily summary. Shuffle: hash-partition by date. */
  def q2Daily(df: DataFrame): DataFrame =
    df.groupBy("date")
      .agg(
        count(lit(1)).as("trades"),
        sum("qty").as("volume"),
        (sum(col("price") * col("qty")) / sum("qty")).as("vwap"),
        avg(when(!col("isBuyerMaker"), 1.0).otherwise(0.0)).as("takerBuyShare")
      )

  def variants(raw: String, clean: String, from: String, to: String): Seq[Variant] = {
    val inWindow = col("date").between(lit(from).cast("date"), lit(to).cast("date"))
    def tsBounds(spark: SparkSession): (Long, Long) = {
      val r = spark.sql(s"select unix_micros(timestamp'$from 00:00:00'), unix_micros(timestamp'$to 00:00:00') + 86400000000").head()
      (r.getLong(0), r.getLong(1))
    }
    val cols = Seq("tradeId", "price", "qty", "tsUs", "isBuyerMaker", "date").map(col)

    def csv(spark: SparkSession): DataFrame =
      Cleaning
        .readRaw(spark, raw)
        .withColumn("tsUs", Cleaning.toMicrosCol(col("time")))
        .withColumn("date", to_date(timestamp_micros(col("tsUs"))))
        .withColumn("price", col("price").cast("double"))
        .withColumn("qty", col("qty").cast("double"))
        .filter(inWindow)
        .select(cols: _*)

    def parquetTs(spark: SparkSession): DataFrame = {
      val (lo, hi) = tsBounds(spark)
      spark.read.parquet(clean).filter(col("tsUs") >= lo && col("tsUs") < hi).select(cols: _*)
    }

    def parquetPruned(spark: SparkSession): DataFrame = spark.read.parquet(clean).filter(inWindow).select(cols: _*)

    Seq(
      Variant("1-csv-naive", "gzip CSV re-parsed per query, filter on derived date, 200 shuffle partitions", 200, cache = false, csv),
      Variant("2-parquet", "Parquet, filter on tsUs (row-group pushdown, no partition pruning), 200 partitions", 200, cache = false, parquetTs),
      Variant("3-parquet-pruned", "Parquet, filter on date partition column (partition pruning), 200 partitions", 200, cache = false, parquetPruned),
      Variant("4-pruned-cached", "as 3, filtered input cached in memory before Q1 and Q2", 200, cache = true, parquetPruned),
      Variant("5-pruned-cached-8p", "as 4, spark.sql.shuffle.partitions = 8 (= cores)", 8, cache = true, parquetPruned)
    )
  }

  def runOnce(v: Variant): Run = {
    val spark = Spark.local(s"bench-${v.name}", v.shufflePartitions)
    try {
      val start = System.nanoTime()
      val base = v.load(spark)
      val input = if (v.cache) { val c = base.cache(); c.count(); c } else base
      val afterCache = System.nanoTime()
      q1Bars(input).write.format("noop").mode("overwrite").save()
      q2Daily(input).write.format("noop").mode("overwrite").save()
      val end = System.nanoTime()
      if (v.cache) input.unpersist(blocking = true)
      Run((end - start) / 1e9, (afterCache - start) / 1e9, (end - afterCache) / 1e9)
    } finally spark.stop()
  }

  /** Untimed: execute Q2 on the uncached input and read the scan and shuffle metrics. */
  def scanStats(v: Variant): ScanStats = {
    val spark = Spark.local(s"scan-${v.name}", v.shufflePartitions)
    try {
      val base = v.load(spark)
      val q = q2Daily(base)
      q.collect()
      val plan = q.queryExecution.executedPlan
      val scans = collect(plan) { case s: FileSourceScanExec => s }
      def metric(name: String) = scans.map(s => s.metrics.get(name).map(_.value).getOrElse(0L)).sum
      val shuffleParts = collect(plan) { case r: AQEShuffleReadExec => r.partitionSpecs.size.toLong }.sum
      ScanStats(metric("numFiles"), metric("numPartitions"), shuffleParts, base.count())
    } finally spark.stop()
  }

  def main(argv: Array[String]): Unit = {
    val o = Args.parse(argv.toSeq)
    val (raw, clean) = (Args.required(o, "raw"), Args.required(o, "clean"))
    val (from, to) = (Args.required(o, "from"), Args.required(o, "to"))
    val runs = o.get("runs").fold(3)(_.toInt)
    val only = o.get("only").map(_.split(',').toSet)
    val all = variants(raw, clean, from, to).filter(v => only.forall(_.exists(v.name.startsWith)))

    o.get("plans").foreach(p => writePlans(p, raw, clean, from, to))

    val results = all.map { v =>
      val scan = scanStats(v)
      val rs = (1 to runs).map { i =>
        val r = runOnce(v)
        println(f"  ${v.name}%-20s run $i: ${r.totalSec}%.2f s (cache build ${r.cacheBuildSec}%.2f s, queries ${r.queriesSec}%.2f s)")
        r
      }
      println(f"  ${v.name}%-20s scan: ${scan.filesRead} files, ${scan.partitionsRead} date partitions, ${scan.rows}%,d rows; Q2 shuffle partitions after AQE: ${scan.shufflePartitionsAfterAqe}")
      Result(v, rs, scan)
    }

    val baseline = results.head.median
    println("\n%-20s %9s %8s %11s %9s %6s %6s %9s".format("variant", "median s", "vs csv", "cache s", "query s", "files", "parts", "aqeParts"))
    results.foreach { r =>
      println(f"${r.variant.name}%-20s ${r.median}%9.2f ${baseline / r.median}%7.2fx ${r.medianCacheBuild}%11.2f ${r.medianQueries}%9.2f ${r.scan.filesRead}%6d ${r.scan.partitionsRead}%6d ${r.scan.shufflePartitionsAfterAqe}%9d")
    }

    o.get("json").foreach { p =>
      val body = results.map { r =>
        val rs = r.runs.map(x => f"""{"totalSec": ${x.totalSec}%.3f, "cacheBuildSec": ${x.cacheBuildSec}%.3f, "queriesSec": ${x.queriesSec}%.3f}""").mkString("[", ", ", "]")
        s"""    {"variant": "${r.variant.name}", "description": "${r.variant.description}", "shufflePartitions": ${r.variant.shufflePartitions}, "cache": ${r.variant.cache}, "runs": $rs, "medianSec": ${r.median}, "medianCacheBuildSec": ${r.medianCacheBuild}, "medianQueriesSec": ${r.medianQueries}, "speedupVsCsv": ${baseline / r.median}, "filesRead": ${r.scan.filesRead}, "datePartitionsRead": ${r.scan.partitionsRead}, "q2ShufflePartitionsAfterAqe": ${r.scan.shufflePartitionsAfterAqe}, "rows": ${r.scan.rows}}"""
      }.mkString(",\n")
      val json = s"""{\n  "window": {"from": "$from", "to": "$to"},\n  "runsPerVariant": $runs,\n  "variants": [\n$body\n  ]\n}\n"""
      Files.write(Paths.get(p), json.getBytes(StandardCharsets.UTF_8))
      println(s"wrote $p")
    }
  }

  /** Physical plans for the docs: where the scans prune and where the shuffles are. */
  def writePlans(path: String, raw: String, clean: String, from: String, to: String): Unit = {
    val spark = Spark.local("bench-plans", 8)
    try {
      val vs = variants(raw, clean, from, to)
      def plan(df: DataFrame): String = df.queryExecution.executedPlan.treeString
      val sb = new StringBuilder("# Spark physical plans (generated by SparkBench)\n\n")
      sb ++= s"Window $from to $to. Look for `PartitionFilters` / `PushedFilters` on the scans and `Exchange` (= shuffle) nodes.\n\n"
      Seq(vs(0) -> "Q1 bars on raw CSV", vs(1) -> "Q1 bars on Parquet, tsUs filter", vs(2) -> "Q1 bars on Parquet, date partition filter")
        .foreach { case (v, title) =>
          sb ++= s"## $title (${v.name})\n\n```\n${plan(q1Bars(v.load(spark)))}```\n\n"
        }
      sb ++= s"## Q2 daily summary on Parquet, date partition filter\n\n```\n${plan(q2Daily(vs(2).load(spark)))}```\n"
      Files.write(Paths.get(path), sb.toString.getBytes(StandardCharsets.UTF_8))
      println(s"wrote $path")
    } finally spark.stop()
  }
}

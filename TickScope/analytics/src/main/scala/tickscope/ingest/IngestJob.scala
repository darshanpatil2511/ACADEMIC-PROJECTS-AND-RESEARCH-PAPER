package tickscope.ingest

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import org.apache.hadoop.fs.{FileSystem, Path}
import org.apache.spark.sql.{SaveMode, SparkSession}
import org.apache.spark.storage.StorageLevel
import tickscope.{Args, Spark}

/** Raw trade CSVs (plain or .gz) -> cleaned Parquet partitioned by date, one batch of daily
  * files at a time.
  *
  * Incremental by design: each batch is classified and written on its own, with dynamic
  * partition overwrite (only the dates in the batch are replaced). Peak memory and spill are
  * bounded by one batch, not by the whole date range — a single job over 30 days filled the
  * laptop's disk with spill. Binance daily files do not overlap, so per-batch duplicate and
  * timestamp-order checks lose nothing.
  *
  * sbt "runMain tickscope.ingest.IngestJob --raw ../data/raw --out ../data/clean"
  * Optional: --batch-days N (default 1), --skip-existing true, --shuffle-partitions N (default 8)
  */
object IngestJob {

  /** BTCUSDT-trades-2026-11-05.csv.gz -> 2026-11-05 */
  def dayOf(fileName: String): Option[String] = """(\d{4}-\d{2}-\d{2})""".r.findFirstIn(fileName)

  def main(argv: Array[String]): Unit = {
    val opts = Args.parse(argv.toSeq)
    val rawPath = Args.required(opts, "raw")
    val outPath = Args.required(opts, "out")
    val batchDays = opts.get("batch-days").fold(1)(_.toInt)
    val skipExisting = opts.get("skip-existing").contains("true")
    val spark = Spark.local("tickscope-ingest", opts.get("shuffle-partitions").fold(8)(_.toInt))
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

    try {
      val started = System.nanoTime()
      val fs = FileSystem.get(new Path(rawPath).toUri, spark.sparkContext.hadoopConfiguration)
      val files = fs
        .listStatus(new Path(rawPath))
        .map(_.getPath)
        .filter(p => p.getName.contains(".csv") && !p.getName.endsWith(".part"))
        .sortBy(_.getName)
        .toSeq
      val todo =
        if (!skipExisting) files
        else files.filterNot(p => dayOf(p.getName).exists(d => fs.exists(new Path(outPath, s"date=$d"))))
      println(s"ingesting ${todo.size} of ${files.size} files in batches of $batchDays day(s)")

      val reports = todo.grouped(batchDays).map { batch =>
        val t0 = System.nanoTime()
        val r = ingestBatch(spark, batch.map(_.toString), outPath)
        println(f"  ${batch.flatMap(p => dayOf(p.getName)).mkString(",")}: ${r.rowsRead}%,d read, ${r.rowsKept}%,d kept, ${(System.nanoTime() - t0) / 1e9}%.1f s")
        r
      }.toSeq

      val total = IngestReport(
        rowsRead = reports.map(_.rowsRead).sum,
        rowsKept = reports.map(_.rowsKept).sum,
        dropped = RejectReason.all.map(r => r -> reports.map(_.dropped.getOrElse(r, 0L)).sum).toMap
      )
      // Files starting with "_" are ignored by Spark readers of the dataset.
      Files.createDirectories(Paths.get(outPath))
      Files.write(Paths.get(outPath, "_ingest_report.json"), total.toJson.getBytes(StandardCharsets.UTF_8))

      val secs = (System.nanoTime() - started) / 1e9
      println(s"\nIngest report ($rawPath -> $outPath)\n${total.pretty}\n" + f"elapsed        $secs%.1f s")
    } finally spark.stop()
  }

  def ingestBatch(spark: SparkSession, paths: Seq[String], outPath: String): IngestReport = {
    // The raw scan feeds three branches of the classification; persist so the gzip files are
    // decompressed and parsed once. Serialized storage keeps the footprint small.
    val raw = Cleaning.readRaw(spark, paths: _*).persist(StorageLevel.MEMORY_AND_DISK_SER)
    val classified = Cleaning.classify(raw).persist(StorageLevel.MEMORY_AND_DISK_SER)
    try {
      val report = Cleaning.report(classified)
      Cleaning.cleanTrades(classified).write.mode(SaveMode.Overwrite).partitionBy("date").parquet(outPath)
      report
    } finally {
      classified.unpersist(blocking = true)
      raw.unpersist(blocking = true)
    }
  }
}

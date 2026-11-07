package tickscope.ingest

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths}

import org.apache.spark.sql.SaveMode
import org.apache.spark.storage.StorageLevel
import tickscope.{Args, Spark}

/** Raw trade CSVs (plain or .gz) -> cleaned Parquet partitioned by date.
  *
  * sbt "runMain tickscope.ingest.IngestJob --raw ../data/raw --out ../data/clean"
  * Optional: --shuffle-partitions N (default 8)
  */
object IngestJob {
  def main(argv: Array[String]): Unit = {
    val opts = Args.parse(argv.toSeq)
    val rawPath = Args.required(opts, "raw")
    val outPath = Args.required(opts, "out")
    val spark = Spark.local("tickscope-ingest", opts.get("shuffle-partitions").fold(8)(_.toInt))

    try {
      val started = System.nanoTime()
      // The raw scan feeds three branches of the classification; persist so the gzip
      // files are decompressed and parsed once.
      val raw = Cleaning.readRaw(spark, rawPath).persist(StorageLevel.MEMORY_AND_DISK)
      val classified = Cleaning.classify(raw).persist(StorageLevel.MEMORY_AND_DISK)

      val report = Cleaning.report(classified)
      Cleaning
        .cleanTrades(classified)
        .write
        .mode(SaveMode.Overwrite)
        .partitionBy("date")
        .parquet(outPath)

      // Files starting with "_" are ignored by Spark readers of the dataset.
      Files.write(Paths.get(outPath, "_ingest_report.json"), report.toJson.getBytes(StandardCharsets.UTF_8))

      val secs = (System.nanoTime() - started) / 1e9
      println(s"\nIngest report ($rawPath -> $outPath)\n${report.pretty}\n" + f"elapsed        $secs%.1f s")
      classified.unpersist()
      raw.unpersist()
    } finally spark.stop()
  }
}

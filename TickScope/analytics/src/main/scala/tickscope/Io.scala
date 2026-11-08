package tickscope

import org.apache.hadoop.fs.{FileSystem, Path}
import org.apache.spark.sql.{DataFrame, SaveMode}

object Io {

  /** Write `df` as one CSV file (with header) sorted by `sortCols`.
    *
    * Spark writes a directory of part files, so this writes a single sorted partition to a
    * temp directory and moves the part file to `outFile`. Uses the Hadoop FileSystem API so
    * the same code works for local paths and S3.
    */
  def writeSingleCsv(df: DataFrame, outFile: String, sortCols: String*): Unit = {
    val tmpDir = outFile + ".tmp"
    df.repartition(1)
      .sortWithinPartitions(sortCols.head, sortCols.tail: _*)
      .write
      .mode(SaveMode.Overwrite)
      .option("header", "true")
      .csv(tmpDir)

    val fs = FileSystem.get(new Path(outFile).toUri, df.sparkSession.sparkContext.hadoopConfiguration)
    val out = new Path(outFile)
    val part = fs.globStatus(new Path(tmpDir, "part-*.csv")).head.getPath
    fs.delete(out, false)
    fs.rename(part, out)
    fs.delete(new Path(tmpDir), true)
    // The local filesystem moves the part's checksum sidecar along with it.
    fs.delete(new Path(out.getParent, s".${out.getName}.crc"), false)
  }
}

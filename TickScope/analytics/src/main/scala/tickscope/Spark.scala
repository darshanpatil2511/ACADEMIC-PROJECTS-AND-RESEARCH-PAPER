package tickscope

import org.apache.spark.sql.SparkSession

/** Builds the SparkSession used by every job. All settings come from here or CLI args. */
object Spark {
  def local(appName: String, shufflePartitions: Int = 8): SparkSession =
    SparkSession
      .builder()
      .appName(appName)
      .master("local[*]")
      .config("spark.sql.shuffle.partitions", shufflePartitions.toString)
      .config("spark.sql.session.timeZone", "UTC")
      .config("spark.ui.enabled", "false")
      .getOrCreate()
}

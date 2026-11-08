package tickscope.ingest

import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.{Column, DataFrame, Dataset, SparkSession}

/** Read, validate and clean Binance spot trade CSVs. */
object Cleaning {

  /** Binance spot trade files have no header. Prices and quantities are read as exact
    * decimals so the tick/lot conversion is exact; malformed fields become null.
    */
  val rawSchema: StructType = StructType(
    Seq(
      StructField("tradeId", LongType),
      StructField("price", DecimalType(20, 8)),
      StructField("qty", DecimalType(20, 8)),
      StructField("quoteQty", DecimalType(24, 8)),
      StructField("time", LongType),
      StructField("isBuyerMaker", BooleanType),
      StructField("isBestMatch", BooleanType)
    )
  )

  val TicksPerUnit = 100L      // price tick 0.01 USDT
  val LotsPerUnit = 100000L    // qty lot 1e-5 BTC

  /** Values below this are milliseconds (~1.7e12 today); microseconds are ~1.7e15. */
  val MicrosThreshold = 100000000000000L // 1e14

  /** Binance switched spot files from ms to µs in 2025. Normalize either to µs. */
  def toMicros(ts: Long): Long = if (ts < MicrosThreshold) ts * 1000L else ts

  def toMicrosCol(ts: Column): Column = when(ts < MicrosThreshold, ts * 1000L).otherwise(ts)

  def readRaw(spark: SparkSession, paths: String*): DataFrame =
    spark.read
      .schema(rawSchema)
      .option("header", "false")
      .option("mode", "PERMISSIVE")
      .csv(paths: _*)

  private val Reason = "reject"
  private val noReason: Column = lit(null).cast(StringType)

  /** Tag every raw row with a reject reason (null = keep).
    *
    * Stages, each applied only to rows that survived the previous one:
    *  1. row-local checks (malformed, non-positive, off-grid)   — no shuffle
    *  2. duplicates: row_number over tradeId                    — shuffle by tradeId
    *  3. backwards timestamps: lag(tsUs) over date by tradeId   — shuffle by date + sort
    */
  def classify(raw: DataFrame): DataFrame = {
    val required = Seq("tradeId", "price", "qty", "quoteQty", "time", "isBuyerMaker")
    val malformed = required.map(c => col(c).isNull).reduce(_ || _)
    val nonPositive = col("price") <= 0 || col("qty") <= 0
    val onGrid = (col("price") * TicksPerUnit) % 1 === 0 && (col("qty") * LotsPerUnit) % 1 === 0

    val rowChecked = raw
      .withColumn("tsUs", toMicrosCol(col("time")))
      .withColumn("date", to_date(timestamp_micros(col("tsUs"))))
      .withColumn(
        Reason,
        when(malformed, RejectReason.Malformed)
          .when(nonPositive, RejectReason.NonPositive)
          .when(!onGrid, RejectReason.OffGrid)
          .otherwise(noReason)
      )

    val byTradeId = Window.partitionBy("tradeId").orderBy("tsUs")
    val dupChecked = rowChecked
      .filter(col(Reason).isNull)
      .withColumn("_rn", row_number().over(byTradeId))
      .withColumn(Reason, when(col("_rn") > 1, RejectReason.Duplicate).otherwise(noReason))
      .drop("_rn")

    val byDate = Window.partitionBy("date").orderBy("tradeId")
    val tsChecked = dupChecked
      .filter(col(Reason).isNull)
      .withColumn("_prevTs", lag("tsUs", 1).over(byDate))
      .withColumn(Reason, when(col("tsUs") < col("_prevTs"), RejectReason.BackwardsTs).otherwise(noReason))
      .drop("_prevTs")

    rowChecked
      .filter(col(Reason).isNotNull)
      .unionByName(dupChecked.filter(col(Reason).isNotNull))
      .unionByName(tsChecked)
  }

  /** The kept rows of a classified frame as typed trades. */
  def cleanTrades(classified: DataFrame): Dataset[Trade] = {
    import classified.sparkSession.implicits._
    classified
      .filter(col(Reason).isNull)
      .select(
        col("tradeId"),
        col("price").cast(DoubleType).as("price"),
        col("qty").cast(DoubleType).as("qty"),
        col("quoteQty").cast(DoubleType).as("quoteQty"),
        (col("price") * TicksPerUnit).cast(LongType).as("priceTicks"),
        (col("qty") * LotsPerUnit).cast(LongType).as("qtyLots"),
        col("tsUs"),
        col("isBuyerMaker"),
        col("date")
      )
      .as[Trade]
  }

  /** Counts per reason, from one aggregation over the classified frame. */
  def report(classified: DataFrame): IngestReport = {
    val counts = classified
      .groupBy(coalesce(col(Reason), lit("kept")).as("outcome"))
      .count()
      .collect()
      .map(r => r.getString(0) -> r.getLong(1))
      .toMap
    val kept = counts.getOrElse("kept", 0L)
    val dropped = RejectReason.all.map(r => r -> counts.getOrElse(r, 0L)).toMap
    IngestReport(rowsRead = kept + dropped.values.sum, rowsKept = kept, dropped = dropped)
  }
}

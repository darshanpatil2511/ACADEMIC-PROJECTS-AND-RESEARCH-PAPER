package tickscope.ingest

import java.nio.file.Files
import java.sql.Date

import org.scalatest.funsuite.AnyFunSuite
import tickscope.{Args, SparkTestSession}

/** Fixture `trades_dirty.csv` (15 rows) plants exactly:
  *   malformed 1 (id 4, price "abc"), non_positive 2 (id 5 price 0, id 6 qty < 0),
  *   off_grid 1 (id 7, price 80000.005), duplicate 2 (id 3 three times),
  *   backwards_ts 1 (id 9 earlier than id 8).
  * Kept: ids 1,2,3,8,10 on 2026-11-05 and 11,12,13 on 2026-11-06 (11 and 12 in ms).
  */
class CleaningSpec extends AnyFunSuite with SparkTestSession {
  import spark.implicits._

  private lazy val classified = Cleaning.classify(Cleaning.readRaw(spark, resource("/fixtures/trades_dirty.csv"))).cache()
  private lazy val trades = Cleaning.cleanTrades(classified).collect().sortBy(_.tradeId)

  test("exact drop counts per reason") {
    val report = Cleaning.report(classified)
    assert(report.rowsRead == 15)
    assert(report.rowsKept == 8)
    assert(
      report.dropped == Map(
        RejectReason.Malformed -> 1L,
        RejectReason.NonPositive -> 2L,
        RejectReason.OffGrid -> 1L,
        RejectReason.Duplicate -> 2L,
        RejectReason.BackwardsTs -> 1L
      )
    )
  }

  test("keeps the right rows, one copy of a duplicated tradeId") {
    assert(trades.map(_.tradeId).toSeq == Seq(1L, 2L, 3L, 8L, 10L, 11L, 12L, 13L))
  }

  test("millisecond timestamps are normalized to microseconds and dated in UTC") {
    val t11 = trades.find(_.tradeId == 11L).get
    assert(t11.tsUs == 1793923200000000L)
    assert(t11.date == Date.valueOf("2026-11-06"))
    assert(trades.find(_.tradeId == 1L).get.date == Date.valueOf("2026-11-05"))
  }

  test("ticks and lots are exact integers") {
    val t2 = trades.find(_.tradeId == 2L).get
    assert(t2.priceTicks == 8000001L) // 80000.01 USDT
    assert(t2.qtyLots == 200L)        // 0.002 BTC
    assert(!trades.find(_.tradeId == 1L).get.isBuyerMaker)
  }

  test("toMicros handles both units") {
    assert(Cleaning.toMicros(1793923200000L) == 1793923200000000L)
    assert(Cleaning.toMicros(1793923200000000L) == 1793923200000000L)
  }

  test("writes Parquet partitioned by date that reads back") {
    val out = Files.createTempDirectory("clean").resolve("trades").toString
    Cleaning.cleanTrades(classified).write.partitionBy("date").parquet(out)
    val dirs = new java.io.File(out).list().filter(_.startsWith("date=")).sorted.toSeq
    assert(dirs == Seq("date=2026-11-05", "date=2026-11-06"))
    assert(spark.read.parquet(out).as[Trade].count() == 8L)
  }

  test("taker side: isBuyerMaker=true means the taker sold") {
    val sides = ExportTrades
      .toTakerFlow(Cleaning.cleanTrades(classified))
      .select("tradeId", "side")
      .as[(Long, String)]
      .collect()
      .toMap
    assert(sides(2L) == "S")
    assert(sides(1L) == "B")
  }

  test("Args parses --key value pairs and rejects junk") {
    assert(Args.parse(Seq("--raw", "a", "--out", "b")) == Map("raw" -> "a", "out" -> "b"))
    assertThrows[IllegalArgumentException](Args.parse(Seq("--raw")))
    assertThrows[IllegalArgumentException](Args.parse(Seq("raw", "a")))
  }
}

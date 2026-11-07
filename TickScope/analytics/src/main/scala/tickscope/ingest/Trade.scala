package tickscope.ingest

import java.sql.Date

/** One cleaned trade.
  *
  * `price`/`qty`/`quoteQty` are doubles for research maths (log returns, VWAP).
  * `priceTicks` (0.01 USDT) and `qtyLots` (1e-5 BTC) are the exact integer values the C++
  * engine uses; they are derived from the decimal text, never from the doubles.
  * `isBuyerMaker = true` means the resting order was the buy, so the taker sold.
  */
final case class Trade(
    tradeId: Long,
    price: Double,
    qty: Double,
    quoteQty: Double,
    priceTicks: Long,
    qtyLots: Long,
    tsUs: Long,
    isBuyerMaker: Boolean,
    date: Date
)

/** Why a raw row was rejected. Checked in this order; a row gets the first reason that applies. */
object RejectReason {
  val Malformed = "malformed"       // a required field failed to parse
  val NonPositive = "non_positive"  // price <= 0 or qty <= 0
  val OffGrid = "off_grid"          // price not a multiple of 0.01, or qty not a multiple of 1e-5
  val Duplicate = "duplicate"       // tradeId already seen (first occurrence by time is kept)
  val BackwardsTs = "backwards_ts"  // timestamp earlier than the previous tradeId's, same day

  val all: Seq[String] = Seq(Malformed, NonPositive, OffGrid, Duplicate, BackwardsTs)
}

final case class IngestReport(rowsRead: Long, rowsKept: Long, dropped: Map[String, Long]) {
  def rowsDropped: Long = dropped.values.sum

  def pretty: String = {
    val lines = RejectReason.all.map(r => f"  $r%-14s ${dropped.getOrElse(r, 0L)}%,d")
    (f"rows read      $rowsRead%,d" +: f"rows kept      $rowsKept%,d" +:
      f"rows dropped   $rowsDropped%,d" +: lines).mkString("\n")
  }

  def toJson: String = {
    val drops = RejectReason.all.map(r => s""""$r": ${dropped.getOrElse(r, 0L)}""").mkString(", ")
    s"""{"rowsRead": $rowsRead, "rowsKept": $rowsKept, "dropped": {$drops}}"""
  }
}

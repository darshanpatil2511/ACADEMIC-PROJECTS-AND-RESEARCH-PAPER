package tickscope

import org.scalatest.funsuite.AnyFunSuite

/** Proves Spark starts on Java 17 and runs a typed Dataset job. */
class SparkSmokeSpec extends AnyFunSuite with SparkTestSession {
  test("Spark runs on Java 17") {
    assert(sys.props("java.specification.version") == "17")
  }

  test("local SparkSession runs a typed Dataset aggregation") {
    import spark.implicits._
    assert(Seq(1L, 2L, 3L, 4L).toDS().reduce(_ + _) == 10L)
  }
}

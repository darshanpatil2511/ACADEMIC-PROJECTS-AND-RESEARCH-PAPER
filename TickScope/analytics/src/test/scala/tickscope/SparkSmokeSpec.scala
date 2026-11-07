package tickscope

import org.scalatest.funsuite.AnyFunSuite

/** Phase 0 placeholder: proves Spark starts on Java 17 and runs a typed Dataset job. */
class SparkSmokeSpec extends AnyFunSuite {
  test("Spark runs on Java 17") {
    assert(sys.props("java.specification.version") == "17")
  }

  test("local SparkSession runs a typed Dataset aggregation") {
    val spark = Spark.local("smoke-test", shufflePartitions = 2)
    import spark.implicits._
    try {
      val total = Seq(1L, 2L, 3L, 4L).toDS().reduce(_ + _)
      assert(total == 10L)
    } finally spark.stop()
  }
}

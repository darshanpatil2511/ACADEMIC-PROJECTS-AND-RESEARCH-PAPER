package tickscope

import org.apache.spark.sql.SparkSession
import org.scalatest.{BeforeAndAfterAll, Suite}

/** One local SparkSession per suite. */
trait SparkTestSession extends BeforeAndAfterAll { self: Suite =>
  @transient lazy val spark: SparkSession = Spark.local(getClass.getSimpleName, shufflePartitions = 2)

  override def afterAll(): Unit =
    try spark.stop()
    finally super.afterAll()

  def resource(path: String): String = getClass.getResource(path).getPath
}

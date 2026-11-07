package tickscope.stats

import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.functions._
import org.apache.spark.sql.{Column, DataFrame}

/** Distribution of a series. Skewness and kurtosis are Spark's population moment ratios:
  * skew = m3 / m2^1.5, excessKurtosis = m4 / m2^2 - 3 (0 for a normal distribution).
  */
final case class Moments(
    n: Long,
    mean: Double,
    std: Double,
    skew: Double,
    excessKurtosis: Double,
    min: Double,
    max: Double,
    beyond4Sigma: Long // observations with |x - mean| > 4 std
)

final case class Autocorrelation(lag: Int, n: Long, rho: Double)

/** OLS of y(t+1) on x(t), with naive and Newey-West (HAC) t-statistics for the slope. */
final case class Predictive(
    n: Long,
    pearsonR: Double,
    slope: Double,
    intercept: Double,
    naiveT: Double,
    hacT: Double,
    hacLags: Int
)

/** Summary statistics computed with Spark aggregates and lag windows only — no collect of
  * the input series. Every function expects a frame ordered by `orderCol` (e.g. bar start);
  * the ordering windows have no partition key, so these are meant for bar-level data
  * (~1,440 rows/day), not raw trades.
  */
object Stats {

  def moments(df: DataFrame, c: String): Moments = {
    val x = col(c)
    val clean = df.filter(x.isNotNull)
    val row = clean
      .agg(count(x), avg(x), stddev_samp(x), skewness(x), kurtosis(x), min(x), max(x))
      .head()
    val (mean, std) = (row.getDouble(1), row.getDouble(2))
    val beyond = clean.filter(abs(x - mean) > lit(4 * std)).count()
    Moments(row.getLong(0), mean, std, row.getDouble(3), row.getDouble(4), row.getDouble(5), row.getDouble(6), beyond)
  }

  /** Pearson correlation of x(t) with x(t - k) for k = 1..maxLag, over the pairs that exist. */
  def autocorrelation(df: DataFrame, c: String, orderCol: String, maxLag: Int): Seq[Autocorrelation] = {
    val w = Window.orderBy(orderCol)
    val lagged = (1 to maxLag).foldLeft(df.select(col(orderCol), col(c))) { (acc, k) =>
      acc.withColumn(s"_lag$k", lag(col(c), k).over(w))
    }
    val aggs: Seq[Column] = (1 to maxLag).flatMap { k =>
      val pair = col(c).isNotNull && col(s"_lag$k").isNotNull
      Seq(corr(col(c), col(s"_lag$k")), count(when(pair, lit(1))))
    }
    val row = lagged.agg(aggs.head, aggs.tail: _*).head()
    (1 to maxLag).map(k => Autocorrelation(k, row.getLong(2 * k - 1), row.getDouble(2 * k - 2)))
  }

  /** Newey-West lag rule of thumb: floor(4 * (n / 100)^(2/9)). */
  def neweyWestLags(n: Long): Int = math.floor(4 * math.pow(n / 100.0, 2.0 / 9.0)).toInt

  /** Does x(t) predict y(t+1)? Regress y(t+1) = a + b x(t) + e.
    *
    * naiveT assumes independent, equal-variance errors: t = b / sqrt(s^2 / Sxx).
    * hacT uses the Newey-West estimator, which stays valid when errors are autocorrelated
    * or heteroskedastic (volatility clusters, so they are):
    *   Var(b) = [ sum u_t^2 + 2 sum_{l=1..L} (1 - l/(L+1)) sum u_t u_{t-l} ] / Sxx^2,
    *   u_t = (x_t - xbar) e_t.
    */
  def predictive(df: DataFrame, xCol: String, yCol: String, orderCol: String): Predictive = {
    val w = Window.orderBy(orderCol)
    val pairs = df
      .select(col(orderCol), col(xCol).as("x"), lead(col(yCol), 1).over(w).as("y"))
      .filter(col("x").isNotNull && col("y").isNotNull)
      .cache()

    val s = pairs.agg(count(lit(1)), avg("x"), avg("y"), corr("x", "y")).head()
    val (n, xBar, yBar, r) = (s.getLong(0), s.getDouble(1), s.getDouble(2), s.getDouble(3))
    val m = pairs
      .agg(sum(pow(col("x") - xBar, 2)), sum((col("x") - xBar) * (col("y") - yBar)))
      .head()
    val (sxx, sxy) = (m.getDouble(0), m.getDouble(1))
    val b = sxy / sxx
    val a = yBar - b * xBar

    val lags = neweyWestLags(n)
    val withU = pairs
      .withColumn("e", col("y") - lit(a) - lit(b) * col("x"))
      .withColumn("u", (col("x") - xBar) * col("e"))
    val uLagged = (1 to lags).foldLeft(withU)((acc, l) => acc.withColumn(s"_u$l", lag(col("u"), l).over(w)))
    val sums = (Seq(sum(col("e") * col("e")), sum(col("u") * col("u"))) ++
      (1 to lags).map(l => coalesce(sum(col("u") * col(s"_u$l")), lit(0.0))))
    val q = uLagged.agg(sums.head, sums.tail: _*).head()

    val sse = q.getDouble(0)
    val naiveVar = (sse / (n - 2)) / sxx
    val hacMeat = q.getDouble(1) + 2 * (1 to lags).map(l => (1.0 - l / (lags + 1.0)) * q.getDouble(1 + l)).sum
    val hacVar = hacMeat / (sxx * sxx)
    pairs.unpersist()
    Predictive(n, r, b, a, b / math.sqrt(naiveVar), b / math.sqrt(hacVar), lags)
  }
}

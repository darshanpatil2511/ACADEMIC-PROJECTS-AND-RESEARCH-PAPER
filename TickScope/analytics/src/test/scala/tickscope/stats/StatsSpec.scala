package tickscope.stats

import org.scalatest.funsuite.AnyFunSuite
import tickscope.SparkTestSession

import scala.util.Random

/** Spark implementations checked against straightforward array implementations. */
class StatsSpec extends AnyFunSuite with SparkTestSession {
  import spark.implicits._

  private val tol = 1e-9

  // Reference implementations on plain arrays.
  private def mean(xs: Seq[Double]) = xs.sum / xs.size
  private def pearson(a: Seq[Double], b: Seq[Double]): Double = {
    val (ma, mb) = (mean(a), mean(b))
    val cov = a.zip(b).map { case (x, y) => (x - ma) * (y - mb) }.sum
    cov / math.sqrt(a.map(x => (x - ma) * (x - ma)).sum * b.map(y => (y - mb) * (y - mb)).sum)
  }

  /** AR(1)-ish series so autocorrelation is clearly non-zero, plus a predictor. */
  private lazy val series: Seq[(Long, Double, Double)] = {
    val rnd = new Random(7)
    val x = Array.fill(500)(rnd.nextGaussian())
    val r = new Array[Double](500)
    for (t <- 1 until 500) r(t) = 0.4 * r(t - 1) + 0.3 * x(t - 1) + rnd.nextGaussian()
    (0 until 500).map(t => (t.toLong, r(t), x(t)))
  }
  private lazy val df = series.toDF("t", "r", "x")

  test("moments match hand computation") {
    val xs = Seq(1.0, 2.0, 3.0, 4.0, 10.0)
    val m = Stats.moments(xs.toDF("v"), "v")
    val mu = mean(xs)
    val m2 = xs.map(x => math.pow(x - mu, 2)).sum / xs.size
    val m3 = xs.map(x => math.pow(x - mu, 3)).sum / xs.size
    val m4 = xs.map(x => math.pow(x - mu, 4)).sum / xs.size
    assert(m.n == 5 && m.mean == 4.0 && m.min == 1.0 && m.max == 10.0)
    assert(math.abs(m.std - math.sqrt(xs.map(x => math.pow(x - mu, 2)).sum / 4)) < tol) // sample std
    assert(math.abs(m.skew - m3 / math.pow(m2, 1.5)) < tol)
    assert(math.abs(m.excessKurtosis - (m4 / (m2 * m2) - 3)) < tol)
  }

  test("beyond-4-sigma count") {
    val xs = Seq.fill(99)(0.0) :+ 100.0 // one huge outlier
    assert(Stats.moments(xs.toDF("v"), "v").beyond4Sigma == 1L)
  }

  test("autocorrelation equals Pearson of the lagged pairs") {
    val r = series.map(_._2)
    val acf = Stats.autocorrelation(df, "r", "t", maxLag = 3)
    for (a <- acf) {
      val expected = pearson(r.drop(a.lag), r.dropRight(a.lag))
      assert(a.n == r.size - a.lag)
      assert(math.abs(a.rho - expected) < tol, s"lag ${a.lag}")
    }
    assert(acf.head.rho > 0.3) // the AR(1) structure is detected
  }

  test("predictive regression: slope, naive t and Newey-West t match a reference") {
    val p = Stats.predictive(df, "x", "r", "t")
    val xs = series.map(_._3).dropRight(1)
    val ys = series.map(_._2).drop(1) // y(t+1)
    val n = xs.size
    val (xb, yb) = (mean(xs), mean(ys))
    val sxx = xs.map(x => (x - xb) * (x - xb)).sum
    val b = xs.zip(ys).map { case (x, y) => (x - xb) * (y - yb) }.sum / sxx
    val a = yb - b * xb
    val e = xs.zip(ys).map { case (x, y) => y - a - b * x }
    val naiveT = b / math.sqrt(e.map(v => v * v).sum / (n - 2) / sxx)
    val u = xs.zip(e).map { case (x, ei) => (x - xb) * ei }
    val lags = Stats.neweyWestLags(n.toLong)
    val meat = u.map(v => v * v).sum +
      2 * (1 to lags).map(l => (1 - l / (lags + 1.0)) * (l until n).map(t => u(t) * u(t - l)).sum).sum
    val hacT = b / math.sqrt(meat / (sxx * sxx))

    assert(p.n == n)
    assert(math.abs(p.slope - b) < tol && math.abs(p.intercept - a) < tol)
    assert(math.abs(p.pearsonR - pearson(xs, ys)) < tol)
    assert(math.abs(p.naiveT - naiveT) < 1e-7)
    assert(math.abs(p.hacT - hacT) < 1e-7)
    assert(p.hacLags == lags)
    assert(p.naiveT > 3) // x really does predict y(t+1) in this series
  }

  test("Newey-West lag rule") {
    assert(Stats.neweyWestLags(100) == 4)
    assert(Stats.neweyWestLags(10080) == 11)
  }
}

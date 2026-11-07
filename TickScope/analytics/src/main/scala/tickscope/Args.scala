package tickscope

/** Minimal `--key value` CLI parsing shared by every job. */
object Args {
  def parse(args: Seq[String]): Map[String, String] = {
    require(args.length % 2 == 0, s"expected --key value pairs, got: ${args.mkString(" ")}")
    args
      .grouped(2)
      .map {
        case Seq(k, v) if k.startsWith("--") => k.drop(2) -> v
        case other => throw new IllegalArgumentException(s"expected --key value, got '${other.mkString(" ")}'")
      }
      .toMap
  }

  def required(opts: Map[String, String], key: String): String =
    opts.getOrElse(key, throw new IllegalArgumentException(s"missing required --$key"))
}

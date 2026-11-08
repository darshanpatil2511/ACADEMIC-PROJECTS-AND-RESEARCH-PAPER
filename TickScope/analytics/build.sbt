ThisBuild / scalaVersion := "2.13.14"
ThisBuild / organization := "io.tickscope"
ThisBuild / version := "0.1.0-SNAPSHOT"

val sparkVersion = "3.5.5"

// Spark 3.5 on Java 17 needs these module opens, or it fails at runtime.
val sparkJavaOpens = Seq(
  "java.base/java.lang",
  "java.base/java.lang.invoke",
  "java.base/java.lang.reflect",
  "java.base/java.io",
  "java.base/java.net",
  "java.base/java.nio",
  "java.base/java.util",
  "java.base/java.util.concurrent",
  "java.base/java.util.concurrent.atomic",
  "java.base/sun.nio.ch",
  "java.base/sun.nio.cs",
  "java.base/sun.security.action",
  "java.base/sun.util.calendar"
).map(p => s"--add-opens=$p=ALL-UNNAMED")

// Spark 3.5 supports Java 8/11/17 only. sbt itself may run on any JDK; the forked JVM
// that runs Spark (tests and `run`) uses Java 17, found in this order:
// $TICKSCOPE_JAVA_HOME, Homebrew openjdk@17, else the JDK sbt runs on (CI sets up 17).
val java17Home: Option[File] =
  sys.env.get("TICKSCOPE_JAVA_HOME").map(file)
    .orElse(Seq("/opt/homebrew/opt/openjdk@17", "/usr/local/opt/openjdk@17").map(file).find(_.exists))

lazy val root = (project in file("."))
  .settings(
    name := "tickscope-analytics",
    libraryDependencies ++= Seq(
      // Compile scope (not "provided") so `sbt run` works locally; mark provided for an EMR fat jar.
      "org.apache.spark" %% "spark-sql" % sparkVersion,
      "org.scalatest" %% "scalatest" % "3.2.19" % Test
    ),
    scalacOptions ++= Seq("-deprecation", "-feature", "-unchecked", "-Xlint", "-Wunused"),
    fork := true,
    javaHome := java17Home,
    javaOptions ++= sparkJavaOpens ++ Seq("-Xmx4g"),
    Test / parallelExecution := false,
    run / connectInput := true
  )

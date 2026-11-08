#!/usr/bin/env bash
# Download N days of Binance spot trade files into data/raw/ as gzip-compressed CSVs.
#
# Usage: scripts/download.sh N [END_DATE=yyyy-mm-dd] [SYMBOL=BTCUSDT]
#   END_DATE defaults to two days ago (UTC), so every day is already published.
#
# Each day: download the .zip and its .CHECKSUM, verify SHA-256, re-compress the CSV to
# .csv.gz (Spark reads gzip natively; ~10x smaller on disk than raw CSV), delete the zip.
# Days that already exist are skipped, so the script is safe to re-run.
set -euo pipefail

usage() { echo "usage: $0 N [END_DATE=yyyy-mm-dd] [SYMBOL=BTCUSDT]" >&2; exit 2; }

[[ $# -ge 1 && $1 =~ ^[0-9]+$ && $1 -gt 0 ]] || usage
DAYS=$1
SYMBOL=${3:-BTCUSDT}
BASE_URL="https://data.binance.vision/data/spot/daily/trades/${SYMBOL}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${ROOT}/data/raw"
mkdir -p "$RAW"

# Date arithmetic that works with both BSD (macOS) and GNU (Linux) date.
shift_date() {  # shift_date yyyy-mm-dd days_back
  if date -u -v-1d +%F >/dev/null 2>&1; then
    date -u -j -v-"$2"d -f %F "$1" +%F
  else
    date -u -d "$1 - $2 days" +%F
  fi
}
today_minus() {  # today_minus days_back
  if date -u -v-1d +%F >/dev/null 2>&1; then date -u -v-"$1"d +%F; else date -u -d "-$1 days" +%F; fi
}

sha256_check() {  # sha256_check checksum_file (run inside its directory)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1" >/dev/null
  else shasum -a 256 -c "$1" >/dev/null; fi
}

END_DATE=${2:-$(today_minus 2)}
[[ $END_DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0; skipped=0; missing=0
for ((i = DAYS - 1; i >= 0; i--)); do
  day=$(shift_date "$END_DATE" "$i")
  name="${SYMBOL}-trades-${day}"
  out="${RAW}/${name}.csv.gz"

  if [[ -s $out ]]; then
    echo "skip   $day (already downloaded)"; skipped=$((skipped + 1)); continue
  fi

  if ! curl -fsS -o "${TMP}/${name}.zip" "${BASE_URL}/${name}.zip"; then
    echo "miss   $day (not published)" >&2; missing=$((missing + 1)); continue
  fi
  curl -fsS -o "${TMP}/${name}.zip.CHECKSUM" "${BASE_URL}/${name}.zip.CHECKSUM"

  (cd "$TMP" && sha256_check "${name}.zip.CHECKSUM") \
    || { echo "FAIL   $day checksum mismatch" >&2; exit 1; }

  # Write to a temp name first so an interrupted run never leaves a truncated file.
  unzip -p "${TMP}/${name}.zip" "${name}.csv" | gzip -6 > "${out}.part"
  mv "${out}.part" "$out"
  rm -f "${TMP}/${name}.zip" "${TMP}/${name}.zip.CHECKSUM"

  echo "ok     $day ($(du -h "$out" | cut -f1))"
  ok=$((ok + 1))
done

echo "done: ${ok} downloaded, ${skipped} skipped, ${missing} missing -> ${RAW}"

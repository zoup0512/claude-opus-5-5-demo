#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HDC_BIN="${HDC:-hdc}"
SERIAL="${SERIAL:-}"
BUNDLE="${BUNDLE:-}"
DURATION_SEC="${DURATION_SEC:-600}"
SAMPLE_INTERVAL_SEC="${SAMPLE_INTERVAL_SEC:-5}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/out/$(date +%Y%m%d-%H%M%S)}"
CLEAR_HILOG="${CLEAR_HILOG:-0}"
SOURCE="${SOURCE:-device}"
HILOG_ARGS="${HILOG_ARGS:-}"

usage() {
  cat <<'EOF'
Usage:
  BUNDLE=com.example.pelican ./collect_hilog.sh

Environment:
  HDC=hdc                  hdc executable
  SERIAL=<target>          optional target from `hdc list targets`
  BUNDLE=<bundle>          optional, enables PID / hidumper side sampling
  DURATION_SEC=600         collection duration
  SAMPLE_INTERVAL_SEC=5    hidumper interval
  OUTPUT_DIR=<dir>         output directory
  CLEAR_HILOG=1            clear cached hilog before collection
  HILOG_ARGS="..."          extra arguments passed after `hdc hilog`
  SOURCE=device            report source label

This script never fabricates device data. If hdc/device is absent it exits non-zero;
use `node generate_sample.mjs && node parse_perf.mjs --self-test` for parser-only checks.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

hdc_cmd() {
  if [[ -n "$SERIAL" ]]; then
    "$HDC_BIN" -t "$SERIAL" "$@"
  else
    "$HDC_BIN" "$@"
  fi
}

if ! command -v "$HDC_BIN" >/dev/null 2>&1; then
  echo "collect_hilog: hdc executable not found: $HDC_BIN" >&2
  exit 2
fi

targets="$("$HDC_BIN" list targets 2>&1 || true)"
if [[ -z "$SERIAL" ]] && ! grep -Eq '[[:alnum:]][[:alnum:]_.:-]*' <<<"$targets"; then
  echo "collect_hilog: no HDC target found" >&2
  echo "$targets" >&2
  exit 3
fi

mkdir -p "$OUTPUT_DIR/raw"
printf '%s\n' "$targets" > "$OUTPUT_DIR/raw/hdc-targets.txt"
{
  printf 'started_at=%s\n' "$(date -Iseconds)"
  printf 'duration_sec=%s\n' "$DURATION_SEC"
  printf 'sample_interval_sec=%s\n' "$SAMPLE_INTERVAL_SEC"
  printf 'bundle=%s\n' "$BUNDLE"
  printf 'serial=%s\n' "$SERIAL"
  printf 'source=%s\n' "$SOURCE"
} > "$OUTPUT_DIR/run.env"

if [[ "$CLEAR_HILOG" == "1" ]]; then
  hdc_cmd shell hilog -r > "$OUTPUT_DIR/raw/hilog-clear.txt" 2>&1 || true
fi

pid_for_bundle() {
  [[ -n "$BUNDLE" ]] || return 1
  local value
  value="$(hdc_cmd shell pidof "$BUNDLE" 2>/dev/null | tr -d '\r' | tr ' ' '\n' | grep -E '^[0-9]+$' | head -n 1 || true)"
  if [[ -z "$value" ]]; then
    value="$(hdc_cmd shell "ps -A 2>/dev/null | grep '$BUNDLE' | grep -v grep" 2>/dev/null | tr -d '\r' | grep -Eo '[0-9]+' | head -n 1 || true)"
  fi
  [[ -n "$value" ]] && printf '%s\n' "$value"
}

side_sampler() {
  local end=$((SECONDS + DURATION_SEC))
  local index=0
  while (( SECONDS < end )); do
    local stamp pid
    stamp="$(date +%Y%m%d-%H%M%S)"
    pid="$(pid_for_bundle || true)"
    {
      printf 'timestamp=%s\n' "$(date -Iseconds)"
      printf 'pid=%s\n' "$pid"
      if [[ -n "$pid" ]]; then
        echo '--- hidumper --mem ---'
        hdc_cmd shell hidumper --mem "$pid" 2>&1 || true
        echo '--- hidumper --cpuusage ---'
        hdc_cmd shell hidumper --cpuusage "$pid" 2>&1 || true
        echo '--- RenderService process memory ---'
        hdc_cmd shell hidumper -s RenderService -a "dumpExistPidMem $pid" 2>&1 || true
      fi
      echo '--- RenderService gles ---'
      if (( index == 0 )); then hdc_cmd shell hidumper -s RenderService -a gles 2>&1 || true; fi
      echo '--- RenderService allSurfacesMem ---'
      hdc_cmd shell hidumper -s RenderService -a allSurfacesMem 2>&1 || true
    } > "$OUTPUT_DIR/raw/diag-${stamp}-${index}.txt"
    index=$((index + 1))
    sleep "$SAMPLE_INTERVAL_SEC"
  done
}

side_sampler &
SIDE_PID=$!
trap 'kill "$SIDE_PID" 2>/dev/null || true' EXIT INT TERM

hilog_file="$OUTPUT_DIR/raw/hilog.txt"
if command -v timeout >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  timeout --signal=INT "${DURATION_SEC}s" hdc_cmd hilog $HILOG_ARGS > "$hilog_file" 2>&1 || status=$?
  status="${status:-0}"
  if [[ "$status" != "0" && "$status" != "124" && "$status" != "130" ]]; then
    echo "collect_hilog: hdc hilog exited with $status" >&2
    exit "$status"
  fi
else
  # Portable fallback for environments without GNU timeout.
  # shellcheck disable=SC2086
  hdc_cmd hilog $HILOG_ARGS > "$hilog_file" 2>&1 &
  HILOG_PID=$!
  sleep "$DURATION_SEC"
  kill -INT "$HILOG_PID" 2>/dev/null || true
  wait "$HILOG_PID" 2>/dev/null || true
fi

wait "$SIDE_PID" 2>/dev/null || true
trap - EXIT INT TERM

node "$SCRIPT_DIR/parse_perf.mjs" \
  --input "$hilog_file" \
  --output-json "$OUTPUT_DIR/report.json" \
  --output-md "$OUTPUT_DIR/report.md" \
  --source "$SOURCE"

echo "collection complete: $OUTPUT_DIR"

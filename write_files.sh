#!/usr/bin/env bash
# Writes files every minute so that TOTAL_MB is consumed in TOTAL_MIN minutes.
# Modes:
#   fixed   - each file is equal sized
#   fib     - writes grow following a Fibonacci sequence
#
# Usage:
#   ./write_files.sh <total_mb> <total_minutes> [target_dir] [fixed|fib]

set -euo pipefail

### --- Argument validation ---
if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 <total_mb> <total_minutes> [target_dir] [fixed|fib]"
  exit 1
fi

TOTAL_MB="$1"
TOTAL_MIN="$2"
TARGET_DIR="${3:-/data/tmp}"
MODE="${4:-fixed}"   # fixed (default) or fib

if ! [[ "$TOTAL_MB" =~ ^[0-9]+$ && "$TOTAL_MIN" =~ ^[0-9]+$ ]]; then
  echo "Error: values must be positive integers."
  exit 1
fi

if (( TOTAL_MB < 1 || TOTAL_MIN < 1 )); then
  echo "Error: values must be >= 1."
  exit 1
fi

mkdir -p "$TARGET_DIR"

### --- Hard stop disk protection (>99.9%) ---
check_disk_usage() {
  local path="$1"
  local usage
  usage=$(df -P "$path" | awk 'NR==2 {print $5}' | sed 's/%//')

  if (( usage >= 99 )); then
    echo "❌ ERROR: Disk usage exceeded safe threshold (>99.9%). Aborting."
    exit 1
  fi
}

### --- Progress bar ---
progress_bar() {
  local current=$1
  local total=$2
  local width=40

  local percent=$(( 100 * current / total ))
  local filled=$(( width * current / total ))
  local empty=$(( width - filled ))

  printf "\r["
  printf "%0.s#" $(seq 1 $filled)
  printf "%0.s-" $(seq 1 $empty)
  printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

### --- Compute file sizes by mode ---
declare -a FILE_SIZES

if [[ "$MODE" == "fixed" ]]; then
  BASE=$(( TOTAL_MB / TOTAL_MIN ))
  REM=$(( TOTAL_MB % TOTAL_MIN ))

  if (( BASE < 1 )); then
    echo "Error: total_mb must be >= total_minutes in fixed mode."
    exit 1
  fi

  for (( i=1; i<=TOTAL_MIN; i++ )); do
    if (( i == TOTAL_MIN )); then
      FILE_SIZES+=($(( BASE + REM )))
    else
      FILE_SIZES+=($BASE)
    fi
  done

elif [[ "$MODE" == "fib" ]]; then
  # Step 1: Generate Fibonacci sequence
  fib=(1 1)
  for (( i=2; i<TOTAL_MIN; i++ )); do
    fib[$i]=$(( fib[i-1] + fib[i-2] ))
  done

  # Step 2: Sum raw Fibonacci values
  raw_sum=0
  for v in "${fib[@]}"; do raw_sum=$(( raw_sum + v )); done

  # Step 3: Determine scaling factor
  scale=$(awk "BEGIN {printf \"%.6f\", $TOTAL_MB / $raw_sum}")

  # Step 4: Create scaled integer sizes
  total_assigned=0
  for (( i=0; i<TOTAL_MIN; i++ )); do
    mb=$(awk "BEGIN {printf \"%d\", ${fib[$i]} * $scale}")
    FILE_SIZES+=("$mb")
    total_assigned=$(( total_assigned + mb ))
  done

  # Step 5: Fix any rounding discrepancies
  missing=$(( TOTAL_MB - total_assigned ))
  FILE_SIZES[$((TOTAL_MIN - 1))]=$(( FILE_SIZES[TOTAL_MIN - 1] + missing ))

else
  echo "Error: mode must be 'fixed' or 'fib'"
  exit 1
fi

### --- Summary ---
echo "----------------------------------------------------------"
echo "Total write:        ${TOTAL_MB} MB"
echo "Total minutes:      ${TOTAL_MIN}"
echo "Pattern mode:       ${MODE}"
echo "Output directory:   ${TARGET_DIR}"
echo "Safety stop:        Hard stop if disk > 99.9%"
echo "----------------------------------------------------------"

echo "File sizes by minute:"
for (( i=0; i<TOTAL_MIN; i++ )); do
  echo "  Minute $((i+1)): ${FILE_SIZES[$i]} MB"
done
echo "----------------------------------------------------------"
echo

trap 'echo; echo "Stopping..."; exit 0' INT

### --- Main write loop ---
for (( minute=1; minute<=TOTAL_MIN; minute++ )); do
  check_disk_usage "$TARGET_DIR"

  SIZE_MB=${FILE_SIZES[$((minute - 1))]}
  UUID=$(uuidgen)
  OUTFILE="${TARGET_DIR}/file_${SIZE_MB}MB_${UUID}.bin"

  echo
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Writing ${SIZE_MB} MB → $OUTFILE"

  dd if=/dev/zero of="$OUTFILE" bs=1M count="$SIZE_MB" status=none

  progress_bar "$minute" "$TOTAL_MIN"

  if (( minute < TOTAL_MIN )); then
    sleep 60
  fi
done

echo
echo "✅ Completed writing ${TOTAL_MB} MB over ${TOTAL_MIN} minutes in ${MODE} mode."

#!/usr/bin/env bash
# Writes files every minute so that TOTAL_MB is consumed in TOTAL_MIN minutes.
# Adds:
#   - Progress bar
#   - Hard stop if disk usage exceeds 99.9%
#
# Usage: ./write_fixed_rate_files.sh <total_mb> <total_minutes> [target_dir]

set -euo pipefail

### --- Argument validation ---
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <total_mb> <total_minutes> [target_dir]"
  exit 1
fi

TOTAL_MB="$1"
TOTAL_MIN="$2"
TARGET_DIR="${3:-/data/tmp}"

if ! [[ "$TOTAL_MB" =~ ^[0-9]+$ && "$TOTAL_MIN" =~ ^[0-9]+$ ]]; then
  echo "Error: total_mb and total_minutes must be positive integers."
  exit 1
fi

if (( TOTAL_MB < 1 || TOTAL_MIN < 1 )); then
  echo "Error: values must be >= 1."
  exit 1
fi

### --- Compute per-file sizes ---
FILE_SIZE_MB=$(( TOTAL_MB / TOTAL_MIN ))
REMAINDER_MB=$(( TOTAL_MB % TOTAL_MIN ))

if (( FILE_SIZE_MB < 1 )); then
  echo "Error: total_mb must be >= total_minutes (minimum 1 MB per file)."
  exit 1
fi

mkdir -p "$TARGET_DIR"

### --- Hard stop disk safety check ---
check_disk_usage() {
  local path="$1"
  local usage
  usage=$(df -P "$path" | awk 'NR==2 {print $5}' | sed 's/%//')

  if (( usage >= 100 )); then
    echo "❌ ERROR: Disk is full. Canceling to prevent system issues."
    exit 1
  fi

  if (( usage >= 99 )); then
    # >= 99% includes 99.9% because df rounds down, so we treat 99% as dangerous
    echo "❌ ERROR: Disk usage exceeded safe threshold (>99.9%). Script aborted."
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

echo "----------------------------------------------------------"
echo "Total write:        ${TOTAL_MB} MB"
echo "Total minutes:      ${TOTAL_MIN}"
echo "File size:          ${FILE_SIZE_MB} MB"
echo "Remainder:          ${REMAINDER_MB} MB added to final file"
echo "Output directory:   ${TARGET_DIR}"
echo "Safety stop:        Hard stop if disk > 99.9% full"
echo "----------------------------------------------------------"
echo "Starting... Press Ctrl+C to stop."
echo

trap 'echo; echo "Stopping..."; exit 0' INT

### --- Main loop ---
for (( minute=1; minute<=TOTAL_MIN; minute++ )); do
  check_disk_usage "$TARGET_DIR"

  SIZE_THIS_FILE_MB=$FILE_SIZE_MB
  if (( minute == TOTAL_MIN && REMAINDER_MB > 0 )); then
    SIZE_THIS_FILE_MB=$(( FILE_SIZE_MB + REMAINDER_MB ))
  fi

  UUID=$(uuidgen)
  OUTFILE="${TARGET_DIR}/file_${SIZE_THIS_FILE_MB}MB_${UUID}.bin"

  echo
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Writing ${SIZE_THIS_FILE_MB} MB → $OUTFILE"

  dd if=/dev/zero of="$OUTFILE" bs=1M count="$SIZE_THIS_FILE_MB" status=none

  echo "Done."

  progress_bar "$minute" "$TOTAL_MIN"

  if (( minute < TOTAL_MIN )); then
    sleep 60
  fi
done

echo
echo
echo "✅ Completed writing ${TOTAL_MB} MB over ${TOTAL_MIN} minutes."

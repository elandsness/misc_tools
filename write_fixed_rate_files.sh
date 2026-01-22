#!/usr/bin/env bash
# Writes files every minute such that TOTAL_MB is consumed in TOTAL_MIN minutes.
# Usage: ./write_fixed_rate_files.sh <total_mb> <total_minutes> [target_dir]

set -euo pipefail

# --- Argument validation ---
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <total_mb> <total_minutes> [target_dir]"
  echo "Example: $0 500 60"
  echo "Example: $0 500 60 /var/tmp"
  exit 1
fi

TOTAL_MB="$1"
TOTAL_MIN="$2"
TARGET_DIR="${3:-/data/tmp}"   # Optional override

# Validate positive integers
if ! [[ "$TOTAL_MB" =~ ^[0-9]+$ && "$TOTAL_MIN" =~ ^[0-9]+$ ]]; then
  echo "Error: total_mb and total_minutes must be positive integers."
  exit 1
fi

if (( TOTAL_MB < 1 )); then
  echo "Error: total_mb must be >= 1."
  exit 1
fi

if (( TOTAL_MIN < 1 )); then
  echo "Error: total_minutes must be >= 1."
  exit 1
fi

# --- Determine file size per minute ---
FILE_SIZE_MB=$(( TOTAL_MB / TOTAL_MIN ))
REMAINDER_MB=$(( TOTAL_MB % TOTAL_MIN ))

if (( FILE_SIZE_MB < 1 )); then
  echo "Error: total_mb must be >= total_minutes (minimum 1MB per file)."
  exit 1
fi

mkdir -p "$TARGET_DIR"

echo "----------------------------------------------------------"
echo "Total to write:     ${TOTAL_MB} MB"
echo "Total minutes:      ${TOTAL_MIN}"
echo "Files per minute:   1"
echo "File size:          ${FILE_SIZE_MB} MB"
echo "Extra MB remainder: ${REMAINDER_MB} MB added to final file"
echo "Output directory:   ${TARGET_DIR}"
echo "----------------------------------------------------------"
echo "Starting... Press Ctrl+C to stop."
echo

# Clean exit on Ctrl+C
trap 'echo; echo "Stopping..."; exit 0' INT

# --- Main loop ---
for (( minute=1; minute<=TOTAL_MIN; minute++ )); do
  SIZE_THIS_FILE_MB=$FILE_SIZE_MB

  # Add remainder to the final file so total is exactly TOTAL_MB
  if (( minute == TOTAL_MIN && REMAINDER_MB > 0 )); then
    SIZE_THIS_FILE_MB=$(( FILE_SIZE_MB + REMAINDER_MB ))
  fi

  UUID=$(uuidgen)
  OUTFILE="${TARGET_DIR}/file_${SIZE_THIS_FILE_MB}MB_${UUID}.bin"

  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Writing ${SIZE_THIS_FILE_MB} MB → $OUTFILE"

  dd if=/dev/zero of="$OUTFILE" bs=1M count="$SIZE_THIS_FILE_MB" status=none

  echo "Done."

  # Don't sleep after the last file
  if (( minute < TOTAL_MIN )); then
    sleep 60
  fi
done

echo
echo "Completed writing ${TOTAL_MB} MB over ${TOTAL_MIN} minutes."

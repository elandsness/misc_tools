#!/usr/bin/env bash
# Creates a new file of random size between MIN_MB ($1) and MAX_MB ($2)
# every INTERVAL_SEC ($3) seconds in TARGET_DIR ($4, default: /data/tmp).

set -euo pipefail

# --- Usage & validation ---
if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <min_mb> <max_mb> <interval_sec> [target_dir]"
  echo "Example: $0 5 20 30              # uses default /data/tmp"
  echo "Example: $0 5 20 30 /var/tmp     # write to /var/tmp"
  exit 1
fi

MIN_MB="$1"
MAX_MB="$2"
INTERVAL_SEC="$3"
TARGET_DIR="${4:-/data/tmp}"  # default if not provided

# Ensure arguments are positive integers
if ! [[ "$MIN_MB" =~ ^[0-9]+$ && "$MAX_MB" =~ ^[0-9]+$ && "$INTERVAL_SEC" =~ ^[0-9]+$ ]]; then
  echo "Error: min_mb, max_mb, and interval_sec must be positive integers."
  exit 1
fi

if (( MIN_MB < 1 )); then
  echo "Error: min_mb must be at least 1."
  exit 1
fi

if (( MAX_MB < MIN_MB )); then
  echo "Error: max_mb must be greater than or equal to min_mb."
  exit 1
fi

if (( INTERVAL_SEC < 1 )); then
  echo "Error: interval_sec must be at least 1."
  exit 1
fi

# Prepare target directory
mkdir -p "$TARGET_DIR"

echo "Writing a new file every ${INTERVAL_SEC}s to $TARGET_DIR with size between $MIN_MB and $MAX_MB MB."
echo "Press Ctrl+C to stop."

# Clean stop on Ctrl+C
trap 'echo; echo "Stopping..."; exit 0' INT

# --- Main loop ---
while true; do
  # Pick a random size in [MIN_MB, MAX_MB]
  RANGE=$((MAX_MB - MIN_MB + 1))
  SIZE_MB=$((RANDOM % RANGE + MIN_MB))

  # Timestamped filename (with random suffix to avoid collisions)
  TS="$(date +'%Y%m%d_%H%M%S')"
  RANDHEX="$(printf '%04x' $RANDOM)"
  OUTFILE="$TARGET_DIR/random_${SIZE_MB}MB_${TS}_${RANDHEX}.bin"

  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Creating $OUTFILE (${SIZE_MB} MB)..."

  # Create the file with exact size using dd from /dev/zero (fast and portable)
  # For random content, replace /dev/zero with /dev/urandom (slower).
  dd if=/dev/zero of="$OUTFILE" bs=1M count="$SIZE_MB" status=none

  echo "Done: $(ls -lh "$OUTFILE" | awk '{print $5, $9}')"
  sleep "$INTERVAL_SEC"
done

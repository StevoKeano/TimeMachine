#!/bin/bash
# tm_versions.sh — list all Time Machine snapshot versions of a file
# Usage: sudo ./tm_versions.sh /Users/Steve/.openclaw/openclaw.json

set -e

TARGET="$1"

if [ -z "$TARGET" ]; then
  echo "Usage: sudo $0 <absolute-file-path>"
  echo "Example: sudo $0 /Users/Steve/.openclaw/openclaw.json"
  exit 1
fi

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: Must run with sudo"
  exit 1
fi

DISK="disk1s1"
MNT="/tmp/tm_snapmnt"
mkdir -p "$MNT"

echo ""
echo "Searching Time Machine snapshots for: $TARGET"
echo "=================================================="
echo ""

PREV_MD5=""
COUNT=0
BASENAME=$(basename "$TARGET")

for snap in $(diskutil apfs listSnapshots $DISK | grep "com.apple.TimeMachine" | awk '{print $3}'); do
  mount_apfs -s "$snap" /dev/"$DISK" "$MNT" 2>/dev/null
  f="$MNT$TARGET"
  if [ -f "$f" ]; then
    HASH=$(md5 -q "$f")
    SIZE=$(ls -al "$f" | awk '{print $5}')
    DATE=$(ls -al "$f" | awk '{print $6, $7, $8}')

    if [ "$HASH" != "$PREV_MD5" ]; then
      COUNT=$((COUNT + 1))
      LABEL="VERSION $COUNT"
    else
      LABEL="  unchanged  "
    fi

    echo "----------------------------------------------------------------------"
    printf "%-14s  %-45s  %s  %6s bytes  %s\n" "$LABEL" "$snap" "$DATE" "$SIZE" "$HASH"
    if [ "$HASH" != "$PREV_MD5" ]; then
      echo ""
      echo "  # Restore commands for VERSION $COUNT:"
      echo "  sudo mount_apfs -s $snap /dev/$DISK $MNT"
      echo "  cp \"$MNT$TARGET\" /tmp/${BASENAME}.v${COUNT}"
      echo "  sudo umount $MNT"
    fi
    PREV_MD5="$HASH"
  fi
  umount "$MNT" 2>/dev/null
done

echo "======================================================================"
echo "Total unique versions found: $COUNT"

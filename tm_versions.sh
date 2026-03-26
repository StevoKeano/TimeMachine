#!/bin/bash
# tm_versions.sh — Interactive Time Machine file version browser
# Usage:
#   sudo ./tm_versions.sh /absolute/path/to/file   — search for file versions
#   sudo ./tm_versions.sh --reset                  — clear saved config
#   sudo ./tm_versions.sh --list                   — list sources/snapshots only
#
# Config saved to ~/.tm_versions.conf

set -e

CONF="$HOME/.tm_versions.conf"
MNT="/tmp/tm_snapmnt"
MODE="search"

# ── Parse args ────────────────────────────────────────────────────────────────
if [ "$1" = "--reset" ]; then
  rm -f "$CONF"
  echo "Config cleared. Run again to reconfigure."
  exit 0
fi

if [ "$1" = "--list" ]; then
  MODE="list"
  TARGET=""
elif [ -z "$1" ]; then
  echo "Usage:"
  echo "  sudo $0 /absolute/path/to/file   — search for file versions"
  echo "  sudo $0 --reset                  — clear saved config"
  echo "  sudo $0 --list                   — list available sources and snapshots"
  exit 1
else
  TARGET="$1"
  if [[ "$TARGET" != /* ]]; then
    echo "ERROR: Path must be absolute (starting with /)"
    exit 1
  fi
fi

if [ "$(id -u)" != "0" ]; then
  echo "ERROR: Must run with sudo"
  exit 1
fi

# ── Load or build config ──────────────────────────────────────────────────────
load_config() {
  if [ -f "$CONF" ]; then
    source "$CONF"
    return 0
  fi
  return 1
}

save_config() {
  cat > "$CONF" << EOF
TM_SOURCE_TYPE="$TM_SOURCE_TYPE"
TM_DISK="$TM_DISK"
TM_BACKUPDB="$TM_BACKUPDB"
TM_MACHINE="$TM_MACHINE"
EOF
  chmod 600 "$CONF"
  echo "Config saved to $CONF"
}

# ── Discover backup sources ───────────────────────────────────────────────────
discover_sources() {
  echo ""
  echo "======================================================================"
  echo "  Discovering Time Machine backup sources..."
  echo "======================================================================"
  echo ""

  SOURCES=()
  LABELS=()
  IDX=0

  # Local APFS snapshots
  while IFS= read -r disk; do
    count=$(diskutil apfs listSnapshots "$disk" 2>/dev/null | grep -c "com.apple.TimeMachine" || true)
    if [ "$count" -gt 0 ]; then
      IDX=$((IDX + 1))
      name=$(diskutil info "$disk" 2>/dev/null | grep "Volume Name" | awk -F: '{print $2}' | xargs)
      SOURCES+=("local|$disk")
      LABELS+=("[$IDX] LOCAL APFS snapshots on $disk ($name) — $count snapshots")
    fi
  done < <(diskutil apfs list 2>/dev/null | grep "APFS Volume Disk" | awk '{print $4}')

  # External Time Machine drives
  for vol in /Volumes/*/; do
    backupdb="${vol}Backups.backupdb"
    if [ -d "$backupdb" ]; then
      volname=$(basename "$vol")
      machines=$(ls "$backupdb" 2>/dev/null | head -3 | tr '\n' ', ')
      IDX=$((IDX + 1))
      SOURCES+=("external|$vol")
      LABELS+=("[$IDX] EXTERNAL drive: $volname — machines: $machines")
    fi
  done

  if [ ${#SOURCES[@]} -eq 0 ]; then
    echo "ERROR: No Time Machine backup sources found."
    exit 1
  fi

  for label in "${LABELS[@]}"; do
    echo "  $label"
  done
  echo ""
}

# ── Choose source interactively ───────────────────────────────────────────────
choose_source() {
  discover_sources
  read -p "Select source number [1-${#SOURCES[@]}]: " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#SOURCES[@]}" ]; then
    echo "Invalid choice."
    exit 1
  fi

  selected="${SOURCES[$((choice-1))]}"
  TM_SOURCE_TYPE=$(echo "$selected" | cut -d'|' -f1)
  TM_SOURCE_PATH=$(echo "$selected" | cut -d'|' -f2)

  if [ "$TM_SOURCE_TYPE" = "local" ]; then
    TM_DISK="$TM_SOURCE_PATH"
    TM_BACKUPDB=""
    TM_MACHINE=""
  else
    TM_DISK=""
    TM_BACKUPDB="${TM_SOURCE_PATH}Backups.backupdb"
    machines=($(ls "$TM_BACKUPDB" 2>/dev/null))
    if [ ${#machines[@]} -eq 1 ]; then
      TM_MACHINE="${machines[0]}"
    else
      echo ""
      echo "Multiple machines found:"
      for i in "${!machines[@]}"; do
        echo "  [$((i+1))] ${machines[$i]}"
      done
      read -p "Select machine [1-${#machines[@]}]: " mchoice
      TM_MACHINE="${machines[$((mchoice-1))]}"
    fi
  fi

  save_config
}

# ── List snapshots for chosen source ─────────────────────────────────────────
list_snapshots() {
  echo ""
  echo "======================================================================"
  echo "  Available snapshots"
  echo "======================================================================"
  echo ""

  SNAPSHOTS=()

  if [ "$TM_SOURCE_TYPE" = "local" ]; then
    while IFS= read -r snap; do
      SNAPSHOTS+=("$snap")
      printf "  %3d.  %s\n" "${#SNAPSHOTS[@]}" "$snap"
    done < <(diskutil apfs listSnapshots "$TM_DISK" 2>/dev/null | grep "com.apple.TimeMachine" | awk '{print $3}')
  else
    while IFS= read -r snap; do
      SNAPSHOTS+=("$snap")
      printf "  %3d.  %s\n" "${#SNAPSHOTS[@]}" "$snap"
    done < <(ls "$TM_BACKUPDB/$TM_MACHINE/" 2>/dev/null | sort)
  fi

  echo ""
  echo "  Total: ${#SNAPSHOTS[@]} snapshots"
  echo ""
}

# ── Choose snapshot range ─────────────────────────────────────────────────────
choose_range() {
  list_snapshots
  total=${#SNAPSHOTS[@]}

  echo "  [A] All snapshots"
  echo "  [R] Range (enter start and end numbers)"
  echo "  [L] Last N snapshots"
  echo ""
  read -p "Select range [A/R/L]: " rchoice

  case "${rchoice^^}" in
    A)
      SNAP_RANGE=("${SNAPSHOTS[@]}")
      ;;
    R)
      read -p "Start number [1-$total]: " rstart
      read -p "End number [$rstart-$total]: " rend
      SNAP_RANGE=("${SNAPSHOTS[@]:$((rstart-1)):$((rend-rstart+1))}")
      ;;
    L)
      read -p "Last how many snapshots? " nlast
      SNAP_RANGE=("${SNAPSHOTS[@]: -$nlast}")
      ;;
    *)
      echo "Invalid. Using all."
      SNAP_RANGE=("${SNAPSHOTS[@]}")
      ;;
  esac

  echo ""
  echo "  Searching ${#SNAP_RANGE[@]} snapshots..."
  echo ""
}

# ── Print version entry ───────────────────────────────────────────────────────
PREV_MD5=""
COUNT=0
SNAP_PATH_FOR_RESTORE=""

print_version() {
  local snap="$1" hash="$2" size="$3" date="$4" type="$5" fpath="$6"
  BASENAME=$(basename "$TARGET")

  if [ "$hash" != "$PREV_MD5" ]; then
    COUNT=$((COUNT + 1))
    LABEL="VERSION $COUNT"
    echo "----------------------------------------------------------------------"
    printf "%-12s  %-50s  %s  %7s bytes  %s\n" "$LABEL" "$snap" "$date" "$size" "$hash"
    echo ""
    echo "  # Restore commands for VERSION $COUNT:"
    if [ "$type" = "local" ]; then
      echo "  sudo mount_apfs -s $snap /dev/$TM_DISK $MNT"
      echo "  cp \"$MNT$TARGET\" /tmp/${BASENAME}.v${COUNT}"
      echo "  sudo umount $MNT"
    else
      echo "  cp \"$fpath\" /tmp/${BASENAME}.v${COUNT}"
    fi
    echo ""
  else
    echo "----------------------------------------------------------------------"
    printf "  unchanged     %-50s  %s  %7s bytes\n" "$snap" "$date" "$size"
  fi

  PREV_MD5="$hash"
}

# ── Search local snapshot ─────────────────────────────────────────────────────
search_local_snapshot() {
  local snap="$1"
  mkdir -p "$MNT"
  mount_apfs -s "$snap" /dev/"$TM_DISK" "$MNT" 2>/dev/null || return 0
  local f="$MNT$TARGET"
  if [ -f "$f" ]; then
    local hash size date
    hash=$(md5 -q "$f")
    size=$(ls -al "$f" | awk '{print $5}')
    date=$(ls -al "$f" | awk '{print $6, $7, $8}')
    print_version "$snap" "$hash" "$size" "$date" "local" "$f"
  fi
  umount "$MNT" 2>/dev/null || true
}

# ── Search external snapshot ──────────────────────────────────────────────────
search_external_snapshot() {
  local snap="$1"
  local fpath="$TM_BACKUPDB/$TM_MACHINE/$snap/Macintosh HD - Data$TARGET"
  if [ ! -f "$fpath" ]; then
    fpath="$TM_BACKUPDB/$TM_MACHINE/$snap$TARGET"
  fi
  if [ -f "$fpath" ]; then
    local hash size date
    hash=$(md5 -q "$fpath")
    size=$(ls -al "$fpath" | awk '{print $5}')
    date=$(ls -al "$fpath" | awk '{print $6, $7, $8}')
    print_version "$snap" "$hash" "$size" "$date" "external" "$fpath"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Load or configure
if ! load_config; then
  echo "No config found — let's set up your backup source."
  choose_source
else
  echo ""
  echo "Using saved config: $TM_SOURCE_TYPE source${TM_DISK:+ — disk $TM_DISK}${TM_MACHINE:+ — machine: $TM_MACHINE}"
  echo "(Run with --reset to change source)"
  echo ""
fi

# List mode
if [ "$MODE" = "list" ]; then
  list_snapshots
  exit 0
fi

# Choose snapshot range
choose_range

# Search
echo ""
echo "Searching for: $TARGET"
echo "======================================================================"
echo ""

for snap in "${SNAP_RANGE[@]}"; do
  if [ "$TM_SOURCE_TYPE" = "local" ]; then
    search_local_snapshot "$snap"
  else
    search_external_snapshot "$snap"
  fi
done

echo "======================================================================"
echo "Total unique versions found: $COUNT"
echo ""
if [ "$COUNT" -gt 0 ]; then
  BASENAME=$(basename "$TARGET")
  echo "Tip: compare versions before restoring:"
  echo "  diff /tmp/${BASENAME}.v1 /tmp/${BASENAME}.v2"
  echo ""
  echo "Then restore safely:"
  echo "  cp $TARGET ${TARGET}.bak-\$(date +%Y%m%d-%H%M%S)"
  echo "  cp /tmp/${BASENAME}.vN $TARGET"
  echo ""
fi

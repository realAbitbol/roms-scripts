#!/usr/bin/env bash

shopt -s nullglob
IFS=$'\n'

# Usage information
usage() {
  cat <<EOF
Usage: $0 [-n|--dry-run] [--debug] base_path
  -n, --dry-run    Preview actions without renaming
      --debug      Print detailed debug information
  base_path        Directory to scan (default: current directory)
EOF
  exit 1
}

# Default settings
DRY_RUN=false
DEBUG=false

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=true; shift ;;
    --debug)      DEBUG=true;  shift ;;
    -h|--help)    usage ;;
    *)            BASE_PATH="$1"; shift ;;
  esac
done
BASE_PATH="${BASE_PATH:-.}"

# Debug output of initial settings
$DEBUG && echo "[DEBUG] Base path: $BASE_PATH; Dry run: $DRY_RUN"

# Find all directories containing .m3u and at least one disc file
mapfile -t targets < <(
  find "$BASE_PATH" -type d \( -iname bios -o -iname '*.m3u' \) -prune -o \
    -type f -iname '*.m3u' -printf '%h\n' | sort -u
)

# Process each target directory
for dir in "${targets[@]}"; do
  # Check for disc file presence
  if compgen -G "$dir"/*.{iso,bin,cue,chd,mdf,mds,nrg,ccd,img,sub,cdi,toc} > /dev/null; then
    newdir="${dir}.m3u"
    $DEBUG && echo "[DEBUG] Would rename: '$dir' → '$newdir'"
    if $DRY_RUN; then
      echo "DRY-RUN: rename '$dir' to '$newdir'"
    else
      mv "$dir" "$newdir"
      echo "Renamed '$dir' → '$newdir'"
    fi
  else
    $DEBUG && echo "[DEBUG] Skipping '$dir': no disc files found"
  fi
done

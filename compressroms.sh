#!/usr/bin/env bash
set -euo pipefail

# Parse dry-run option
DRY_RUN=false
if [[ "${1-:-}" == "--dry-run" || "${1-:-}" == "-n" ]]; then
  DRY_RUN=true
  echo "Running in dry-run mode: no changes will be modified"
fi

# Helper: run or simulate a command safely
run_cmd() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# Directory containing all ROMs (adjust to your mount point)
ROM_DIR="/storage/shared/RetroArch/roms"
LOG="$HOME/rom_compress.log"

# Initialize log
echo "Compression started at $(date)" > "$LOG"
$DRY_RUN && echo "[DRY-RUN] No files will be modified" | tee -a "$LOG"

# Function to process CD images → CHD
process_cd() {
  local file="$1"
  local base="${file%.*}"
  local out="${base}.chd"
  echo "Compressing CD image: '$file' → '$out'" | tee -a "$LOG"
  run_cmd chdman createcd -i "$file" -o "$out"
  # Always remove the original CD image
  run_cmd rm -v "$file"
  # Remove .cue only if it exists
  if [[ -f "${base}.cue" ]]; then
    run_cmd rm -v "${base}.cue"
  fi
}

# Function to convert PSP ISO → CSO
process_psp() {
  local iso="$1"
  local cso="${iso%.*}.cso"
  echo "Converting PSP ISO: '$iso' → '$cso'" | tee -a "$LOG"
  run_cmd ciso -z9 "$iso" "$cso"
  run_cmd rm -v "$iso"
}

# Function to zip cartridge ROMs
process_cartridge() {
  local rom="$1"
  local zipf="${rom%.*}.zip"
  echo "Zipping ROM: '$rom' → '$zipf'" | tee -a "$LOG"
  run_cmd zip -j "$zipf" "$rom"
  run_cmd rm -v "$rom"
}

# Find and process CD-based images (excluding BIOS folder)
find "$ROM_DIR" -type f \( -iname '*.cue' -o -iname '*.bin' -o -iname '*.iso' -o -iname '*.img' -o -iname '*.ccd' \) -not -path "*/bios/*" -not -path "*/BIOS/*" -print0 |
while IFS= read -r -d '' file; do
  process_cd "$file"
done

# Find and process PSP ISOs (excluding BIOS folder)
find "$ROM_DIR" -type f -iname '*.iso' -not -path "*/bios/*" -not -path "*/BIOS/*" -print0 |
while IFS= read -r -d '' iso; do
  # Skip CD images already handled
  [[ "${iso%.*}.chd" -ot "$iso" ]] && process_psp "$iso"
done

# Find and process cartridge ROMs (excluding BIOS folder)
find "$ROM_DIR" -type f \( -iname '*.nes' -o -iname '*.sfc' -o -iname '*.smc' -o -iname '*.gba' -o -iname '*.gb' -o -iname '*.gbc' \) -not -path "*/bios/*" -not -path "*/BIOS/*" -print0 |
while IFS= read -r -d '' rom; do
  process_cartridge "$rom"
done

echo "Compression complete at $(date)" | tee -a "$LOG"

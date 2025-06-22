#!/usr/bin/env bash
shopt -s nullglob
IFS=$'\n'

# Usage information
usage() {
  cat <<EOF
Usage: $0 [-n|--dry-run] [--debug] [base_path]
  -n, --dry-run    Preview actions without file operations
  --debug          Show detailed debug output
  base_path        Directory to scan (default: current directory)
EOF
  exit 1
}

# Parse options
DRY_RUN=false; DEBUG=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=true; shift ;;
    --debug)      DEBUG=true;  shift ;;
    -h|--help)    usage ;;
    *)            BASE_PATH="$1"; shift ;;
  esac
done
BASE_PATH="${BASE_PATH:-.}"
$DEBUG && echo "[DEBUG] Scanning base: $BASE_PATH"

# Emacs-style regex for supported image formats
EXT_REGEX='.*\.\(iso\|bin\|cue\|mdf\|mds\|nrg\|chd\|ccd\|img\|sub\|cdi\|toc\)$'

# Find files, excluding 'bios' and any '*.m3u' directories
mapfile -t files < <(
  find "$BASE_PATH" \
    -type d \( -iname bios -o -iname '*.m3u' \) -prune -o \
    -type f -iregex "$EXT_REGEX" -print
)
$DEBUG && echo "[DEBUG] Found ${#files[@]} disc files"

declare -A groups

# Group only files marked as multi-disc
for f in "${files[@]}"; do
  name=$(basename "$f")
  [[ "$name" =~ \([Dd]isc[[:space:]][0-9]+\) ]] || continue
  dir=$(dirname "$f")
  base="${name%.*}"                     # Strip final extension
  game="${base% *(Disc*}"               # Remove disc suffix
  key="$dir|$game"
  groups["$key"]+="$f"$'\n'
done
$DEBUG && echo "[DEBUG] Grouped into ${#groups[@]} games"

# Process each multi-disc game
for key in "${!groups[@]}"; do
  IFS='|' read -r dir game <<< "$key"
  readarray -t discs <<< "${groups[$key]}"
  (( ${#discs[@]} > 1 )) || continue

  # Remove any existing playlist
  old_m3u="$dir/$game.m3u"
  if [[ -f "$old_m3u" ]]; then
    $DEBUG && echo "[DEBUG] Deleting existing playlist: $old_m3u"
    $DRY_RUN || rm "$old_m3u"
  fi

  # Generate new playlist with numeric sorting
  new_m3u="$dir/$game.m3u"
  $DEBUG && echo "[DEBUG] Generating playlist: $new_m3u"
  $DRY_RUN || printf '#EXTM3U\n' > "$new_m3u"

  # Build an array of basename entries
  entries=()
  for disc in "${discs[@]}"; do
    bn=$(basename "$disc")
    case "${disc,,}" in
      *.cue|*.ccd|*.toc) entries+=("$bn") ;;
      *)
        cue="${disc%.*}.cue"
        if [[ ! -f "$dir/$(basename "$cue")" ]]; then
          entries+=("$bn")
        fi ;;
    esac
  done

  # Sort by disc number extracted from "(Disc N)"
  IFS=$'\n' sorted=($(printf '%s\n' "${entries[@]}" \
    | awk -F '[()]' '/[Dd]isc/ {print $2 " " $0}' \
    | sort -n \
    | cut -d' ' -f2-))
  unset IFS

  # Write sorted entries to playlist
  for entry in "${sorted[@]}"; do
    if $DRY_RUN; then
      echo "  - $entry"
    else
      echo "$entry" >> "$new_m3u"
    fi
    $DEBUG && echo "[DEBUG] Added entry: $entry"
  done

  # Create destination folder and move files
  dest="$dir/${game}.m3u"
  $DEBUG && echo "[DEBUG] Creating folder: $dest"
  $DRY_RUN || mkdir -p "$dest"
  for disc in "${discs[@]}"; do
    $DEBUG && echo "[DEBUG] Moving: $disc → $dest/"
    $DRY_RUN || mv "$disc" "$dest/"
  done
  $DEBUG && echo "[DEBUG] Moving playlist: $new_m3u → $dest/"
  $DRY_RUN || mv "$new_m3u" "$dest/"

  echo "Processed game: $game"
done

#!/usr/bin/env bash
shopt -s nullglob
IFS=$'\n'

# Usage information
usage() {
  cat <<EOF
Usage: $0 [-n|--dry-run] [--debug] [base_path]
  -n, --dry-run    Preview without changes
  --debug          Show debug output
  base_path        Directory to scan (default: current)
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
$DEBUG && echo "[DEBUG] Scanning: $BASE_PATH"

# Regex for disc formats
EXT_REGEX='.*\.\(iso\|bin\|cue\|mdf\|mds\|nrg\|chd\|ccd\|img\|sub\|cdi\|toc\)$'

# Collect ALL files, don't exclude .m3u dirs during initial scan
mapfile -t files < <(
  find "$BASE_PATH" \
    -type d \( -iname bios \) -prune -o \
    -type f -iregex "$EXT_REGEX" -print
)
$DEBUG && echo "[DEBUG] Found ${#files[@]} files"

declare -A groups

# Group multi-disc files - improved regex pattern
for f in "${files[@]}"; do
  name=$(basename "$f")
  # More flexible disc pattern matching
  if [[ "$name" =~ \([Dd]isc[[:space:]]*[0-9]+\) ]] || [[ "$name" =~ [Dd]isc[[:space:]]*[0-9]+ ]]; then
    dir=$(dirname "$f")
    base="${name%.*}"
    # Remove disc suffix more comprehensively
    game=$(echo "$base" | sed -E 's/[[:space:]]*[\(\[]?[Dd]isc[[:space:]]*[0-9]+[\)\]]?.*$//')
    key="$dir|$game"
    groups["$key"]+="$f"$'\n'
    $DEBUG && echo "[DEBUG] Added to group '$game': $name"
  fi
done
$DEBUG && echo "[DEBUG] Groups: ${#groups[@]}"

# Process each game
for key in "${!groups[@]}"; do
  IFS='|' read -r dir game <<< "$key"
  
  # Fix: Filter out empty entries when reading array
  mapfile -t discs < <(printf '%s' "${groups[$key]}" | grep -v '^$')
  
  (( ${#discs[@]} > 1 )) || { $DEBUG && echo "[DEBUG] Skipping single disc: $game"; continue; }

  # Check if already in correct folder structure
  parent=$(basename "$dir")
  need_folder=true
  if [[ "$parent" == "$game.m3u" ]]; then
    $DEBUG && echo "[DEBUG] Already in $parent folder"
    dest="$dir"
    need_folder=false
  else
    dest="$dir/$game.m3u"
    $DEBUG && echo "[DEBUG] Creating folder: $dest"
    if [[ "$DRY_RUN" == false ]]; then
      mkdir -p "$dest"
    fi
  fi

  # Remove old playlist if creating new folder
  if [[ "$need_folder" == true ]]; then
    old="$dir/$game.m3u"
    if [[ -f "$old" ]]; then
      $DEBUG && echo "[DEBUG] Removing old playlist: $old"
      $DRY_RUN || rm "$old"
    fi
  fi

  # Generate playlist
  m3u="$dest/$game.m3u"
  $DEBUG && echo "[DEBUG] Creating playlist: $m3u"
  $DRY_RUN || printf '#EXTM3U\n' > "$m3u"

  # Build entries array with descriptor preference
  entries=()
  for disc in "${discs[@]}"; do
    [[ -n "$disc" ]] || continue  # Skip empty entries
    bn=$(basename "$disc")
    case "${disc,,}" in
      *.cue|*.ccd|*.toc) entries+=("$bn") ;;
      *)
        cue="${disc%.*}.cue"
        if [[ ! -f "$(dirname "$disc")/$(basename "$cue")" ]]; then
          entries+=("$bn")
        fi ;;
    esac
  done

  # Sort by disc number WITHOUT adding prefixes to final output
  declare -a sorted_entries
  while IFS= read -r line; do
    [[ -n "$line" ]] && sorted_entries+=("$line")  # Only add non-empty lines
  done < <(printf '%s\n' "${entries[@]}" | sort -V)

  # Write entries to playlist
  for entry in "${sorted_entries[@]}"; do
    if [[ "$DRY_RUN" == true ]]; then
      echo "  - $entry"
    else
      echo "$entry" >> "$m3u"
    fi
    $DEBUG && echo "[DEBUG] Added entry: $entry"
  done

  # Move files only if we created a new folder
  if [[ "$need_folder" == true ]]; then
    for disc in "${discs[@]}"; do
      [[ -n "$disc" ]] || continue  # Skip empty entries
      bn=$(basename "$disc")
      $DEBUG && echo "[DEBUG] Moving: $disc → $dest/$bn"
      $DRY_RUN || mv "$disc" "$dest/$bn"
    done
  fi

  echo "Processed: $game"
  unset sorted_entries
done

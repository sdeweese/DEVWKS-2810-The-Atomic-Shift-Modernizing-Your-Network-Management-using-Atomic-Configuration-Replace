#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIRED_DIR="$REPO_DIR/configs/desired"
LINK_NAME="c9300x-lab.cfg"
CATALOG_DIR="${CATALOG_DIR:-$REPO_DIR/configs/pod-targets}"
POD_ID_VALUE="${POD_ID:-}"
POD_NUM=""
POD_NUM_PADDED=""

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  echo "Usage:"
  echo "  $(basename "$0")                 # interactive selection for this pod"
  echo "  $(basename "$0") <file.cfg|dayX|N>"
  echo "  $(basename "$0") --list          # list available targets"
  echo "  $(basename "$0") --pod-info      # show detected pod and allowed files"
  echo "  $(basename "$0") --help          # show help"
  echo
  echo "Overrides:"
  echo "  POD_ID=13                         # override pod detection"
  echo "  POD_ID=POD-13                     # override pod detection"
  echo "  CATALOG_DIR=/path/to/pod-targets  # optional source for first-run copy"
}

detect_pod_id() {
  if [[ -z "$POD_ID_VALUE" ]]; then
    local candidate
    for candidate in "$HOME/PODID" "/home/auto/PODID"; do
      if [[ -f "$candidate" ]]; then
        POD_ID_VALUE="$(head -n 1 "$candidate" | tr -d '[:space:]')"
        break
      fi
    done
  fi

  [[ -z "$POD_ID_VALUE" ]] && die "unable to detect pod id. Set POD_ID or create ~/PODID (example: POD-13)."

  if [[ "$POD_ID_VALUE" =~ ^POD-?([0-9]{1,2})$ ]]; then
    POD_NUM="${BASH_REMATCH[1]}"
  elif [[ "$POD_ID_VALUE" =~ ^([0-9]{1,2})$ ]]; then
    POD_NUM="${BASH_REMATCH[1]}"
  else
    die "unsupported POD id format '$POD_ID_VALUE'. Expected POD-13, POD13, or 13."
  fi

  (( POD_NUM >= 1 && POD_NUM <= 30 )) || die "pod number '$POD_NUM' is out of supported range (1-30)."
  printf -v POD_NUM_PADDED "%02d" "$POD_NUM"
}

allowed_target_names() {
  local prefix="POD-$POD_NUM_PADDED-day"

  {
    find "$DESIRED_DIR" -maxdepth 1 -type f -name "${prefix}*.cfg" -exec basename {} \; 2>/dev/null
    find "$CATALOG_DIR" -maxdepth 1 -type f -name "${prefix}*.cfg" -exec basename {} \; 2>/dev/null
  } | sort -u
}

is_allowed_target() {
  local candidate="$1"
  [[ "$candidate" =~ ^POD-${POD_NUM_PADDED}-day[^/]*\.cfg$ ]]
}

resolve_target_arg() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "POD-$POD_NUM_PADDED-day${raw}.cfg"
  elif [[ "$raw" =~ ^day[^/]*$ ]]; then
    echo "POD-$POD_NUM_PADDED-${raw}.cfg"
  else
    echo "$raw"
  fi
}

bootstrap_from_catalog() {
  [[ -d "$CATALOG_DIR" ]] || return 0

  local prefix="POD-$POD_NUM_PADDED-day"
  local src
  while IFS= read -r src; do
    local base
    base="$(basename "$src")"
    [[ ! -f "$DESIRED_DIR/$base" ]] && cp "$src" "$DESIRED_DIR/$base"
  done < <(find "$CATALOG_DIR" -maxdepth 1 -type f -name "${prefix}*.cfg" 2>/dev/null | sort)

  return 0
}

current_target() {
  local link_path="$DESIRED_DIR/$LINK_NAME"
  if [[ -L "$link_path" ]]; then
    readlink "$link_path"
  elif [[ -e "$link_path" ]]; then
    echo "(exists, but is not a symlink)"
  else
    echo "(missing)"
  fi
}

gather_cfg_files() {
  local prefix="POD-$POD_NUM_PADDED-day"
  find "$DESIRED_DIR" -maxdepth 1 -type f -name "${prefix}*.cfg" -exec basename {} \; | sort
}

pod_info() {
  local vlan=$((POD_NUM + 20))
  local peer=$((POD_NUM + 20))

  echo "Detected pod: POD-$POD_NUM_PADDED"
  echo "Expected VLAN mapping for this pod: $vlan"
  echo "Expected peer pod mapping (pod + 20): POD-$peer"
  echo "Allowed target files:"
  local found=0
  while IFS= read -r f; do
    found=1
    echo "  - $f"
  done < <(allowed_target_names)
  [[ $found -eq 0 ]] && echo "  - (none found)"
}

list_targets() {
  echo "Current $LINK_NAME target: $(current_target)"
  echo
  echo "Detected pod: POD-$POD_NUM_PADDED"
  echo "Available allowed files in $DESIRED_DIR:"

  local cfg_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && cfg_files+=("$f")
  done < <(gather_cfg_files)

  if [[ ${#cfg_files[@]} -eq 0 ]]; then
    echo "  (none found)"
    return
  fi

  local i=1
  local f
  for f in "${cfg_files[@]}"; do
    if [[ "$f" == "$LINK_NAME" ]]; then
      continue
    fi
    printf "  %2d) %s\n" "$i" "$f"
    ((i++))
  done
}

set_target() {
  local target_file
  target_file="$(resolve_target_arg "$1")"
  local target_path="$DESIRED_DIR/$target_file"

  if [[ "$target_file" == "$LINK_NAME" ]]; then
    echo "Error: target cannot be $LINK_NAME itself."
    exit 1
  fi

  is_allowed_target "$target_file" || die "target '$target_file' is not allowed for POD-$POD_NUM_PADDED."

  if [[ ! -f "$target_path" ]]; then
    if [[ -f "$CATALOG_DIR/$target_file" ]]; then
      cp "$CATALOG_DIR/$target_file" "$target_path"
    else
      die "file not found for this pod: $target_path"
    fi
  fi

  (
    cd "$DESIRED_DIR"
    ln -sfn "$target_file" "$LINK_NAME"
  )

  echo "Updated: $LINK_NAME -> $(current_target)"
}

interactive_select() {
  local cfg_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && cfg_files+=("$f")
  done < <(gather_cfg_files)

  local selectable=()
  local f
  for f in "${cfg_files[@]}"; do
    [[ "$f" == "$LINK_NAME" ]] && continue
    selectable+=("$f")
  done

  if [[ ${#selectable[@]} -eq 0 ]]; then
    die "no allowed pod files found for POD-$POD_NUM_PADDED in $DESIRED_DIR"
  fi

  echo "Current $LINK_NAME target: $(current_target)"
  echo "Select a target file:"

  local i=1
  for f in "${selectable[@]}"; do
    printf "  %2d) %s\n" "$i" "$f"
    ((i++))
  done

  echo
  read -r -p "Enter number: " choice

  if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
    echo "Error: please enter a numeric value."
    exit 1
  fi

  if (( choice < 1 || choice > ${#selectable[@]} )); then
    echo "Error: selection out of range."
    exit 1
  fi

  set_target "${selectable[$((choice - 1))]}"
}

if [[ ! -d "$DESIRED_DIR" ]]; then
  die "expected directory does not exist: $DESIRED_DIR"
fi

detect_pod_id
bootstrap_from_catalog

case "${1:-}" in
  -h|--help)
    usage
    ;;
  -l|--list)
    list_targets
    ;;
  --pod-info)
    pod_info
    ;;
  "")
    interactive_select
    ;;
  *)
    set_target "$1"
    ;;
esac

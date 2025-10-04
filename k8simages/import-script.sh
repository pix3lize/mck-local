#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Defaults
IMAGES_DIR="./exported-images"
CLUSTER_NAME=""

usage() {
  cat <<'EOF'
Usage:
  import-script.sh -c <cluster-name> [-d /path/to/exported-images]

Description:
  Loads all Docker images from *.tar / *.tar.gz in the given folder into the local Docker daemon,
  then imports each loaded image into the specified k3d cluster.

Options:
  -c   k3d cluster name (required)
  -d   directory with exported images (default: /exported-images)
  -h   show this help

Examples:
  import-script.sh -c dev
  import-script.sh -c dev -d /tmp/my-tars
EOF
}

# --- Parse flags ---
while getopts ":c:d:h" opt; do
  case "$opt" in
    c) CLUSTER_NAME="$OPTARG" ;;
    d) IMAGES_DIR="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "ERROR: -c <cluster-name> is required." >&2
  usage
  exit 1
fi

# --- Dependency checks ---
for bin in docker k3d; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: '$bin' is not installed or not in PATH." >&2
    exit 1
  fi
done

# --- Directory check ---
if [[ ! -d "$IMAGES_DIR" ]]; then
  echo "ERROR: Directory not found: $IMAGES_DIR" >&2
  exit 1
fi

# --- Collect .tar / .tar.gz files ---
shopt -s nullglob
TAR_FILES=()
for file in "$IMAGES_DIR"/*.tar "$IMAGES_DIR"/*.tar.gz; do
  if [[ -f "$file" ]]; then
    TAR_FILES+=("$file")
  fi
done
shopt -u nullglob

if [[ ${#TAR_FILES[@]} -eq 0 ]]; then
  echo "No .tar or .tar.gz files found in: $IMAGES_DIR"
  exit 0
fi

echo "Found ${#TAR_FILES[@]} archive(s) in $IMAGES_DIR"
echo "Target k3d cluster: $CLUSTER_NAME"
echo

# Keep a unique list of images we import (for a clean summary)
IMPORTED_IMAGES=()

for TAR in "${TAR_FILES[@]}"; do
  echo "==> Loading: $TAR"
  # docker load outputs lines like:
  #  - "Loaded image: repo/name:tag"
  #  - (or sometimes) "Loaded image ID: sha256:..."
  # We capture stdout+stderr to parse tags.
  LOAD_OUTPUT="$(docker load -i "$TAR" 2>&1 || true)"
  echo "$LOAD_OUTPUT"

  # Extract "Loaded image: <name:tag>" lines
  TAGS=()
  while IFS= read -r line; do
    if [[ "$line" =~ ^Loaded\ image:\ (.+)$ ]]; then
      TAGS+=("${BASH_REMATCH[1]}")
    fi
  done <<< "$LOAD_OUTPUT"
  
  if [[ ${#TAGS[@]} -eq 0 ]]; then
    echo "WARN: No 'Loaded image: <name:tag>' lines detected. The archive may have only an image ID (no RepoTags)."
    echo "      In that case, consider tagging the image manually after load, then re-run k3d import."
    echo
    continue
  fi

   # Import each tag into k3d
  for IMG in "${TAGS[@]}"; do
    # Check if already imported (simple array search)
    ALREADY_IMPORTED=false
    for IMPORTED in "${IMPORTED_IMAGES[@]+"${IMPORTED_IMAGES[@]}"}"; do
      if [[ "$IMPORTED" == "$IMG" ]]; then
        ALREADY_IMPORTED=true
        break
      fi
    done
    
    if [[ "$ALREADY_IMPORTED" == "true" ]]; then
      echo "   (skip) Already imported this tag in this run: $IMG"
      continue
    fi
    
    echo "   -> Importing into k3d cluster '$CLUSTER_NAME': $IMG"
    # k3d will look up $IMG from local Docker and push it into cluster nodes' containerd
    k3d image import "$IMG" -c "$CLUSTER_NAME"
    IMPORTED_IMAGES+=("$IMG")
  done

  echo
done

# --- Summary ---
if [[ ${#IMPORTED_IMAGES[@]} -gt 0 ]]; then
  echo "Import complete. Images imported into k3d cluster '$CLUSTER_NAME':"
  for IMG in "${IMPORTED_IMAGES[@]}"; do
    echo "  - $IMG"
  done
else
  echo "No images were imported into k3d (no tags detected across archives)."
fi

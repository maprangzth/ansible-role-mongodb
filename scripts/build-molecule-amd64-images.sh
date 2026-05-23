#!/usr/bin/env bash
# Pre-build amd64 molecule base images on arm64 hosts (Apple Silicon).
# Required only for scenarios that test MongoDB versions/OS combos that
# don't publish arm64 server packages (e.g., MongoDB 8.0 on Debian 12).
#
# Each scenario referenced here has:
#   - Dockerfile.amd64 (companion to Dockerfile.j2)
#   - `pre_build_image: true` + matching image name in molecule.yml
#
# CI on amd64 Linux runners doesn't need this — molecule's default
# Dockerfile.j2 build path works there.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

build() {
  local scenario="$1"
  local tag="$2"
  local dockerfile_path="$REPO_ROOT/molecule/$scenario/Dockerfile.amd64"

  if [ ! -f "$dockerfile_path" ]; then
    echo "SKIP $scenario (no Dockerfile.amd64)"
    return
  fi

  echo "BUILD $scenario  →  $tag"
  docker buildx build \
    --platform linux/amd64 \
    --load \
    -t "$tag" \
    -f "$dockerfile_path" \
    "$REPO_ROOT/molecule/$scenario"

  # Verify arch
  arch=$(docker image inspect "$tag" --format '{{.Architecture}}')
  if [ "$arch" != "amd64" ]; then
    echo "FAIL $scenario built as $arch, not amd64"
    exit 1
  fi
  echo "OK    $scenario built as $arch"
}

build debian12 local/molecule-debian12-amd64:bookworm

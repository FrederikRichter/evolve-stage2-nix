#!/usr/bin/env bash
set -euo pipefail

# update.sh - Check and update Evolve Stage 2 launcher package in flake.nix
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_FILE="${SCRIPT_DIR}/flake.nix"
ASSET_URL="https://assets.modded-evolve.com/client/linux/ModdedEvolveClient-Setup.run"

CHECK_ONLY=0
FORCE_UPDATE=0

for arg in "$@"; do
  case "$arg" in
    --check)
      CHECK_ONLY=1
      ;;
    --force)
      FORCE_UPDATE=1
      ;;
    -h|--help)
      echo "Usage: $0 [--check] [--force]"
      echo "  --check   Check if an update is available without modifying files"
      echo "  --force   Force recalculating hash and updating flake.nix"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$FLAKE_FILE" ]; then
  echo "Error: $FLAKE_FILE not found" >&2
  exit 1
fi

CURRENT_VERSION=$(sed -n -E 's/^[[:space:]]*version = "([^"]+)";.*/\1/p' "$FLAKE_FILE")
CURRENT_HASH=$(sed -n -E 's/^[[:space:]]*hash = "([^"]+)";.*/\1/p' "$FLAKE_FILE")

echo "Current flake version : $CURRENT_VERSION"
echo "Current flake hash    : $CURRENT_HASH"

# Fetch upstream version from script header using HTTP byte-range request
echo "Checking upstream at: $ASSET_URL"
LATEST_VERSION=$(curl -s -f -r 0-4096 "$ASSET_URL" | sed -n -E 's/^VERSION="([^"]+)"/\1/p' | head -n1)

if [ -z "$LATEST_VERSION" ]; then
  echo "Error: Unable to extract version from upstream installer header." >&2
  exit 1
fi

echo "Upstream version      : $LATEST_VERSION"

if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ "$LATEST_VERSION" != "$CURRENT_VERSION" ]; then
    echo "Update available: $CURRENT_VERSION -> $LATEST_VERSION"
    exit 2
  else
    echo "Flake is already up to date ($CURRENT_VERSION)."
    exit 0
  fi
fi

if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
  echo "No version bump needed ($CURRENT_VERSION == $LATEST_VERSION)."
  exit 0
fi

echo "Fetching SRI hash for upstream installer..."
PREFETCH_OUT=$(nix store prefetch-file --hash-type sha256 --json "$ASSET_URL" 2>&1)
LATEST_HASH=$(echo "$PREFETCH_OUT" | grep -o '"hash":"[^"]*"' | head -n1 | cut -d'"' -f4)

if [ -z "$LATEST_HASH" ]; then
  echo "Error: Failed to obtain hash from nix store prefetch-file." >&2
  echo "$PREFETCH_OUT" >&2
  exit 1
fi

echo "Upstream SRI hash     : $LATEST_HASH"

if [ "$LATEST_VERSION" = "$CURRENT_VERSION" ] && [ "$LATEST_HASH" = "$CURRENT_HASH" ]; then
  echo "Both version and hash match. No update required."
  exit 0
fi

echo "Updating $FLAKE_FILE..."
sed -i -E "s|version = \"[^\"]+\";|version = \"$LATEST_VERSION\";|" "$FLAKE_FILE"
sed -i -E "s|hash = \"[^\"]+\";|hash = \"$LATEST_HASH\";|" "$FLAKE_FILE"

echo "Updating flake inputs (flake.lock)..."
nix flake update --flake "$SCRIPT_DIR"

echo "Verifying package build..."
NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link "${SCRIPT_DIR}#modded-evolve"

echo "Successfully updated to version $LATEST_VERSION ($LATEST_HASH)!"

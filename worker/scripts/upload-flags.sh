#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bucket="cf-assessment-flags"
dry_run=false
while (($#)); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --bucket) shift; bucket="${1:?Missing bucket name}" ;;
    *) echo "Usage: $0 [--bucket NAME] [--dry-run]" >&2; exit 2 ;;
  esac
  shift
done
[[ "$bucket" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || { echo 'Invalid bucket name' >&2; exit 2; }
cache=".flags-cache"
mkdir -p "$cache"
# npm package includes flags/4x3 and its MIT license. Download only; no package scripts.
version="${FLAG_ICONS_VERSION:-7.5.0}"
archive=$(npm pack "flag-icons@$version" --ignore-scripts --pack-destination "$cache" --silent)
tar -xzf "$cache/$archive" -C "$cache"
for file in "$cache"/package/flags/4x3/*.svg; do
  cc=$(basename "$file" .svg)
  [[ "$cc" =~ ^[a-zA-Z]{2}$ ]] || continue
  cc=$(printf '%s' "$cc" | tr '[:upper:]' '[:lower:]')
  if "$dry_run"; then
    printf 'Would upload %s to %s/flags/%s.svg (image/svg+xml)\n' "$file" "$bucket" "$cc"
  else
    npx wrangler r2 object put "$bucket/flags/$cc.svg" --file "$file" --content-type image/svg+xml --remote
  fi
done

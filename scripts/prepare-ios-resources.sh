#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
icon_source="$repo_dir/assets/bookreader-icon.png"
icon_target="$repo_dir/iosApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

if [[ ! -f "$icon_source" ]]; then
  echo "Missing app icon: $icon_source" >&2
  exit 1
fi

mkdir -p "$(dirname "$icon_target")"
if command -v sips >/dev/null 2>&1; then
  sips -z 1024 1024 "$icon_source" --out "$icon_target" >/dev/null
else
  cp "$icon_source" "$icon_target"
fi

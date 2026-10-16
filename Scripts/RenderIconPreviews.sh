#!/usr/bin/env bash
set -euo pipefail

repo_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_directory"
developer_directory="${DEVELOPER_DIR:-$(xcode-select -p)}"
icon_tool="${developer_directory%/Developer}/Applications/Icon Composer.app/Contents/Executables/ictool"
output_directory="${1:-dist/icon-previews}"
mkdir -p "$output_directory"
for appearance in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    "$icon_tool" GevunIcon.icon --export-image --output-file "$output_directory/$appearance.png" \
        --platform iOS --rendition "$appearance" --width 1024 --height 1024 --scale 1
done

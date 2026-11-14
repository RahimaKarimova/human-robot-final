#!/bin/bash
# Run the source project with an installed Godot editor; no exported app required.
set -euo pipefail
project_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-play}"
case "$mode" in
    play|editor|test|resume-market) ;;
    *) printf 'Usage: bash Launch-Mac.sh [play|editor|test|resume-market]\n' >&2; exit 2 ;;
esac

godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
    for candidate in "/Applications/Godot.app/Contents/MacOS/Godot" \
        "${HOME}/Applications/Godot.app/Contents/MacOS/Godot" \
        "${HOME}/Downloads/Godot.app/Contents/MacOS/Godot"; do
        if [[ -x "$candidate" ]]; then godot_bin="$candidate"; break; fi
    done
fi
if [[ -z "$godot_bin" ]] && command -v godot >/dev/null 2>&1; then
    godot_bin="$(command -v godot)"
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
    printf '%s\n' 'Godot was not found. Install Godot 4.5.2 Standard for macOS:' \
        'https://godotengine.org/download/archive/4.5.2-stable/' \
        'Move Godot.app into Applications and open it once, then run this task again.' \
        'For a renamed/custom installation, set GODOT_BIN to its Contents/MacOS/Godot executable.' >&2
    exit 1
fi
godot_version="$("$godot_bin" --version)"
IFS=. read -r godot_major godot_minor remainder <<< "$godot_version"
if [[ "$godot_major" != 4 || ! "$godot_minor" =~ ^[0-9]+$ || "$godot_minor" -lt 5 ]]; then
    printf 'Godot 4.5 or newer in the 4.x series is required. Found: %s\n' "$godot_version" >&2
    exit 1
fi
printf 'Using Godot %s\n' "$godot_version"
if [[ "$mode" == editor ]]; then
    exec "$godot_bin" --path "$project_root" --editor
fi
printf 'Preparing game assets (the first run may take a moment)...\n'
if ! "$godot_bin" --headless --path "$project_root" --editor --import --quit; then
    printf 'Asset preparation failed. Run bash Launch-Mac.sh editor to inspect the error.\n' >&2
    exit 1
fi
case "$mode" in
    play) exec "$godot_bin" --path "$project_root" ;;
    test) exec "$godot_bin" --headless --path "$project_root" res://tests/runner.tscn ;;
    resume-market) exec "$godot_bin" --path "$project_root" -- --resume-market ;;
esac

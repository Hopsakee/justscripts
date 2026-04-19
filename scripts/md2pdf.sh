#!/usr/bin/env bash
# Convert markdown to PDF using pandoc with a selectable layout profile.
# Usage: md2pdf <file.md> [layout]    (default: a4-work)
# Layouts live in ../pdf-layouts/*.yaml

SCRIPT_DIR="$(dirname "$0")"
LAYOUTS_DIR="$SCRIPT_DIR/../pdf-layouts"

list_layouts() {
    ls "$LAYOUTS_DIR"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/\.yaml$//'
}

if [ -z "$1" ]; then
    echo "Usage: md2pdf <file.md> [layout]    (default: a4-work)"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

INPUT="$1"
LAYOUT="${2:-a4-work}"
CONFIG="$LAYOUTS_DIR/${LAYOUT}.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Error: layout '$LAYOUT' not found at $CONFIG"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

pandoc "$INPUT" -o "${INPUT%.md}.pdf" -d "$CONFIG" --pdf-engine-opt=-interaction=nonstopmode

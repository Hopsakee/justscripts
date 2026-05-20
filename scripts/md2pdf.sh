#!/usr/bin/env bash
# Convert markdown to PDF using pandoc with a selectable layout profile.
# Usage: md2pdf <file.md> [layout]    (default: a4-work)
# Layouts live in ../pdf-layouts/*.yaml
#
# Auto-discovery, in this order:
#   1. ../pdf-layouts/<layout>.tex          -> --include-in-header (absolute path)
#   2. ../pdf-layouts/lua/*.lua             -> --lua-filter        (applied to every layout)
#   3. ../pdf-layouts/lua/<layout>/*.lua    -> --lua-filter        (layout-scoped)
#
# Layout-scoped filters keep one layout's quirks (e.g. boox-delight's
# table-width rebalancing) from leaking into the others.

# Resolve the script's real path via BASH_SOURCE (works for PATH lookup
# and direct invocation alike) + readlink to follow symlinks. Fall back
# to dirname-$BASH_SOURCE if readlink is unavailable.
SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LAYOUTS_DIR="$(cd "$SCRIPT_DIR/../pdf-layouts" && pwd)"
LUA_DIR="$LAYOUTS_DIR/lua"

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

EXTRA_ARGS=()

TEX_PREAMBLE="$LAYOUTS_DIR/${LAYOUT}.tex"
if [ -f "$TEX_PREAMBLE" ]; then
    EXTRA_ARGS+=("--include-in-header=$TEX_PREAMBLE")
fi

# Global Lua filters — apply to every layout.
if [ -d "$LUA_DIR" ]; then
    while IFS= read -r -d '' filter; do
        EXTRA_ARGS+=("--lua-filter=$filter")
    done < <(find "$LUA_DIR" -maxdepth 1 -type f -name '*.lua' ! -name '.*' -print0 | sort -z)
fi

# Layout-scoped Lua filters — apply only when this layout is active.
LAYOUT_LUA_DIR="$LUA_DIR/$LAYOUT"
if [ -d "$LAYOUT_LUA_DIR" ]; then
    while IFS= read -r -d '' filter; do
        EXTRA_ARGS+=("--lua-filter=$filter")
    done < <(find "$LAYOUT_LUA_DIR" -maxdepth 1 -type f -name '*.lua' ! -name '.*' -print0 | sort -z)
fi

pandoc "$INPUT" -o "${INPUT%.md}.pdf" -d "$CONFIG" \
    "${EXTRA_ARGS[@]}" \
    --pdf-engine-opt=-interaction=nonstopmode

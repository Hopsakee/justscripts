#!/usr/bin/env bash
# Convert epub to PDF using pandoc with a selectable layout profile.
# Usage: epub2pdf <file.epub> [layout]              (default: boox-delight)
# Usage: epub2pdf <directory>  [layout]             (converts every *.epub in dir)
# Layouts live in ../pdf-layouts/*.yaml
#
# Auto-discovery, in this order (mirrors md2pdf.sh):
#   1. ../pdf-layouts/<layout>.yaml         -> pandoc defaults file (required)
#   2. ../pdf-layouts/<layout>.tex          -> --include-in-header (absolute path)
#   3. ../pdf-layouts/lua/*.lua             -> --lua-filter        (applied to every layout)
#   4. ../pdf-layouts/lua/<layout>/*.lua    -> --lua-filter        (layout-scoped)
#
# Uses 'xelatex' (set in each layout YAML) for broader Unicode coverage than pdflatex.

# Resolve the script's real path via BASH_SOURCE (works for PATH lookup and
# direct invocation alike) + readlink to follow symlinks. Mirrors md2pdf.sh.
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
    echo "Usage: epub2pdf <file.epub> [layout]    (default: boox-delight)"
    echo "Usage: epub2pdf <directory>  [layout]   (converts every *.epub in dir)"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

INPUT="$1"
LAYOUT="${2:-boox-delight}"
CONFIG="$LAYOUTS_DIR/${LAYOUT}.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Error: layout '$LAYOUT' not found at $CONFIG"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

# check if the variable is a file or directory
if [[ ! ( -f "$INPUT" || -d "$INPUT" ) ]]; then
    echo "Error: '$INPUT' not found"
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

convert_one() {
    local f="$1"
    if [[ ! "$f" == *.epub ]]; then
        echo "Error: '$f' is not an .epub file" >&2
        return 1
    fi
    pandoc "$f" -o "${f%.epub}.pdf" -d "$CONFIG" \
        "${EXTRA_ARGS[@]}" \
        --pdf-engine-opt=-interaction=nonstopmode
}

# Directory mode — convert every *.epub in the given directory (non-recursive).
if [ -d "$INPUT" ]; then
    if ! compgen -G "$INPUT/*.epub" > /dev/null; then
        echo "Error: No .epub files found in directory '$INPUT'"
        exit 1
    fi
    echo "Converting all .epub files in directory '$INPUT' (layout: $LAYOUT)"
    rc=0
    for f in "$INPUT"/*.epub; do
        convert_one "$f" || rc=$?
    done
    exit "$rc"
fi

# Single-file mode.
convert_one "$INPUT"

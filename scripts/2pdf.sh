#!/usr/bin/env bash
# Convert any source to PDF using pandoc with a selectable layout profile.
# Collapses the former md2pdf.sh + epub2pdf.sh into one tool.
#
# Usage: 2pdf <source> [layout]    (default layout: boox-delight)
#   <source> may be:
#     - a Markdown file  (.md / .markdown)
#     - an EPUB file     (.epub)
#     - an HTML file     (.html / .htm)
#     - an http(s) URL   (fetched and treated as HTML)
#     - a directory      (batch-converts every supported file inside it)
#
# Layouts live in ../pdf-layouts/*.yaml and are shared across every input type.
# Auto-discovery for the selected layout, in this order:
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

usage() {
    echo "Usage: 2pdf <source> [layout]    (default layout: boox-delight)"
    echo "  <source>: a .md/.markdown, .epub, .html/.htm file, an http(s) URL, or a directory of those"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
}

if [ -z "$1" ]; then
    usage
    exit 1
fi

SOURCE="$1"
LAYOUT="${2:-boox-delight}"
CONFIG="$LAYOUTS_DIR/${LAYOUT}.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Error: layout '$LAYOUT' not found at $CONFIG"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

# Assemble the layout-specific pandoc args once (same for every file converted).
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

# Convert one source (file path or URL) to a sibling/CWD .pdf.
# Determines pandoc input format + output path from the source, then runs pandoc
# with the shared layout args. Returns pandoc's exit status.
convert_one() {
    local orig="$1" input="$1"
    local srcfmt="" output tmp_html=""
    # Local copy of the layout args so URL-only filters never leak to file conversions.
    local extra=("${EXTRA_ARGS[@]}")

    case "$input" in
        http://*|https://*)
            # URL: pandoc cannot key off an extension reliably, so force html.
            srcfmt="html"
            local base
            base="$(basename "${input%%\?*}")"   # drop any query string
            base="${base%.html}"; base="${base%.htm}"
            [ -z "$base" ] && base="output"
            output="./${base}.pdf"
            # Fetch to a LOCAL temp file before converting. When the input is a
            # URL, pandoc resolves --include-in-header and image paths relative
            # to the URL's host, so it would try to fetch our local layout .tex
            # from the remote server (403) and corrupt the LaTeX preamble.
            # Converting a local copy makes resource resolution local again.
            tmp_html="$(mktemp --suffix=.html)"
            if ! curl -fsSL "$input" -o "$tmp_html"; then
                echo "Error: failed to fetch '$orig'" >&2
                rm -f "$tmp_html"
                return 1
            fi
            # Drop images for URL conversions — see url-strip-images.lua.
            extra+=("--lua-filter=$LAYOUTS_DIR/url-strip-images.lua")
            input="$tmp_html"
            ;;
        *.md|*.markdown)
            output="${input%.*}.pdf"             # pandoc auto-detects markdown
            ;;
        *.epub)
            output="${input%.epub}.pdf"          # pandoc auto-detects epub
            ;;
        *.html|*.htm)
            srcfmt="html"
            output="${input%.*}.pdf"
            ;;
        *)
            echo "Error: unsupported source '$input' (expected .md, .markdown, .epub, .html, .htm, or an http(s) URL)" >&2
            return 2
            ;;
    esac

    local fmt_args=()
    [ -n "$srcfmt" ] && fmt_args+=(-f "$srcfmt")

    echo "Converting '$orig' -> '$output' (layout: $LAYOUT)"
    pandoc "$input" "${fmt_args[@]}" -o "$output" -d "$CONFIG" \
        "${extra[@]}" \
        --pdf-engine-opt=-interaction=nonstopmode
    local rc=$?
    [ -n "$tmp_html" ] && rm -f "$tmp_html"
    return $rc
}

# URL source — single conversion only (no directory semantics for URLs).
case "$SOURCE" in
    http://*|https://*)
        convert_one "$SOURCE"
        exit $?
        ;;
esac

# Directory source — batch-convert every supported file inside it.
if [ -d "$SOURCE" ]; then
    shopt -s nullglob
    files=("$SOURCE"/*.md "$SOURCE"/*.markdown "$SOURCE"/*.epub "$SOURCE"/*.html "$SOURCE"/*.htm)
    shopt -u nullglob
    if [ ${#files[@]} -eq 0 ]; then
        echo "Error: no supported files (.md/.markdown/.epub/.html/.htm) found in directory '$SOURCE'" >&2
        exit 1
    fi
    echo "Converting ${#files[@]} file(s) in directory '$SOURCE'"
    status=0
    for f in "${files[@]}"; do
        convert_one "$f" || status=$?
    done
    exit $status
fi

# Single file source.
if [ ! -f "$SOURCE" ]; then
    echo "Error: '$SOURCE' not found (expected a file, directory, or http(s) URL)" >&2
    exit 1
fi

convert_one "$SOURCE"

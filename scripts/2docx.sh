#!/usr/bin/env bash
# Convert Markdown (or HTML/EPUB) to DOCX using pandoc with a selectable layout
# profile. The DOCX sibling of 2pdf.sh — same layout-discovery mechanics, same
# shared markdown preprocessing, so a document handed to colleagues as .docx
# looks like the same document handed to them as .pdf.
#
# Usage: 2docx <source> [layout]    (default layout: a4-work)
#   <source> may be:
#     - a Markdown file  (.md / .markdown)
#     - an HTML file     (.html / .htm)
#     - an EPUB file     (.epub)
#     - a directory      (batch-converts every supported file inside it)
#   (http(s) URLs are not supported here — use 2pdf.sh for those.)
#
# Layouts live in ../docx-layouts/*.yaml. Auto-discovery for the selected
# layout, in this order:
#   1. ../docx-layouts/<layout>.docx        -> --reference-doc (absolute path)
#   2. ../docx-layouts/lua/*.lua            -> --lua-filter    (every layout)
#   3. ../docx-layouts/lua/<layout>/*.lua   -> --lua-filter    (layout-scoped)
#   4. ../md-preprocess/*.sed               -> sed -E over the RAW markdown
#      source (every layout; shared with 2pdf.sh)
#   5. ../md-preprocess/<layout>/*.sed      -> sed -E over the RAW markdown
#      source, layout-scoped (markdown sources only)
#
# A DOCX gets its whole appearance from the reference document: pandoc emits
# paragraphs tagged with style NAMES and Word looks each one up there. That is
# why the reference .docx matters more here than any pandoc flag, and why
# Obsidian callouts need one — see docx-layouts/lua/callouts.lua and
# scripts/make_docx_reference.py.

# Resolve the script's real path via BASH_SOURCE (works for PATH lookup
# and direct invocation alike) + readlink to follow symlinks. Fall back
# to dirname-$BASH_SOURCE if readlink is unavailable.
SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LAYOUTS_DIR="$(cd "$SCRIPT_DIR/../docx-layouts" && pwd)"
LUA_DIR="$LAYOUTS_DIR/lua"
# Raw-markdown transforms are format-independent (Obsidian callouts, wikilinks,
# HD numbers), so they live outside both layout directories and are applied by
# 2pdf.sh and 2docx.sh alike.
PREPROCESS_DIR="$(cd "$SCRIPT_DIR/../md-preprocess" && pwd)"

list_layouts() {
    ls "$LAYOUTS_DIR"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/\.yaml$//'
}

usage() {
    echo "Usage: 2docx <source> [layout]    (default layout: a4-work)"
    echo "  <source>: a .md/.markdown, .html/.htm, .epub file, or a directory of those"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
}

if [ -z "$1" ]; then
    usage
    exit 1
fi

SOURCE="$1"
LAYOUT="${2:-a4-work}"
CONFIG="$LAYOUTS_DIR/${LAYOUT}.yaml"

if [ ! -f "$CONFIG" ]; then
    echo "Error: layout '$LAYOUT' not found at $CONFIG"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

# Raw-text preprocessing scripts: global first, then layout-scoped, mirroring
# the Lua filter split below. Collected as -f args so sed applies them in order.
PREPROCESS_ARGS=()
if [ -d "$PREPROCESS_DIR" ]; then
    while IFS= read -r -d '' pp; do
        PREPROCESS_ARGS+=(-f "$pp")
    done < <(find "$PREPROCESS_DIR" -maxdepth 1 -type f -name '*.sed' ! -name '.*' -print0 | sort -z)
fi
LAYOUT_PREPROCESS_DIR="$PREPROCESS_DIR/$LAYOUT"
if [ -d "$LAYOUT_PREPROCESS_DIR" ]; then
    while IFS= read -r -d '' pp; do
        PREPROCESS_ARGS+=(-f "$pp")
    done < <(find "$LAYOUT_PREPROCESS_DIR" -maxdepth 1 -type f -name '*.sed' ! -name '.*' -print0 | sort -z)
fi

# Assemble the layout-specific pandoc args once (same for every file converted).
EXTRA_ARGS=()

REFERENCE_DOC="$LAYOUTS_DIR/${LAYOUT}.docx"
if [ -f "$REFERENCE_DOC" ]; then
    EXTRA_ARGS+=("--reference-doc=$REFERENCE_DOC")
else
    # Without it pandoc falls back to its built-in reference document, which has
    # no callout styles: callout text would come out unstyled rather than boxed.
    echo "Warning: no reference document at $REFERENCE_DOC — callouts will not be styled." >&2
    echo "         Regenerate it with: scripts/make_docx_reference.py $LAYOUT" >&2
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

# Convert one source file to a sibling .docx. Determines pandoc input format +
# output path from the source, then runs pandoc with the shared layout args.
# Returns pandoc's exit status.
convert_one() {
    local orig="$1" input="$1"
    local srcfmt="" output tmp_md=""
    local extra=("${EXTRA_ARGS[@]}")

    case "$input" in
        *.md|*.markdown)
            output="${input%.*}.docx"             # pandoc auto-detects markdown
            # Keep pandoc's resource lookup (images, includes) anchored to the
            # source's own directory as well as the working directory, so images
            # resolve when converting a file that lives somewhere else — and
            # still resolve after the preprocessing pass moves the text to /tmp.
            extra+=("--resource-path=$(dirname "$input"):.")
            if [ ${#PREPROCESS_ARGS[@]} -gt 0 ]; then
                # Raw-text pass BEFORE pandoc parses. Obsidian callouts have no
                # AST-level seam left once pandoc has folded "[!info] Titel"
                # into the first paragraph's inlines, and one bracket layer of a
                # "[[@name]]" wikilink is enough for pandoc's citation extension
                # to mis-parse the rest — see md-preprocess/*.sed.
                tmp_md="$(mktemp --suffix=.md)"
                sed -E "${PREPROCESS_ARGS[@]}" "$input" > "$tmp_md"
                input="$tmp_md"
            fi
            ;;
        *.html|*.htm)
            srcfmt="html"
            output="${input%.*}.docx"
            ;;
        *.epub)
            output="${input%.epub}.docx"          # pandoc auto-detects epub
            ;;
        *)
            echo "Error: unsupported source '$input' (expected .md, .markdown, .html, .htm, or .epub)" >&2
            return 2
            ;;
    esac

    local fmt_args=()
    [ -n "$srcfmt" ] && fmt_args+=(-f "$srcfmt")

    echo "Converting '$orig' -> '$output' (layout: $LAYOUT)"
    pandoc "$input" "${fmt_args[@]}" -o "$output" -d "$CONFIG" "${extra[@]}"
    local rc=$?
    [ -n "$tmp_md" ] && rm -f "$tmp_md"
    return $rc
}

# Directory source — batch-convert every supported file inside it.
if [ -d "$SOURCE" ]; then
    shopt -s nullglob
    files=("$SOURCE"/*.md "$SOURCE"/*.markdown "$SOURCE"/*.html "$SOURCE"/*.htm "$SOURCE"/*.epub)
    shopt -u nullglob
    if [ ${#files[@]} -eq 0 ]; then
        echo "Error: no supported files (.md/.markdown/.html/.htm/.epub) found in directory '$SOURCE'" >&2
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
    echo "Error: '$SOURCE' not found (expected a file or a directory)" >&2
    exit 1
fi

convert_one "$SOURCE"

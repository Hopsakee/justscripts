#!/usr/bin/env bash
# Convert a markdown source to DOCX using pandoc and a selectable layout's
# reference template.
#
# Sibling to 2pdf.sh, but a separate script on purpose: DOCX and PDF are
# genuinely different pipelines (a reference .docx + docx-scoped Lua filters
# vs a LaTeX preamble + xelatex). Folding "give me docx instead" into 2pdf.sh
# as a hidden third argument would just move the single-responsibility
# violation from the tool name into the tool body -- 2pdf converts to PDF.
#
# Usage: 2docx <source.md> <layout>
#   <source.md>: a .md/.markdown file (only source type wired up so far --
#                epub/html could be added later the same way 2pdf.sh has them)
#   <layout>: a layout with a <layout>-reference.docx in ../layouts/docx/
#
# Layout files, per layout <name>:
#   ../layouts/docx/<name>-reference.docx    -> --reference-doc (required)
#   ../layouts/docx/lua/<name>/*.lua         -> --lua-filter (docx-scoped, optional)
#   ../layouts/preprocess/*.sed                -> sed -E over RAW markdown (shared convention w/ 2pdf.sh)
#   ../layouts/preprocess/<name>/*.sed         -> sed -E, layout-scoped (shared convention w/ 2pdf.sh)
#
# No <layout>.yaml is read here. Those hold PDF/xelatex-only keys
# (pdf-engine, fonts, colorlinks) with no docx equivalent -- pairing a PDF
# yaml with the docx path would be misleading name-borrowing, not reuse.
#
# The preprocessing-discovery block below is intentionally duplicated from
# 2pdf.sh rather than shared via a sourced library: each script stays a
# small, independently-readable tool, matching the existing pattern of
# separate to-* justscripts in this repo.

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_PATH="$(readlink -f "$SCRIPT_PATH" 2>/dev/null || echo "$SCRIPT_PATH")"
fi
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LAYOUTS_ROOT="$(cd "$SCRIPT_DIR/../layouts" && pwd)"
DOCX_DIR="$LAYOUTS_ROOT/docx"
PREPROCESS_DIR="$LAYOUTS_ROOT/preprocess"

list_layouts() {
    ls "$DOCX_DIR"/*-reference.docx 2>/dev/null | xargs -n1 basename | sed 's/-reference\.docx$//'
}

usage() {
    echo "Usage: 2docx <source.md> <layout>"
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
}

if [ -z "$1" ] || [ -z "$2" ]; then
    usage
    exit 1
fi

SOURCE="$1"
LAYOUT="$2"
REFERENCE_DOC="$DOCX_DIR/${LAYOUT}-reference.docx"

if [ ! -f "$REFERENCE_DOC" ]; then
    echo "Error: no docx reference template for layout '$LAYOUT' (expected $REFERENCE_DOC)" >&2
    echo "Available layouts:"
    list_layouts | sed 's/^/  /'
    exit 1
fi

case "$SOURCE" in
    *.md|*.markdown) ;;
    *)
        echo "Error: '$SOURCE' -- 2docx currently only supports .md/.markdown sources" >&2
        exit 2
        ;;
esac

if [ ! -f "$SOURCE" ]; then
    echo "Error: '$SOURCE' not found" >&2
    exit 1
fi

# Raw-text preprocessing scripts: global first, then layout-scoped, same
# discovery order as 2pdf.sh (see that script's header for why this pass
# has to run on raw text, before pandoc parses it).
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

EXTRA_ARGS=("--reference-doc=$REFERENCE_DOC")

LAYOUT_LUA_DOCX_DIR="$DOCX_DIR/lua/$LAYOUT"
if [ -d "$LAYOUT_LUA_DOCX_DIR" ]; then
    while IFS= read -r -d '' filter; do
        EXTRA_ARGS+=("--lua-filter=$filter")
    done < <(find "$LAYOUT_LUA_DOCX_DIR" -maxdepth 1 -type f -name '*.lua' ! -name '.*' -print0 | sort -z)
fi

output="${SOURCE%.*}.docx"
input="$SOURCE"
tmp_md=""
if [ ${#PREPROCESS_ARGS[@]} -gt 0 ]; then
    tmp_md="$(mktemp --suffix=.md)"
    sed -E "${PREPROCESS_ARGS[@]}" "$SOURCE" > "$tmp_md"
    input="$tmp_md"
fi

echo "Converting '$SOURCE' -> '$output' (layout: $LAYOUT)"
# Same lists_without_preceding_blankline reader extension 2pdf.sh uses --
# Obsidian notes routinely start a list right after a paragraph with no
# blank line, which pandoc's own markdown dialect otherwise flattens into
# one run-on line regardless of output format.
pandoc "$input" -f markdown+lists_without_preceding_blankline -o "$output" "${EXTRA_ARGS[@]}"
rc=$?
[ -n "$tmp_md" ] && rm -f "$tmp_md"
exit $rc

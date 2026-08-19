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
# Before any preprocessing, the source always goes through
# normalize_line_endings() first (CRLF/bare-CR -> LF) -- see that function's
# own comment in this file (duplicated from 2pdf.sh, same reason as below).
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

# Normalize line endings BEFORE any other markdown preprocessing. Every
# *.sed rule below is ^/$-anchored and GNU sed splits records on \n only --
# a source with CRLF endings leaves a trailing \r that a rule's trailing $
# can swallow into captured text, and a source with BARE-CR ("classic Mac")
# endings has NO \n at all, so sed treats the whole file as one giant line
# and no ^/$ anchor ever matches past the first/last line. Reproduced
# 2026-08-19: a pasted Obsidian callout with bare-CR line endings defeated
# the callout-marker sed rule entirely -- the whole blockquote collapsed
# into one run-on paragraph with the literal "[!type]" marker text intact.
# wc -l counts \n bytes, so it's 0 for both an empty/one-line file (nothing
# to normalize -- tr is still a safe no-op there) and a bare-CR file (every
# \r IS the line break, so converting each to \n is exactly correct).
normalize_line_endings() {
    local src="$1" dst="$2"
    if [ "$(wc -l < "$src")" -gt 0 ]; then
        sed $'s/\r$//' "$src" > "$dst"       # CRLF -> LF (strip the leftover \r)
    else
        tr '\r' '\n' < "$src" > "$dst"       # bare-CR -> LF
    fi
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

tmp_norm="$(mktemp --suffix=.md)"
if ! normalize_line_endings "$SOURCE" "$tmp_norm"; then
    echo "Error: line-ending normalization failed for '$SOURCE'" >&2
    rm -f "$tmp_norm"
    exit 1
fi
input="$tmp_norm"

tmp_md=""
if [ ${#PREPROCESS_ARGS[@]} -gt 0 ]; then
    tmp_md="$(mktemp --suffix=.md)"
    if ! sed -E "${PREPROCESS_ARGS[@]}" "$input" > "$tmp_md"; then
        # Same failure-surfacing fix as 2pdf.sh (code-review finding,
        # 2026-08-19) -- a failing sed here previously still fed pandoc
        # whatever partial/empty output it produced instead of erroring.
        echo "Error: preprocessing sed pass failed for '$SOURCE'" >&2
        rm -f "$tmp_norm" "$tmp_md"
        exit 1
    fi
    input="$tmp_md"
fi

echo "Converting '$SOURCE' -> '$output' (layout: $LAYOUT)"
# Same lists_without_preceding_blankline reader extension 2pdf.sh uses --
# Obsidian notes routinely start a list right after a paragraph with no
# blank line, which pandoc's own markdown dialect otherwise flattens into
# one run-on line regardless of output format.
pandoc "$input" -f markdown+lists_without_preceding_blankline -o "$output" "${EXTRA_ARGS[@]}"
rc=$?
rm -f "$tmp_norm"
[ -n "$tmp_md" ] && rm -f "$tmp_md"
exit $rc

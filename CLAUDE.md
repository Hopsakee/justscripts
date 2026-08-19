# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A flat collection of self-contained scripts (Python via `uv` PEP 723 inline metadata, plus a
few Bash pandoc wrappers), invoked through a single root `justfile`. No package, no build step,
no test suite, no lint config — each script is meant to be read top-to-bottom and to declare its
own dependencies. Intended to be cloned to `~/justscripts` (the `justfile` assumes this via
`home_dir()`).

## Commands

```bash
just                          # list all recipes
just run <script_name> [args] # run any scripts/<name>.py by name
just to-pdf <source> [layout] # markdown/epub/html/url -> PDF (default layout: boox-delight)
just to-docx <file.md> <layout>  # markdown -> DOCX (only a4-work has a reference template)
just pdf-extract <file.pdf> [--force] [--dry-run]  # PDF -> <name>_text.md

uv run scripts/<name>.py [args]   # run a script directly, bypassing just
```

There is no test/lint/build command — verify a change by running the affected script or `just`
recipe directly and inspecting its output (e.g. actually generate a PDF and open it).

## Architecture

**Two independent layers:** standalone `scripts/*.py` utilities (no shared code between them —
each is fully self-contained per PEP 723, dependencies declared inline in the `# /// script`
block), and the **document-conversion pipeline** (`2pdf.sh`, `2docx.sh`, `pdf_extract.py`) which
shares the `layouts/` directory as a layout system.

### The conversion pipeline (`2pdf.sh` / `2docx.sh` + `layouts/`)

`layouts/` is split by output format first (`layouts/pdf/`, `layouts/docx/`), with a shared
`layouts/preprocess/` for raw-text passes both scripts use. A "layout" is a named bundle of
pandoc configuration, not a single file — for layout `<name>`, both scripts auto-discover (in
this order) whatever pieces exist under their format's subtree — nothing is required except the
format-specific base file:

| Piece | PDF (`2pdf.sh`) | DOCX (`2docx.sh`) |
|---|---|---|
| Base config | `layouts/pdf/<name>.yaml` (pandoc defaults file: paper size, fonts, `pdf-engine: xelatex`) — **required** | `layouts/docx/<name>-reference.docx` (Word styles) — **required** |
| LaTeX preamble | `layouts/pdf/<name>.tex` → `--include-in-header` | n/a |
| Lua filters (global) | `layouts/pdf/lua/*.lua` | n/a |
| Lua filters (layout-scoped) | `layouts/pdf/lua/<name>/*.lua` | `layouts/docx/lua/<name>/*.lua` |
| Raw-text sed preprocessing (global) | `layouts/preprocess/*.sed` | same, shared |
| Raw-text sed preprocessing (layout-scoped) | `layouts/preprocess/<name>/*.sed` | same, shared |

The sed preprocessing pass runs on the **raw markdown text before pandoc parses it**, not as a
Lua/AST filter — this is deliberate: e.g. stripping Obsidian `[[wikilinks]]` after pandoc's
citation extension has already partially parsed a `[[@name]]` bracket produces a mis-parsed
`Cite` node, so the fix has to happen upstream of the parser.

`2pdf.sh` and `2docx.sh` are siblings, not variants of one tool — PDF (xelatex + LaTeX preamble)
and DOCX (reference-doc + docx-scoped Lua) are different enough pipelines that a shared "format"
flag would just hide the split inside the script body instead of the filename. Some
preprocessing-discovery logic is intentionally duplicated between the two rather than factored
into a shared library, matching the "small independently-readable script" pattern used
throughout the repo.

Obsidian callouts are the one construct handled in both formats and the reason the Lua/sed split
exists: `layouts/preprocess/callouts.sed` turns a `> [!type] Titel` marker into an invisible
HTML-comment seam, and each format's Lua filter restyles the blockquote from there — a tcolorbox
for PDF, a set of `custom-style` paragraph styles (`Callout`, `Callout Title`, `Callout Tight`,
`Callout Gap`, defined in the reference document by
`layouts/docx/build-a4-work-reference-docx.py`) for DOCX. A marker-less blockquote stays a plain
quote in both. See documentation/2docx.md for what a Word box can and cannot contain.

Adding a layout: drop `layouts/pdf/<name>.yaml` (PDF) and/or `layouts/docx/<name>-reference.docx`
(DOCX) — no code changes needed, both scripts list layouts by globbing their format's directory.

`2pdf.sh` supports Markdown/EPUB/HTML/URL/directory-of-those; `2docx.sh` currently only supports
Markdown (same discovery pattern could be extended to it, but nothing has needed that yet).

`scripts/pdf_extract.py` is the reverse direction (PDF → markdown, via `pymupdf4llm`), used as
the "Tier 1 extractor" by the separate `pkw-librarian` project — not part of the layout system
above. It mtime-caches its `<name>_text.md` sidecar against the source PDF.

`scripts/docx_c.sh` is an old, unfinished stub (syntactically incomplete) predating `2docx.sh` —
don't build on it.

### Script conventions

- Python scripts: `#!/usr/bin/env -S uv run` shebang + PEP 723 `# /// script` block declaring
  `requires-python` and `dependencies`; no external `requirements.txt`/lockfile.
- Bash scripts: resolve their own directory via `BASH_SOURCE` + `readlink -f` (so they work both
  via PATH and direct invocation/symlink), and fail loudly with a non-zero exit on unsupported
  input rather than silently falling back.
- `justfile` recipes are thin wrappers that call `uv run '{{home_dir()}}/justscripts/scripts/...'`
  — paths are absolute via `home_dir()` so recipes work regardless of the caller's cwd.
- Per-script docs beyond an inline docstring go in `documentation/<script>.md`, linked from the
  README's "Available Scripts" table.

## Secret scanning

`gitleaks` runs in CI (`.github/workflows/secret-scan.yml`) on every push/PR using
`.gitleaks.toml`, which extends the default ruleset with a couple of narrowly-scoped personal
rules (specific email, specific private-repo name) — deliberately not broad terms, to avoid
false-positiving on this repo's own public self-references.

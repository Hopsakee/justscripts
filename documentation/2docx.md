# 2docx

Convert a Markdown source to DOCX using [pandoc](https://pandoc.org/) and a layout's reference
template. Sibling to [2pdf](2pdf.md), not a mode of it — DOCX and PDF are different pipelines (a
reference `.docx` + docx-scoped Lua filters vs a LaTeX preamble + xelatex), so this is its own
script rather than a hidden third argument on `2pdf.sh`.

```bash
just to-docx path/to/file.md a4-work    # only layout with a docx reference template so far
```

Produces `path/to/file.docx` next to the source file.

> The recipe is called `to-docx` (not `2docx`) for the same reason `to-pdf` isn't `2pdf` —
> [just recipe names cannot start with a digit](https://github.com/casey/just/blob/master/GRAMMAR.md).
> The underlying script is `scripts/2docx.sh` and can also be invoked directly.

## Supported sources

Only `.md` / `.markdown` for now. `2pdf.sh` also handles EPUB, HTML, and URLs; `2docx.sh` could
grow the same way, but nothing has exercised that path yet, so it isn't claimed here.

## Layout files

A layout named `<name>` needs, under `layouts/docx/`:

| File | Required | Purpose |
|---|---|---|
| `<name>-reference.docx` | yes | `--reference-doc` — Word styles (headings, body text, callout box, margins) |
| `lua/<name>/*.lua` | no | docx-scoped Lua filters, e.g. flattening nested lists inside callouts so Word's callout-box style can cover the whole block, not just its first line |
| `../preprocess/*.sed`, `../preprocess/<name>/*.sed` | no | shared with `2pdf.sh` — raw-text passes before pandoc parses (Obsidian wikilink/HD stripping, callout-marker insertion) |

No `<name>.yaml` is read here — that file's keys (`pdf-engine`, fonts, `colorlinks`) are
PDF/xelatex-only and have no docx equivalent, and PDF layout files live in the sibling
`layouts/pdf/` directory.

## `a4-work`

The only layout with a docx reference template. `layouts/docx/a4-work-reference.docx` is derived
from Jelle's `WDODelta rapport staand_stripped.docx` corporate template — see the file's own
build history for the specific fixes applied (bold-forcing style bug, missing `Compact`/
`BlockText`/`FirstParagraph` styles, oversized left margin, missing heading spacing, callout
border/shading, OOXML element ordering). Regenerate it by re-running that derivation against a
fresh copy of the source template if the corporate template itself changes upstream — don't
hand-edit the derived `.docx` directly, the fixes are all scripted transforms for a reason.

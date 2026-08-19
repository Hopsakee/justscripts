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
| `<name>-reference.docx` | yes | `--reference-doc` — Word styles (headings, body text, callout box, margins). A DOCX has no preamble to include: pandoc only tags paragraphs with style *names*, so this file is where the whole layout lives |
| `lua/<name>/*.lua` | no | docx-scoped Lua filters, e.g. rendering Obsidian callouts as callout boxes (see below) |
| `../preprocess/*.sed`, `../preprocess/<name>/*.sed` | no | shared with `2pdf.sh` — raw-text passes before pandoc parses (Obsidian wikilink/HD stripping, callout-marker insertion) |

No `<name>.yaml` is read here — that file's keys (`pdf-engine`, fonts, `colorlinks`) are
PDF/xelatex-only and have no docx equivalent, and PDF layout files live in the sibling
`layouts/pdf/` directory.

## Obsidian callouts

This is what the docx-scoped Lua filter is for. Pandoc knows nothing about Obsidian's callout
syntax, so a plain `pandoc note.md -o note.docx` turns

```markdown
> [!important] Let op deze versie
> Dit document bevat **interne** informatie.
```

into a Word blockquote reading *"[!important] Let op deze versie Dit document bevat interne
informatie."* — marker printed, title glued to the body, any list inside escaping the quote.

The pipeline has two halves:

1. **`layouts/preprocess/callouts.sed`** (shared with `2pdf.sh`) rewrites the marker line into an
   invisible HTML comment plus, for a titled callout, a bold title line. This runs on the raw
   markdown, before pandoc parses: at AST level the marker has already been absorbed into the
   first paragraph and there is no seam left to cut on.
2. **`layouts/docx/lua/a4-work/callouts.lua`** matches that comment and tags the blockquote's
   paragraphs with `custom-style`, which pandoc's docx writer turns into Word paragraph styles.

Four styles in the reference document draw the box, all defined by
`layouts/docx/build-a4-work-reference-docx.py`:

| Style | Role |
|---|---|
| `Callout` | body paragraphs — accent-blue left border + light tint fill, the same colours as the PDF's `wdocallout` tcolorbox |
| `Callout Title` | the callout's own title line: bold, house blue, kept with the body across a page break |
| `Callout Tight` | rows of a run inside the box — list items, code lines |
| `Callout Gap` | 4pt unshaded spacer between two callouts that touch |

Ordinary blockquotes (no `[!type]` marker) are deliberately **not** boxed — they get plain
indented `BlockText`, the same restraint the PDF path shows a marker-less quote. Boxing them, an
earlier approach here, made every `> quote` pose as a callout and let a quote following a callout
shade into that callout's box.

### What the box does and does not survive

| Inside a callout | Result |
|---|---|
| paragraphs, **bold**/*italic*/links/inline code | full support, inside the box |
| the callout's own title | bold, house blue |
| bulleted / numbered lists, nested | inside the box, bullet or number rendered as text (see below) |
| fenced code blocks | inside the box, one monospace line per source line |
| images | inside the box, with their caption |
| a markdown heading | becomes a title line inside the box, not a document heading |
| an ordinary quote nested in a callout | kept inside the box; its extra indent is dropped |
| a nested callout | a second title inside the same box, not a box in a box |
| tables | kept, but **breaks the box** — a Word table's look comes from a table style, which no paragraph style can reach |
| two callouts in a row | two boxes, thanks to `Callout Gap` |

**Why list bullets and code lines become text.** In Word a box like this is not an object: it is
background shading plus a left border repeated on every paragraph, and Word draws both at the
paragraph's own indent. Pandoc's docx writer hardcodes `Compact` for list-item paragraphs and
`SourceCode` for code-block paragraphs regardless of any wrapping `custom-style` Div, and a real
Word list takes its indent from the numbering definition rather than from the paragraph style — so
those rows fall outside the box, or sit further right and tear white notches into it. Both are
therefore flattened into ordinary paragraphs that carry their bullet, number, or code line as
text. The box stays a box and the text stays editable; the cost is that a callout's list is no
longer a Word list object with automatic renumbering (and no list structure for screen readers).
**Lists and code blocks outside callouts are untouched.**

Reaching a real numbered-and-boxed list would need a post-generation XML rewrite (a custom style
referenced by both `numPr` and a bordered `pPr`), not a Lua filter — deliberately out of scope.

## `a4-work`

The only layout with a docx reference template. `layouts/docx/a4-work-reference.docx` is derived
from Jelle's `WDODelta rapport staand_stripped.docx` corporate template — see the file's own
build history for the specific fixes applied (bold-forcing style bug, missing `Compact`/
`BlockText`/`FirstParagraph` styles, oversized left margin, missing heading spacing, callout
border/shading, OOXML element ordering, the callout and code styles). Regenerate it by re-running
that derivation against a fresh copy of the source template if the corporate template itself
changes upstream — don't hand-edit the derived `.docx` directly, the fixes are all scripted
transforms for a reason.

Two more styles pandoc names that no Word template defines are added there as well: `SourceCode`
for fenced code blocks and `VerbatimChar` for inline code — without them code came out in the body
font, including the per-line code inlines the callout filter emits.

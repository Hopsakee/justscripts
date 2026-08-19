# 2docx

Convert Markdown (or HTML/EPUB) to DOCX using [pandoc](https://pandoc.org/) and a selectable
layout profile. The DOCX sibling of [`2pdf.sh`](2pdf.md): same layout-discovery mechanics, same
shared markdown preprocessing, so a note handed to colleagues as `.docx` looks like the same note
handed to them as `.pdf`.

```bash
just to-docx path/to/notitie.md              # default layout: a4-work
just to-docx path/to/notitie.md plain        # pandoc's own typography
just to-docx path/to/dir/ a4-work            # batch: every supported file in the directory
```

Produces `path/to/notitie.docx` next to the input.

> The recipe is called `to-docx` (not `2docx`) because [just recipe names cannot start with a
> digit](https://github.com/casey/just/blob/master/GRAMMAR.md). The underlying script is
> `scripts/2docx.sh` and can also be invoked directly.

## Obsidian callouts

This is the reason the script exists. Pandoc knows nothing about Obsidian's callout syntax, so a
plain `pandoc notitie.md -o notitie.docx` turns

```markdown
> [!important] Let op deze versie
> Dit document bevat **interne** informatie.
```

into a Word blockquote reading *"[!important] Let op deze versie Dit document bevat interne
informatie."* — marker included, title glued to the body text, and any list inside the callout
escaping the quote altogether.

`2docx.sh` renders it as a real callout box instead: a shaded block with a 3pt accent bar down the
left, the callout's own title in bold house blue above the body. The pipeline has two halves:

1. **`md-preprocess/callouts.sed`** (shared with `2pdf.sh`) rewrites every callout marker line into
   an invisible HTML comment plus, when the callout had a title, a bold title line. This happens on
   the raw markdown, before pandoc parses — at AST level the marker has already been absorbed into
   the first paragraph and there is no seam left to cut on.
2. **`docx-layouts/lua/callouts.lua`** matches that comment and re-emits the blockquote with
   `custom-style` attributes, which pandoc's docx writer turns into the Word paragraph styles
   `Callout`, `Callout Title`, `Callout List` and `Callout Gap` — defined in the layout's reference
   document.

The callout *type* (`important`, `info`, `warning`, …) is never printed: one sober box serves every
type, matching the PDF layout, where the huisstijl asks to "beperk het aantal huisstijlkleuren per
scherm". The type is captured in the filter, so a per-type colour variant has an obvious place to
hook in.

### What the box does and does not survive

| Inside a callout | Result |
|---|---|
| paragraphs, **bold**/*italic*/links/inline code | full support, inside the box |
| the callout's own title | bold, house blue, kept with the body across a page break |
| bulleted / numbered lists, nested | inside the box, bullet or number rendered as text (see below) |
| fenced code blocks | inside the box, monospace, line breaks kept |
| images | inside the box, with their caption |
| a markdown heading | becomes a bold title line inside the box, not a document heading — Word can only shade paragraphs, and a real heading style would leave a white hole in the box |
| an ordinary quote nested in a callout | kept inside the box; its extra indent is dropped, for the same reason |
| a nested callout | renders as a second title inside the same box, not as a box in a box |
| tables | kept, but a Word table takes its look from a table style, out of reach of a paragraph style, so a table does break the box |
| ordinary blockquotes (no `[!type]`) | left alone — still a Word blockquote |

**Why list bullets become text.** In Word a box like this is not an object: it is background
shading plus a left border repeated on every paragraph, and Word draws both at the paragraph's own
indent. A real Word list takes its indent from the numbering definition rather than from the
paragraph style, so its rows sit further right than the rest of the callout — the shading then
starts a centimetre in and the accent bar breaks off, leaving white notches in the middle of the
box. Style indents cannot win that argument, so list items inside a callout become ordinary callout
paragraphs carrying their bullet or number as text, all at one indent. The box stays a box and the
text stays editable; the cost is that those rows are no longer a Word list object with automatic
renumbering. **Lists outside callouts are untouched real Word lists.**

## Layouts

Layouts live in `docx-layouts/` at the repo root.

| Layout | Look | Use case |
|---|---|---|
| `a4-work` (default) | WDODelta huisstijl: Calibri, donkerblauw `#075895` headings with a `#00b0ea` rule under H1, near-black body text, light-blue callout boxes, Dutch as document language | Documents to share with WDODelta colleagues — the DOCX counterpart of the `a4-work` PDF layout |
| `plain` | pandoc's own typography, untouched; grey callout boxes | Anything not going out under the huisstijl, or text to paste into a template that brings its own styles |

For the selected layout, `2docx.sh` auto-discovers, in order:

1. `docx-layouts/<layout>.docx` → `--reference-doc`
2. `docx-layouts/lua/*.lua` → `--lua-filter` (global, applied to every layout)
3. `docx-layouts/lua/<layout>/*.lua` → `--lua-filter` (layout-scoped)
4. `md-preprocess/*.sed` → `sed -E` over the raw markdown (global, shared with `2pdf.sh`)
5. `md-preprocess/<layout>/*.sed` → `sed -E` over the raw markdown (layout-scoped)

Step 5 is why `a4-work` also strips Obsidian `[[wikilinks]]` and Hopsakee Decimal numbers here: the
PDF and DOCX layouts share the name `a4-work`, so both pick up
`md-preprocess/a4-work/wikilinks-hd.sed`. `plain`, like the personal PDF layouts, leaves them in.

## Reference documents: where a DOCX layout lives

A DOCX has no preamble to include. Pandoc writes paragraphs tagged with style *names* and Word
resolves each name against the styles stored in the reference document, so `docx-layouts/*.docx`
is to this tool what `pdf-layouts/*.tex` is to `2pdf.sh` — including the callout styles, which
exist nowhere in pandoc and have to be defined there for the boxes to appear at all.

Binary `.docx` files are not reviewable in git, so they are generated from code:
[`scripts/make_docx_reference.py`](../scripts/make_docx_reference.py) is the source of truth. It
takes pandoc's own default `reference.docx` and rewrites `word/styles.xml`.

```bash
just docx-reference             # regenerate every profile
just docx-reference a4-work     # one profile
```

Edit the `PROFILES` table in that script (fonts, colours, heading sizes, callout shading), rerun it,
and commit the regenerated `.docx` files. To adjust a layout by hand in Word instead, restyle
`docx-layouts/<layout>.docx` there and keep the style *names* — but the next regeneration overwrites
it, so port anything worth keeping back into the script.

## Dependencies

Only pandoc — no LaTeX, no fonts to install, since Word does the typesetting:

```bash
sudo apt install pandoc
```

The `a4-work` reference document asks Word for Calibri (present on any Windows/Office machine,
which is where these documents are read). On Linux, install `fonts-crosextra-carlito` for a
metric-compatible substitute if you also want to *view* the result locally.

## Sanity check

```bash
pandoc --version                              # 2.x or 3.x
just to-docx some-note-with-callouts.md       # writes some-note-with-callouts.docx
```

Open the result and confirm the callouts are shaded boxes with an accent bar. If they came out as
unstyled paragraphs, the reference document is missing or lost its styles — `2docx.sh` warns about
the missing file, and `just docx-reference` restores it.

## Troubleshooting

- **Callout text appears, but with no box** — the reference document has no `Callout` style (a
  hand-restyled or replaced `docx-layouts/<layout>.docx`). Regenerate with `just docx-reference`.
- **`[!important]` still shows up literally** — the markdown preprocessing did not run. It only
  applies to `.md`/`.markdown` inputs; converting an `.html` or `.epub` export of the same note
  skips it, because the marker is gone by then anyway (into HTML text, in the worst case).
- **A callout ends up with two titles** — that is a nested callout. Word cannot nest shading from a
  paragraph style; the inner callout renders as another title line inside the same box.
- **Fonts look wrong on Linux** — expected. `a4-work` targets Calibri because it is aimed at Word on
  Windows; LibreOffice substitutes something else unless Carlito is installed.
- **Images do not appear** — pandoc resolves image paths relative to the working directory and the
  source file's own directory; a path pointing outside both (an Obsidian vault-absolute
  `attachments/…`, for instance) will not resolve. Run the conversion from the vault root.

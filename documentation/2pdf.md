# 2pdf

Convert any source to PDF using [pandoc](https://pandoc.org/) and a selectable layout profile.
`2pdf.sh` collapses the former `md2pdf.sh` and `epub2pdf.sh` into a single tool and adds HTML/URL support.

```bash
just to-pdf path/to/file.md                  # Markdown,  default layout: a4-work
just to-pdf path/to/file.md a4-personal      # Markdown,  A4 serif
just to-pdf path/to/book.epub boox-delight   # EPUB,      Boox editorial layout
just to-pdf path/to/page.html boox-delight   # local HTML file
just to-pdf https://example.com/article.html boox-delight   # remote URL (fetched as HTML)
just to-pdf path/to/dir/ boox                # batch: every supported file in the directory
```

Produces `path/to/file.pdf` next to a file input. For a URL the PDF lands in the current
directory, named after the last URL path segment.

> The recipe is called `to-pdf` (not `2pdf`) because [just recipe names cannot start with a
> digit](https://github.com/casey/just/blob/master/GRAMMAR.md) (`NAME = [a-zA-Z_][a-zA-Z0-9_-]*`).
> The underlying script is `scripts/2pdf.sh` and can also be invoked directly.

## Supported sources

| Source | Detected by | Notes |
|---|---|---|
| `.md` / `.markdown` | extension | pandoc auto-detects markdown |
| `.epub` | extension | pandoc auto-detects epub |
| `.html` / `.htm` | extension | read as HTML |
| `http(s)://…` | URL scheme | fetched by pandoc, forced to HTML input; PDF written to CWD |
| a directory | `-d` test | batch-converts `*.md *.markdown *.epub *.html *.htm` inside |

Unsupported extensions and unknown layout names fail loudly with a non-zero exit — the tool never
silently falls back to a different format or layout.

## Layouts

Layouts live in `pdf-layouts/*.yaml` at the repo root and are **shared across every input type**.
Each file is a pandoc "defaults" file that controls the complete look: paper size, margins, fonts,
font size, line height, link colour, etc.

| Layout | Paper | Font | Use case |
|---|---|---|---|
| `a4-work` (default) | A4 | DejaVu Sans | Documents to share with colleagues |
| `a4-personal` | A4 | DejaVu Serif | Personal long-form reading at A4 |
| `boox` | A5 | DejaVu Serif | Boox Note Air 3C ereader (minimal) |
| `boox-delight` | A5 | DejaVu Serif | Boox Note Air 3C ereader — editorial palette, colored headings, code panels, wide-table auto-rotation |

For each selected layout, `2pdf.sh` auto-discovers, in order:

1. `pdf-layouts/<layout>.tex` → `--include-in-header` (e.g. `boox-delight.tex`)
2. `pdf-layouts/lua/*.lua` → `--lua-filter` (global, applied to every layout)
3. `pdf-layouts/lua/<layout>/*.lua` → `--lua-filter` (layout-scoped, e.g. `lua/boox-delight/table-widths.lua`)

Layout-scoped filters keep one layout's quirks from leaking into the others.

To add a new layout, drop a `name.yaml` file into `pdf-layouts/` and it becomes available as
`just to-pdf file.md name`.

## Dependencies

`2pdf.sh` wraps `pandoc` with XeLaTeX as the PDF engine (required for Unicode + custom fonts).
Install on Debian / Ubuntu / Pop!_OS:

```bash
sudo apt update
sudo apt install pandoc
sudo apt install texlive-xetex texlive-base texlive-latex-recommended texlive-fonts-recommended
sudo apt install fonts-dejavu
```

Notes:

- `texlive-xetex` pulls in the XeLaTeX engine, which handles Unicode and custom fonts far better than the default `pdflatex`. The three `texlive-*` packages above are a *minimal* working set — you do **not** need the full `texlive-full` (several GB).
- `fonts-dejavu` provides "DejaVu Sans / Serif / Sans Mono", referenced by all bundled layouts. Without it, xelatex falls back to a default and the layout may look off.
- `boox-delight.tex` requires TeX Live 2021 or newer for soft-gray table rules (older `colortbl` ignores `\arrayrulecolor`); it compiles clean either way.
- On other platforms, follow pandoc's own guide: <https://pandoc.org/installing.html>.

## Sanity check

```bash
pandoc --version    # should print pandoc 2.x or 3.x
xelatex --version   # should print XeTeX, Version 3.x
fc-list | grep -i "dejavu"   # should list DejaVu Sans / Serif / Sans Mono
```

If all three succeed, `just to-pdf file.md` will work.

## Troubleshooting

- **`xelatex not found`** — install `texlive-xetex` (see above). The script explicitly sets `pdf-engine: xelatex` in each layout yaml, so pandoc never falls back to `pdflatex`.
- **`Unicode character ... not set up for use with LaTeX`** — means pandoc chose `pdflatex` instead of `xelatex`. Check that the selected layout yaml still contains `pdf-engine: xelatex`.
- **`Package fontspec Error: The font "X" cannot be found`** — the font declared in the yaml isn't installed. Install the matching font package (e.g. `fonts-dejavu`, `fonts-crosextra-carlito`, `fonts-inter`, etc.), or edit the yaml to reference a font you have.
- **Messy HTML / URL output** — `2pdf.sh` converts the HTML as-is (pandoc), including site navigation chrome. It does not strip boilerplate. For clean single-article extraction, pre-process the page first.
- **Huge install size** — `texlive-full` is several GB. The four packages above are ~600 MB and cover the bundled layouts.
- **Adding Calibri on Linux** — Microsoft's Calibri isn't in any apt package. `fonts-crosextra-carlito` is a free, metric-compatible clone (same character widths, near-identical look). Install it and reference `"Carlito"` in a layout yaml.

## Customising a layout

Edit the relevant yaml in `pdf-layouts/`. Common pandoc variables:

```yaml
pdf-engine: xelatex
variables:
  papersize: a4              # a4, a5, letter
  geometry: margin=2.5cm     # or "top=2cm,left=3cm,..."
  mainfont: "DejaVu Sans"    # body font (must be installed)
  sansfont: "DejaVu Sans"    # sans (for headings if mainfont is serif)
  monofont: "DejaVu Sans Mono"
  fontsize: 11pt
  linestretch: 1.25
  colorlinks: true
  linkcolor: "Blue"
  urlcolor: "Blue"
```

See the pandoc manual for the full list: <https://pandoc.org/MANUAL.html#variables-for-latex>.

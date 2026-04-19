# md2pdf

Convert a Markdown file to PDF using [pandoc](https://pandoc.org/) and a selectable layout profile.

```bash
just md2pdf path/to/file.md               # default layout: a4-work
just md2pdf path/to/file.md a4-personal
just md2pdf path/to/file.md boox
```

Produces `path/to/file.pdf` next to the input.

## Layouts

Layouts live in `pdf-layouts/*.yaml` at the repo root and are **shared** with `epub2pdf.sh` (the Boox layout is used by both). Each file is a pandoc "defaults" file that controls the complete look: paper size, margins, fonts, font size, line height, link colour, etc.

| Layout | Paper | Font | Use case |
|---|---|---|---|
| `a4-work` (default) | A4 | DejaVu Sans | Documents to share with colleagues |
| `a4-personal` | A4 | DejaVu Serif | Personal long-form reading at A4 |
| `boox` | A5 | DejaVu Serif | Boox Note Air 3C ereader |

To add a new layout, drop a `name.yaml` file into `pdf-layouts/` and it becomes available as `just md2pdf file.md name`.

## Dependencies

`md2pdf.sh` wraps `pandoc` with XeLaTeX as the PDF engine (required for Unicode + custom fonts). Install on Debian / Ubuntu / Pop!_OS:

```bash
sudo apt update
sudo apt install pandoc
sudo apt install texlive-xetex texlive-base texlive-latex-recommended texlive-fonts-recommended
sudo apt install fonts-dejavu
```

Notes:

- `texlive-xetex` pulls in the XeLaTeX engine, which handles Unicode and custom fonts far better than the default `pdflatex`. The three `texlive-*` packages above are a *minimal* working set — you do **not** need the full `texlive-full` (several GB).
- `fonts-dejavu` provides "DejaVu Sans / Serif / Sans Mono", referenced by all three default layouts. Without it, xelatex falls back to a default and the layout may look off.
- On other platforms, follow pandoc's own guide: <https://pandoc.org/installing.html>. TeX distributions on macOS (MacTeX / BasicTeX) and Windows (MiKTeX / TeX Live) also ship xelatex.

## Sanity check

```bash
pandoc --version    # should print pandoc 2.x or 3.x
xelatex --version   # should print XeTeX, Version 3.x
fc-list | grep -i "dejavu"   # should list DejaVu Sans / Serif / Sans Mono
```

If all three succeed, `just md2pdf file.md` will work.

## Troubleshooting

- **`xelatex not found`** — install `texlive-xetex` (see above). The script explicitly sets `pdf-engine: xelatex` in each layout yaml, so pandoc never falls back to `pdflatex`.
- **`Unicode character ... not set up for use with LaTeX`** — means pandoc chose `pdflatex` instead of `xelatex`. Check that the selected layout yaml still contains `pdf-engine: xelatex`.
- **`Package fontspec Error: The font "X" cannot be found`** — the font declared in the yaml isn't installed. Install the matching font package (e.g. `fonts-dejavu`, `fonts-crosextra-carlito`, `fonts-inter`, etc.), or edit the yaml to reference a font you have.
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

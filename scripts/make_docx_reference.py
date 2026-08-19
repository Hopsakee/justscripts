#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Generate the pandoc reference documents used by 2docx.sh.

A pandoc DOCX conversion gets its entire look from a "reference document":
pandoc writes paragraphs that carry style NAMES (Heading1, BodyText, ...) and
Word resolves each name against the styles defined in that .docx. Anything
pandoc has no style for -- an Obsidian callout box, for instance -- can only be
styled by defining a paragraph style and pointing pandoc at it with a
`Div {custom-style="..."}` (see docx-layouts/lua/callouts.lua).

So the reference document is where the DOCX layout actually lives, the way
pdf-layouts/*.tex is where the PDF layout lives. Binary .docx files are not
reviewable in git, so this script is the source of truth: it starts from
pandoc's own default reference.docx and rewrites `word/styles.xml`, adding the
callout styles and (per profile) the house-style body/heading styles.

Usage:
    ./scripts/make_docx_reference.py            # regenerate every profile
    ./scripts/make_docx_reference.py a4-work    # one profile
    just docx-reference                         # same, via the justfile

Requires `pandoc` on PATH (it supplies the base reference.docx).
Output: docx-layouts/<profile>.docx -- commit the regenerated files.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# Style profiles. Sizes are OOXML half-points (52 = 26pt); measures in twips
# (1/20 pt, so 284 ~= 0.5 cm); colours are RRGGBB hex without '#'.
#
# a4-work mirrors pdf-layouts/a4-work.tex + lua/a4-work/callouts.lua so a
# document shared as .docx looks like the same document shared as .pdf:
# WDODelta huisstijl (donkerblauw #075895 headings, blauw #00b0ea as the single
# accent, near-black body text), and one sober callout box for every callout
# type ("beperk het aantal huisstijlkleuren per scherm").
PROFILES: dict[str, dict] = {
    "a4-work": {
        "body_font": "Calibri",
        "body_size": 22,  # 11pt, matching a4-work.yaml
        "body_color": "1A1A1A",
        "lang": "nl-NL",
        "heading_font": "Calibri",
        "heading_color": "075895",
        # 26 / 19 / 15 / 12.5 pt -- the same heading staircase as a4-work.tex
        "heading_sizes": (52, 38, 30, 25),
        "h1_rule_color": "00B0EA",
        "link_color": "075895",
        "callout_bg": "EAF6FC",
        "callout_bar": "00B0EA",
        "callout_title_color": "075895",
    },
    "plain": {
        # Pandoc's own typography, untouched: only the callout styles are added,
        # in neutral grey so the box reads as a box in any house style.
        "body_font": None,
        "body_size": None,
        "body_color": None,
        "lang": None,
        "heading_font": None,
        "heading_color": None,
        "heading_sizes": None,
        "h1_rule_color": None,
        "link_color": None,
        "callout_bg": "F2F4F6",
        "callout_bar": "8C8C8C",
        "callout_title_color": "333333",
    },
}

# Callout geometry, shared by all profiles so the three callout styles line up.
# They MUST agree on left/right indent and on the left border, otherwise Word
# draws the accent bar and the shading at different x-positions per paragraph
# and the box falls apart into steps.
CALLOUT_INDENT_LEFT = 284  # 0.5 cm
CALLOUT_INDENT_RIGHT = 284
CALLOUT_BAR_WIDTH = 24  # eighths of a point -> 3pt, as the PDF's borderline west
CALLOUT_BAR_SPACE = 6  # points between bar and text


def bar(color: str) -> str:
    return (
        f'<w:pBdr><w:left w:val="single" w:sz="{CALLOUT_BAR_WIDTH}" '
        f'w:space="{CALLOUT_BAR_SPACE}" w:color="{color}"/></w:pBdr>'
    )


def callout_styles(p: dict) -> dict[str, str]:
    """The paragraph styles the callouts Lua filter targets, as raw style XML.

    Written out in full rather than mutated in place because OOXML fixes the
    order of a <w:style>'s children; emitting the whole element keeps that
    order provably right.

    - Callout      body paragraphs of the box
    - CalloutGap   hairline spacer keeping two touching callouts apart
    - CalloutTitle the callout's own title line (bold, house blue)
    - CalloutList  list rows inside a box: deliberately the SAME indent and the
                   same bar as Callout, only tighter spacing. Their bullet is
                   text, not Word numbering (see docx-layouts/lua/callouts.lua):
                   Word draws shading and border at each paragraph's own indent,
                   so a row sitting further right tears a white notch out of
                   the box.
    """
    bg, barcol, title = p["callout_bg"], p["callout_bar"], p["callout_title_color"]
    shd = f'<w:shd w:val="clear" w:color="auto" w:fill="{bg}"/>'
    return {
        "Callout": (
            '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Callout">'
            '<w:name w:val="Callout"/>'
            '<w:basedOn w:val="BodyText"/>'
            '<w:next w:val="BodyText"/>'
            "<w:qFormat/>"
            "<w:pPr>"
            f"{bar(barcol)}{shd}"
            '<w:spacing w:before="80" w:after="80"/>'
            f'<w:ind w:left="{CALLOUT_INDENT_LEFT}" w:right="{CALLOUT_INDENT_RIGHT}"/>'
            "</w:pPr>"
            "</w:style>"
        ),
        "CalloutTitle": (
            '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutTitle">'
            '<w:name w:val="Callout Title"/>'
            '<w:basedOn w:val="Callout"/>'
            '<w:next w:val="Callout"/>'
            "<w:qFormat/>"
            "<w:pPr>"
            "<w:keepNext/>"
            f"{bar(barcol)}{shd}"
            '<w:spacing w:before="140" w:after="40"/>'
            f'<w:ind w:left="{CALLOUT_INDENT_LEFT}" w:right="{CALLOUT_INDENT_RIGHT}"/>'
            "</w:pPr>"
            f'<w:rPr><w:b/><w:color w:val="{title}"/></w:rPr>'
            "</w:style>"
        ),
        "CalloutGap": (
            # Spacer between two callouts that touch. No shading and a tiny font,
            # so it reads as the gap between two boxes rather than as a blank
            # line of body text.
            '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutGap">'
            '<w:name w:val="Callout Gap"/>'
            '<w:basedOn w:val="Normal"/>'
            '<w:next w:val="BodyText"/>'
            "<w:qFormat/>"
            '<w:pPr><w:spacing w:before="0" w:after="0" w:line="120"'
            ' w:lineRule="exact"/></w:pPr>'
            '<w:rPr><w:sz w:val="8"/><w:szCs w:val="8"/></w:rPr>'
            "</w:style>"
        ),
        "CalloutList": (
            '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutList">'
            '<w:name w:val="Callout List"/>'
            '<w:basedOn w:val="Callout"/>'
            '<w:next w:val="Callout"/>'
            "<w:qFormat/>"
            "<w:pPr>"
            f"{bar(barcol)}{shd}"
            '<w:spacing w:before="20" w:after="20"/>'
            f'<w:ind w:left="{CALLOUT_INDENT_LEFT}" w:right="{CALLOUT_INDENT_RIGHT}"/>'
            "</w:pPr>"
            "</w:style>"
        ),
    }


def heading_styles(p: dict) -> dict[str, str]:
    """Heading1-4 in the profile's font/colour/size staircase (if it sets one)."""
    if not p["heading_sizes"]:
        return {}
    font, color = p["heading_font"], p["heading_color"]
    out: dict[str, str] = {}
    # space before/after per level, in twips: generous above, tight below.
    spacing = [(360, 120), (280, 100), (220, 80), (180, 60)]
    for i, size in enumerate(p["heading_sizes"], start=1):
        before, after = spacing[i - 1]
        # H1 carries the single accent rule, echoing the \titlerule in a4-work.tex.
        rule = ""
        if i == 1 and p["h1_rule_color"]:
            rule = (
                "<w:pBdr>"
                f'<w:bottom w:val="single" w:sz="12" w:space="2" '
                f'w:color="{p["h1_rule_color"]}"/>'
                "</w:pBdr>"
            )
        out[f"Heading{i}"] = (
            f'<w:style w:type="paragraph" w:styleId="Heading{i}">'
            f'<w:name w:val="heading {i}"/>'
            '<w:basedOn w:val="Normal"/>'
            '<w:next w:val="BodyText"/>'
            f'<w:link w:val="Heading{i}Char"/>'
            '<w:uiPriority w:val="9"/>'
            "<w:qFormat/>"
            "<w:pPr>"
            "<w:keepNext/><w:keepLines/>"
            f"{rule}"
            f'<w:spacing w:before="{before}" w:after="{after}"/>'
            f'<w:outlineLvl w:val="{i - 1}"/>'
            "</w:pPr>"
            "<w:rPr>"
            f'<w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:cs="{font}"/>'
            "<w:b/>"
            f'<w:color w:val="{color}"/>'
            f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>'
            "</w:rPr>"
            "</w:style>"
        )
    return out


def extra_styles(p: dict) -> dict[str, str]:
    """Profile styles beyond headings and callouts."""
    out: dict[str, str] = {}
    if p["link_color"]:
        out["Hyperlink"] = (
            '<w:style w:type="character" w:styleId="Hyperlink">'
            '<w:name w:val="Hyperlink"/>'
            '<w:basedOn w:val="DefaultParagraphFont"/>'
            '<w:uiPriority w:val="99"/>'
            "<w:unhideWhenUsed/>"
            "<w:rPr>"
            f'<w:color w:val="{p["link_color"]}"/>'
            '<w:u w:val="single"/>'
            "</w:rPr>"
            "</w:style>"
        )
    if p["heading_color"]:
        # Title/Subtitle in the house blue, so a metadata title matches H1.
        out["Title"] = (
            '<w:style w:type="paragraph" w:styleId="Title">'
            '<w:name w:val="Title"/>'
            '<w:basedOn w:val="Normal"/>'
            '<w:next w:val="BodyText"/>'
            '<w:link w:val="TitleChar"/>'
            '<w:uiPriority w:val="10"/>'
            "<w:qFormat/>"
            "<w:pPr>"
            '<w:spacing w:before="0" w:after="200"/>'
            "<w:contextualSpacing/>"
            "</w:pPr>"
            "<w:rPr>"
            f'<w:rFonts w:ascii="{p["heading_font"]}" w:hAnsi="{p["heading_font"]}"'
            f' w:cs="{p["heading_font"]}"/>'
            "<w:b/>"
            f'<w:color w:val="{p["heading_color"]}"/>'
            '<w:sz w:val="60"/><w:szCs w:val="60"/>'
            "</w:rPr>"
            "</w:style>"
        )
    return out


def doc_defaults(p: dict) -> str | None:
    """Replacement <w:rPrDefault> run properties: body font, size, colour, lang."""
    if not any((p["body_font"], p["body_size"], p["body_color"], p["lang"])):
        return None
    parts = []
    if p["body_font"]:
        f = p["body_font"]
        parts.append(
            f'<w:rFonts w:ascii="{f}" w:eastAsia="{f}" w:hAnsi="{f}" w:cs="{f}"/>'
        )
    if p["body_color"]:
        parts.append(f'<w:color w:val="{p["body_color"]}"/>')
    if p["body_size"]:
        parts.append(f'<w:sz w:val="{p["body_size"]}"/>')
        parts.append(f'<w:szCs w:val="{p["body_size"]}"/>')
    if p["lang"]:
        parts.append(f'<w:lang w:val="{p["lang"]}"/>')
    return "<w:rPrDefault><w:rPr>" + "".join(parts) + "</w:rPr></w:rPrDefault>"


def style_id(xml: str) -> str:
    marker = 'w:styleId="'
    start = xml.index(marker) + len(marker)
    return xml[start : xml.index('"', start)]


def find_style(styles_xml: str, sid: str) -> tuple[int, int] | None:
    """Byte range of the <w:style> element with this styleId, if present.

    Plain string scanning rather than an XML parse: ElementTree rewrites the
    whole document (namespace prefixes, self-closing forms, attribute order),
    which produces a needlessly large diff against pandoc's own file and risks
    changing parts we never meant to touch.
    """
    needle = f'w:styleId="{sid}">'
    pos = styles_xml.find(needle)
    if pos == -1:
        return None
    start = styles_xml.rfind("<w:style ", 0, pos)
    end = styles_xml.index("</w:style>", pos) + len("</w:style>")
    return start, end


def patch_styles(styles_xml: str, profile: dict) -> str:
    replacements: dict[str, str] = {}
    replacements.update(heading_styles(profile))
    replacements.update(extra_styles(profile))
    replacements.update(callout_styles(profile))

    for sid, xml in replacements.items():
        assert style_id(xml) == sid, f"style id mismatch for {sid}"
        span = find_style(styles_xml, sid)
        if span:
            styles_xml = styles_xml[: span[0]] + xml + styles_xml[span[1] :]
        else:
            # Append before </w:styles>; order of styles is not significant.
            styles_xml = styles_xml.replace("</w:styles>", xml + "</w:styles>")

    defaults = doc_defaults(profile)
    if defaults:
        start = styles_xml.index("<w:rPrDefault>")
        end = styles_xml.index("</w:rPrDefault>") + len("</w:rPrDefault>")
        styles_xml = styles_xml[:start] + defaults + styles_xml[end:]

    return styles_xml


def base_reference(work: Path) -> Path:
    """pandoc's own default reference.docx -- the base we patch."""
    if not shutil.which("pandoc"):
        sys.exit("Error: pandoc not found on PATH (needed for its reference.docx)")
    out = work / "base.docx"
    with out.open("wb") as fh:
        proc = subprocess.run(
            ["pandoc", "--print-default-data-file", "reference.docx"],
            stdout=fh,
            stderr=subprocess.PIPE,
        )
    if proc.returncode != 0:
        sys.exit(f"Error: pandoc failed: {proc.stderr.decode().strip()}")
    return out


def build(name: str, profile: dict, base: Path, dest: Path) -> None:
    """Copy the base reference doc, swapping in the patched word/styles.xml."""
    tmp = dest.with_suffix(".docx.tmp")
    with zipfile.ZipFile(base) as src, zipfile.ZipFile(
        tmp, "w", zipfile.ZIP_DEFLATED
    ) as out:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename == "word/styles.xml":
                data = patch_styles(data.decode("utf-8"), profile).encode("utf-8")
            out.writestr(item, data)
    tmp.replace(dest)
    print(f"wrote {dest}  (profile: {name})")


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "profiles",
        nargs="*",
        help=f"profiles to build (default: all of {', '.join(sorted(PROFILES))})",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=repo_root / "docx-layouts",
        help="output directory (default: docx-layouts/)",
    )
    args = parser.parse_args()
    names = args.profiles or sorted(PROFILES)
    unknown = [n for n in names if n not in PROFILES]
    if unknown:
        sys.exit(
            f"Error: unknown profile(s) {', '.join(unknown)}; "
            f"known: {', '.join(sorted(PROFILES))}"
        )

    args.out.mkdir(parents=True, exist_ok=True)
    work = args.out / ".build"
    work.mkdir(exist_ok=True)
    try:
        base = base_reference(work)
        for name in names:
            build(name, PROFILES[name], base, args.out / f"{name}.docx")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Derive pdf-layouts/a4-work-reference.docx from Jelle's corporate WDODelta
template. Run this again (against a fresh copy of the source template) if
the corporate template changes upstream -- don't hand-edit the derived
.docx directly, everything here is a scripted, re-runnable transform.

Source: ~/Drive/Downloads/WDODelta rapport staand_stripped.docx (Jelle's own
file, never modified by this script -- only read).

Fixes applied, in order, all found and verified against the actual OOXML
this session (2026-08-18):

1. BodyText style forced bold+Arial+11pt on every paragraph using it (a
   leftover from whatever the source template originally used "Body Text"
   for) -- stripped that rPr override, added real paragraph spacing instead
   (pandoc's own default reference.docx uses before=after=180 twips; the
   source template had none at all).
2. Compact, BlockText, and FirstParagraph are paragraph styles pandoc's
   docx writer references by name for list items, blockquote paragraphs,
   and the paragraph right after a heading -- none of the three existed in
   the source template. A dangling w:pStyle reference to a style that
   doesn't exist collapses to zero formatting; Word doesn't error, it just
   silently drops it. Added all three (values from pandoc's own default
   reference.docx where sensible).
3. Left margin was 3827 twips (6.75cm) vs 1417 (2.5cm) on the right -- an
   asymmetric binding-style margin wrong for a normal shared document.
   Set left=right=1417.
4. Heading2 and Heading4 had no before/after spacing at all; Heading3 only
   had a token 2pt before. Added real spacing to all three (Heading1
   already had after=260, just needed before=0 added explicitly).
5. BlockText had no border or shading -- gave it a left accent-blue border
   + light tint fill, same colours as the PDF path's wdocallout tcolorbox
   (00B0EA / EAF6FC), so DOCX and PDF read as one system.
6. OOXML w:pPr child elements have a strict required order (CT_PPrBase):
   pBdr/shd must come before spacing/ind, and keepNext/keepLines/numPr
   must come before spacing. Steps 4 and 5 above initially landed these in
   the wrong order -- Word's lenient parser can silently drop out-of-
   sequence elements during its repair pass. Fixed by emitting them in
   spec order from the start.
"""
import argparse
import sys
import zipfile

DEFAULT_SRC = "/home/jelle/Drive/Downloads/WDODelta rapport staand_stripped.docx"
DEFAULT_DST = "/home/jelle/Code/justscripts/pdf-layouts/a4-work-reference.docx"


def build(src: str, dst: str) -> None:
    with zipfile.ZipFile(src, "r") as zsrc:
        styles = zsrc.read("word/styles.xml").decode("utf-8")
        document = zsrc.read("word/document.xml").decode("utf-8")
        infos = zsrc.infolist()
        contents = {i.filename: zsrc.read(i.filename) for i in infos}

    # --- 1. BodyText: strip bogus bold/Arial, add real paragraph spacing ---
    old_bodytext = (
        '<w:style w:type="paragraph" w:styleId="BodyText"><w:name w:val="Body Text"/>'
        '<w:basedOn w:val="Normal"/><w:link w:val="BodyTextChar"/><w:semiHidden/>'
        '<w:rsid w:val="00781F03"/><w:rPr><w:rFonts w:cs="Arial"/><w:b/><w:bCs/>'
        '<w:sz w:val="22"/></w:rPr></w:style>'
    )
    assert old_bodytext in styles, "BodyText style text not found verbatim -- source template changed?"
    new_bodytext = (
        '<w:style w:type="paragraph" w:styleId="BodyText"><w:name w:val="Body Text"/>'
        '<w:basedOn w:val="Normal"/><w:link w:val="BodyTextChar"/><w:rsid w:val="00781F03"/>'
        '<w:pPr><w:spacing w:after="180" w:before="180"/></w:pPr></w:style>'
    )
    styles = styles.replace(old_bodytext, new_bodytext)

    # --- 2. Add Compact, BlockText (with border/shading, step 5+6 folded
    # in directly since there's no reason to land it wrong first), and
    # FirstParagraph -- none exist in the source template. ---
    new_blocktext = (
        '<w:style w:type="paragraph" w:styleId="BlockText">'
        '<w:name w:val="Block Text"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
        '<w:uiPriority w:val="9"/><w:unhideWhenUsed/><w:qFormat/>'
        '<w:pPr>'
        '<w:pBdr><w:left w:val="single" w:sz="18" w:space="10" w:color="00B0EA"/></w:pBdr>'
        '<w:shd w:val="clear" w:color="auto" w:fill="EAF6FC"/>'
        '<w:spacing w:after="100" w:before="100"/>'
        '<w:ind w:firstLine="0" w:left="480" w:right="120"/>'
        '</w:pPr></w:style>'
    )
    extra_styles = (
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Compact">'
        '<w:name w:val="Compact"/><w:basedOn w:val="BodyText"/><w:qFormat/>'
        '<w:pPr><w:spacing w:after="36" w:before="36"/></w:pPr></w:style>'
        + new_blocktext +
        '<w:style w:type="paragraph" w:customStyle="1" w:styleId="FirstParagraph">'
        '<w:name w:val="First Paragraph"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
        '<w:qFormat/></w:style>'
    )
    marker = '</w:style><w:style w:type="paragraph" w:styleId="Heading1"'
    assert marker in styles, "Heading1 marker not found verbatim -- source template changed?"
    styles = styles.replace(marker, "</w:style>" + extra_styles + '<w:style w:type="paragraph" w:styleId="Heading1"', 1)

    # --- 3. Left margin: match the right margin (2.5cm), was 6.75cm. ---
    old_margin = (
        '<w:pgMar w:top="850" w:right="1417" w:bottom="1417" w:left="3827" '
        'w:header="709" w:footer="624" w:gutter="0"/>'
    )
    assert old_margin in document, "pgMar string not found verbatim -- source template changed?"
    new_margin = old_margin.replace('w:left="3827"', 'w:left="1417"')
    document = document.replace(old_margin, new_margin)

    # --- 4. Heading1 needs before=0 added; Heading2/Heading4 need spacing
    # added (schema order: after keepNext/keepLines/numPr, before outlineLvl,
    # matching the position Heading3's original spacing already sat in). ---
    old_h1 = (
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
        '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:link w:val="Heading1Char"/>'
        '<w:uiPriority w:val="9"/><w:qFormat/><w:rsid w:val="00EC6C2C"/><w:pPr><w:keepNext/>'
        '<w:keepLines/><w:numPr><w:numId w:val="41"/></w:numPr>'
        '<w:spacing w:after="260" w:line="620" w:lineRule="exact"/>'
        '<w:outlineLvl w:val="0"/></w:pPr>'
    )
    assert old_h1 in styles, "Heading1 pPr not found verbatim -- source template changed?"
    new_h1 = old_h1.replace('<w:spacing w:after="260"', '<w:spacing w:before="0" w:after="260"')
    styles = styles.replace(old_h1, new_h1)

    old_h2 = (
        '<w:pPr><w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="1"/><w:numId w:val="41"/>'
        '</w:numPr><w:outlineLvl w:val="1"/></w:pPr>'
    )
    assert old_h2 in styles, "Heading2 pPr not found verbatim -- source template changed?"
    new_h2 = old_h2.replace(
        '</w:numPr><w:outlineLvl',
        '</w:numPr><w:spacing w:before="300" w:after="150"/><w:outlineLvl',
    )
    styles = styles.replace(old_h2, new_h2)

    old_h4 = (
        '<w:pPr><w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="3"/><w:numId w:val="41"/>'
        '</w:numPr><w:outlineLvl w:val="3"/></w:pPr>'
    )
    assert old_h4 in styles, "Heading4 pPr not found verbatim -- source template changed?"
    new_h4 = old_h4.replace(
        '</w:numPr><w:outlineLvl',
        '</w:numPr><w:spacing w:before="180" w:after="80"/><w:outlineLvl',
    )
    styles = styles.replace(old_h4, new_h4)

    old_h3 = (
        '<w:pPr><w:keepNext/><w:keepLines/><w:numPr><w:ilvl w:val="2"/><w:numId w:val="41"/>'
        '</w:numPr><w:spacing w:before="40"/><w:outlineLvl w:val="2"/></w:pPr>'
    )
    assert old_h3 in styles, "Heading3 pPr not found verbatim -- source template changed?"
    new_h3 = old_h3.replace('w:before="40"', 'w:before="220" w:after="100"')
    styles = styles.replace(old_h3, new_h3)

    contents["word/styles.xml"] = styles.encode("utf-8")
    contents["word/document.xml"] = document.encode("utf-8")

    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in infos:
            zout.writestr(item, contents[item.filename])

    print(f"wrote {dst}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--src", default=DEFAULT_SRC, help="source corporate template (read-only)")
    parser.add_argument("--dst", default=DEFAULT_DST, help="output reference docx")
    args = parser.parse_args()
    try:
        build(args.src, args.dst)
    except AssertionError as e:
        print(f"Error: {e}", file=sys.stderr)
        print("The source template's XML no longer matches what this script expects.", file=sys.stderr)
        print("Re-derive the fixes by hand against the new template instead of guessing.", file=sys.stderr)
        sys.exit(1)

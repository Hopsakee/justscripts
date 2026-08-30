#!/usr/bin/env python3
"""Derive layouts/docx/a4-work-reference.docx from Jelle's corporate WDODelta
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
5. BlockText (pandoc's style for ordinary blockquote paragraphs) had no
   border or shading. It briefly carried the accent-blue box, but that made
   every plain "> quote" look like a callout, and two callouts in a row shade
   into one box with two titles. The box moved to the dedicated Callout
   styles of fix 8; BlockText is now a plain indented quote, which is what
   the PDF path gives a marker-less blockquote too.
6. OOXML w:pPr child elements have a strict required order (CT_PPrBase):
   pBdr/shd must come before spacing/ind, and keepNext/keepLines/numPr
   must come before spacing. Steps 4 and 5 above initially landed these in
   the wrong order -- Word's lenient parser can silently drop out-of-
   sequence elements during its repair pass. Fixed by emitting them in
   spec order from the start.
7. Heading1-4 all number via numId=41 -> abstractNumId=28, which is a
   numStyleLink to the "WDODHoofdstukken" numbering style (numId=33 ->
   abstractNumId=2) -- the actual per-level numFmt/lvlText definitions
   live on THAT abstractNum, not on 28 itself. Jelle wants numbering only
   through Heading2 ("1.5. Titel"), not cascading into Heading3/4
   ("1.5.1.1. Titel") -- set ilvl=2/3 (Heading3/Heading4) to numFmt="none"
   with an empty lvlText, the standard OOXML way to keep a level in the
   hierarchy (so a later Heading2 still resets correctly) while showing no
   number for it. Left Heading3/4's own w:numPr in styles.xml untouched --
   the fix belongs at the numbering-definition level, not duplicated at
   every consumer.
8. Callout, Callout Title, Callout Tight and Callout Gap did not exist -- no
   template has them, because they are not Word's or pandoc's idea, they are
   this repo's: docx/lua/a4-work/callouts.lua tags an Obsidian callout's
   paragraphs with them via `custom-style`, and Word draws the box from
   their shading + left border. They carry the accent-blue box that fix 5
   took off BlockText, in the same colours as the PDF's wdocallout tcolorbox
   (00B0EA / EAF6FC), so a callout still reads as one system across formats
   while a plain quote no longer poses as one.
   All three box styles MUST keep identical indents and border, because Word
   draws shading and border per paragraph at that paragraph's own indent: a
   row sitting further right tears a white notch out of the box.
9. SourceCode and VerbatimChar did not exist either, and pandoc names them
   for every fenced code block and every inline `code` span -- so code came
   out in the body font, including the per-line Code inlines the callout
   filter emits to keep a fenced block inside the box.
"""
import argparse
import sys
import zipfile

DEFAULT_SRC = "/home/jelle/Drive/Downloads/WDODelta rapport staand_stripped.docx"
DEFAULT_DST = "/home/jelle/Code/justscripts/layouts/docx/a4-work-reference.docx"

# --- The styles pandoc (and this repo's callout filter) name but no Word
# template defines. Kept as module-level constants, in OOXML child order per
# CT_PPrBase (pBdr, shd, spacing, ind -- see fix 6), so the exact same strings
# are available to anything that has to re-apply them to an already-derived
# reference document when the corporate source is not at hand.

# Callout box geometry, shared by every box style below. Word draws shading and
# border per paragraph, at that paragraph's own indent -- so these MUST agree,
# or the box tears open at any row that sits further right (which is also why
# the filter flattens a callout's lists to text bullets instead of leaving them
# as Word list paragraphs, whose indent comes from the numbering definition and
# outranks any paragraph style).
CALLOUT_BORDER = '<w:pBdr><w:left w:val="single" w:sz="18" w:space="10" w:color="00B0EA"/></w:pBdr>'
CALLOUT_SHADING = '<w:shd w:val="clear" w:color="auto" w:fill="EAF6FC"/>'
CALLOUT_INDENT = '<w:ind w:firstLine="0" w:left="480" w:right="120"/>'

CALLOUT_STYLES = (
    # Body paragraphs of the box.
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Callout">'
    '<w:name w:val="Callout"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
    '<w:qFormat/><w:pPr>'
    + CALLOUT_BORDER + CALLOUT_SHADING
    + '<w:spacing w:after="100" w:before="100"/>' + CALLOUT_INDENT +
    '</w:pPr></w:style>'
    # The callout's own title line: bold, house blue, kept with the body it
    # introduces so a page break cannot leave the title stranded.
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutTitle">'
    '<w:name w:val="Callout Title"/><w:basedOn w:val="Callout"/><w:next w:val="Callout"/>'
    '<w:qFormat/><w:pPr><w:keepNext/>'
    + CALLOUT_BORDER + CALLOUT_SHADING
    + '<w:spacing w:after="40" w:before="140"/>' + CALLOUT_INDENT +
    '</w:pPr><w:rPr><w:b/><w:color w:val="075895"/></w:rPr></w:style>'
    # Rows that belong to a run inside the box -- list items and code lines.
    # Same box, tighter spacing, so a flattened list does not read as a stack
    # of separate paragraphs.
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutTight">'
    '<w:name w:val="Callout Tight"/><w:basedOn w:val="Callout"/><w:next w:val="Callout"/>'
    '<w:qFormat/><w:pPr>'
    + CALLOUT_BORDER + CALLOUT_SHADING
    + '<w:spacing w:after="20" w:before="20"/>' + CALLOUT_INDENT +
    '</w:pPr></w:style>'
    # Spacer between two callouts that touch: no shading and a 4pt line, so
    # they read as two boxes instead of shading into one with two titles.
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="CalloutGap">'
    '<w:name w:val="Callout Gap"/><w:basedOn w:val="Normal"/><w:next w:val="BodyText"/>'
    '<w:qFormat/>'
    '<w:pPr><w:spacing w:after="0" w:before="0" w:line="120" w:lineRule="exact"/></w:pPr>'
    '<w:rPr><w:sz w:val="8"/><w:szCs w:val="8"/></w:rPr></w:style>'
)

# Fenced code blocks (SourceCode) and inline code / the callout filter's
# per-line Code inlines (VerbatimChar). Consolas with a Courier New fallback:
# both ship with Office, and the source template names neither.
CODE_STYLES = (
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="SourceCode">'
    '<w:name w:val="Source Code"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
    '<w:qFormat/><w:pPr><w:spacing w:after="20" w:before="20"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Courier New"/>'
    '<w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>'
    '<w:style w:type="character" w:customStyle="1" w:styleId="VerbatimChar">'
    '<w:name w:val="Verbatim Char"/><w:basedOn w:val="DefaultParagraphFont"/>'
    '<w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Courier New"/>'
    '<w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>'
)

# BlockText is pandoc's style for an ordinary blockquote's paragraphs. Plain
# indented quote, deliberately NOT the callout box: a marker-less "> quote"
# gets the same restrained treatment in the PDF path.
BLOCKTEXT_STYLE = (
    '<w:style w:type="paragraph" w:styleId="BlockText">'
    '<w:name w:val="Block Text"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
    '<w:uiPriority w:val="9"/><w:unhideWhenUsed/><w:qFormat/>'
    '<w:pPr><w:spacing w:after="100" w:before="100"/>'
    '<w:ind w:firstLine="0" w:left="480" w:right="480"/></w:pPr></w:style>'
)

MISSING_STYLES = (
    '<w:style w:type="paragraph" w:customStyle="1" w:styleId="Compact">'
    '<w:name w:val="Compact"/><w:basedOn w:val="BodyText"/><w:qFormat/>'
    '<w:pPr><w:spacing w:after="36" w:before="36"/></w:pPr></w:style>'
    + BLOCKTEXT_STYLE
    + '<w:style w:type="paragraph" w:customStyle="1" w:styleId="FirstParagraph">'
    '<w:name w:val="First Paragraph"/><w:basedOn w:val="BodyText"/><w:next w:val="BodyText"/>'
    '<w:qFormat/></w:style>'
    + CALLOUT_STYLES
    + CODE_STYLES
)


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

    # --- 2. Add the styles pandoc names but no Word template defines:
    # Compact/BlockText/FirstParagraph (step 2), the callout box styles
    # (step 8) and the code styles (step 9). Step 6's element order is
    # folded in directly -- there's no reason to land it wrong first. ---
    marker = '</w:style><w:style w:type="paragraph" w:styleId="Heading1"'
    assert marker in styles, "Heading1 marker not found verbatim -- source template changed?"
    styles = styles.replace(
        marker,
        "</w:style>" + MISSING_STYLES + '<w:style w:type="paragraph" w:styleId="Heading1"',
        1,
    )

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

    # --- 7. Stop numbering at Heading2: blank out ilvl=2/3 (Heading3/4) on
    # the abstractNum the "WDODHoofdstukken" numStyleLink actually points
    # at (abstractNumId=2, not the 28 that Heading1-4's own numPr names --
    # see docstring). ---
    numbering = contents["word/numbering.xml"].decode("utf-8")

    old_lvl2 = (
        '<w:lvl w:ilvl="2"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
        '<w:pStyle w:val="Heading3"/><w:suff w:val="space"/>'
        '<w:lvlText w:val="%1.%2.%3."/>'
    )
    assert old_lvl2 in numbering, "abstractNum ilvl=2 (Heading3) not found verbatim -- source template changed?"
    new_lvl2 = old_lvl2.replace('w:numFmt w:val="decimal"', 'w:numFmt w:val="none"').replace(
        'w:lvlText w:val="%1.%2.%3."', 'w:lvlText w:val=""'
    )
    numbering = numbering.replace(old_lvl2, new_lvl2)

    old_lvl3 = (
        '<w:lvl w:ilvl="3"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
        '<w:pStyle w:val="Heading4"/><w:suff w:val="space"/>'
        '<w:lvlText w:val="%1.%2.%3.%4."/>'
    )
    assert old_lvl3 in numbering, "abstractNum ilvl=3 (Heading4) not found verbatim -- source template changed?"
    new_lvl3 = old_lvl3.replace('w:numFmt w:val="decimal"', 'w:numFmt w:val="none"').replace(
        'w:lvlText w:val="%1.%2.%3.%4."', 'w:lvlText w:val=""'
    )
    numbering = numbering.replace(old_lvl3, new_lvl3)

    contents["word/styles.xml"] = styles.encode("utf-8")
    contents["word/document.xml"] = document.encode("utf-8")
    contents["word/numbering.xml"] = numbering.encode("utf-8")

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

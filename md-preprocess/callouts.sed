# callouts.sed — GLOBAL raw-text preprocessing, applied to every layout by both
# 2pdf.sh and 2docx.sh. It lives in md-preprocess/ rather than inside one of the
# layout directories because the transform is about MARKDOWN, not about the
# output format: an Obsidian callout is just as broken in a .docx as in a .pdf.
#
# Pandoc has no notion of Obsidian's callout syntax. A source block like
#
#     > [!danger] Dit is de interne versie
#     > Dit document bevat ...
#
# renders as an ordinary blockquote in which "[!danger]" survives as literal
# body text and the callout title runs on into the first paragraph. On a
# 60-page Boox read that noise repeats at every callout.
#
# The fix keeps the blockquote — it reads well on e-ink, indented and visually
# distinct — and rewrites the marker line into an invisible HTML-comment tag,
# followed by the callout's own title (when present) as a bold title line:
#
#     > <!-- callout:danger -->
#     > **Dit is de interne versie**
#     >
#     > Dit document bevat ...
#
# The HTML comment is the machine-readable seam: pandoc's latex and docx writers
# both drop raw HTML, so layouts without extra machinery print nothing for it,
# while a Lua filter can match it and restyle the whole blockquote as a real
# callout box — pdf-layouts/lua/a4-work/callouts.lua does that for the PDF
# (a tcolorbox), docx-layouts/lua/callouts.lua for the DOCX (Word paragraph
# styles with shading and an accent bar). The callout TYPE is never
# printed as text — it is a markup label, not a word (Jelle, 2026-07-30).
# Untitled callouts therefore emit only the comment line; the old fallback
# that printed the capitalised type ("> [!warning]" -> "**Warning**") is gone.
#
# The empty quoted line matters: without it pandoc folds the title into the
# first body paragraph, so the bold title runs on inline instead of standing
# on its own line the way Obsidian shows it.
#
# This is GLOBAL rather than layout-scoped because callouts render badly in
# all four layouts (boox-delight, boox, a4-personal, a4-work). Layout-scoped
# rules live in md-preprocess/<layout>/*.sed — the same split the Lua filters
# already use (lua/*.lua global, lua/<layout>/*.lua scoped).
#
# Must run BEFORE pandoc parses, not as a post-parse Lua filter: at AST level
# the marker has already been absorbed into the first paragraph's inlines,
# mixed in with the title text, and there is no reliable seam left to cut on.

# Titled callout, any nesting depth, optional fold marker (-/+):
#   "> [!info] Titel"   -> "> <!-- callout:info -->" + "> **Titel**" + "> "
#   "> > [!tip]- Titel" -> same, one quote level deeper
s/^([[:space:]]*(>[[:space:]]*)+)\[!([A-Za-z]+)\][-+]?[[:space:]]+(.+)$/\1<!-- callout:\L\3\E -->\n\1**\4**\n\1/

# Untitled callout — only the invisible tag; the type is a markup label and
# is never printed ("> [!warning]" -> "> <!-- callout:warning -->").
s/^([[:space:]]*(>[[:space:]]*)+)\[!([A-Za-z]+)\][-+]?[[:space:]]*$/\1<!-- callout:\L\3\E -->\n\1/

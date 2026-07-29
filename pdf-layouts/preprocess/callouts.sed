# callouts.sed — GLOBAL raw-text preprocessing, applied to every layout.
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
# distinct — and turns the marker line into a bold title line instead:
#
#     > **Dit is de interne versie**
#     >
#     > Dit document bevat ...
#
# The empty quoted line matters: without it pandoc folds the title into the
# first body paragraph, so the bold title runs on inline instead of standing
# on its own line the way Obsidian shows it.
#
# This is GLOBAL rather than layout-scoped because callouts render badly in
# all four layouts (boox-delight, boox, a4-personal, a4-work). Layout-scoped
# rules live in preprocess/<layout>/*.sed — the same split the Lua filters
# already use (lua/*.lua global, lua/<layout>/*.lua scoped).
#
# Must run BEFORE pandoc parses, not as a post-parse Lua filter: at AST level
# the marker has already been absorbed into the first paragraph's inlines,
# mixed in with the title text, and there is no reliable seam left to cut on.

# Titled callout, any nesting depth, optional fold marker (-/+):
#   "> [!info] Titel"      -> "> **Titel**"
#   "> > [!tip]- Titel"    -> "> > **Titel**"
s/^([[:space:]]*(>[[:space:]]*)+)\[!([A-Za-z]+)\][-+]?[[:space:]]+(.+)$/\1**\4**\n\1/

# Untitled callout — no title text to promote, so fall back to the callout
# type itself with its first letter capitalised ("> [!warning]" -> "> **Warning**").
# Rare in practice; better than leaving "[!warning]" in the body.
s/^([[:space:]]*(>[[:space:]]*)+)\[!([A-Za-z]+)\][-+]?[[:space:]]*$/\1**\u\3**\n\1/

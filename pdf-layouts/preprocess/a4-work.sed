# a4-work.sed — raw-text preprocessing for the a4-work layout, run via
# `sed -E -f` over the markdown SOURCE, before pandoc parses it.
#
# a4-work is Jelle's "share with other people" layout (WDODelta colleagues,
# management) — unlike the personal layouts (boox-delight, boox, a4-personal),
# it must not leak Obsidian's internal markup or Jelle's private Hopsakee
# Decimal (HD) filing-system numbers into a document someone outside the
# vault reads. Personal layouts have no file here, so they render untouched.
#
# Must run BEFORE pandoc parses the text, not as a post-parse Lua filter:
# once one bracket layer of an Obsidian "[[@name]]" mention is gone, pandoc's
# citation extension partially consumes the remainder into a Cite AST node,
# which is much harder to clean up correctly than the raw text ever was.

# Obsidian pipe-alias wikilink: [[target|display]] -> keep only the display text.
s/\[\[[^]|]*\|([^]]*)\]\]/\1/g

# Plain Obsidian wikilink: [[target]] -> keep only the target text.
s/\[\[([^]]*)\]\]/\1/g

# Hopsakee Decimal numbers, e.g. "_d5.43.36", "_d0.02" — Jelle's personal
# filing-system codes, not meaningful to an external reader. Requires a
# literal "d" immediately followed by digits and at least one ".NN" group,
# so normal prose ("domein", "Datalab") never matches.
s/_?d[0-9]{1,2}(\.[0-9]{1,3}){1,3}//g

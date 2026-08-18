-- docx-callouts.lua — a4-work scoped, DOCX output only.
--
-- Mirrors the two-tier model sibling callouts.lua already established for
-- PDF: a real Obsidian [!type] callout gets a distinct box; an ordinary
-- blockquote (no marker) is left alone. Word forces list items to the
-- built-in "Compact"/"ListParagraph" style no matter what surrounding
-- Div/custom-style wraps them (confirmed empirically: wrapping a BulletList
-- or its items in a custom-style Div has zero effect on the emitted pStyle
-- for docx) -- so a callout's own lead-in line picks up BlockText but any
-- nested list inside it does not, and the docx callout box visibly stops
-- after line one. Fix, for marked callouts only: flatten any nested list
-- into plain bulleted paragraphs (prefixed with a literal bullet/dash
-- glyph) so they become ordinary Para blocks -- which DO pick up the
-- wrapping custom-style Div correctly. Plain quotes keep pandoc's native
-- behaviour (first line gets BlockText, nested lists don't) rather than
-- being boxed as if they were callouts -- same scope Jelle's actual report
-- named ("de call-out", not "elke quote").
--
-- Known tradeoff: this trades away real Word list semantics for callout
-- content specifically -- no numbering field, no auto-renumbering, no
-- list-structure for screen readers, just a bullet/dash character in the
-- text. That's the width of the pandoc/Word limitation above: a real
-- numbered ListParagraph-with-border style is possible in principle (a
-- custom style referenced by both numPr and a bordered pPr) but pandoc's
-- docx writer hardcodes "Compact" for every list item regardless of any
-- AST-level override, so reaching it needs a post-generation XML rewrite,
-- not a Lua filter. Left as a callout-only, deliberately-scoped tradeoff
-- rather than a silent general one.
--
-- The marker regex is duplicated from callouts.lua rather than shared: that
-- file's BlockQuote is itself a pandoc filter entry point (a global
-- function), so dofile-ing it here would register its BlockQuote too and
-- collide with this file's own. Two lines of duplication beats that.
local MARKER = '<!%-%- callout:(%w+) %-%->'

local function marker_type(block)
  if block.t == 'RawBlock' and block.format == 'html' then
    return block.text:match(MARKER)
  end
  if block.t == 'Para' and #block.content >= 1 then
    local first = block.content[1]
    if first.t == 'RawInline' and first.format == 'html' then
      return first.text:match(MARKER)
    end
  end
  return nil
end

local function wrap(block)
  return pandoc.Div({block}, pandoc.Attr('', {}, {['custom-style'] = 'BlockText'}))
end

local function bullet_prefix(depth, ordered, n)
  local indent = string.rep('    ', depth)
  local glyph = ordered and (n .. '.') or (depth > 0 and '\u{2013}' or '\u{2022}')
  return indent .. glyph .. '\u{00A0}\u{00A0}'
end

local function flatten_list(list, depth)
  local out = {}
  local ordered = list.t == 'OrderedList'
  local n = ordered and (list.start or 1) or nil
  for _, item in ipairs(list.content) do
    for _, b in ipairs(item) do
      if b.t == 'Para' or b.t == 'Plain' then
        local inlines = {pandoc.Str(bullet_prefix(depth, ordered, n))}
        for _, inline in ipairs(b.content) do inlines[#inlines + 1] = inline end
        out[#out + 1] = pandoc.Para(inlines)
      elseif b.t == 'BulletList' or b.t == 'OrderedList' then
        for _, sub in ipairs(flatten_list(b, depth + 1)) do out[#out + 1] = sub end
      else
        out[#out + 1] = b
      end
    end
    if ordered then n = n + 1 end
  end
  return out
end

local function styleize(blocks)
  local out = {}
  for _, b in ipairs(blocks) do
    if b.t == 'BulletList' or b.t == 'OrderedList' then
      for _, p in ipairs(flatten_list(b, 0)) do out[#out + 1] = wrap(p) end
    elseif b.t == 'Para' or b.t == 'Plain' then
      out[#out + 1] = wrap(b)
    else
      out[#out + 1] = b
    end
  end
  return out
end

function BlockQuote(el)
  local blocks = el.content
  if #blocks == 0 or not marker_type(blocks[1]) then
    return nil -- ordinary blockquote: leave to pandoc's native handling
  end
  return pandoc.Div(styleize(blocks))
end

-- docx/lua/a4-work/callouts.lua — a4-work scoped, DOCX output only.
--
-- Mirrors the two-tier model sibling callouts.lua already established for
-- PDF: a real Obsidian [!type] callout gets a distinct box; an ordinary
-- blockquote (no marker) is left alone.
--
-- The box is drawn by four paragraph styles the reference document defines
-- (see build-a4-work-reference-docx.py, fix 8), which this filter attaches
-- with `custom-style`:
--
--     Callout        body paragraphs of the box
--     CalloutTitle   the callout's own title line (bold, house blue)
--     CalloutTight   rows of a run inside the box: list items, code lines
--     CalloutGap     spacer between two callouts that touch
--
-- Dedicated styles rather than reusing pandoc's BlockText, which was the
-- first approach here: BlockText is also what pandoc gives an ORDINARY
-- blockquote, so boxing it boxed every plain "> quote" as if it were a
-- callout -- the exact two-tier distinction the PDF path makes and the
-- comment above claims. Worse, Word has no concept of a callout ending: it
-- shades paragraph by paragraph, so a plain quote or a second callout
-- following the first shaded straight into the same box, and a page of
-- callouts came out as one giant blue block with several bold titles in it. Word forces list items to the
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
-- A CodeBlock inside a callout has the exact same problem -- pandoc's docx
-- writer hardcodes "SourceCode" for code-block paragraphs regardless of any
-- wrapping custom-style Div (confirmed empirically the same way as lists,
-- 2026-08-19), so it fell straight through the old `else out[#out+1]=b`
-- branch below unstyled, visibly breaking the callout box in the middle of
-- any callout that contained a fenced code block. Fix: same flattening
-- tactic as lists -- split into one Para-per-line, each line as a `Code`
-- inline (keeps the monospace VerbatimChar run style) so it becomes an
-- ordinary Para block that DOES pick up the wrap.
--
-- A Table inside a callout has the same underlying issue but NO equivalent
-- fix: tested wrapping the whole Table in a custom-style Div, setting
-- custom-style on every Cell, and setting it on the Table itself -- pandoc's
-- docx writer emits pStyle="Compact" / tblStyle="Table" regardless in all
-- three cases (2026-08-19). Unlike lists/code, there's no flatten-to-Para
-- escape hatch that preserves a table's actual structure; giving a table
-- the callout's border/shading would need a post-generation XML rewrite
-- (inject w:tcPr/w:shd per cell), which is out of scope for a Lua filter.
-- A table inside a callout is therefore left unstyled on purpose -- same
-- class of accepted, documented limitation as the list tradeoff above, not
-- an oversight.
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

local function styled(block, name)
  return pandoc.Div({block}, pandoc.Attr('', {}, {['custom-style'] = name}))
end

-- callouts.sed emits a titled callout's title as a paragraph holding nothing
-- but one Strong span, so that shape identifies the title line. An untitled
-- callout has no such paragraph and gets no title style.
local function is_title_para(block)
  if not block or block.t ~= 'Para' then return false end
  local seen_strong = false
  for _, inline in ipairs(block.content) do
    if inline.t == 'Strong' then
      if seen_strong then return false end
      seen_strong = true
    elseif inline.t ~= 'Space' and inline.t ~= 'SoftBreak' then
      return false
    end
  end
  return seen_strong
end

local function bullet_prefix(depth, ordered, n)
  local indent = string.rep('    ', depth)
  local glyph = ordered and (n .. '.') or (depth > 0 and '\u{2013}' or '\u{2022}')
  return indent .. glyph .. '\u{00A0}\u{00A0}'
end

-- Only the item's first Para/Plain gets a bullet/number glyph. A "loose"
-- list item can hold more than one paragraph (a continuation paragraph
-- under the same bullet); without this guard every one of them was getting
-- re-prefixed with the SAME glyph -- an ordered item with two paragraphs
-- rendered as "1. First\n1. Continuation" instead of "1. First" followed by
-- an indented continuation line.
local function continuation_indent(depth)
  return string.rep('    ', depth) .. '\u{00A0}\u{00A0}\u{00A0}'
end

local function flatten_list(list, depth)
  local out = {}
  local ordered = list.t == 'OrderedList'
  local n = ordered and (list.start or 1) or nil
  for _, item in ipairs(list.content) do
    local seen_para = false
    for _, b in ipairs(item) do
      if b.t == 'Para' or b.t == 'Plain' then
        local prefix = seen_para and continuation_indent(depth) or bullet_prefix(depth, ordered, n)
        seen_para = true
        local inlines = {pandoc.Str(prefix)}
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

-- One Para per source line, each rendered as a `Code` inline so it keeps
-- the monospace VerbatimChar run style pandoc already uses for inline code.
-- The trailing "\n" appended before gmatch makes an empty CodeBlock (and a
-- CodeBlock whose text doesn't end in a newline) both produce a clean final
-- line instead of gmatch silently dropping it.
local function flatten_codeblock(cb)
  local out = {}
  for line in (cb.text .. '\n'):gmatch('([^\n]*)\n') do
    out[#out + 1] = pandoc.Para({pandoc.Code(line)})
  end
  return out
end

-- Everything a callout contains has to come out as a paragraph carrying one of
-- the callout styles, because shading a paragraph is the only way Word can put
-- something inside the box. Block types Word styles from somewhere else are
-- therefore re-emitted rather than passed through: a Header would take a real
-- heading style, a standalone image its Figure/Image Caption styles, a nested
-- plain quote its BlockText indent -- each of them punching a white hole in the
-- middle of the box (and, for the heading, adding a callout's aside to the
-- document outline). Tables are the one exception, for the reason in the header
-- comment above: no paragraph style can reach a table's own tblStyle.
local function styleize(blocks)
  local out = {}
  local emit
  emit = function(b)
    if b.t == 'BulletList' or b.t == 'OrderedList' then
      for _, p in ipairs(flatten_list(b, 0)) do out[#out + 1] = styled(p, 'CalloutTight') end
    elseif b.t == 'CodeBlock' then
      for _, p in ipairs(flatten_codeblock(b)) do out[#out + 1] = styled(p, 'CalloutTight') end
    elseif b.t == 'Para' or b.t == 'Plain' then
      out[#out + 1] = styled(b, is_title_para(b) and 'CalloutTitle' or 'Callout')
    elseif b.t == 'Header' then
      -- A heading inside a callout titles the box, not the document.
      out[#out + 1] = styled(pandoc.Para(b.content), 'CalloutTitle')
    elseif b.t == 'Figure' then
      for _, inner in ipairs(b.content) do emit(inner) end
      if b.caption and b.caption.long then
        for _, inner in ipairs(b.caption.long) do emit(inner) end
      end
    elseif b.t == 'BlockQuote' then
      -- An ordinary quote nested in a callout. A nested CALLOUT is already a
      -- Div by the time we get here (pandoc walks children first) and takes the
      -- branch below, keeping its own styles.
      for _, inner in ipairs(b.content) do emit(inner) end
    else
      out[#out + 1] = b
    end
  end
  for _, b in ipairs(blocks) do emit(b) end
  return out
end

-- Class on the Div each callout is wrapped in, so the second pass below can
-- tell "end of one callout, start of the next" from "next paragraph of the same
-- callout" -- both are just adjacent Divs otherwise.
local CONTAINER_CLASS = 'callout'

local function callout_blockquote(el)
  local blocks = el.content
  if #blocks == 0 or not marker_type(blocks[1]) then
    return nil -- ordinary blockquote: leave to pandoc's native handling
  end
  return pandoc.Div(styleize(blocks), pandoc.Attr('', {CONTAINER_CLASS}, {}))
end

-- Word shades paragraph by paragraph and has no idea a callout ended, so two
-- callouts written back to back in the markdown shade into a single box with
-- two titles. A CalloutGap paragraph between them (4pt, unshaded) is the Word
-- equivalent of the gap Obsidian draws.
local function separate_touching_callouts(blocks)
  local out = pandoc.List()
  for i, block in ipairs(blocks) do
    local touching = i > 1
      and block.t == 'Div' and block.classes:includes(CONTAINER_CLASS)
      and blocks[i - 1].t == 'Div' and blocks[i - 1].classes:includes(CONTAINER_CLASS)
    if touching then
      -- A non-breaking space, not an empty paragraph: pandoc drops those.
      out:insert(styled(pandoc.Para({pandoc.Str('\u{00A0}')}), 'CalloutGap'))
    end
    out:insert(block)
  end
  return out
end

-- Two passes, in this order: rewrite the callouts, then separate the ones that
-- ended up touching. One pass cannot do both -- the gap belongs between whole
-- callouts, and inside a callout the very same kind of Divs sit side by side.
return {
  {BlockQuote = callout_blockquote},
  {Blocks = separate_touching_callouts},
}

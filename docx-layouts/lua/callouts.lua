-- callouts.lua — DOCX: render Obsidian callouts as real callout boxes instead
-- of a blockquote with literal "[!important]" text in it.
--
-- Global (applies to every docx layout), because callouts render badly in all
-- of them; per-layout filters would live in lua/<layout>/.
--
-- Upstream seam: md-preprocess/callouts.sed (shared with 2pdf.sh) rewrites
-- every Obsidian callout marker line ("> [!important]" / "> [!info] Titel")
-- into an invisible HTML comment as the first line of the blockquote:
--
--     > <!-- callout:important -->
--     > **Titel**            (only when the callout had its own title)
--     >
--     > body ...
--
-- This filter matches that comment, drops it, and re-emits the blockquote as
-- Divs carrying `custom-style` attributes. Pandoc's docx writer turns those
-- into Word paragraph styles, which docx-layouts/<layout>.docx defines with
-- background shading and a left accent bar — the same look the PDF gets from
-- the `wdocallout` tcolorbox in pdf-layouts/a4-work.tex:
--
--     CalloutTitle   the callout's own title line (bold, house blue)
--     Callout        every body paragraph
--     CalloutList    list rows inside the callout
--     CalloutGap     a hairline spacer between two callouts that touch
--
-- Blockquotes WITHOUT the comment (ordinary quotes) pass through untouched —
-- the box is for callouts only.
--
-- Why the type is not printed: like the PDF layout, one sober box serves every
-- callout type ("beperk het aantal huisstijlkleuren per scherm"), and the type
-- is a markup label, not a word (Jelle, 2026-07-30). It is captured here so a
-- per-type variant has an obvious place to hook in.
--
-- WHY A CALLOUT'S LISTS ARE FLATTENED (the one lossy step in here)
-- In Word, a box like this is not an object: it is background shading plus a
-- left border repeated on every paragraph, and Word draws both at the
-- paragraph's own indent. A real Word list takes its indent from the numbering
-- definition, not from the paragraph style, so list rows sit further right than
-- the rest of the callout — the shading then starts a centimetre in and the
-- accent bar breaks off, leaving white notches in the middle of the box (worse
-- in LibreOffice, which ignores the style indent for numbered paragraphs
-- entirely). Style indents cannot win that argument, so list items inside a
-- callout become ordinary callout paragraphs that carry their bullet or number
-- as text, all at one indent. The box stays a box, the text stays editable, and
-- the cost is that those rows are no longer a Word list object with automatic
-- renumbering. Lists OUTSIDE callouts are untouched real Word lists.

local MARKER = '<!%-%- callout:(%w+) %-%->'

-- Bullet glyph per nesting depth, mirroring Word's own bullet sequence.
local BULLETS = { '\u{2022}', '\u{25E6}', '\u{25AA}' }
-- One depth step, as two em spaces. Indentation has to live in the text: giving
-- deeper rows a larger style indent would move the shading and the accent bar
-- with them and break the box open again.
local DEPTH_STEP = '\u{2003}\u{2003}'

local function styled(blocks, name)
  return pandoc.Div(blocks, pandoc.Attr('', {}, { { 'custom-style', name } }))
end

local function marker_type(block)
  -- A comment alone on its own quoted line usually parses as RawBlock(html);
  -- cover the RawInline-inside-Para shape too, to be robust across pandoc
  -- versions and edge inputs.
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

-- The sed seam emits a titled callout's title as a paragraph holding nothing
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

local function marker_for(list, index, depth)
  if list.t == 'OrderedList' then
    local start = 1
    if list.listAttributes and list.listAttributes.start then
      start = list.listAttributes.start
    end
    return tostring(start + index - 1) .. '.'
  end
  -- Deeper than the glyph list goes, the sequence repeats, the way Word's own
  -- bullet levels cycle.
  return BULLETS[(depth % #BULLETS) + 1]
end

local flatten_list

-- One list item -> callout paragraphs. The first paragraph gets the bullet or
-- number, later paragraphs of the same item get the indent only, so they line
-- up under their sibling text.
local function flatten_item(item, marker, depth, out)
  local first = true
  for _, block in ipairs(item) do
    if block.t == 'Para' or block.t == 'Plain' then
      local inlines = pandoc.List(block.content)
      local prefix = string.rep(DEPTH_STEP, depth)
      if first then
        inlines:insert(1, pandoc.Str(prefix .. marker))
        inlines:insert(2, pandoc.Space())
        first = false
      else
        inlines:insert(1, pandoc.Str(prefix .. DEPTH_STEP))
      end
      out:insert(pandoc.Para(inlines))
    elseif block.t == 'BulletList' or block.t == 'OrderedList' then
      flatten_list(block, depth + 1, out)
    else
      -- Anything else (code block, nested callout Div, table): keep as-is.
      out:insert(block)
    end
  end
end

flatten_list = function(list, depth, out)
  for i, item in ipairs(list.content) do
    flatten_item(item, marker_for(list, i, depth), depth, out)
  end
end

-- A fenced code block inside a callout would come out as pandoc's SourceCode
-- style — unshaded, so it punches a hole in the box. Re-emitted as one callout
-- paragraph of inline code with hard line breaks: same monospace text, same
-- line structure, but inside the shading.
local function code_paragraph(block)
  local inlines = pandoc.List()
  local first = true
  for line in (block.text .. '\n'):gmatch('([^\n]*)\n') do
    if not first then inlines:insert(pandoc.LineBreak()) end
    inlines:insert(pandoc.Code(line))
    first = false
  end
  -- Trailing blank line from the final newline: drop it.
  if #inlines >= 2 and inlines[#inlines].text == '' then
    inlines:remove(#inlines)
    inlines:remove(#inlines)
  end
  return pandoc.Para(inlines)
end

-- Class on the container each callout is wrapped in. Word has no concept of a
-- callout ending: it just shades paragraphs, so two callouts written back to
-- back in the markdown would shade into one box with two titles. The second
-- pass below finds containers that touch and puts a hairline spacer paragraph
-- between them, which is the Word equivalent of the gap Obsidian draws.
local CONTAINER_CLASS = 'callout'

local function callout(blocks)
  return pandoc.Div(blocks, pandoc.Attr('', { CONTAINER_CLASS }, {}))
end

local function is_callout(block)
  return block.t == 'Div' and block.classes:includes(CONTAINER_CLASS)
end

local function gap()
  -- A styled paragraph rather than an empty one: pandoc drops empty paragraphs,
  -- and the CalloutGap style is a few points tall so the gap stays tight.
  return styled({ pandoc.Para({ pandoc.Str('\u{00A0}') }) }, 'CalloutGap')
end

local function separate_touching_callouts(blocks)
  local out = pandoc.List()
  for i, block in ipairs(blocks) do
    if i > 1 and is_callout(block) and is_callout(blocks[i - 1]) then
      out:insert(gap())
    end
    out:insert(block)
  end
  return out
end

local function callout_blockquote(el)
  local blocks = el.content
  if #blocks == 0 then return nil end
  local ctype = marker_type(blocks[1])
  if not ctype then return nil end -- ordinary blockquote: leave alone

  local rest = pandoc.List()

  -- If the marker sat inline in a Para with trailing content, keep the rest.
  if blocks[1].t == 'Para' and #blocks[1].content > 1 then
    local inlines = {}
    for i = 2, #blocks[1].content do inlines[#inlines + 1] = blocks[1].content[i] end
    while inlines[1] and (inlines[1].t == 'Space' or inlines[1].t == 'SoftBreak') do
      table.remove(inlines, 1)
    end
    if #inlines > 0 then rest:insert(pandoc.Para(inlines)) end
  end

  for i = 2, #blocks do rest:insert(blocks[i]) end

  local out = pandoc.List()
  local start = 1
  if is_title_para(rest[1]) then
    out:insert(styled({ rest[1] }, 'CalloutTitle'))
    start = 2
  end

  -- Body paragraphs and flattened list rows are collected separately so each
  -- run of them can be wrapped in the style that fits, and consecutive runs
  -- still share one continuous box.
  local body = pandoc.List()
  local rows = pandoc.List()

  local function flush_rows()
    if #rows > 0 then
      out:insert(styled(rows, 'CalloutList'))
      rows = pandoc.List()
    end
  end
  local function flush_body()
    if #body > 0 then
      out:insert(styled(body, 'Callout'))
      body = pandoc.List()
    end
  end

  -- Everything a callout can contain has to end up as a paragraph carrying one
  -- of the callout styles, because shading a paragraph is the only way Word can
  -- put something inside the box. Blocks that Word styles from somewhere else
  -- (a figure, a heading, a nested quote) are therefore re-emitted as callout
  -- paragraphs instead of being handed over as-is, which would leave a white
  -- hole in the middle of the box. Tables are the exception: a Word table takes
  -- its look from a table style, out of reach of a paragraph style, so a table
  -- inside a callout does break the box.
  local emit
  emit = function(block)
    local t = block.t
    if t == 'BulletList' or t == 'OrderedList' then
      flush_body()
      flatten_list(block, 0, rows)
    elseif t == 'CodeBlock' then
      flush_rows()
      body:insert(code_paragraph(block))
    elseif t == 'Header' then
      -- A heading inside a callout is a heading of the box, not of the
      -- document, so it becomes a title line rather than an outline entry.
      flush_rows()
      flush_body()
      out:insert(styled({ pandoc.Para(block.content) }, 'CalloutTitle'))
    elseif t == 'Figure' then
      -- pandoc wraps a standalone image in a Figure, whose paragraphs Word
      -- styles as Figure/Image Caption; unwrap it so image and caption stay in.
      flush_rows()
      for _, inner in ipairs(block.content) do body:insert(inner) end
      if block.caption and block.caption.long then
        for _, inner in ipairs(block.caption.long) do body:insert(inner) end
      end
    elseif t == 'BlockQuote' then
      -- An ordinary quote nested inside a callout (a nested CALLOUT is already
      -- a Div by now, and passes through the branch below). Its extra indent
      -- cannot survive — that is what would tear the box — so keep the text.
      for _, inner in ipairs(block.content) do emit(inner) end
    else
      flush_rows()
      body:insert(block)
    end
  end

  for i = start, #rest do emit(rest[i]) end
  flush_rows()
  flush_body()

  return callout(out)
end

-- Two passes, in order: rewrite the callouts, then separate the ones that ended
-- up touching. One pass cannot do both — the gap belongs between whole
-- callouts, and inside a callout the very same Divs sit next to each other.
return {
  { BlockQuote = callout_blockquote },
  { Blocks = separate_touching_callouts },
}

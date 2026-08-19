-- callouts.lua — a4-work scoped: render Obsidian callouts as real callout
-- boxes instead of plain blockquotes.
--
-- Upstream seam: md-preprocess/callouts.sed (global, shared with 2docx.sh)
-- rewrites every Obsidian
-- callout marker line ("> [!important]" / "> [!info] Titel") into an
-- invisible HTML comment as the first line of the blockquote:
--
--     > <!-- callout:important -->
--     > **Titel**            (only when the callout had its own title)
--     >
--     > body ...
--
-- This filter matches that comment, drops it, and wraps the remaining
-- blockquote content in the `wdocallout` tcolorbox environment defined in
-- a4-work.tex. Blockquotes WITHOUT the comment (ordinary quotes) pass
-- through untouched — the box is for callouts only.
--
-- The captured type (important/warning/info/...) is currently unused: the
-- a4-work layout deliberately uses ONE sober huisstijl box style for all
-- types ("beperk het aantal huisstijlkleuren"). Per-type colours would hook
-- in here if ever wanted.

local MARKER = '<!%-%- callout:(%w+) %-%->'

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

function BlockQuote(el)
  local blocks = el.content
  if #blocks == 0 then return nil end
  local ctype = marker_type(blocks[1])
  if not ctype then return nil end -- ordinary blockquote: leave alone

  local out = pandoc.List()
  out:insert(pandoc.RawBlock('latex', '\\begin{wdocallout}'))

  -- If the marker sat inline in a Para with trailing content, keep the rest.
  if blocks[1].t == 'Para' and #blocks[1].content > 1 then
    local rest = {}
    for i = 2, #blocks[1].content do rest[#rest + 1] = blocks[1].content[i] end
    while rest[1] and (rest[1].t == 'Space' or rest[1].t == 'SoftBreak') do
      table.remove(rest, 1)
    end
    if #rest > 0 then out:insert(pandoc.Para(rest)) end
  end

  for i = 2, #blocks do out:insert(blocks[i]) end
  out:insert(pandoc.RawBlock('latex', '\\end{wdocallout}'))
  return out
end

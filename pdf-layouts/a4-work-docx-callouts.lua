-- Word forces list items to the built-in "Compact"/"ListParagraph" style no
-- matter what surrounding Div/custom-style wraps them (confirmed empirically:
-- wrapping a BulletList or its items in a custom-style Div has zero effect on
-- the emitted pStyle for docx). So a callout's own lead-in line gets styled
-- but any nested list inside it does not -- the docx callout box then visibly
-- stops after line one. Fix: inside a BlockQuote, flatten any nested list
-- into plain bulleted paragraphs (prefixed with a literal bullet/dash glyph)
-- so they become ordinary Para blocks -- which DO pick up the wrapping
-- custom-style Div correctly.

local function bullet_prefix(depth, ordered, n)
  local indent = string.rep('    ', depth)
  if ordered then
    return indent .. n .. '.\u{00A0}\u{00A0}'
  elseif depth > 0 then
    return indent .. '\u{2013}\u{00A0}\u{00A0}'  -- en dash for nested level
  else
    return indent .. '\u{2022}\u{00A0}\u{00A0}'  -- bullet for top level
  end
end

local function flatten_list(list, depth)
  local out = {}
  local ordered = list.t == 'OrderedList'
  local n = ordered and (list.start or 1) or nil
  for _, item in ipairs(list.content) do
    for _, b in ipairs(item) do
      if b.t == 'Para' or b.t == 'Plain' then
        local prefix = pandoc.Str(bullet_prefix(depth, ordered, n))
        local inlines = {prefix}
        for _, inline in ipairs(b.content) do inlines[#inlines+1] = inline end
        out[#out+1] = pandoc.Para(inlines)
      elseif b.t == 'BulletList' or b.t == 'OrderedList' then
        for _, sub in ipairs(flatten_list(b, depth + 1)) do out[#out+1] = sub end
      else
        out[#out+1] = b
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
      for _, p in ipairs(flatten_list(b, 0)) do
        out[#out+1] = pandoc.Div({p}, pandoc.Attr('', {}, {['custom-style']='BlockText'}))
      end
    elseif b.t == 'Para' or b.t == 'Plain' then
      out[#out+1] = pandoc.Div({b}, pandoc.Attr('', {}, {['custom-style']='BlockText'}))
    else
      out[#out+1] = b
    end
  end
  return out
end

function BlockQuote(el)
  return pandoc.Div(styleize(el.content))
end

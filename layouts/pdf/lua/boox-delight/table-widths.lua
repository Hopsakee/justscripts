-- table-widths.lua
-- Rebalances pandoc table column widths from content shape, fixing the classic
-- pandoc-pipe-table failure where a short header label (e.g. "As") collapses
-- a column to ~7% of text width while bold content labels ("Datatype",
-- "Tooltype", "Reversibility") overflow into the next column.
--
-- Heuristic per column:
--   1. longest_word_i  = max length of any whitespace-delimited token
--      (an unbreakable unit LaTeX cannot hyphenate without help)
--   2. content_chars_i = total character count across all cells
--   3. min_width_i     = (longest_word_i + 2) / CHARS_PER_LINE  -- breathing room
--   4. raw_share_i     = content_chars_i / sum(content_chars)
--   5. width_i = max(min_width_i, raw_share_i)
--   6. if sum > 1.0, scale; if sum < 1.0, distribute surplus by raw_share
--
-- This guarantees that each column is wide enough to fit its longest single
-- token (so bold labels don't overrun), while still proportional to content.
--
-- Skipped when widths are already set (any column with width > 0).
--
-- Wide-table rotation (added 2026-05-19):
--   When the pre-normalize sum of widths exceeds 1.0 — meaning even with the
--   longest-word floors the table demands more than full portrait page width —
--   OR when column count meets ROTATE_COLS_THRESHOLD, the filter wraps the
--   Table in \begin{landscape}...\end{landscape} (pdflscape) so the rendered
--   page rotates 90° and the columns get the wider landscape canvas. The
--   width rebalance still runs inside the landscape wrap; relative widths
--   stay valid because they're proportions, not absolute lengths. Requires
--   the sibling boox-delight.tex preamble to load \usepackage{pdflscape}.

local CHARS_PER_LINE         = 60   -- approx chars per A5 line at 9.5pt; tweak if needed
local FLOOR_CHARS            = 4    -- absolute minimum column width in chars
local ROTATE_COLS_THRESHOLD  = 4    -- tables with ≥ N columns auto-rotate to landscape
local stringify              = pandoc.utils.stringify

local function cell_text(cell)
  if type(cell) ~= "table" then return tostring(cell or "") end
  if cell.contents then return stringify(cell.contents) end
  return stringify(cell)
end

local function longest_word(text)
  local m = 0
  for word in text:gmatch("%S+") do
    if #word > m then m = #word end
  end
  return m
end

local function collect_rows(tbl)
  local rows = {}
  if tbl.head and tbl.head.rows then
    for _, r in ipairs(tbl.head.rows) do table.insert(rows, r) end
  end
  for _, body in ipairs(tbl.bodies or {}) do
    for _, r in ipairs(body.body or {}) do table.insert(rows, r) end
    for _, r in ipairs(body.head or {}) do table.insert(rows, r) end
  end
  if tbl.foot and tbl.foot.rows then
    for _, r in ipairs(tbl.foot.rows) do table.insert(rows, r) end
  end
  return rows
end

local function measure_column(rows, col_idx)
  local content_chars = 0
  local max_word_len  = 0
  for _, row in ipairs(rows) do
    local cells = row.cells or row
    local c = cells[col_idx]
    if c then
      local s  = cell_text(c)
      content_chars = content_chars + #s
      local lw = longest_word(s)
      if lw > max_word_len then max_word_len = lw end
    end
  end
  if max_word_len < FLOOR_CHARS then max_word_len = FLOOR_CHARS end
  return content_chars, max_word_len
end

function Table(tbl)
  local colspecs = tbl.colspecs
  if not colspecs or #colspecs == 0 then return nil end
  -- NOTE: we deliberately rewrite widths even when pandoc has already computed
  -- them from the pipe-table separator dashes — pandoc's heuristic is exactly
  -- what causes the "Datatype/Tooltype" overflow this filter exists to fix.

  local rows = collect_rows(tbl)
  local n = #colspecs

  -- 1. measure
  local content   = {}
  local min_width = {}
  local total_content = 0
  for i = 1, n do
    local cc, mw = measure_column(rows, i)
    content[i] = cc
    min_width[i] = (mw + 2) / CHARS_PER_LINE   -- +2 chars breathing room
    total_content = total_content + cc
  end
  -- Zero-content table → no signal to act on; leave pandoc's choices alone.
  if total_content == 0 then return nil end

  -- 2. raw share by content, floored at min_width
  local widths = {}
  local sum_widths = 0
  for i = 1, n do
    local raw = content[i] / total_content
    widths[i] = (raw > min_width[i]) and raw or min_width[i]
    sum_widths = sum_widths + widths[i]
  end

  -- 2b. wide-table decision (BEFORE renormalize, so sum_widths still reflects
  -- the true content+floor demand). Wide = either many columns OR the floored
  -- demand already exceeds portrait page width.
  local is_wide = (n >= ROTATE_COLS_THRESHOLD) or (sum_widths > 1.0)

  -- 3. renormalize so total = 1.0
  if sum_widths >= 1.0 then
    -- over-budget: scale proportionally
    for i = 1, n do widths[i] = widths[i] / sum_widths end
  else
    -- under-budget: distribute surplus by raw content share
    local surplus = 1.0 - sum_widths
    for i = 1, n do
      widths[i] = widths[i] + surplus * (content[i] / total_content)
    end
  end

  -- 4. write back
  for i, spec in ipairs(colspecs) do
    spec[2] = widths[i]
  end
  tbl.colspecs = colspecs

  -- 5. wrap in landscape env if wide. Returning a Blocks list replaces the
  -- single Table node with three nodes in document order.
  if is_wide then
    return {
      pandoc.RawBlock("latex", "\\begin{landscape}"),
      tbl,
      pandoc.RawBlock("latex", "\\end{landscape}"),
    }
  end
  return tbl
end

-- Builds one editable Aseprite file of a footman facing from frame PNGs.
-- Run by tools/anim/build_footman.py --aseprite <exe>:
--   aseprite -b --script-param list=<manifest.txt> --script-param out=<file.aseprite> --script footman_aseprite.lua
-- The manifest's first line is "<cell width> <cell height> <soldiers>"; every
-- other line is "<tag>|<ms>|<png soldier 1>|...|<png soldier n>", one per frame.
-- Each soldier gets a layer and a cell of his own, side by side; frames keep
-- their tag (idle, walk, strike, death) and duration.

local list = app.params["list"]
local out = app.params["out"]
local rows = {}
local cw, ch, n
for line in io.lines(list) do
  if cw == nil then
    local a, b, c = line:match("^(%d+) (%d+) (%d+)$")
    cw, ch, n = tonumber(a), tonumber(b), tonumber(c)
  else
    local parts = {}
    for p in (line .. "|"):gmatch("(.-)|") do parts[#parts + 1] = p end
    rows[#rows + 1] = { tag = parts[1], ms = tonumber(parts[2]), files = { table.unpack(parts, 3) } }
  end
end

local spr = Sprite(cw * n, ch, ColorMode.RGB)
local layers = { spr.layers[1] }
layers[1].name = "soldier 1"
for s = 2, n do
  local l = spr:newLayer()
  l.name = "soldier " .. s
  layers[s] = l
end

local ranges, order = {}, {}
for i, row in ipairs(rows) do
  local frame = (i == 1) and spr.frames[1] or spr:newEmptyFrame()
  frame.duration = row.ms / 1000
  for s = 1, n do
    spr:newCel(layers[s], frame, Image{ fromFile = row.files[s] }, Point((s - 1) * cw, 0))
  end
  local r = ranges[row.tag]
  if r == nil then
    ranges[row.tag] = { from = i, to = i }
    order[#order + 1] = row.tag
  else
    r.to = i
  end
end
for _, name in ipairs(order) do
  local tag = spr:newTag(ranges[name].from, ranges[name].to)
  tag.name = name
end
spr:saveAs(out)
print("saved " .. out .. " (" .. #rows .. " frames, " .. n .. " soldiers)")

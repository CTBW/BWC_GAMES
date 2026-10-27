-- Cleans cut frames in Aseprite's batch mode: removes what the generator left
-- floating beside a figure, keeps everything attached to it.
--   aseprite -b --script-param list=<files.txt> --script tools/anim/ase_cleanup.lua
-- files.txt: one "<png path>|<flags>" per line; flag "arrows" also drops a
-- loosed arrow drawn in flight (the game shoots its own).
-- Rules, per detached piece (8-connected, not the largest piece = the figure):
--   * 4 px or less, 2 px or more away                  -> speck, removed
--   * under 80 px and nearly colourless (saturation < 0.15) -> ghost blade or a
--     neighbour's steel sliver, removed
--   * "arrows": 100 px or more and 5 px or more away     -> loosed arrow, removed
-- Coloured parts close to the figure (a tail tip, spikes, a dropped tool) stay.
-- Prints one line per changed file: "<path> <removed px>".

local list = app.params["list"]
local function sat(c)
  local r, g, b = app.pixelColor.rgbaR(c) / 255, app.pixelColor.rgbaG(c) / 255, app.pixelColor.rgbaB(c) / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local l = (mx + mn) / 2
  local d = mx - mn
  if d == 0 then return 0 end
  if l <= 0.5 then return d / (mx + mn) end
  return d / (2 - mx - mn)
end

local function clean(path, flags)
  local spr = app.open(path)
  if not spr then return end
  local img = spr.cels[1].image
  local w, h = img.width, img.height
  local alpha, label = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      alpha[y * w + x] = app.pixelColor.rgbaA(img:getPixel(x, y)) > 0
    end
  end
  -- Label the pieces.
  local pieces, n = {}, 0
  for i = 0, w * h - 1 do
    if alpha[i] and not label[i] then
      n = n + 1
      local stack, px = { i }, {}
      label[i] = n
      while #stack > 0 do
        local j = table.remove(stack)
        px[#px + 1] = j
        local x, y = j % w, j // w
        for dy = -1, 1 do
          for dx = -1, 1 do
            local nx, ny = x + dx, y + dy
            if nx >= 0 and ny >= 0 and nx < w and ny < h then
              local k = ny * w + nx
              if alpha[k] and not label[k] then
                label[k] = n
                stack[#stack + 1] = k
              end
            end
          end
        end
      end
      pieces[n] = px
    end
  end
  if n <= 1 then spr:close() return end
  local main = 1
  for k = 2, n do if #pieces[k] > #pieces[main] then main = k end end
  local function gap(px)
    -- Chebyshev distance from the piece to the figure, up to 9.
    local best = 9
    for _, j in ipairs(px) do
      local x, y = j % w, j // w
      for r = 1, best - 1 do
        local hit = false
        for dy = -r, r do
          for dx = -r, r do
            if math.max(math.abs(dx), math.abs(dy)) == r then
              local nx, ny = x + dx, y + dy
              if nx >= 0 and ny >= 0 and nx < w and ny < h and label[ny * w + nx] == main then hit = true break end
            end
          end
          if hit then break end
        end
        if hit then best = r break end
      end
      if best == 1 then break end
    end
    return best
  end
  local removed = 0
  local arrows = flags:find("arrows") ~= nil
  for k = 1, n do
    if k ~= main then
      local px = pieces[k]
      local s = #px
      local g = gap(px)
      local ms = 0
      for _, j in ipairs(px) do ms = ms + sat(img:getPixel(j % w, j // w)) end
      ms = ms / s
      local drop = (s <= 4 and g >= 2) or (s < 80 and ms < 0.15) or (arrows and s >= 100 and g >= 5)
      if drop then
        for _, j in ipairs(px) do img:drawPixel(j % w, j // w, app.pixelColor.rgba(0, 0, 0, 0)) end
        removed = removed + s
      end
    end
  end
  if removed > 0 then
    spr:saveAs(path)
    print(path .. " " .. removed)
  end
  spr:close()
end

for line in io.lines(list) do
  local path, flags = line:match("^(.-)|(.*)$")
  if path then clean(path, flags) end
end

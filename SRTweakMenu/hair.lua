-- The native barber functions operate on the local player's customization
-- record even when the character creator document is closed.
local G = require("game")
local labels = require("data.hair_labels")
local H = {}
local restore

local function record(p)
  if p ~= 0 and G.player() == p then return wml.read_u32(p + 0x13B0) end
end

local function current(p, area)
  local owner = record(p)
  if not owner or owner == 0 then return end
  local _, id, primary, secondary = G.vint(("tweak_out(pcr_get_hair_info(%d))"):format(area))
  if id == -2 then
    -- The getter uses -2 for both an empty slot and an unlisted item.
    local slot = wml.read_u32(0x00E8D270 + area * 4)
    if (wml.callx(0x007C21B0, { eax = owner, edx = slot }, wml.buffer(15)) & 0xFF) ~= 0 then return end
    id = -1
  end
  if type(id) ~= "number" or type(primary) ~= "number" or type(secondary) ~= "number" then return end
  return { id = id, primary = primary, secondary = secondary }
end

local function options(area)
  local _, count = G.vint(([[
    local report = rawget(_G, "pcr_report_hair_items")
    if report then
      local list, n = {}, 0
      rawset(_G, "TWK_hair_item", function(id, crc, label)
        n = n + 1
        list[n] = { id, crc, label }
      end)
      report(%d, "TWK_hair_item")
      rawset(_G, "TWK_hair_item", nil)
      rawset(_G, "TWK_hair_list", list)
      tweak_out(n)
    end
  ]]):format(area))
  if not count then return end
  local entries = { { -1, "None" } }
  -- The host returns at most 128 values per bridge call.
  for first = 1, count, 40 do
    local batch = table.pack(G.vint(([[
      local list = rawget(_G, "TWK_hair_list")
      for i = %d, %d do tweak_out(list[i][1], list[i][2], list[i][3]) end
    ]]):format(first, math.min(first + 39, count))))
    for i = 2, batch.n, 3 do
      local id, crc, label = batch[i], batch[i + 1], batch[i + 2]
      if type(id) == "number" then
        label = label or (crc and labels[crc & 0xFFFFFFFF]) or ("Style " .. (id + 1))
        entries[#entries + 1] = { id, label }
      end
    end
  end
  G.vint('rawset(_G, "TWK_hair_list", nil)')
  if #entries > 1 then return entries end
end

local function ready()
  local _, done = G.vint("tweak_out(pcu_is_streaming_done())")
  return done == true
end

local function put(area, style)
  local _, applied = G.vint(("pcr_change_hair(%d, %d, %d, %d) tweak_out(true)")
    :format(area, style.id, style.primary, style.secondary))
  return applied == true
end

function H.update(p)
  if not restore then return end
  if p ~= restore.p or record(p) ~= restore.owner or wml.read_u32(p + 0x44) ~= restore.actor then
    restore = nil
  elseif ready() and put(restore.area, restore.style) then
    restore = nil
  end
end

function H.page(F, p, area, title)
  if not G.playing(p) then return "Can't preview hair right now" end
  if restore then return "Wait for the previous style to finish restoring" end
  local owner = record(p)
  local actor = wml.read_u32(p + 0x44)
  local function same() return G.player() == p and wml.read_u32(p + 0x44) == actor and record(p) == owner end
  local kept = current(p, area)
  if not kept or (kept.id >= 0 and kept.primary < 0) then
    return "Couldn't read the current hair style and colors"
  end
  -- The barber treats an absent secondary swatch as palette entry zero.
  if kept.id >= 0 then kept.secondary = math.max(0, kept.secondary) end
  local entries = options(area)
  if not entries then return "No hair catalog available" end
  local color = kept.id >= 0 and kept or current(p, (area == 1 or area == 2) and 2 or 0)
  local primary = color and math.max(0, color.primary) or 0
  local secondary = color and math.max(0, color.secondary) or primary
  local rows, cursor = {}, 1
  local wanted, submitted = kept.id, kept.id
  local closed = false

  local function preview()
    if closed or wanted == submitted or not same() or not G.playing(p) or not ready() then return end
    if put(area, { id = wanted, primary = primary, secondary = secondary }) then submitted = wanted end
  end
  local function accept()
    preview()
    if wanted ~= submitted or not ready() then return "Wait for the style to finish loading" end
    if not same() or not G.playing(p) then return "Can't apply hair right now" end
    local worn = current(p, area)
    if not worn or worn.id ~= wanted then return "Couldn't apply this style" end
    if worn.id >= 0 then worn.secondary = math.max(0, worn.secondary) end
    kept = worn
  end
  for i, entry in ipairs(entries) do
    if entry[1] == kept.id then cursor = i end
    local function choose()
      wanted = entry[1]
      preview()
    end
    rows[i] = { label = entry[2], kind = "action",
      help = "Up and Down preview. Accept keeps this style. Back offers Save Changes.",
      hover = choose,
      run = function()
        choose()
        return accept() or "Style applied"
      end }
  end
  local function update()
    if not closed then preview() end
  end
  F.hair_preview = update
  return { title = title, rows = rows, cursor = cursor,
    dirty = function() return wanted ~= kept.id or submitted ~= kept.id end,
    accept = accept,
    back = function()
      closed = true
      if F.hair_preview == update then F.hair_preview = nil end
      if submitted ~= kept.id and same() then
        restore = { p = p, owner = owner, actor = actor, area = area, style = kept }
        H.update(p)
      end
    end }
end

return H

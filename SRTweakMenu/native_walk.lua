-- The stock walk-style catalog owns genuine persistent walk overrides.
-- Preview only the resolved clip: pcr_preview_anim belongs to the stock editor.
local G = require("game")
local W = {}
-- Stock customizable_walk.xtbl; checked against the live native state IDs.
local STATES = {
  "walk",
  "custom walk female 2",
  "custom walk female 1",
  "custom walk female 3",
  "custom walk female 4",
  "custom walk female 5",
  "custom walk female 6",
  "custom walk female 7",
  "custom walk male 1",
  "custom walk male 2",
  "custom walk male 5",
  "custom walk male 6",
  "custom walk extra 7",
  "custom walk extra 8",
  "custom walk extra 10",
  "custom walk extra 1",
  "custom walk extra 2",
  "custom walk extra 3",
  "custom walk extra 4",
  "custom walk extra 5",
  "custom walk extra 6",
  "custom walk extra 9",
  "custom walk male 4",
  "custom walk male 3",
}

local function state_id(name)
  return wml.callx(0x006EF510, {}, wml.buffer(14, name))
end

local function catalog()
  local _, count = G.vint([[
    local list, count = {}, 0
    rawset(_G, "TWK_walk_add", function(label, id, current)
      count = count + 1
      list[count] = { label or false, id, current == true }
    end)
    pcr_report_anims("walk_style", "TWK_walk_add")
    rawset(_G, "TWK_walk_add", nil)
    rawset(_G, "TWK_walk_list", list)
    tweak_out(count)
  ]])
  if type(count) ~= "number" then return {} end
  local entries = {}
  for first = 1, count, 40 do
    local values = table.pack(G.vint(([[
      local list = rawget(_G, "TWK_walk_list")
      for i = %d, %d do tweak_out(list[i][1], list[i][2], list[i][3]) end
    ]]):format(first, math.min(first + 39, count))))
    for i = 2, values.n, 3 do
      local label, id, current = values[i], values[i + 1], values[i + 2]
      if type(id) == "number" and id >= 0 and id % 1 == 0 then
        entries[#entries + 1] = { label = label, id = id, current = current == true }
      end
    end
  end
  G.vint('rawset(_G, "TWK_walk_list", nil)')
  return entries
end

-- Keep walk style (Customize > Movement): the last stock style applied here
-- is remembered in saved_presets.lua and put back when the game has dropped
-- the player to the default walk (a new model, a load). It only ever acts
-- on the default walk, so a walk the game itself switched to is left alone.
local presets = require("presets")
local function remember(name)
  local all = presets.all()
  if all.walk ~= name then
    all.walk = name
    presets.write()
  end
end
function W.kept() return presets.all().walk end
function W.keep(p, tick)
  local wanted = presets.all().walk
  if type(wanted) ~= "string" or tick % 120 ~= 0 then return end
  if p == 0 or G.player() ~= p or not G.playing(p) or wml.read_u32(p + 0x18D4) ~= 0
    or wml.read_u32(0x00E8D308) == 1 then return end
  local default, target = state_id("walk"), state_id(wanted)
  if default == 0xFFFFFFFF or target == 0xFFFFFFFF or target == default
    or wml.read_u32(p + 0x1138) ~= default then return end
  local table_ptr, count = wml.read_u32(0x025274D4), wml.read_u32(0x025274D8)
  if table_ptr == 0 or count == 0 or count > 256 then return end
  for _, entry in ipairs(catalog()) do
    if entry.id < count and wml.read_u32(table_ptr + entry.id * 12 + 8) == target then
      G.vint(('pcr_set_anim("walk_style", %d)'):format(entry.id))
      wml.log("walk style kept: " .. wanted .. (wml.read_u32(p + 0x1138) == target and "" or " (didn't take)"))
      return
    end
  end
end

function W.page(p, previews)
  if p == 0 or not G.playing(p) then return "Walk styles need a player on foot" end
  local actor = wml.read_u32(p + 0x44)
  local table_ptr, count = wml.read_u32(0x025274D4), wml.read_u32(0x025274D8)
  if table_ptr == 0 or count == 0 or count > 256 then return "The walk-style catalog is not ready" end
  local names = {}
  for _, name in ipairs(STATES) do
    local id = state_id(name)
    if id ~= 0xFFFFFFFF then names[id] = name end
  end
  local function valid()
    return G.player() == p and G.playing(p) and wml.read_u32(p + 0x44) == actor
      and wml.read_u32(p + 0x18D4) == 0
  end
  local rows, cursor = {}, 1
  local default = state_id("walk")
  if default ~= 0xFFFFFFFF then
    rows[1] = { label = "Default", kind = "action", preview_clip = function() return "State", "walk" end,
      help = "Preview in place. Accept restores your default walking style.",
      run = function()
        if not valid() then return "Can't change walk style right now" end
        local ok = G.lua('character_set_walk_variant(LOCAL_PLAYER, "default")')
        if not ok or wml.read_u32(p + 0x1138) ~= default then return "Couldn't restore the default walk" end
        remember(false)
        return "Walk: Default"
      end }
  end
  for _, entry in ipairs(catalog()) do
    if entry.id < count then
      local state = wml.read_u32(table_ptr + entry.id * 12 + 8)
      local name = names[state]
      -- The native table, not inferred animation names, authorizes the override.
      if name then
        if entry.current then cursor = #rows + 1 end
        rows[#rows + 1] = { label = type(entry.label) == "string" and entry.label or name, kind = "action",
          preview_clip = function() return "State", name end,
          help = "Preview in place. Accept applies this stock walking style.",
          run = function()
            if not valid() then return "Can't change walk style right now" end
            if wml.read_u32(0x00E8D308) == 1 then return "Close the character editor before applying a walk style" end
            if wml.read_u32(0x025274D4) ~= table_ptr or wml.read_u32(0x025274D8) ~= count
              or wml.read_u32(table_ptr + entry.id * 12 + 8) ~= state then return "The walk-style catalog changed; reopen this page" end
            local ok = G.vint(('pcr_set_anim("walk_style", %d)'):format(entry.id))
            if not ok or wml.read_u32(p + 0x1138) ~= state then return "Couldn't apply this walk style" end
            remember(name)
            return "Walk: " .. (type(entry.label) == "string" and entry.label or name)
          end }
      end
    end
  end
  if #rows == 0 then return "No stock walking styles are available" end
  if previews then
    rows[#rows + 1] = { label = "Other Walk Previews", kind = "page",
      help = "Browse additional clips without changing your walking behavior.",
      open = function() return { title = "Other Walk Previews", rows = { previews } } end }
  end
  return { title = "Walk Style", rows = rows, cursor = cursor }
end

return W

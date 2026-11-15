-- SR Tweak Menu (Saints Row 2) - jumping, swimming, how cars ride, and paint.
-- The jump height is the game's own multiplier (the one its Low Gravity
-- cheat uses); cars are changed on their live Havok vehicle (springs,
-- dampers), so cars already on the road change too; paint goes through the
-- calls the paint shop's live preview makes. Addresses and conventions were
-- read in the game's code; every value is put back when a row goes off.

local G = require("game")
local read_u8, read_u32, read_f32 = wml.read_u8, wml.read_u32, wml.read_f32
local write_f32 = wml.write_f32

local P = {}
local F

-- ---------------------------------------------------------------- jumping and swimming
local JUMP = 0x027A6A58   -- f32: jump height x this (0 = the game's own 0.85 m); zeroed on every load
local SWIM = 0x00EB7D3C   -- f32: fast swimming speed, m/s (4.5)
local jump_written = false
local swim_own

local function jump_frame()
  local j = 1.0
  if F.enabled then
    j = (F.items.jump_height.v or 0.85) / 0.85
    if F.items.jump.v then j = j * (F.items.jump_boost.v or 1) end
  end
  if math.abs(j - 1.0) > 1e-3 then write_f32(JUMP, j); jump_written = true
  elseif jump_written then
    jump_written = false
    if not F.on("low_gravity") then write_f32(JUMP, 0) end   -- (the cheat keeps its own)
  end
end

-- ---------------------------------------------------------------- cars on the road
-- Every live car: its Havok vehicle instance (veh+0x53C, cars only).
local function each_car(fn)
  for i = 0, 0xFFF do
    local o = read_u32(0x02149C64 + i * 16)
    if o ~= 0 and read_u32(o + 0x4C) == 5 and (read_u32(o + 0x44) & 0xFFF) == i and read_u8(o + 0x84D8) == 1 then
      local inst = read_u32(o + 0x53C)
      if inst ~= 0 then fn(o, inst) end
    end
  end
end
-- Kept values per key: address -> original float.
local kept = {}
local function scale(key, addr, factor)
  local k = kept[key] or {}
  kept[key] = k
  if k[addr] == nil then k[addr] = read_f32(addr) end
  write_f32(addr, k[addr] * factor)
end
local function restore(key)
  for addr, v in pairs(kept[key] or {}) do pcall(write_f32, addr, v) end
  kept[key] = nil
end
-- Bouncy: the springs' damping cut, so the road throws cars up.
local function bounce(inst, k)
  local S = read_u32(inst + 0x34); if S == 0 then return end
  local arr, n = read_u32(S + 0x14), read_u32(S + 0x18)
  if arr == 0 or n > 16 then return end
  for i = 0, n - 1 do
    local e = arr + i * 12
    scale("bouncy_cars", e + 4, k); scale("bouncy_cars", e + 8, k)
  end
end
-- Less stiff: spin damping (normal, in collisions) and the chassis' angular damping.
local function spin(inst, k)
  local D = read_u32(inst + 0x44)
  if D ~= 0 then scale("soft_spin", D + 0x08, k); scale("soft_spin", D + 0x0C, k) end
  local C = read_u32(inst + 0x18)
  if C ~= 0 then scale("soft_spin", C + 0x188, k) end
end

-- ---------------------------------------------------------------- paint
local PAINT_SLOT, PAINT_COLOUR, PAINT_INSTALL, PAINT_SET = 0x00ACA360, 0x00AC9F40, 0x00AC7AE0, 0x00AC7C60
local function vehicle(p)
  local h = G.vehicle_handle(p)
  if not h then return nil end
  local veh = read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if veh == 0 or read_u32(veh + 0x44) ~= h then return nil end
  return veh
end
-- The component the model paints `slot_name` ("Body Color1" primary, "Body Color2" secondary) with.
local function paint_component(veh, slot_name)
  local info = read_u32(veh + 0x84E4)
  if info == 0 or read_u8(info + 0x7C) ~= 1 then return nil end
  local T = read_u32(info + 0x78)
  if T == 0 then return nil end
  local st = wml.callx(PAINT_SLOT, { ecx = wml.buffer(11, slot_name) })
  if st == 0 then return nil end
  local n, arr = read_u32(T), read_u32(T + 4)
  if n > 200 then return nil end
  for i = 0, n - 1 do
    if read_u32(arr + i * 16) == st then return read_u32(arr + i * 16 + 8) end
  end
end
local function paint(p, slot_name, colour)
  local veh = vehicle(p)
  if not veh then return "Get in a vehicle first" end
  if read_u8(veh + 0x84D8) ~= 1 then return "Only cars can be painted" end
  local inst = read_u32(veh + 0x84D4)
  local comp = paint_component(veh, slot_name)
  if inst == 0 or not comp or read_u8(comp + 0x10) == 0 then return "This vehicle can't take that colour" end
  local col = wml.callx(PAINT_COLOUR, { eax = wml.buffer(12, colour) })
  if col == 0 then return "The game doesn't know " .. colour end
  wml.call(PAINT_INSTALL, inst, comp, 0)
  wml.call(PAINT_SET, inst, comp, 0, col)
end

-- ---------------------------------------------------------------- car customization
-- The live editor fits parts directly on the current vehicle.
local VEHICLE_CUSTOMIZE = require("vehicle_customize")

-- ---------------------------------------------------------------- rows
function P.setup(features)
  F = features
  local fmtx = F.fmtx

  F.add_rows("Player", nil, {
    { id = "jump", label = "High jump", kind = "toggle", needs = "none", v = wml.setting("high_jump", false),
      help = "Jump higher. Set the height below." },
    { id = "jump_boost", label = "High jump boost", kind = "value", needs = "none", default = 1.0, min = 1, max = 10, step = 0.5, fmt = fmtx,
      oneshot = true, v = wml.setting("jump_multiplier", 4.0), help = "How many times higher High jump takes you." },
    { id = "jump_height", label = "Game jump height", kind = "value", needs = "none", default = 0.85, min = 0.2, max = 6, step = 0.05,
      fmt = function(v) return string.format("%.2f m", v) end, oneshot = true,
      help = "The game's own jump height (0.85 m)." },
    { id = "swim_speed", label = "Swim speed", kind = "value", needs = "none", default = 4.5, min = 1, max = 40, step = 0.5,
      fmt = function(v) return string.format("%.1f", v) end,
      help = "How fast you swim when you swim fast (game: 4.5).",
      update = function(ctx, p, v, it) swim_own = swim_own or read_f32(SWIM); write_f32(SWIM, it.v) end,
      off = function() if swim_own then write_f32(SWIM, swim_own); swim_own = nil end end },
  })

  F.add_rows("Vehicles", nil, {
    { id = "bouncy_cars", label = "Bouncy cars", kind = "toggle", needs = "none", v = wml.setting("bouncy_cars", false),
      help = "Every car on the road bounces along like it's on springs. Experimental.",
      update = function()
        if F.tick % 30 ~= 0 then return end
        local k = 4 / (F.items.bounce_strength.v or 25)
        each_car(function(veh, inst) bounce(inst, k) end)
      end,
      off = function() restore("bouncy_cars") end },
    { id = "bounce_strength", label = "Bounce strength", kind = "value", needs = "none", default = 25, min = 5, max = 60, step = 5,
      fmt = F.fmtint, oneshot = true, hidden = function() return not F.items.bouncy_cars.v end,
      help = "How hard the road throws cars up (from the next time a car is reached: switch Bouncy cars off and on to redo them).",
      change = function() restore("bouncy_cars") end },
    { id = "soft_spin", label = "Less stiff cars", kind = "toggle", needs = "none", v = wml.setting("less_stiff_cars", false),
      help = "Cars turn, slide and spin more freely: their spin damping is cut. Experimental.",
      update = function()
        if F.tick % 30 ~= 0 then return end
        local k = F.items.spin_damping.v or 0.5
        each_car(function(veh, inst) spin(inst, k) end)
      end,
      off = function() restore("soft_spin") end },
    { id = "spin_damping", label = "Spin damping", kind = "value", needs = "none", default = 0.5, min = 0.1, max = 0.9, step = 0.1,
      fmt = fmtx, oneshot = true, hidden = function() return not F.items.soft_spin.v end,
      help = "How much of the game's spin damping cars keep (0.5 = half).",
      change = function() restore("soft_spin") end },
  })

  local COLOURS = F.data("vehicle_colors")
  local colour_items = {}
  for _, c in ipairs(COLOURS) do colour_items[#colour_items + 1] = { c[1], c[1] } end
  F.add_rows("Vehicles", nil, {
    { id = "vehicle_custom", label = "Customize Vehicle", kind = "page", needs = "vehicle",
      help = "Preview and fit parts on your parked vehicle. Use the sticks or I/J/K/L to orbit and the triggers or Z/X to zoom.",
      open = function(ctx, p) return VEHICLE_CUSTOMIZE.page(F, p) end },
    { id = "vehicle_presets", label = "Vehicle Presets", kind = "page", needs = "vehicle",
      help = "Save this vehicle's parts and paint in a slot, and fit them again on any vehicle of the same model.",
      open = function(ctx, p) return VEHICLE_CUSTOMIZE.presets_page(p) end },
    { id = "paint", label = "Paint vehicle", kind = "list", needs = "vehicle", items = colour_items, nosave = true,
      help = "Left/Right to choose (Shift: 10 at a time), Enter to apply.",
      run = function(ctx, p, v, it) return paint(p, "Body Color1", it.items[it.v][1]) or ("Painted " .. it.items[it.v][2]) end },
    { id = "paint2", label = "Secondary color", kind = "list", needs = "vehicle", items = colour_items, nosave = true,
      help = "Left/Right to choose (Shift: 10 at a time), Enter to apply.",
      run = function(ctx, p, v, it) return paint(p, "Body Color2", it.items[it.v][1]) or ("Secondary: " .. it.items[it.v][2]) end },
  })
end

function P.after_update(p) jump_frame() end

return P

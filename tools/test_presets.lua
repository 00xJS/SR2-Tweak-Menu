-- From the repo root: build/lua.exe tools/test_presets.lua
-- Saved looks and vehicle presets against a fake game: save, change, load,
-- and read the file back as a fresh start would.
package.path = "SRTweakMenu/?.lua"
local scratch = (os.getenv("TEMP") or ".") .. "\\sr2_tweak_menu_test"
os.execute('mkdir "' .. scratch .. '" 2>nul')
os.remove(scratch .. "\\saved_presets.lua")

local mem = {}
local function rd(a, n) local v = 0 for i = n - 1, 0, -1 do v = (v << 8) | (mem[a + i] or 0) end return v end
local function wr(a, n, v) for i = 0, n - 1 do mem[a + i] = v & 0xFF; v = v >> 8 end end
local function wide(a, text) for i = 1, #text do wr(a + (i - 1) * 2, 2, text:byte(i)) end wr(a + #text * 2, 2, 0) end

-- The character: morphs by set, skin, hair by area, voice.
local SETS = { nose = { "bridge width", "nose depth" }, jaw = { 7 } }
local morphs = { ["global gender/body gender"] = 0.2, ["global body/body fat"] = 0.4, ["global body/body muscle"] = 0.6,
  ["global body/old"] = 0.1, ["nose/bridge width"] = 0.3, ["nose/nose depth"] = 0.7, ["jaw/7"] = 0.5 }
local skin, voice, listed = 2, 1, {}
local hair = { [0] = { 4, 1, 2 }, { -2, -1, -1 }, { 3, 5, 5 }, { -2, -1, -1 }, { 1, 0, 0 } }
local buffers = {}
-- What each customization slot wears: { item, variant, colours, c0, c1, c2, wear, logo, logo colour }.
local worn = { [8] = { 3, 1, 2, 4, 5, -1, 0, -1, -1 }, [14] = { 7, 0, 0, -1, -1, -1, 1, -1, -1 }, [50] = { 9, 0, 0, -1, -1, -1, 0, -1, -1 } }
local ITEM_NAMES = { [3] = "coat_leather", [7] = "shoes_sneaker", [9] = "tattoo_tribal", [11] = "coat_leather" }

-- The car: two part slots and a paint slot; fitted[slot address] = component.
local P, CAR, INFO, INST, CAT, ARR, POOL = 0x10000000, 0x20000000, 0x21000000, 0x22000000, 0x23000000, 0x23001000, 0x30000000
local fitted, paint = {}, {}
local function slot(i, name, components, count, kind_flag)
  local a, kind = ARR + i * 16, 0x24000000 + i * 0x100
  wr(a, 4, kind); wr(a + 8, 4, components); wr(a + 0xC, 1, count)
  wr(kind, 4, kind + 0x40); wide(kind + 0x40, name); wr(kind + 8, 4, kind_flag)
  for c = 0, count - 1 do wr(components + c * 0x38 + 0x34, 1, 2); wr(components + c * 0x38 + 0x10, 1, kind_flag) end
  return a
end
local function car(bumpers)
  mem, fitted, paint = {}, {}, {}
  wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, P)
  wr(P + 0x44, 4, 0xAAAA); wr(P + 0x13B0, 4, 0x11000000); wr(P + 0xD74, 4, 0x1234)
  wr(0x02149C64 + 0x234 * 16, 4, CAR)
  wr(CAR + 0x44, 4, 0x1234); wr(CAR + 0x4C, 4, 5); wr(CAR + 0x84D8, 1, 1)
  wr(CAR + 0x84D4, 4, INST); wr(CAR + 0x84E4, 4, INFO)
  wr(INFO + 0x7C, 1, 1); wr(INFO + 0x78, 4, CAT); wr(CAT, 4, 3); wr(CAT + 4, 4, ARR)
  wr(0x0252A084, 4, POOL)
  -- the item table: 12 items, item i's name at 0x50000000 + i * 0x100
  wr(0x025288D8, 4, 12)
  for i = 0, 11 do wr(0x029E8CD0 + i * 0x78 + 8, 4, 0x50000000 + i * 0x100) end
  return { slot(0, "Front Bumper", 0x25000000, bumpers, 0), slot(1, "Spoiler", 0x26000000, 2, 0),
    slot(2, "Body Color1", 0x27000000, 1, 1) }
end

wml = {
  mod_folder = scratch, log = function() end,
  read_u8 = function(a) return rd(a, 1) end, read_u16 = function(a) return rd(a, 2) end,
  read_u32 = function(a) return rd(a, 4) end,
  buffer = function(n, text) buffers[n] = text return 0x7F000000 + n end,
  script = function() return true end,
  call = function(a, inst, component, index, record)
    if a == 0x00AC7AE0 then
      for _, s in ipairs({ ARR, ARR + 16, ARR + 32 }) do
        local base = rd(s + 8, 4)
        if component >= base and component < base + rd(s + 0xC, 1) * 0x38 then fitted[s] = component end
      end
    elseif a == 0x00AC7C60 then paint[component .. ":" .. index] = record end
    return 0
  end,
  callx = function(a, regs, _, component)
    if a == 0x00AC8080 then return fitted[regs.edx] or 0 end
    if a == 0x00AC80B0 then return paint[regs.esi .. ":" .. regs.edx] or POOL end
    if a == 0x00AC7DF0 then for s, c in pairs(fitted) do if c == component then fitted[s] = nil end end return 0 end
    if a == 0x006EF510 then return ({ walk = 50, ["custom walk male 1"] = 61 })[buffers[14]] or 0xFFFFFFFF end
    if a == 0x00AC9F40 then
      for i, c in ipairs(require("data.vehicle_colors")) do
        if c[1] == buffers[12] then return POOL + (i - 1) * 28 end
      end
      return 0
    end
    return 0
  end,
  read_string = function(a) return ITEM_NAMES[(a - 0x50000000) // 0x100] or "" end,
  vint = function(code)
    if code:find("pcu_is_streaming_done", 1, true) then return true, true end
    if code:find("for s = 6, 72 do", 1, true) then
      local out = {}
      for s = 6, 72 do
        local w = worn[s]
        if w then out[#out + 1] = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", s, w[1], w[2], w[3], w[4], w[5], w[6], w[7], w[8], w[9]) end
      end
      return true, #out, table.concat(out, ";")
    end
    if code:find("pcu_remove_clothing()", 1, true) then
      for s in pairs(worn) do if s < 44 then worn[s] = nil end end
      return true, true
    end
    local q = code:match("^tweak_out%(pcu_get_slot_info%((%d+)%)%)$")
    if q then
      local w = worn[tonumber(q)]
      if not w then return true, -1 end
      return true, tonumber(q), w[1]
    end
    local args = code:match("^pcu_set_slot_info%(([^)]*)%)")
    if args then
      local t = {}
      for v in args:gmatch("[^,%s]+") do t[#t + 1] = v end
      local function n(v) return v == "nil" and -1 or tonumber(v) end
      worn[tonumber(t[1])] = { n(t[2]), n(t[3]), n(t[4]), n(t[5]), n(t[6]), n(t[7]), n(t[8]), n(t[9]), n(t[10]) }
      return true, true
    end
    if code:find("pcr_report_anims", 1, true) then return true, 2 end
    if code:find("tweak_out(list[i][1], list[i][2], list[i][3])", 1, true) then return true, "Plain", 0, false, "Swagger", 1, false end
    local walk = code:match('^pcr_set_anim%("walk_style", (%d+)%)$')
    if walk then wr(P + 0x1138, 4, rd(0x40000000 + tonumber(walk) * 12 + 8, 4)) return true end
    local set = code:match('pcr_report_avail_morphs%("([^"]+)"')
    if set then listed = SETS[set] or {} return true, #listed end
    set = code:match('tweak_out%(list%[i%], pcr_get_morph_value%("([^"]+)"')
    if set then
      local out = {}
      for _, id in ipairs(listed) do out[#out + 1] = id out[#out + 1] = morphs[set .. "/" .. id] end
      return true, table.unpack(out)
    end
    local s, id = code:match('^tweak_out%(pcr_get_morph_value%("([^"]+)", "?([^")]+)"?%)%)$')
    if s then return true, morphs[s .. "/" .. id] end
    local value
    s, id, value = code:match('^pcr_apply_morph_value%("([^"]+)", "?([^",]+)"?, ([%d.]+)%)$')
    if s then morphs[s .. "/" .. id] = tonumber(value) return true end
    if code:find("pcr_report_skin_colors", 1, true) then return true, 3 end
    if code:find("tweak_out(row[1], row[2], row[3], row[4])", 1, true) then
      return true, 0, false, "A", skin == 0, 1, false, "B", skin == 1, 2, false, "C", skin == 2
    end
    id = code:match("^pcr_change_skin_color%((%d+)%)$")
    if id then skin = tonumber(id) return true end
    local area = code:match("pcr_get_hair_info%((%d+)%)")
    if area then return true, table.unpack(hair[tonumber(area)]) end
    local a, b, c, d = code:match("^pcr_change_hair%((%d+), (%-?%d+), (%d+), (%d+)%)")
    if a then hair[tonumber(a)] = { tonumber(b), tonumber(c), tonumber(d) } return true, true end
    if code:find("pcr_get_current_voice_number", 1, true) then return true, voice end
    local name = code:match('^pcr_set_voice%("([^"]+)", false%)$')
    if name then voice = ({ MALE_WHITE = 0, MALE_BLACK = 1, MALE_LATINO = 2, FEMALE_WHITE = 3 })[name] return true end
    return true
  end,
}

local function row(page, label)
  for _, r in ipairs(page.rows) do if r.label == label then return r end end
end
local function reload()
  for _, name in ipairs({ "presets", "looks", "vehicle_customize" }) do package.loaded[name] = nil end
  return require("looks"), require("vehicle_customize")
end

-- ------------------------------------------------------------------ looks
local slots = car(3)
wr(P + 0xD74, 4, 0)   -- on foot
local looks = reload()
local F = {}
local page = looks.row(F).open(nil, P)
assert(row(page, "Load this slot").run():find("empty"))
assert(row(page, "Save to this slot").run():find("^Saved"))
assert(page.rows[1].options[1]:find("saved"))
-- Change everything, then load the slot.
for key in pairs(morphs) do morphs[key] = 0.9 end
skin, voice, hair[0], hair[2] = 0, 3, { 9, 9, 9 }, { -2, -1, -1 }
worn[8], worn[14], worn[20] = { 5, 0, 0, -1, -1, -1, 0, -1, -1 }, nil, { 2, 0, 0, -1, -1, -1, 0, -1, -1 }
assert(row(page, "Save to this slot").run():find("Press again"))   -- a filled slot asks first
page.rows[1].v = 2; page.rows[1].change()
page.rows[1].v = 1; page.rows[1].change()
assert(row(page, "Load this slot").run():find("Applying"))
for _ = 1, 50 do looks.update(P) end
assert(looks.status() == "DONE", looks.status())
assert(math.abs(morphs["global gender/body gender"] - 0.2) < 0.001 and math.abs(morphs["nose/nose depth"] - 0.7) < 0.001
  and math.abs(morphs["jaw/7"] - 0.5) < 0.001 and math.abs(morphs["global body/old"] - 0.1) < 0.001)
assert(skin == 2 and voice == 1 and hair[0][1] == 4 and hair[0][2] == 1 and hair[2][1] == 3)
-- The clothes came back, with the coat's colours; the chain put on since is gone.
assert(worn[8] and worn[8][1] == 3 and worn[8][3] == 2 and worn[8][4] == 4 and worn[8][5] == 5 and worn[8][6] == -1, "coat")
assert(worn[14] and worn[14][1] == 7 and worn[14][7] == 1, "shoes and their wear option")
assert(worn[20] == nil and worn[50] and worn[50][1] == 9, "chain off, tattoo kept")
-- An item moved in the table (a mod) is found again by its name.
ITEM_NAMES[3] = "something_else"
worn[8] = nil
row(page, "Load this slot").run()
for _ = 1, 50 do looks.update(P) end
assert(worn[8] and worn[8][1] == 11, "coat found again by name at index 11")
ITEM_NAMES[3] = "coat_leather"
-- A fresh start reads the same look from the file.
looks = reload()
morphs["nose/bridge width"] = 0
page = looks.row(F).open(nil, P)
assert(page.rows[1].options[1]:find("saved"))
row(page, "Load this slot").run()
for _ = 1, 50 do looks.update(P) end
assert(math.abs(morphs["nose/bridge width"] - 0.3) < 0.001)
-- A new character mid-load cancels it.
morphs["nose/bridge width"] = 0
row(page, "Load this slot").run()
wr(P + 0x44, 4, 0xBBBB)
looks.update(P)
assert(looks.status() == "CANCELLED" and morphs["nose/bridge width"] == 0)
-- Deleting asks twice.
assert(row(page, "Delete this slot").run():find("Press again"))
assert(row(page, "Delete this slot").run():find("deleted"))
assert(page.rows[1].options[1]:find("empty"))

-- ---------------------------------------------------------------- vehicles
slots = car(3)
local _, V = reload()
local colors = require("data.vehicle_colors")
fitted[slots[1]] = 0x25000000 + 2 * 0x38
fitted[slots[3]] = 0x27000000
paint[0x27000000 .. ":0"] = POOL + 4 * 28
page = V.presets_page(P)
assert(type(page) == "table", tostring(page))
assert(row(page, "Save to this slot").run():find("^Saved"))
fitted[slots[1]], fitted[slots[2]] = 0x25000000, 0x26000000 + 0x38
paint[0x27000000 .. ":0"] = POOL
_, V = reload()   -- a fresh start
page = V.presets_page(P)
assert(row(page, "Load this slot").run() == "Preset loaded")
assert(fitted[slots[1]] == 0x25000000 + 2 * 0x38 and fitted[slots[2]] == nil)
assert(paint[0x27000000 .. ":0"] == POOL + 4 * 28, "paint comes back by name: " .. colors[5][1])
-- Another model (a different catalog) has its own, empty, slots.
car(2)
page = V.presets_page(P)
assert(row(page, "Load this slot").run():find("empty"))
-- On foot there is no page.
wr(P + 0xD74, 4, 0)
assert(type(V.presets_page(P)) == "string")
os.remove(scratch .. "\\saved_presets.lua")

-- -------------------------------------------------------------- walk style
-- The kept style comes back only from the default walk.
reload()
package.loaded.native_walk = nil
local W = require("native_walk")
wr(0x025274D4, 4, 0x40000000); wr(0x025274D8, 4, 2)
wr(0x40000000 + 8, 4, 50); wr(0x40000000 + 12 + 8, 4, 61)
wr(P + 0x1138, 4, 50)
W.keep(P, 120)
assert(rd(P + 0x1138, 4) == 50, "nothing kept yet")
require("presets").all().walk = "custom walk male 1"
W.keep(P, 119)
assert(rd(P + 0x1138, 4) == 50, "only every 120 ticks")
W.keep(P, 120)
assert(rd(P + 0x1138, 4) == 61, "the kept walk comes back")
wr(P + 0x1138, 4, 77)   -- a walk the game chose
W.keep(P, 240)
assert(rd(P + 0x1138, 4) == 77, "another walk is left alone")
print("presets: ok")

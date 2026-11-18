-- SR Tweak Menu (Saints Row 2) - saved looks: the character's face and body
-- sliders, skin color, hair (with its colors) and voice, kept in a slot and
-- put back later. Everything goes through the calls the Customize pages use
-- (face_body.lua, hair.lua); a look is applied a few changes a frame, waiting
-- for the game to finish streaming in between.
--
-- Clothing, jewelry and tattoos: the clothing store's own calls (interface
-- state). pcu_get_slot_info(slot) reads what a slot wears (item, variant,
-- colours, wear option, logo); loading takes everything off with
-- pcu_remove_clothing (it leaves hair, tattoos and the underwear the game
-- insists on) and puts each item back with pcu_set_slot_info, one at a time,
-- waiting for streaming. Items are kept by index and by name, so a look still
-- finds its items if a table mod moves them. Tattoos are added, not taken off.
-- Read in the game's code, not yet tried in play.
local G = require("game")
local body = require("face_body")
local barber = require("hair")
local presets = require("presets")
local L = {}

local SETS = { "global gender", "global body",
  "crown", "forehead", "brow", "eyes", "nose", "cheekbones", "ears", "chin", "mouth", "jaw" }
-- The body controls aren't in the sets' own reports (Body Type names them).
local NAMED = { ["global gender"] = { "body gender" }, ["global body"] = { "body fat", "body muscle", "old" } }
local AREAS = 5   -- head hair, mustache, beard, sideburns, eyebrows (0-4)

-- The customization slots kept: 6-37 (tie to piercings), 41 suit, 44 and
-- 48-72 tattoos. (0-4 hair is the barber's; 5 eyelashes, 38-40 eyes,
-- stubble, teeth, 42-43 privacy bars, 45-47 make-up and 73+ are left alone.)
local CLOTH_CAPTURE = [[
local out, n = {}, 0
for s = 6, 72 do
  if s <= 37 or s == 41 or s == 44 or s >= 48 then
    local slot, item, _, _, _, var, _, _, nc, c0, _, _, _, c1, _, _, _, c2,
      _, _, _, _, wear, _, _, _, logo, _, _, logoc = pcu_get_slot_info(s)
    if slot and slot >= 0 and item then
      n = n + 1
      out[n] = string.format("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d", s, item, var or 0, nc or 0,
        c0 or -1, c1 or -1, c2 or -1, wear or 0, logo or -1, logoc or -1)
    end
  end
end
tweak_out(n, table.concat(out, ";"))]]
-- The item table: 0x78-byte records from 0x029E8CD0 (count at 0x025288D8), the name at +8.
local ITEMS, ITEM_SIZE, ITEM_COUNT = 0x029E8CD0, 0x78, 0x025288D8
local function item_name(index)
  if index < 0 or index >= wml.read_u32(ITEM_COUNT) then return nil end
  local ptr = wml.read_u32(ITEMS + index * ITEM_SIZE + 8)
  return ptr ~= 0 and wml.read_string(ptr) or nil
end
-- The saved item's index now: where it was, or found again by its name.
local function item_index(entry)
  if not entry.name or entry.name == "" then return entry[2] end
  if item_name(entry[2]) == entry.name then return entry[2] end
  for i = 0, math.min(wml.read_u32(ITEM_COUNT), 20000) - 1 do
    if item_name(i) == entry.name then return i end
  end
end
local function capture_clothes()
  local ok, n, packed = G.vint(CLOTH_CAPTURE)
  if not ok or type(n) ~= "number" or type(packed) ~= "string" then return nil end
  local clothes = {}
  for e in packed:gmatch("[^;]+") do
    local t = {}
    for v in e:gmatch("-?%d+") do t[#t + 1] = math.tointeger(tonumber(v)) end
    if #t == 10 then
      t.name = item_name(t[2])
      clothes[#clothes + 1] = t
    end
  end
  return clothes
end
local job, last

local function usable(p)
  return p ~= 0 and G.playing(p) and body.record(p) and not body.busy() and not barber.busy() and body.ready()
end

function L.capture(p)
  if not usable(p) then return nil, "Wait until your character is ready and on foot" end
  local look = { morphs = {}, hair = {} }
  for _, set in ipairs(SETS) do
    local seen = {}
    for _, entry in ipairs(body.morph_values(set)) do
      seen[entry[1]] = true
      look.morphs[#look.morphs + 1] = { set, entry[1], entry[2] }
    end
    for _, id in ipairs(NAMED[set] or {}) do
      local value = not seen[id] and body.morph_value(set, id)
      if value then look.morphs[#look.morphs + 1] = { set, id, value } end
    end
  end
  if #look.morphs == 0 then return nil, "Couldn't read your character's face and body" end
  look.skin = body.skin_current()
  for area = 0, AREAS - 1 do
    local style = barber.current(p, area)
    if style then look.hair[area + 1] = { style.id, style.primary, style.secondary } end
  end
  local _, voice = G.vint("tweak_out(pcr_get_current_voice_number())")
  if type(voice) == "number" and body.VOICES[voice + 1] then look.voice = voice end
  look.clothes = capture_clothes()
  return look
end

-- Steps answer "same" (nothing to change), "changed", or "retry".
local function steps(p, look)
  local list = {}
  local function add(step) list[#list + 1] = step end
  local function morph(entry)
    add(function()
      local now = body.morph_value(entry[1], entry[2])
      if not now then return "missing" end
      if math.abs(now - entry[3]) < 0.005 then return "same" end
      return body.put(entry[1], entry[2], entry[3]) and "changed" or "retry"
    end)
  end
  -- Gender first: it decides which body the other controls shape.
  for _, entry in ipairs(look.morphs or {}) do
    if entry[1] == "global gender" then morph(entry) end
  end
  if type(look.skin) == "number" then
    add(function()
      if body.skin_current() == look.skin then return "same" end
      return body.skin_put(look.skin) and "changed" or "retry"
    end)
  end
  for _, entry in ipairs(look.morphs or {}) do
    if entry[1] ~= "global gender" then morph(entry) end
  end
  for area = 0, AREAS - 1 do
    local saved = look.hair and look.hair[area + 1]
    if saved then
      add(function()
        local now = barber.current(p, area)
        if not now then return "missing" end
        if now.id == saved[1] and (saved[1] < 0 or (now.primary == saved[2] and now.secondary == saved[3])) then
          return "same"
        end
        return barber.put(area, { id = saved[1], primary = math.max(0, saved[2]), secondary = math.max(0, saved[3]) })
          and "changed" or "retry"
      end)
    end
  end
  if look.voice and body.VOICES[look.voice + 1] then
    add(function()
      local _, now = G.vint("tweak_out(pcr_get_current_voice_number())")
      if now == look.voice then return "same" end
      if not G.vint(("pcr_set_voice(%q, false)"):format(body.VOICES[look.voice + 1][1])) then return "retry" end
      G.lua("T.own_persona = character_get_persona(LOCAL_PLAYER)")
      if L.F then L.F.voice_chosen = nil end
      return "changed"
    end)
  end
  -- Clothing last (the body decides which wear options fit). Looks saved
  -- before clothing was kept have none, and keep what you wear.
  if type(look.clothes) == "table" then
    add(function()
      local ok = G.vint("pcu_wear_current_clothing() pcu_clear_preview_slot() pcu_remove_clothing() tweak_out(true)")
      return ok and "changed" or "retry"
    end)
    local function opt(v) return v >= 0 and tostring(v) or "nil" end
    for _, t in ipairs(look.clothes) do
      add(function()
        local index = item_index(t)
        if not index then return "missing" end
        local _, slot_now, item_now = G.vint(("tweak_out(pcu_get_slot_info(%d))"):format(t[1]))
        if slot_now == t[1] and item_now == index then return "same" end
        local ok = G.vint(("pcu_set_slot_info(%d, %d, %d, %d, %s, %s, %s, %d, %d, %d, false) tweak_out(true)")
          :format(t[1], index, t[3], t[4], opt(t[5]), opt(t[6]), opt(t[7]), t[8], t[9], t[10]))
        if not ok then return "retry" end
        _, slot_now, item_now = G.vint(("tweak_out(pcu_get_slot_info(%d))"):format(t[1]))
        -- (the game refuses an item quietly: one this body can't wear, say)
        return item_now == index and "changed" or "missing"
      end)
    end
    add(function() G.vint("pcu_wear_current_clothing()") return "same" end)
  end
  return list
end

function L.apply(p, look)
  if job then return "A look is still being applied", true end
  if not usable(p) then return "Wait until your character is ready and on foot", true end
  job = { p = p, actor = wml.read_u32(p + 0x44), owner = body.record(p), steps = steps(p, look),
    at = 1, tries = 0, waited = 0, changed = 0, skipped = 0 }
  last = nil
  return "Applying the look..."
end

function L.status()
  if job then return ("APPLYING %d%%"):format(math.floor((job.at - 1) * 100 / math.max(1, #job.steps))) end
  return last or ""
end

function L.update(p)
  if not job then return end
  if p == 0 or p ~= job.p or wml.read_u32(p + 0x44) ~= job.actor or body.record(p) ~= job.owner then
    job, last = nil, "CANCELLED"
    return
  end
  if not usable(p) then
    job.waited = job.waited + 1
    -- (about ten seconds of the game never becoming ready)
    if job.waited > 600 then job, last = nil, "TIMED OUT" end
    return
  end
  job.waited = 0
  local changes, looked = 0, 0
  while job.at <= #job.steps and changes < 6 and looked < 40 do
    local result = job.steps[job.at]()
    looked = looked + 1
    if result == "retry" then
      job.tries = job.tries + 1
      if job.tries < 5 then return end
      result = "missing"
    end
    job.at, job.tries = job.at + 1, 0
    if result == "missing" then job.skipped = job.skipped + 1 end
    if result == "changed" then
      job.changed, changes = job.changed + 1, changes + 1
      if not body.ready() then return end
    end
  end
  if job.at > #job.steps then
    last = job.skipped > 0 and ("DONE, " .. job.skipped .. " SKIPPED") or "DONE"
    wml.log(("saved look applied: %d changed, %d skipped of %d"):format(job.changed, job.skipped, #job.steps))
    job = nil
  end
end

function L.row(F)
  L.F = F
  return { label = "Saved Looks", kind = "page",
    help = "Keep your face, body, skin, hair, voice and clothing in a slot and put them back later.",
    open = function(_, p)
      last = nil
      return presets.page({ title = "Saved Looks", noun = "Look", slots = 8,
        store = function()
          local all = presets.all()
          all.looks = type(all.looks) == "table" and all.looks or {}
          return all.looks
        end,
        capture = function() return L.capture(G.player()) end,
        apply = function(look) return L.apply(G.player(), look) end,
        status = L.status,
        save_help = "Saves your face and body sliders, skin color, hair, voice, and the clothing, jewelry and tattoos you wear.",
        load_help = "Puts the saved look on your character, clothes included. It takes a few seconds; stay on foot. Items this body can't wear are skipped.",
      })
    end }
end

return L

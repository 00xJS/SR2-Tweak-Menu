-- SR Tweak Menu (Saints Row 2) - rows that need the game engine itself
-- (calls into SR2_pc.exe, not its scripts): No Clip, spawning, the free
-- camera, field of view, respect, play as anyone. Addresses and calling
-- conventions were read in the game's code; Juiced Patch does many of the
-- same things and was the map. Each *_row() gives a tab its row.

local G = require("game")
local F  -- (features, for the frame hook; set by E.attach)
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u32, write_f32 = wml.write_u8, wml.write_u32, wml.write_f32
local E = {}

local FRAME_TIME = 0x00E84384   -- f32: the last frame's length in seconds, before game speed

-- Handle -> object pointer (nil if gone); kind at +0x4C: 1 human, 5 vehicle.
local function object(h)
  if not h or h == 0 or h == 0xFFFFFFFF then return nil end
  local o = read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if o == 0 or read_u32(o + 0x44) ~= h then return nil end
  return o
end
local function dt()
  local t = read_f32(FRAME_TIME)
  if t ~= t or t <= 0 or t > 0.25 then return 1 / 60 end
  return t
end

local function not_yet(id, label, why)
  return { id = id, label = label .. " (not yet)", kind = "action", needs = "none", nosave = true,
    help = why or "Not on Saints Row 2 yet.",
    run = function() return label .. " isn't on Saints Row 2 yet" end }
end

-- ---------------------------------------------------------------- No Clip
-- On: the on-foot control update (0x004FAA90) returns at once and the
-- keyboard's move axes aren't read, so walking and gravity stop; the player
-- is invulnerable, can't ragdoll and holsters. Each frame the body is moved
-- the way the camera faces: W/S forward and back, A/D sideways, Space up, E
-- down, Shift faster.
local NOCLIP_KEYS = { [0x00C1370F] = "\xA1\x78\xE7\x34\x02", [0x00C13745] = "\xA1\x80\xE7\x34\x02",
                      [0x00C1375B] = "\xA1\x90\xE7\x34\x02", [0x00C13776] = "\xA1\x88\xE7\x34\x02" }
local noclip_on = false
local function body(p)
  local a = read_u32(p + 0x570); if a == 0 then return nil end
  local b = read_u32(a + 0x08); if b == 0 then return nil end
  local c = read_u32(b + 0x40); if c == 0 then return nil end
  local rb = read_u32(c + 0x18); if rb == 0 then return nil end
  return rb
end
local function set_noclip(p, on)
  if on == noclip_on then return end
  noclip_on = on
  wml.callx(0x00960800, { ecx = p }, 1, 0)                      -- collision
  local q = read_u32(p + 0x570)
  if q ~= 0 then write_f32(q + 0x164, 0); write_f32(q + 0x144, 0) end   -- no fall speed
  wml.patch(0x004FAA90, on and "\xC3" or "\x55")
  for at, bytes in pairs(NOCLIP_KEYS) do wml.patch(at, on and "\x90\x90\x90\x90\x90" or bytes) end
  wml.patch(0x00DD04F4, string.pack("<f", on and 0.0 or 1.5))
  local anim = on and wml.call(0x006EF510, wml.buffer(4, "streaking stand")) or 0xFFFFFFFF
  local cell = wml.buffer(5); write_u32(cell, anim)
  wml.callx(0x009695F0, { ecx = p }, cell)                      -- stand still
  wml.call(0x009D9FD0, p)                                       -- leave fine aim
  if on then wml.call(0x005E8140) end                           -- leave the car
  wml.call(0x009ACB10, p, 0)                                    -- stop ragdoll
  local b = on and 1 or 0
  wml.callx(0x00965B50, {}, p, b); wml.callx(0x009661E0, {}, p, b); wml.callx(0x00965F40, {}, p, b)
end
local function noclip_frame(p)
  local rb = body(p); if not rb then return end
  local dx, dy, dz = read_f32(0x025F5B50), read_f32(0x025F5B54), read_f32(0x025F5B58)
  write_f32(p + 0x38, dx); write_f32(p + 0x40, dz)
  if F.menu_open() then return end
  local s = (wml.key_down("SHIFT") and 80 or 40) * dt()
  local x, y, z = read_f32(rb + 0x30), read_f32(rb + 0x34), read_f32(rb + 0x38)
  if wml.key_down("W") then x, y, z = x + s * dx, y + s * dy, z + s * dz end
  if wml.key_down("S") then x, y, z = x - s * dx, y - s * dy, z - s * dz end
  if wml.key_down("A") then x, z = x - s * dz, z + s * dx end
  if wml.key_down("D") then x, z = x + s * dz, z - s * dx end
  if wml.key_down("SPACE") then y = y + s end
  if wml.key_down("E") then y = y - s end
  write_f32(rb + 0x30, x); write_f32(rb + 0x34, y); write_f32(rb + 0x38, z)
end
function E.noclip_row()
  return { id = "noclip", label = "No Clip", kind = "toggle", nosave = true,
    help = "Fly through anything: W/S forward and back, A/D sideways, Space up, E down, Shift faster.",
    update = function(ctx, p) set_noclip(p, true) noclip_frame(p) end,
    off = function(ctx, p) set_noclip(p, false) end }
end

-- ---------------------------------------------------------------- vehicles
local VEH = { BY_NAME = 0x00AE4090, SPAWN = 0x00AE4AE0, LAST = 0x0252A0E0, FREE = 0x022A84D0,
  PTR = 0x00AE28F0, DELETE = 0x00AA4490, FADE = 0x00AABC80, ENTER = 0x00597C40, UNRAGDOLL = 0x009ACB10 }
local spawned_vehicles = {}
local vehicle_session
local function sync_vehicles(p)
  local actor = p ~= 0 and read_u32(p + 0x44) or 0
  if not vehicle_session or vehicle_session.p ~= p or vehicle_session.actor ~= actor then
    spawned_vehicles = {}
    vehicle_session = { p = p, actor = actor }
  end
end

-- Spawns `name` (an xtbl name) in front of the player and puts them in it.
local function spawn_vehicle(name)
  local p = G.player(); if p == 0 then return "Load a game first" end
  sync_vehicles(p)
  if read_u32(VEH.FREE) == 0 then return "Too many vehicles about: try again elsewhere" end
  local idx = wml.callx(VEH.BY_NAME, { ecx = wml.buffer(0, name) })
  if idx == 0xFFFFFFFF then return "The game doesn't know " .. name end
  wml.call(VEH.SPAWN, idx)
  local v = wml.callx(VEH.PTR, { ecx = read_u32(VEH.LAST) })
  if v == 0 then return "The vehicle didn't spawn" end
  spawned_vehicles[#spawned_vehicles + 1] = {
    handle = read_u32(VEH.LAST), vehicle = v,
    instance = read_u32(v + 0x84D4), info = read_u32(v + 0x84E4) }
  wml.callx(VEH.FADE, { eax = v, edx = 500 })
  wml.call(VEH.UNRAGDOLL, p, 0)
  wml.callx(VEH.ENTER, { esi = p, edi = v }, 0)
end

function E.spawn_vehicle_row()
  local V = F.data("vehicles")
  local list = {}
  for _, v in ipairs(V) do list[#list + 1] = { v[1], v[2] .. (v[3] and v[3] ~= "car" and (" (" .. v[3] .. ")") or "") } end
  table.sort(list, function(a, b) return a[2]:lower() < b[2]:lower() end)
  return { id = "spawn_vehicle", label = "Spawn vehicle", kind = "list", items = list, nosave = true,
    help = "Left/Right to choose, Enter puts you in a new one (the last one spawned goes when you spawn another).",
    run = function(ctx, p, v, it) return spawn_vehicle(it.items[it.v][1]) or ("Spawned " .. it.items[it.v][2]) end }
end

-- The phone's vehicle cheats as list rows { cheat name, "Shown name" }.
function E.cheat_vehicles()
  local list = {}
  for _, c in ipairs(F.data("cheats")) do
    if c[3] == "Vehicles" and c.code and c[4]:find("Drop", 1, true) then list[#list + 1] = { c[2], c[2] } end
  end
  table.sort(list, function(a, b) return a[2]:lower() < b[2]:lower() end)
  return list
end

-- ---------------------------------------------------------------- people
local NPC = { CHAR = 0x004A5A90, CREATE = 0x009CFCE0, FOLLOW = 0x0098EC10, DELETE = 0x00960240 }
local BODYGUARDS = require("bodyguards")

-- Characters for spawning: every preset the game loads (data/characters_all.lua,
-- in the Models tab's groups), "Name (Group)"; the old cheat list if it's missing.
local function character_list()
  local list = {}
  for _, g in ipairs(F.data("characters_all")) do
    for _, c in ipairs(g[2]) do list[#list + 1] = { c[1], c[2] .. " (" .. g[1] .. ")" } end
  end
  if #list > 0 then return list end
  for _, c in ipairs(F.data("characters")) do list[#list + 1] = { c[2], c[3] or c[2] } end
  table.sort(list, function(a, b) return a[2]:lower() < b[2]:lower() end)
  return list
end

-- Creates `name` (a character preset) two metres in front of the player;
-- `follow`: as a follower (the game allows three).
local function spawn_person(name, follow)
  local p = G.player(); if p == 0 or not G.playing(p) then return nil, "Load a game first" end
  if follow then
    local room, why = BODYGUARDS.room(p)
    if not room then return nil, why end
  end
  local ch = wml.callx(NPC.CHAR, { ecx = wml.buffer(2, name) })
  if ch == 0 then return nil, "The game doesn't know " .. name end
  local s = wml.buffer(3, string.rep("\0", 0x60))
  write_u32(s + 0x00, 7); write_u32(s + 0x04, 2); write_u32(s + 0x08, 2)
  write_u32(s + 0x0C, ch); write_u32(s + 0x10, read_u32(0x033D630C))
  local fx, fz = read_f32(p + 0x38), read_f32(p + 0x40)
  write_f32(s + 0x20, read_f32(p + 0x14) + fx * 2)
  write_f32(s + 0x24, read_f32(p + 0x18))
  write_f32(s + 0x28, read_f32(p + 0x1C) + fz * 2)
  for i = 0, 8 do write_u32(s + 0x2C + i * 4, read_u32(p + 0x20 + i * 4)) end
  write_u32(s + 0x50, read_u16(p + 0x48))
  write_u8(s + 0x55, 1); write_u8(s + 0x57, 1)
  local h = wml.callx(NPC.CREATE, { eax = s })
  if h == 0 then return nil, "They didn't spawn (too many people about?)" end
  local kept, why = BODYGUARDS.track(p, h, follow, ch)
  if not kept then
    local token = read_u32(h + 0x44)
    if object(token) == h and read_u32(h + 0xD4) == ch then
      wml.callx(NPC.DELETE, { ecx = h }, 0)
    end
    return nil, why
  end
  return h, why
end

function E.spawn_person_row()
  return { id = "spawn_person", label = "Spawn person", kind = "list", items = character_list(), nosave = true,
    help = "Left/Right to choose, Enter puts them in front of you.",
    run = function(ctx, p, v, it)
      local h, why = spawn_person(it.items[it.v][1], false)
      return h and ("Spawned " .. it.items[it.v][2]) or why
    end }
end
function E.bodyguard_row()
  return { id = "bodyguard", label = "Spawn bodyguard", kind = "list", items = character_list(), nosave = true,
    help = "Spawn an armed follower. Uses your native homie limit, up to three; follows, fights and boards vehicles with you.",
    run = function(ctx, p, v, it)
      local h, why = spawn_person(it.items[it.v][1], true)
      return h and (why or (it.items[it.v][2] .. " has your back")) or why
    end }
end
function E.remove_people_row()
  return { id = "remove_people", label = "Remove spawned people", kind = "action",
    help = "Everyone the menu spawned goes away.",
    run = function(_, p) return BODYGUARDS.remove(p) end }
end

-- ---------------------------------------------------------------- camera
-- Free camera: the game's slew camera (mode 2 leaves the camera to its
-- globals), flown with its own slew mover each frame; or held on the shot
-- while you play on (Free camera mode), with the world kept loading round
-- you, not the camera (the streaming centre's mode test, 0x009DF503).
local CAM_MODE, CAM_POS, CAM_ORIENT = 0x025F5AE8, 0x025F5B20, 0x025F5B5C
local STREAM_TEST = { 0x009DF503, "\x0F\x85\xA6\x02\x00\x00", "\x90\x90\x90\x90\x90\x90" }
local free_on, holding = false, false
local function hold_shot(on)
  if on == holding then return end
  holding = on
  wml.patch(STREAM_TEST[1], on and STREAM_TEST[3] or STREAM_TEST[2])
end
function E.free_cam_row()
  return { id = "free_cam", label = "Free camera", kind = "toggle", nosave = true,
    help = "Detaches the camera: fly it about (the game's slew camera), or leave it on the shot and play on (Free camera mode).",
    update = function()
      if not free_on then free_on = true; write_u32(CAM_MODE, 2) end
      local hold = F.items.cam_mode and F.items.cam_mode.v == 2
      hold_shot(hold)
      if not hold then wml.call(0x00C01650, CAM_POS, CAM_ORIENT, wml.f2u(dt()), 0, 0) end
    end,
    off = function()
      free_on = false
      hold_shot(false)
      write_u32(CAM_MODE, G.in_cutscene() and 5 or 0)
    end }
end
function E.cam_mode_row()
  return { id = "cam_mode", label = "Free camera mode", kind = "choice", needs = "none", options = { "Fly", "Hold this shot" }, v = 1,
    nosave = true, help = "Fly: move the free camera. Hold this shot: it stays put and you play on in front of it." }
end

-- No fog: the game's own fog override (its debug command's flag and values).
function E.no_fog_row()
  return { id = "no_fog", label = "No fog", kind = "toggle", needs = "none",
    help = "Removes the distance fog.",
    update = function() write_u8(0x025273BE, 1); write_f32(0x00E989A0, 0.0); write_f32(0x00E989A4, 0.0) end,
    off = function() write_u8(0x025273BE, 0); write_f32(0x00E989A0, 0.25); write_f32(0x00E989A4, 0.40) end }
end

-- ---------------------------------------------------------------- the player
function E.respect_row()
  return { id = "respect", label = "Respect +5,000", kind = "action",
    help = "Adds 5,000 respect.",
    run = function(ctx, p)
      local r = read_u32(p + 0x1200)
      if r >= 0x80000000 then r = 0 end
      write_u32(p + 0x1200, r + 5000)
      return "Added 5,000 respect"
    end }
end

-- Play as any character preset (live), and back.
function E.play_as(name)
  local ch = wml.callx(NPC.CHAR, { ecx = wml.buffer(6, name) })
  if ch == 0 then return "The game doesn't know " .. name end
  local slot = wml.buffer(7); write_u32(slot, ch)
  wml.call(0x006856A0, slot, 1)
end
function E.restore_player() wml.call(0x00685D50, 0, 1) end

function E.play_as_row()
  return { id = "play_as", label = "Play as", kind = "list", items = character_list(), nosave = true,
    help = "Left/Right to choose, Enter switches you to them.",
    run = function(ctx, p, v, it) return E.play_as(it.items[it.v][1]) or ("You're " .. it.items[it.v][2]) end }
end

-- ---------------------------------------------------------------- more spawning
function E.remove_vehicles_row()
  return { id = "remove_vehicles", label = "Remove spawned vehicles", kind = "action",
    help = "Every vehicle the menu spawned goes away (not the one you're in).",
    run = function(ctx, p)
      sync_vehicles(p)
      local n, mine = 0, read_u32(p + 0xD74)
      for _, entry in ipairs(spawned_vehicles) do
        local o = object(entry.handle)
        if o == entry.vehicle and read_u32(o + 0x4C) == 5 and entry.handle ~= mine
          and read_u32(o + 0x84D4) == entry.instance and read_u32(o + 0x84E4) == entry.info then
          wml.callx(VEH.DELETE, { ecx = o }, 0); n = n + 1
        end
      end
      spawned_vehicles = {}
      return "Removed " .. n
    end }
end

-- Crowds: n random people from the character list around you.
local function crowd_row(id, label, n)
  return { id = id, label = label, kind = "action",
    help = "Spawns " .. n .. " random people around you.",
    run = function()
      local list, made = character_list(), 0
      if #list == 0 then return "No character list" end
      for _ = 1, n do if spawn_person(list[math.random(#list)][1], false) then made = made + 1 end end
      return "Spawned " .. made .. " people"
    end }
end
function E.crowd_small_row() return crowd_row("crowd_small", "Spawn 10 random people", 10) end
function E.crowd_big_row() return crowd_row("crowd_big", "Spawn a crowd (40)", 40) end

-- Every human the game has, but you (the object table's live type-1 entries).
local function humans()
  local list, p = {}, G.player()
  for i = 0, 0xFFF do
    local o = read_u32(0x02149C64 + i * 16)
    if o ~= 0 and o ~= p and read_u32(o + 0x4C) == 1 and (read_u32(o + 0x44) & 0xFFF) == i then list[#list + 1] = o end
  end
  return list
end
-- Recruit: the nearest person on your side (the team byte at human+0x111C,
-- where get_team reads it - yours is the gang you joined) follows you, with
-- the call Spawn bodyguard uses. SR2's own recruit prompt only knows the Saints.
function E.recruit_row()
  return { id = "recruit_nearest", label = "Recruit nearest gang member", kind = "action",
    help = "The nearest member of the gang you're with (the Saints, or the one picked in Join Gang) within 20 metres joins you as a homie.",
    run = function(ctx, p) return BODYGUARDS.recruit(p, humans()) end }
end
function E.drop_row()
  return { id = "drop", label = "Ragdoll all NPCs", kind = "action",
    help = "Everybody around you falls over.",
    run = function()
      local list = humans()
      for _, o in ipairs(list) do wml.call(0x009AC180, o, 3000, 0, 0, 0, 0, 1, 0) end
      return "Down they go (" .. #list .. ")"
    end }
end

-- Everybody...: every person around takes one of the game's animation
-- states (looked up by name; 0x006EF510 gives -1 for one SR2 hasn't got),
-- set with the same call No Clip uses on you. "Back to normal" clears it.
local EVERYBODY = {
  { { "breakdancer stand" }, "Breakdance" },
  { { "pole stand", "stage stand" }, "Strip dance" },
  { { "drunk stand" }, "Drunk" },
  { { "cower stand", "cower stand variant 1" }, "Cower" },
  { { "protest Stand" }, "Protest" },
  { { "streaking stand" }, "Streak" },
  { { "tour Stand" }, "Tourists" },
  { false, "Back to normal" },
}
-- (each person plays the state's clip as a looping track of their own - the
-- way Emotes plays yours - so nobody's script or AI state is forced; the
-- tracks are stopped again by Back to normal)
local PLAYBACK = require("emote_playback")
local everybody_tracks = {}
local function everybody_stop()
  for _, t in ipairs(everybody_tracks) do
    local o = object(t.handle)
    if o and o == t.token.p then pcall(PLAYBACK.stop, o, t.token) end
  end
  everybody_tracks = {}
end
local function state_index(name)
  local i = wml.call(0x006EF510, wml.buffer(4, name))
  return i ~= 0xFFFFFFFF and i or nil
end
local function set_state(o, index)
  local cell = wml.buffer(5); write_u32(cell, index)
  wml.callx(0x009695F0, { ecx = o }, cell)
end
function E.everybody_row()
  return { id = "everybody", label = "Everybody...", kind = "list", items = EVERYBODY, nosave = true,
    help = "Left/Right to pick what people near you do, Enter to start. Back to normal stops it.",
    run = function(ctx, p, v, it)
      local choice = it.items[it.v]
      everybody_stop()
      if not choice[1] then return "Everybody back to normal" end
      local list, n = humans(), 0
      for i, o in ipairs(list) do
        local name = choice[1][(i - 1) % #choice[1] + 1]
        local ok, token = pcall(PLAYBACK.play_other, o, "State", name, true)
        if ok and token and not token.external then
          n = n + 1
          everybody_tracks[#everybody_tracks + 1] = { handle = read_u32(o + 0x44), token = token }
        end
      end
      if n == 0 then return "Nobody near you could play that (" .. #list .. " people)" end
      return string.format("Everybody: %s (%d of %d people)", choice[2], n, #list)
    end }
end

-- ---------------------------------------------------------------- staged scenes
-- Two people spawned in front of you, placed and set going on one of the
-- game's paired animations (as its own ambient pairs are). Experimental: the
-- placement is worked out from the game's code, not yet seen in play.
local SCENES = {
  { { "pair dance a", "pair dance a" }, "Dance pair", 0.7 },
  { { "pair dance c", "pair dance c" }, "Dance pair 2", 0.7 },
  { { "Lapdance Stand Give", "Lapdance Sit Get" }, "Lap dance", 0 },
  { { "Lover Sit B", "Lover Sit A" }, "Lovers", 0 },
  { { "Picnic Sit A", "Picnic Sit B" }, "Picnic", 0 },
  { { "Blunt Sit Left", "Blunt Sit Right" }, "Smoke a blunt", 0 },
  { { "RPS Stand", "RPS Stand" }, "Rock, paper, scissors", 0.8 },
  { { "talking long", "talking yes" }, "Chat", 0.9 },
}
local scene_people = {}
-- Puts a human at x, y, z facing yaw (radians), with the teleport script's call.
local function place(h, x, y, z, yaw)
  local pos, m = wml.buffer(10), wml.buffer(11)
  write_f32(pos, x); write_f32(pos + 4, y); write_f32(pos + 8, z)
  local c, s = math.cos(yaw), math.sin(yaw)
  local rows = { c, 0, -s, 0, 1, 0, s, 0, c }
  for k = 1, 9 do write_f32(m + (k - 1) * 4, rows[k]) end
  wml.callx(0x009A0B00, { ecx = m, edx = pos }, h, 0, 1, 0, 0)
end
function E.scene_row()
  local items = {}
  for _, s in ipairs(SCENES) do items[#items + 1] = { s, s[2] } end
  return { id = "scene", label = "Stage a scene", kind = "list", items = items, nosave = true,
    help = "Left/Right to choose, Enter: two people act it out in front of you. Experimental.",
    run = function(ctx, p, v, it)
      local sc = it.items[it.v][1]
      local list = character_list()
      if #list == 0 then return "No character list" end
      local fx, fz = read_f32(p + 0x38), read_f32(p + 0x40)
      local yaw = math.atan(fx, fz)
      local cx, cy, cz = read_f32(p + 0x14) + fx * 3, read_f32(p + 0x18), read_f32(p + 0x1C) + fz * 3
      local made = 0
      for i = 1, 2 do
        local h = spawn_person(list[math.random(#list)][1], false)
        if h then
          made = made + 1
          scene_people[#scene_people + 1] = read_u32(h + 0x44)
          local off = (i == 1) and -sc[3] / 2 or sc[3] / 2
          place(h, cx + fx * off, cy, cz + fz * off, (i == 1) and yaw or yaw + math.pi)
          local idx = state_index(sc[1][i])
          if idx then set_state(h, idx) end
        end
      end
      return made == 2 and ("Scene: " .. sc[2]) or "Couldn't spawn the people (too many about?)"
    end }
end
function E.clear_scene_row()
  return { id = "clear_scene", label = "Clear scene", kind = "action",
    help = "The people from Stage a scene go away.",
    run = function()
      local n = 0
      local p = G.player()
      for _, h in ipairs(scene_people) do
        if BODYGUARDS.remove_one(p,h) then n = n + 1 end
      end
      scene_people = {}
      return "Cleared " .. n
    end }
end

function E.dismiss_homies_row()
  return { id = "dismiss_homies", label = "Dismiss homies", kind = "action",
    help = "Dismiss your party and cancel bodyguards still waiting to join.",
    run = function(_, p) return BODYGUARDS.dismiss(p) end }
end

function E.attach(features)
  F = features
  F.after_updates[#F.after_updates + 1] = BODYGUARDS.update
  F.after_updates[#F.after_updates + 1] = function(p) sync_vehicles(p) end
end
return E

-- SR Tweak Menu (Saints Row 2) - rows that change the game's memory: health,
-- regen and falls, sprint, the gun in your hand, vehicles, gravity and game
-- speed, districts and the rewards' damage resistances. Addresses and
-- conventions were read in the game's code. Every row keeps the game's own
-- value and puts it back when switched off.

local G = require("game")
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32
local S = wml.setting

local M = {}
local F

-- ---------------------------------------------------------------- held values
-- hold(key, addr, kind, value): writes value, keeping what was there under
-- key; release(key) puts every value kept under key back. kind: "u8",
-- "u16", "u32", "f32".
local held = {}
local READ = { u8 = read_u8, u16 = read_u16, u32 = read_u32, f32 = read_f32 }
local WRITE = { u8 = write_u8, u16 = write_u16, u32 = write_u32, f32 = write_f32 }
local function hold(key, addr, kind, value)
  local h = held[key] or {}
  held[key] = h
  if h[addr] == nil then h[addr] = { kind, READ[kind](addr) } end
  WRITE[kind](addr, value)
end
local function release(key)
  local h = held[key]
  if not h then return end
  for addr, v in pairs(h) do pcall(WRITE[v[1]], addr, v[2]) end
  held[key] = nil
end
local function original(key, addr)
  local h = held[key]
  return h and h[addr] and h[addr][2]
end

-- ---------------------------------------------------------------- people
local HP_SET = 0x00969C90   -- thiscall ecx = human, (f32 *hp): clamps, and 0 kills
local function set_hp(h, v)
  local b = wml.buffer(11); write_f32(b, v)
  wml.callx(HP_SET, { ecx = h }, b)
end
-- The game's live NPC list (not the player), circular through +0x1160.
local function each_npc(fn)
  local head = read_u32(0x0215FFC0)
  if head == 0 then return 0 end
  local p, n, me, done = head, 0, read_u32(G.PLAYER), 0
  repeat
    if p ~= me and (read_u8(p + 0x80) & 0x0B) == 0 and read_f32(p + 0x1124) > 0 then fn(p); done = done + 1 end
    p = read_u32(p + 0x1160); n = n + 1
  until p == 0 or p == head or n > 512
  return done
end

-- ---------------------------------------------------------------- the gun in your hand
-- The weapon record of what you hold (shared with everyone using that gun).
local function held_weapon(p)
  if p == 0 then return nil end
  local item = read_u32(p + 0x10CC); if item == 0 then return nil end
  local w = read_u32(item + 0xC4); if w == 0 then return nil end
  local rec = read_u32(w + 8)
  return rec ~= 0 and rec or nil
end
-- A row that edits fields of the held gun's record: when you switch guns
-- the last one is put back and the new one changed.
local function gun_row(id, label, help, edit)
  local on_rec
  return { id = id, label = label, kind = "toggle", help = help,
    update = function(ctx, p, v, it)
      local rec = held_weapon(p)
      if rec ~= on_rec then release(id); on_rec = rec; if rec then edit(rec, it) end end
    end,
    off = function() release(id); on_rec = nil end }
end

-- A weapon's record by its weapons.xtbl name (0x00B716E0, cdecl).
local function weapon_record(name)
  local r = wml.call(0x00B716E0, wml.buffer(13, name))
  return r ~= 0 and r or nil
end
-- The explosion a weapon's shots make: its record's explosion pointer set to
-- another weapon's (a rocket's, a grenade's, a molotov's). Experimental.
local function blast_row(id, label, help, source, melee)
  return gun_row(id, label, help, function(rec, it)
    local src = weapon_record(type(source) == "function" and source() or source)
    if not src then return end
    hold(id, rec + 0x120, "u32", read_u32(src + 0x120))
  end)
end

-- ---------------------------------------------------------------- vehicles
local function vehicle(p)
  local h = G.vehicle_handle(p)
  if not h then return nil end
  local veh = read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if veh == 0 or read_u32(veh + 0x44) ~= h then return nil end
  return veh
end
local VEH_SET_HP = 0x00ABB6B0         -- thiscall ecx = vehicle, (i32 hp), ret 4
local VEH_INVULNERABLE = 0x00AB91C0   -- stdcall (vehicle, bool), ret 8
local VEH_HEAVY = 0x00AB9BE0          -- stdcall (vehicle, bool), ret 8
local function repair(veh) wml.callx(VEH_SET_HP, { ecx = veh }, read_u32(veh + 0x8C24)) end
-- A per-vehicle switch: on for the car you're in, off again for every car it
-- was put on.
local function car_switch(id, fn)
  local cars = {}
  return function(ctx, p)
    local veh = vehicle(p)
    if veh and not cars[veh] then cars[veh] = true; wml.callx(fn, {}, veh, 1) end
  end, function()
    for veh in pairs(cars) do pcall(wml.callx, fn, {}, veh, 0) end
    cars = {}
  end
end
-- Every vehicle model's record.
local function each_vehicle_info(fn)
  local base, n = read_u32(0x00AC743D), read_u32(0x0252A0D8)
  if base == 0 or n > 400 then return end
  for i = 0, n - 1 do fn(base + i * 0x7D0) end
end

-- ---------------------------------------------------------------- districts
local HOODS = {}
local HOOD_INDEX = 0x004B1960   -- eax = name -> index or -1
local function hood_record(name)
  local i = wml.callx(HOOD_INDEX, { eax = wml.buffer(12, name) })
  if i == 0xFFFFFFFF then return nil end
  local base, n = read_u32(0x02526C94), read_u32(0x02526C90)
  if base == 0 or i >= n then return nil end
  return base + i * 0xA8
end
local PUNCH_BLAST = { { "pipe_bomb" }, { "grenade" }, { "rpg_launcher" }, { "satchel" } }
local OWNERS = { { 0, "Saints" }, { 1, "Brotherhood" }, { 2, "Ronin" }, { 3, "Sons of Samedi" }, { 6, "Ultor" },
  { 5, "Police" }, { 4, "Neutral" }, { -1, "Starting owners" } }

-- ---------------------------------------------------------------- sprint and running
-- SR1's presets, in seconds: { name, use, recharge, delay }. SR2's own
-- values are SR1's (10, 9, 2).
local SPRINT_PRESETS = {
  { "Game's own", 10, 9, 2 },
  { "Multiplayer", 3, 6, 2 },
  { "Pimp", 2, 7, 2 },
  { "Short", 1, 12, 2 },
}
-- Run boost: each update the player's body is moved a little further the way
-- it just moved on foot (as SR1's run boost does with its teleport).
local function body(p)
  local a = read_u32(p + 0x570); if a == 0 then return nil end
  local b = read_u32(a + 0x08); if b == 0 then return nil end
  local c = read_u32(b + 0x40); if c == 0 then return nil end
  local rb = read_u32(c + 0x18); if rb == 0 then return nil end
  return rb
end
local run_last = nil
local function run_boost(p, v)
  local rb = (v == 0) and body(p)
  if not rb or F.on("noclip") then run_last = nil return end
  local x, z = read_f32(rb + 0x30), read_f32(rb + 0x38)
  if run_last then
    local dx, dz = x - run_last[1], z - run_last[2]
    local step = math.sqrt(dx * dx + dz * dz)
    -- (walking pace and teleports are left alone)
    if step > 0.03 and step < 1.0 then
      local k = (F.items.run_speed.v or 1) - 1
      x, z = x + dx * k, z + dz * k
      write_f32(rb + 0x30, x); write_f32(rb + 0x38, z)
    end
  end
  run_last = { x, z }
end

-- ---------------------------------------------------------------- rows
function M.setup(features)
  F = features
  local fmtx, fmtint = F.fmtx, F.fmtint

  -- Districts: { "District" } rows, Whole city first.
  local DATA = F.data("hoods")
  local by_district, order = {}, {}
  for _, h in ipairs(DATA) do
    if h[2] ~= "" and h[2] ~= "Ocean" then
      if not by_district[h[2]] then by_district[h[2]] = {}; order[#order + 1] = h[2] end
      table.insert(by_district[h[2]], h[1])
    end
  end
  table.sort(order)
  HOODS = { { false, "Whole city" } }
  for _, d in ipairs(order) do HOODS[#HOODS + 1] = { d, d } end

  F.add_rows("Player", nil, {
    { id = "no_regen", label = "No health regen", kind = "toggle", v = S("no_health_regen", false),
      help = "Your health no longer comes back on its own: eat, drink or call 911.",
      update = function(ctx, p) if (read_u32(p + 0x110C) & 0x04) == 0 then wml.callx(0x009694A0, { edi = p }, 1) end end,
      off = function(ctx, p) wml.callx(0x009694A0, { edi = p }, 0) end },
    { id = "fall_damage", label = "Fall damage", kind = "value", needs = "none", default = 0.2, min = 0, max = 1, step = 0.05,
      fmt = function(v) return string.format("%.2f", v) end,
      help = "How much health a hard landing costs per metre (game: 0.20). 0 = none.",
      update = function(ctx, p, v, it) hold("fall_damage", 0x02797BC8, "f32", it.v) end,
      off = function() release("fall_damage") end },
    { id = "landing", label = "Soft landing", kind = "toggle", v = S("soft_landing", false),
      help = "Falls never hurt or stagger you.",
      update = function(ctx, p) hold("landing", p + 0x18B4, "f32", 0.0); hold("landing", 0x02797400, "f32", 100) end,
      off = function() release("landing") end },
    { id = "sprint_preset", label = "Sprint", kind = "value", needs = "none", default = 1, min = 1, max = #SPRINT_PRESETS, step = 1,
      v = S("sprint_preset", 1), fmt = function(v) return SPRINT_PRESETS[v] and SPRINT_PRESETS[v][1] or "?" end,
      help = "How long you can sprint: the game's own (10 s), Multiplayer (3 s), Pimp (2 s) or Short (1 s). Infinite sprint overrides it.",
      update = function(ctx, p, v, it)
        local pr = SPRINT_PRESETS[it.v]
        hold("sprint_preset", 0x021F2A94, "u32", pr[2] * 1000)
        hold("sprint_preset", 0x021F2A8C, "u32", pr[3] * 1000)
        hold("sprint_preset", 0x021F2A88, "u32", pr[4] * 1000)
      end,
      off = function() release("sprint_preset") end },
    { id = "run", label = "Run boost", kind = "toggle", v = S("run_boost", false),
      help = "Run and sprint faster: set the speed below. Experimental: a very high speed can push you into walls.",
      update = function(ctx, p, v) run_boost(p, v) end,
      off = function() run_last = nil end },
    { id = "run_speed", label = "Run speed", kind = "value", default = 1.0, min = 1, max = 6, step = 0.25, fmt = fmtx, oneshot = true,
      v = S("run_speed_multiplier", 1.5), help = "How much faster Run boost makes you." },
    { id = "sprint", label = "Infinite sprint", kind = "toggle", needs = "none", v = S("infinite_sprint", false),
      help = "Sprint without running out (the game's own unlimited sprint reward, kept while on).",
      update = function() hold("sprint", 0x025297E4, "u32", 3) end,
      off = function() release("sprint") end },
  })

  F.add_rows("Weapons", nil, {
    gun_row("infinite_ammo", "Infinite ammo", "The gun in your hand never runs out (and everyone's of the same kind).",
      function(rec) hold("infinite_ammo", rec + 0x10, "u32", read_u32(rec + 0x10) | 0x08) end),
    gun_row("no_reload", "No reload", "The gun in your hand never needs reloading (and everyone's of the same kind).",
      function(rec) hold("no_reload", rec + 0x10, "u32", read_u32(rec + 0x10) | 0x40) end),
    gun_row("fire", "Rapid fire", "The gun in your hand fires as fast as it can (everyone's of the same kind too).",
      function(rec) hold("fire", rec + 0xEE, "u16", 30) end),
    gun_row("one_hit", "One-hit kill", "The gun in your hand kills people in one hit (everyone's of the same kind too).",
      function(rec) hold("one_hit", rec + 0x108, "f32", 100000); hold("one_hit", rec + 0x114, "f32", 100000) end),
    gun_row("harder_hits", "Heavy knockback", "Shots knock people down and throw them further.",
      function(rec) hold("harder_hits", rec + 0x228, "f32", read_f32(rec + 0x228) * 8) end),
    blast_row("rocket_ammo", "Rocket ammo", "The gun in your hand blows up what it hits, like a rocket. Experimental. The blast can hurt you up close.",
      "rpg_launcher"),
    { id = "fire_ammo", label = "Fire ammo", kind = "toggle",
      help = "People damaged by your weapon catch fire.",
      change = function()
        if F.items.fire_ammo.v and (not wml.fire_hits or wml.fire_hits(false) == nil) then
          F.items.fire_ammo.v = false
          return "Native weapon damage events are unavailable in this game build"
        end
      end },
    blast_row("explosive_punch", "Explosive melee", "Hits with the melee weapon in your hand blow up whoever or whatever you hit. Experimental.",
      function() return PUNCH_BLAST[F.items.punch_blast.v][1] end),
    { id = "punch_blast", label = "Melee blast", kind = "choice", needs = "none", options = { "Small", "Grenade", "Rocket", "Huge" }, v = 2,
      hidden = function() return not F.items.explosive_punch.v end,
      help = "How big the explosive melee blast is (from the next weapon you switch to)." },
  })

  local god_on, god_off = car_switch("veh_god", VEH_INVULNERABLE)
  local tank_on, tank_off = car_switch("tank", VEH_HEAVY)
  local speed_cars = {}
  F.add_rows("Vehicles", nil, {
    { id = "veh_god", label = "Vehicle god mode", kind = "toggle", needs = "vehicle", every = 10,
      help = "The vehicle you're in can't be damaged, and stays repaired.",
      update = function(ctx, p)
        god_on(ctx, p)
        local veh = vehicle(p)
        if veh and read_u32(veh + 0x8C28) < read_u32(veh + 0x8C24) then repair(veh) end
      end,
      off = function() god_off() end },
    { id = "veh_repair", label = "Repair vehicle", kind = "action", needs = "vehicle", help = "Fixes the vehicle you're in.",
      run = function(ctx, p)
        local veh = vehicle(p)
        if veh then repair(veh) end
        G.vehicle_lua("vehicle_repair(v, 1.0)")
        return "Repaired"
      end },
    { id = "tank", label = "Tank mode", kind = "toggle", needs = "vehicle", every = 10,
      help = "The vehicle you drive is immovable in collisions: you bulldoze traffic.",
      update = tank_on, off = tank_off },
    { id = "max_speed", label = "Extra top speed (mph)", kind = "value", needs = "vehicle", default = 0, min = 0, max = 250, step = 10,
      fmt = function(v) return v == 0 and "game's" or string.format("%d", v) end, every = 30,
      help = "The top speed of the vehicle you drive, in mph (0 = the game's own). Above 100 the engine may not get there.",
      update = function(ctx, p, v, it)
        local veh = vehicle(p)
        if veh then speed_cars[veh] = true; write_f32(veh + 0x9540, it.v * 0.44704) end
      end,
      off = function()
        for veh in pairs(speed_cars) do pcall(write_f32, veh + 0x9540, -1.0) end
        speed_cars = {}
      end },
    { id = "acceleration", label = "Acceleration", kind = "value", needs = "none", default = 1.0, min = 1.0, max = 4.0, step = 0.25, fmt = fmtx,
      help = "Engine power for every vehicle (x1 = the game's own).",
      update = function(ctx, p, v, it)
        local own = original("acceleration", 0x027973E4) or read_f32(0x027973E4)
        hold("acceleration", 0x027973E4, "f32", own * it.v)
      end,
      off = function() release("acceleration") end },
    { id = "car_grip", label = "Extra car grip", kind = "toggle", needs = "none",
      help = "Keeps vehicles planted at high speed: more tyre grip. Experimental: from vehicles spawned after you switch it on.",
      update = function()
        if held.car_grip then return end
        each_vehicle_info(function(info)
          local axles = read_u32(info + 0x2F0)
          if axles > 4 then return end
          for i = 0, axles - 1 do
            local a = info + 0x2F4 + i * 0x38
            hold("car_grip", a + 0x0C, "f32", read_f32(a + 0x0C) * 1.5)
            hold("car_grip", a + 0x14, "f32", read_f32(a + 0x14) * 1.5)
          end
        end)
      end,
      off = function() release("car_grip") end },
    { id = "nitro_all", label = "Nitrous in every vehicle", kind = "toggle", needs = "none",
      help = "Every vehicle model can use nitrous. Experimental: from vehicles spawned after you switch it on.",
      update = function()
        if held.nitro_all then return end
        each_vehicle_info(function(info) hold("nitro_all", info + 0x5B0, "u8", read_u8(info + 0x5B0) | 0x02) end)
      end,
      off = function() release("nitro_all") end },
  })

  F.add_rows("World", nil, {
    { id = "kill_all", label = "Kill Everyone", kind = "action",
      help = "Everyone around you dies.",
      run = function() local n = each_npc(function(h) set_hp(h, 0) end) return "Killed " .. n end },
    { id = "gravity", label = "Gravity", kind = "value", needs = "none", default = 1.0, min = 0.1, max = 2.0, step = 0.1, fmt = fmtx,
      help = "How hard everything falls (x1 = the game's own; the low gravity cheat is x0.25). You jump higher with less.",
      update = function(ctx, p, v, it)
        local g = read_u32(0x02527D94)
        if g ~= 0 then hold("gravity", g + 0x14, "f32", -9.8 * it.v) end
      end,
      off = function() release("gravity") end },
    { id = "game_speed", label = "Game speed", kind = "value", needs = "none", default = 1.0, min = 0.1, max = 2.0, step = 0.1, fmt = fmtx,
      help = "Slow motion (below x1) or fast forward, for the whole world.",
      update = function(ctx, p, v, it) hold("game_speed", 0x00E8438C, "f32", 1.0 / it.v) end,
      off = function() release("game_speed") end },
    { id = "district", label = "District", kind = "list", needs = "player", items = HOODS, nosave = true,
      help = "Pick a district (or the whole city), then its owner below and Apply." },
    { id = "district_owner", label = "Owner", kind = "choice", needs = "player", options = (function()
        local o = {} for i, w in ipairs(OWNERS) do o[i] = w[2] end return o end)(), nosave = true,
      help = "Who the district goes to." },
    { id = "district_apply", label = "Apply", kind = "action",
      help = "Hands the district to that owner (the map follows).",
      run = function()
        local pick = F.items.district.items[F.items.district.v]
        local owner = OWNERS[F.items.district_owner.v]
        local names = {}
        if pick[1] then names = by_district[pick[1]] or {}
        else for _, h in ipairs(DATA) do names[#names + 1] = h[1] end end
        local n = 0
        for _, name in ipairs(names) do
          local r = hood_record(name)
          if r and (read_u8(r + 0x58) & 0x02) == 0 then
            write_u32(r + 0x4C, owner[1] >= 0 and owner[1] or read_u32(r + 0x50)); n = n + 1
          end
        end
        return string.format("%s: %s (%d neighbourhoods)", pick[2], owner[2], n)
      end },
    { id = "explore_map", label = "Reveal the whole map", kind = "action",
      help = "Every neighbourhood explored on the map.",
      run = function()
        local base, n = read_u32(0x02526C94), read_u32(0x02526C90)
        if base == 0 then return "No map yet" end
        for i = 0, n - 1 do wml.callx(0x004B1750, { ecx = base + i * 0xA8 }, 0) end
        return "Map revealed"
      end },
  })

  F.add_rows("Visual", nil, {
    { id = "freeze_world", label = "Freeze world", kind = "toggle", needs = "none",
      help = "Pauses the world while the menu or the free camera is in use (as SR1's Freeze World).",
      update = function()
        local FC = require("freecam")
        if F.menu_open() or FC.flying() then hold("freeze_world", 0x00E8438C, "f32", 1000.0) else release("freeze_world") end
      end,
      off = function() release("freeze_world") end },
  })

  -- The rewards' damage resistances (bullet, explosion, vehicle, fire): the
  -- incoming damage multiplier, 0 = none. They're saved with your game, so a
  -- save made while one is on keeps it until you switch it off again.
  local function resist_row(id, label, src, what)
    return { id = id, label = label, kind = "toggle",
      help = what .. " can't hurt you. Saving while it's on keeps it in that save until you switch it off.",
      update = function(ctx, p) hold(id, p + 0x188C + 4 * src, "f32", 0.0) end,
      off = function() release(id) end }
  end
  F.add_rows("Settings", nil, {
    resist_row("reward_bulletproof", "Bulletproof", 0, "Bullets"),
    resist_row("reward_blastproof", "Explosion-proof", 1, "Explosions"),
    resist_row("reward_crashproof", "Crash-proof", 2, "Being hit by vehicles"),
    resist_row("reward_fireproof", "Fireproof", 3, "Fire"),
  })
  -- Fire ammo uses the same configured damage per second and burn update
  -- as native fire. 0x98E2A0 selects these tuning values; 0x54D451 names
  -- the single-player value Fire_Damage_Per_second. The ignition argument
  -- is DPS, not duration. Do not add a second, guessed health drain.
  local function lookup(handle)
    local victim = read_u32(0x02149C64 + (handle & 0xFFF) * 16)
    if victim ~= 0 and read_u32(victim + 0x44) == handle then return victim end
  end
  F.after_updates[#F.after_updates + 1] = function(p)
    if not wml.fire_hits then return end
    local enabled = p ~= 0 and F.on("fire_ammo") and not F.menu_open()
    for _, handle in ipairs(wml.fire_hits(enabled) or {}) do
      local victim = lookup(handle)
      if enabled and victim and victim ~= p
        and read_u32(victim + 0x4C) == 1 and read_f32(victim + 0x1124) > 0
        and (read_u32(victim + 0xC0) & 0x400) == 0 then
        local address = 0x0279748C
        if read_u8(0x02528B48) == 1 and read_u8(0x02528B49) == 0 then address = 0x0279749C end
        local dps = read_f32(address)
        if dps == dps and dps > 0 and dps < math.huge then
          wml.callx(0x0098D3C0, { ecx = p }, victim, wml.f2u(dps), 0, 0, 0)
        end
      end
    end
  end
end

return M

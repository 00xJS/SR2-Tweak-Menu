-- SR Tweak Menu (Saints Row 2) - things the game hands out: cash and weapon
-- pickups (drops, money rain, the money gun), the cash people drop, the
-- garage, quick save, unlocks and rewards, and what gangs carry and drive.
-- Addresses and conventions were read in the game's code.

local G = require("game")
local read_u8, read_u16, read_u32, read_f32 = wml.read_u8, wml.read_u16, wml.read_u32, wml.read_f32
local write_u8, write_u16, write_u32, write_f32 = wml.write_u8, wml.write_u16, wml.write_u32, wml.write_f32
local S = wml.setting

local I = {}
local F

-- ---------------------------------------------------------------- kept values
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
  for addr, v in pairs(held[key] or {}) do pcall(WRITE[v[1]], addr, v[2]) end
  held[key] = nil
end

-- ---------------------------------------------------------------- pickups
local function vec3(slot, x, y, z)
  local b = wml.buffer(slot)
  write_f32(b, x); write_f32(b + 4, y); write_f32(b + 8, z)
  return b
end
-- A cash bill of `dollars` at x, y, z (the game's own drop, 0x00931F20);
-- `pop` throws it up a little. Returns the item.
local function spawn_cash(p, x, y, z, dollars, pop)
  return wml.callx(0x00931F20, { eax = vec3(6, x, y, z), edx = p + 0x20 },
    wml.f2u(dollars), 1, read_u16(p + 0x48), pop and 0 or 1)
end
-- A weapon pickup by xtbl name, with the game's own ammo amount.
local function spawn_weapon(p, name, x, y, z)
  local rec = wml.call(0x00B716E0, wml.buffer(7, name))
  if rec == 0 then return 0 end
  local info = read_u32(rec + 0x40)
  if info == 0 then return 0 end
  local prm = wml.buffer(8)
  wml.callx(0x005918B0, { eax = prm, ecx = vec3(6, x, y, z) }, info, p + 0x20, read_u16(p + 0x48))
  write_u8(prm, 0x49)
  return wml.callx(0x00931140, { edx = prm, ecx = 0 }, 0)
end
local function around(p, r)
  local a, d = math.random() * 2 * math.pi, r * (0.4 + 0.6 * math.random())
  return read_f32(p + 0x14) + d * math.cos(a), read_f32(p + 0x18) + 0.5, read_f32(p + 0x1C) + d * math.sin(a)
end
local function bill(v) return v > 0 and v or math.random(10, 500) end

-- ---------------------------------------------------------------- money gun
-- The game's own per-shot event (on_weapon_fired, as its missions use)
-- counts your shots in the game's Lua; each new shot throws a bill from your
-- hand the way the camera faces. (SR2 keeps no "where the bullet hit".)
local shots_seen, gun_armed_at = nil, -1000
local function money_gun(p, dollars)
  if F.tick - gun_armed_at > 300 then   -- (missions can clear the event: set it again now and then)
    gun_armed_at = F.tick
    G.lua('if not rawget(_G, "tweak_on_fire") then rawset(_G, "tweak_on_fire", function() '
      .. 'rawset(_G, "TWEAK_SHOTS", (rawget(_G, "TWEAK_SHOTS") or 0) + 1) end) end on_weapon_fired("tweak_on_fire", LOCAL_PLAYER)')
  end
  local _, n = wml.script('tweak_out(rawget(_G, "TWEAK_SHOTS") or 0)')
  n = tonumber(n) or 0
  if shots_seen == nil or n < shots_seen then shots_seen = n end
  if n == shots_seen then return end
  shots_seen = n
  local fx, fy, fz = read_f32(0x025F5B50), read_f32(0x025F5B54), read_f32(0x025F5B58)
  local it = spawn_cash(p, read_f32(p + 0x14) + fx, read_f32(p + 0x18) + 1.4, read_f32(p + 0x1C) + fz, dollars, false)
  if it ~= 0 then
    local body = read_u32(it + 0x7C)
    wml.callx(0x006FC9E0, { ecx = body }, vec3(9, fx * 25, fy * 25 + 2, fz * 25))
  end
end

-- ---------------------------------------------------------------- garage
-- A car spawned by name is added to your garage the next update, then the
-- one in the street goes (as the game's vehicle rewards do).
local garage_pending
local function garage_add(h) return (wml.callx(0x00555610, { eax = h }, 0, 0x014099B0, wml.f2u(0.0)) & 0xFF) == 1 end
local function garage_tick()
  if not garage_pending then return end
  local h = garage_pending
  garage_pending = nil
  local v = read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if v ~= 0 and read_u32(v + 0x44) == h and garage_add(h) then
    wml.callx(read_u32(read_u32(v) + 0x10), { ecx = v }, 0)
    write_u32(0x0252A0E0, 0)
  end
end

-- ---------------------------------------------------------------- quick save
-- The slot last used in the save menu if there is one (as the pause menu's
-- Save does), else the autosave.
local saving
local function cstr(a, max)
  local t = {}
  for i = 0, max do local c = read_u8(a + i); if c == 0 then break end t[#t + 1] = string.char(c) end
  return table.concat(t)
end
local function quick_save()
  if read_u8(0x02527BD2) ~= 0 then return "Already saving" end
  if cstr(0x01F7A9C0, 260) ~= "" then wml.call(0x00695A60, 0x01F7A9C0, 0, 0); saving = "manual"
  else wml.call(0x00696090); saving = "auto" end
  return "Saving"
end
local function save_tick()
  if saving == "manual" and read_u8(0x02527BD2) == 1 and read_u8(0x02527BDB) == 0 then wml.call(0x00696120) end
  if saving and read_u8(0x02527BD2) == 0 then saving = nil end
end

-- ---------------------------------------------------------------- unlocks
-- The game's unlockables: queued (7 at a time) and applied by the game as it
-- would a reward; saved with your game.
local unlock_todo = {}
local function unlocks_each(fn)
  local base, n = read_u32(0x006BC809), read_u32(0x0145A29C)
  if base == 0 or n > 2000 then return end
  for i = 0, n - 1 do fn(base + i * 0xD0) end
end
local function unlock_types(types)
  local n = 0
  unlocks_each(function(r)
    if read_u8(r + 0xC4) == 0 and types[read_u32(r + 4)] then unlock_todo[#unlock_todo + 1] = r; n = n + 1 end
  end)
  return n
end
local function unlock_names(names)
  local n = 0
  for _, name in ipairs(names) do
    local r = wml.callx(0x006BC860, { ecx = wml.buffer(7, name) })
    if r ~= 0 and read_u8(r + 0xC4) == 0 then unlock_todo[#unlock_todo + 1] = r; n = n + 1 end
  end
  return n
end
local function unlock_tick()
  while #unlock_todo > 0 and read_u32(0x01459A5C) < 7 do
    local r = table.remove(unlock_todo, 1)
    if read_u8(r + 0xC4) == 0 then wml.callx(0x006BC8A0, { ecx = r }) end
  end
end

-- ---------------------------------------------------------------- rows
function I.setup(features)
  F = features
  local fmtint = F.fmtint
  local function dollars(v) return v == 0 and "Random" or ("$" .. v) end

  local WEAPONS = F.data("weapons")
  local weapon_items = { { "random", "Random mix" } }
  for _, w in ipairs(WEAPONS) do weapon_items[#weapon_items + 1] = { w[1], w[2] } end
  local VEHICLES = F.data("vehicles")
  local vehicle_items = {}
  for _, v in ipairs(VEHICLES) do vehicle_items[#vehicle_items + 1] = { v[1], v[2] } end
  table.sort(vehicle_items, function(a, b) return a[2]:lower() < b[2]:lower() end)

  F.add_rows("World", nil, {
    { id = "cash_rain", label = "Drop cash around me", kind = "action",
      help = "Scatters 10 bills of $10 to $500 on the ground around you.",
      run = function(ctx, p)
        for _ = 1, 10 do local x, y, z = around(p, 3); spawn_cash(p, x, y, z, math.random(10, 500), true) end
        return "Cash!"
      end },
    { id = "money_rain", label = "Money rain", kind = "toggle",
      help = "Cash falls around you as you walk: pick it up as you go. On foot only.",
      update = function(ctx, p, v)
        if v ~= 0 then return end
        local every = math.max(1, math.floor(60 / (F.items.money_rain_rate.v or 3)))
        if F.tick % every ~= 0 then return end
        local x, y, z = around(p, 4)
        spawn_cash(p, x, y + 6, z, bill(F.items.money_rain_bill.v or 0), false)
      end },
    { id = "money_rain_rate", label = "Money rain: bills a second", kind = "value", needs = "none", default = 3, min = 1, max = 10,
      step = 1, fmt = fmtint, oneshot = true, help = "How many bills fall each second." },
    { id = "money_rain_bill", label = "Money rain: bill", kind = "value", needs = "none", default = 0, min = 0, max = 1000, step = 50,
      fmt = dollars, oneshot = true, help = "How much each bill is worth (Random: $10 to $500)." },
    { id = "weapon_rain", label = "Drop weapons around me", kind = "list", items = weapon_items, nosave = true,
      help = "Drops 6 of the picked weapon, or a random mix, on the ground around you.",
      run = function(ctx, p, v, it)
        local pick, n = it.items[it.v][1], 0
        for _ = 1, 6 do
          local name = pick == "random" and weapon_items[math.random(2, #weapon_items)][1] or pick
          local x, y, z = around(p, 3)
          if spawn_weapon(p, name, x, y, z) ~= 0 then n = n + 1 end
        end
        return n > 0 and ("Dropped " .. n) or "That one has no pickup"
      end },
    { id = "cash_drop_chance", label = "Cash drop chance", kind = "value", needs = "none", default = 25, min = 0, max = 100, step = 5,
      fmt = function(v) return v .. "%" end,
      help = "How often people and gang members drop cash when they die. The game's own is 25%.",
      update = function(ctx, p, v, it)
        hold("cash_drop", 0x0279770C, "f32", it.v / 100); hold("cash_drop", 0x02797710, "f32", it.v / 100)
      end,
      off = function() release("cash_drop") end },
    { id = "no_guns", label = "Gangs and police without guns", kind = "toggle", needs = "none",
      help = "Gang members and police come at you with bats, knives and nightsticks. People already out keep what they have.",
      update = function()
        if held.no_guns then return end
        local n = read_u32(0x02526C78)
        if n > 200 then return end
        for i = 0, n - 1 do
          local r = 0x00F60D90 + i * 0x674
          for _, team in ipairs({ 1, 2, 3, 5, 6 }) do
            for _, cat in ipairs({ 1, 2 }) do hold("no_guns", r + 0x14 + team * 0xCC + cat * 0x44, "u8", 0) end
          end
        end
      end,
      off = function() release("no_guns") end },
    { id = "gang_civ_cars", label = "Gangs drive ordinary cars", kind = "toggle", needs = "none",
      help = "Gang members drive ordinary cars, not their gang rides. Cars already on the road keep theirs.",
      update = function()
        if held.gang_civ_cars then return end
        local b, n = read_u32(0x02526C6C), read_u32(0x02526C68)
        if b == 0 or n > 1000 then return end
        local civ
        for i = 0, n - 1 do
          local g = b + i * 0x34
          if read_u32(g + 8) == 7 and read_u32(g + 0x1C) >= 4 then civ = g break end
        end
        if not civ then return end
        for i = 0, n - 1 do
          local g = b + i * 0x34
          local team = read_u32(g + 8)
          if team >= 1 and team <= 3 then
            hold("gang_civ_cars", g + 0x1C, "u32", read_u32(civ + 0x1C))
            hold("gang_civ_cars", g + 0x20, "u32", read_u32(civ + 0x20))
            hold("gang_civ_cars", g + 0x24, "u32", read_u32(civ + 0x24))
          end
        end
      end,
      off = function() release("gang_civ_cars") end },
  })

  F.add_rows("Weapons", nil, {
    { id = "money_gun", label = "Money gun", kind = "toggle",
      help = "Every shot throws a bill the way you aim; pick them up after. Experimental.",
      update = function(ctx, p, v) if v == 0 then money_gun(p, F.items.money_gun_cash.v or 100) end end,
      off = function() shots_seen = nil end },
    { id = "money_gun_cash", label = "Money gun bill ($)", kind = "value", needs = "none", default = 100, min = 100, max = 10000, step = 100,
      fmt = fmtint, oneshot = true, help = "How many dollars each bill from the money gun is worth. Default 100." },
  })

  F.add_rows("Vehicles", nil, {
    { id = "garage", label = "Deliver to garage", kind = "list", items = vehicle_items, nosave = true,
      help = "Adds the selected vehicle to your garage.",
      run = function()
        local it = F.items.garage
        local idx = wml.callx(0x00AE4090, { ecx = wml.buffer(7, it.items[it.v][1]) })
        if idx == 0xFFFFFFFF then return "The game doesn't know that one" end
        if read_u32(0x022A84D0) == 0 then return "Too many vehicles about: try again elsewhere" end
        wml.call(0x00AE4AE0, idx)
        garage_pending = read_u32(0x0252A0E0)
        return "Delivered: " .. it.items[it.v][2]
      end },
    { id = "garage_this", label = "Store this car in the garage", kind = "action", needs = "vehicle",
      help = "Adds the vehicle you're in to your garage (it stays with you).",
      run = function(ctx, p)
        return garage_add(read_u32(p + 0xD74)) and "Stored in your garage" or "The game won't store this one"
      end },
  })

  local save_key = tostring(S("quick_save_key", "F9"))
  F.add_rows("Settings", nil, {
    { id = "unlock_music", label = "Unlock all music", kind = "action",
      help = "Every song in the music store, ready for your playlists.",
      run = function()
        local g, n = read_u32(0x01F99BF8), read_u32(0x01F91BF4)
        if g == 0 or n > 500 then return "No music list yet" end
        local songs = 0
        for i = 0, n - 1 do
          local t, c = read_u32(g + i * 12 + 4), read_u32(g + i * 12 + 8)
          for j = 0, c - 1 do write_u32(t + j * 0x2C + 0x14, 2); songs = songs + 1 end
        end
        return "Unlocked " .. songs .. " songs"
      end },
    { id = "unlock_collectibles", label = "Unlock all collectibles", kind = "action",
      help = "Every bonus song and the discount the hidden CDs unlock (the CDs themselves stay to find).",
      run = function() return "Unlocking " .. unlock_names({ "Diversion_CD1", "Diversion_CD2", "Diversion_CD3", "Diversion_CD4", "Diversion_CD5" }) end },
    { id = "unlock_clothing", label = "Unlock all clothing", kind = "action",
      help = "Every clothing reward added to your wardrobe.",
      run = function() return "Unlocking " .. unlock_types({ [8] = true }) end },
    { id = "unlock_reward_clothing", label = "Unlock reward clothing", kind = "action",
      help = "The outfits activities give as rewards, now.",
      run = function() return "Unlocking " .. unlock_types({ [26] = true }) end },
    { id = "crib_ammo", label = "Unlimited crib ammo", kind = "action",
      help = "Every crib's weapon locker refills your ammo for good (the activity rewards).",
      run = function() return "Unlocking " .. unlock_names({ "Drug_1_whole", "FUZZ_1_whole", "Snatch_2_whole", "Diversion_Hitman_ALL" }) end },
    { id = "reward_free_shopping", label = "Free shopping", kind = "toggle",
      help = "Everything in every store is free. Saving while it's on keeps it in that save until you switch it off.",
      update = function()
        local n = read_u32(0x01F99C80)
        if n > 400 then return end
        for i = 0, n - 1 do hold("free_shopping", 0x029E8468 + i * 0x30 + 0x0C, "f32", 1.0) end
        write_f32(0x025287F0, 1.0)
      end,
      off = function() release("free_shopping") write_f32(0x025287F0, 0) end },
    { id = "reward_police_forget", label = "Police forget fast", kind = "toggle",
      help = "Police notoriety fades almost at once. Saving while it's on keeps it in that save until you switch it off.",
      update = function() hold("police_forget", 0x01409B10 + 3 * 4, "f32", 10.0) end,
      off = function() release("police_forget") end },
    { id = "reward_gangs_forget", label = "Gangs forget fast", kind = "toggle",
      help = "Every gang's notoriety fades almost at once. Saving while it's on keeps it in that save until you switch it off.",
      update = function() for i = 0, 2 do hold("gangs_forget", 0x01409B10 + i * 4, "f32", 10.0) end end,
      off = function() release("gangs_forget") end },
    { id = "quick_save", label = "Quick save (" .. (save_key ~= "" and save_key or "no key") .. ")", kind = "toggle",
      v = S("quick_save", false),
      help = "Press " .. (save_key ~= "" and save_key or "the quick_save_key in mod.ini") .. " to save at once: the slot you last saved to, or the autosave.",
      update = function() if save_key ~= "" and wml.key_pressed(save_key) and not F.menu_open() then quick_save() end end },
  })
end

-- Every frame.
function I.after_update(p)
  garage_tick()
  save_tick()
  unlock_tick()
end

return I

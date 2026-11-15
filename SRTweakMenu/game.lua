-- SR Tweak Menu (Saints Row 2) - the game: addresses and the calls the
-- menu makes, for the PC build Juiced Patch supports (Steam/GOG). SR1's
-- game.lua has the same names for the Xbox 360 recompilation.
--
-- SR2 runs most of its gameplay from its own Lua 5.0 (the mission scripts):
-- G.lua runs a line of it, and the game's script functions (cash_add,
-- turn_invulnerable, teleport...) do the work wherever they can. Its
-- interface Lua ("vint": HUD, menus, the phone) holds the phone's cheats.
-- Addresses are for what neither can reach.

local read_u8, read_u32, read_f32 = wml.read_u8, wml.read_u32, wml.read_f32

local G = {}

G.PLAYER       = 0x021703D4  -- the local player's object (0 when none)
G.GAME_LOADED  = 0x00E94D3E  -- u8: 1 once a game is running
G.GAMEMODE     = 0x00E8B210  -- s8: -1 in single player and co-op story
G.IN_CUTSCENE  = 0x02527D14  -- u8
G.WAYPOINT_SET = 0x01F7A418  -- u32: non-zero while a map waypoint is set
G.WAYPOINT_POS = 0x029B9CD0  -- 3 floats: the waypoint
G.TELEPORT_POS = 0x027B305A  -- 3 floats (unaligned): where G.TELEPORT puts the player
G.TELEPORT     = 0x009D3C50  -- cdecl, no arguments: moves the player (or their car) there

-- Offsets in an object (the player is one).
G.P = {
  POS = 0x14,     -- 3 floats
  ORIENT = 0x20,  -- 3x3 floats
}

-- Notoriety teams, as the mission scripts name them.
G.TEAMS = { police = "Police", brotherhood = "Brotherhood", ronin = "Ronin", samedi = "Samedi", ultor = "Ultor" }
G.GANGS = { "Brotherhood", "Ronin", "Samedi", "Ultor" }

G.debug = false

function G.vec(a) return read_f32(a), read_f32(a + 4), read_f32(a + 8) end

-- The player's object, or 0 outside a single-player (or co-op) game.
function G.player()
  if read_u8(G.GAME_LOADED) ~= 1 then return 0 end
  if read_u8(G.GAMEMODE) ~= 0xFF then return 0 end
  return read_u32(G.PLAYER)
end

function G.in_cutscene() return read_u8(G.IN_CUTSCENE) ~= 0 end

-- On foot and in control: a player, no cutscene, not in a vehicle (SR1's
-- G.playing, for the menu's hold-Back toggle).
function G.playing(p)
  if not p or p == 0 then return false end
  if G.in_cutscene() then return false end
  return G.vehicle_handle(p) == nil
end

-- The handle of the vehicle the player is in, or nil on foot.
G.P.VEHICLE = 0xD74
function G.vehicle_handle(p)
  if p == 0 then return nil end
  local h = read_u32(p + G.P.VEHICLE)
  if h == 0 or h == 0xFFFFFFFF then return nil end
  return h
end

-- Runs Lua on the game's own state (its mission-script functions). `ctx`
-- is SR1's hook context, kept so rows read the same; SR2 doesn't need it.
function G.script(ctx, code)
  if G.debug then wml.log("script: " .. code) end
  return wml.script(code)
end

-- G.lua(fmt, ...): the same, formatted; strings are passed as Lua strings
-- (%q), numbers as they are. Use %s for every argument.
local function lit(v)
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) == "boolean" or v == nil then return tostring(v) end
  if math.type(v) == "integer" then return tostring(v) end
  return string.format("%.4f", v)
end
-- The code can keep values between calls in the table T (TWEAK in the
-- game's globals): the game guards its globals, so new names can't be
-- made with a plain assignment.
local PRELUDE = 'local T = rawget(_G, "TWEAK") if not T then T = {} rawset(_G, "TWEAK", T) end '
function G.lua(fmt, ...)
  local args = table.pack(...)
  for i = 1, args.n do args[i] = lit(args[i]) end
  local code = string.format(fmt, table.unpack(args, 1, args.n))
  if code:find("T%.") then code = PRELUDE .. code end
  return G.script(nil, code)
end

-- Runs code with `v` set to the name of the vehicle the player is in (it
-- does nothing on foot).
function G.vehicle_lua(fmt, ...)
  return G.lua('local v = get_char_vehicle_name(LOCAL_PLAYER) if v and v ~= "" then ' .. fmt .. ' end', ...)
end

-- The interface's Lua (the phone, the HUD).
function G.vint(code)
  if G.debug then wml.log("vint: " .. code) end
  return wml.vint(code)
end

-- The phone's cheats, through the game's own cheat code (what dialing a
-- number and picking the cheat on the phone end up calling): a cheat is
-- unlocked by its number (it then shows on the phone too) and switched by
-- its slot in the save's list of unlocked cheats. Cheats mark the save as
-- cheated, as on the phone.
G.CHEAT_UNLOCK = 0x00687870   -- eax = "#number" -> slot (or -1)
G.CHEAT_TOGGLE = 0x00687A00   -- eax = slot
G.CHEAT_ACTIVE = 0x006878C0   -- eax = slot -> al: on?
function G.cheat_slot(number)
  local slot = wml.callx(G.CHEAT_UNLOCK, { eax = wml.buffer(9, "#" .. tostring(number)) })
  if slot == 0xFFFFFFFF then return nil end
  return slot
end
function G.cheat_on(slot) return (wml.callx(G.CHEAT_ACTIVE, { eax = slot }) & 0xFF) ~= 0 end
-- Switches the cheat with this number on or off; returns whether it's on.
function G.cheat_set(number, on)
  local slot = G.cheat_slot(number)
  if not slot then return nil end
  if G.cheat_on(slot) ~= on then wml.callx(G.CHEAT_TOGGLE, { eax = slot }) end
  return G.cheat_on(slot)
end

-- Puts the player (and the car they're in) at x, y, z.
function G.teleport(x, y, z)
  wml.write_f32(G.TELEPORT_POS, x)
  wml.write_f32(G.TELEPORT_POS + 4, y)
  wml.write_f32(G.TELEPORT_POS + 8, z)
  wml.call(G.TELEPORT)
end

-- The waypoint set on the map, or nil.
function G.waypoint()
  if read_u32(G.WAYPOINT_SET) == 0 then return nil end
  return G.vec(G.WAYPOINT_POS)
end

-- One-line messages: the menu draws its own status line, so these only go
-- to the log (SR2 has no HUD message call wired up yet).
function G.hud(text) wml.log("hud: " .. tostring(text)) end

return G

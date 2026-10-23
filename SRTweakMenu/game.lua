-- SR Tweak Menu (Saints Row 2) - the game: addresses and the calls the
-- menu makes, for the PC build Juiced Patch supports (Steam/GOG). SR1's
-- game.lua has the same names for the Xbox 360 recompilation.
--
-- SR2 runs most of its gameplay from its own Lua 5.0 (the mission scripts):
-- G.script runs a line of it, and the game's script functions (cash_add,
-- turn_invulnerable, teleport...) do the work wherever they can. Addresses
-- are for what the scripts can't reach.

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

G.debug = false

function G.vec(a) return read_f32(a), read_f32(a + 4), read_f32(a + 8) end

-- The player's object, or 0 outside a single-player (or co-op) game.
function G.player()
  if read_u8(G.GAME_LOADED) ~= 1 then return 0 end
  if read_u8(G.GAMEMODE) ~= 0xFF then return 0 end
  return read_u32(G.PLAYER)
end

function G.in_cutscene() return read_u8(G.IN_CUTSCENE) ~= 0 end

-- Runs Lua on the game's own state (its mission-script functions). `ctx`
-- is SR1's hook context, kept so rows read the same; SR2 doesn't need it.
function G.script(ctx, code)
  if G.debug then wml.log("script: " .. code) end
  return wml.script(code)
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

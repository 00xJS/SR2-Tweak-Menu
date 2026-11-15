-- SR2 PC animation tracks. The mission wrapper action_play_do can set the
-- player's script mode to 2 even when an action fails. Play only the clip,
-- without setting a script mode, animation state override or borrowed set.
local G = require("game")
local clips = require("data.emote_clips")
local read = wml.read_u32
local call = wml.callx
local INVALID = 0xFFFFFFFF
local OVERLAY, LOOP = 0x40, 0x02
local BLEND = wml.f2u(0.1)
local ONE = wml.f2u(1)
local M = {}

local function player_animation(p)
  local owner = read(p + 0x5E0)
  if owner == 0 or owner == INVALID then return end
  local id = read(owner)
  if id >= 0x80000000 then return end
  -- Same pool lookup as action_stop_custom.
  return owner, id, 0x0340D240 + (id % 190) * 0x5E8
end

local function track_count(player)
  return math.min(read(player + 0x23C), 10)
end

local function find_track(player, field, value)
  for i = 0, track_count(player) - 1 do
    local track = player + 0x254 + i * 0x58
    if read(track + field) == value then return track end
  end
end

function M.same_actor(p, token)
  if type(token) ~= "table" or p == 0 or p ~= token.p then return false end
  if read(p + 0x44) ~= token.actor or read(p + 0xD4) ~= token.preset then return false end
  local owner, id = player_animation(p)
  return owner == token.owner and id == token.id
end

local function owned_track(p, token)
  if not M.same_actor(p, token) then return end
  local _, _, player = player_animation(p)
  local track = find_track(player, 0, token.handle >> 4)
  if track and read(track + 4) == token.file then return track, player end
end

function M.stop(p, token)
  if type(token) ~= "table" or token.external then return end
  local track, player = owned_track(p, token)
  if track then call(0x00CE72A0, { eax = token.handle }, player) end
end

function M.active(p, token)
  return owned_track(p, token) ~= nil
end

function M.can_play(p)
  if not G.playing(p) or read(p + 0x18D4) ~= 0 then return false end
  local ran, ready = G.lua("tweak_out(not character_is_dead(LOCAL_PLAYER)"
    .. " and not character_is_ragdolled(LOCAL_PLAYER))")
  return ran and ready == true
end

local function start_track(p, owner, id, player, file, loop)
  if file >= read(0x024E1864) then return end
  -- A registered clip may still be paged out. Also leave tracks that the
  -- game already started for this file under the game's ownership.
  if read(0x024F2F00 + file * 32 + 0x1C) == 0 then return end
  local existing = find_track(player, 4, file)
  if existing then
    return { p = p, actor = read(p + 0x44), preset = read(p + 0xD4), owner = owner, id = id, handle = read(existing) << 4, file = file, external = true }
  end
  local handle = call(0x00CE6D20, {}, player, file, loop and (OVERLAY | LOOP) or OVERLAY, 0, ONE, BLEND, ONE)
  if handle == INVALID then return end
  return { p = p, actor = read(p + 0x44), preset = read(p + 0xD4), owner = owner, id = id, handle = handle, file = file }
end

local function clip_file(clip)
  return call(0x00CEC2A0, { ecx = wml.buffer(14, clip .. ".anim") })
end

local function named_file(owner, action, name)
  local key = call(action and 0x006EF580 or 0x006EF510, {}, wml.buffer(14, name))
  if key == INVALID then return end
  -- A set entry is an animation definition. Its clip ID is at +0xC.
  local definition = call(action and 0x006EF6A0 or 0x006EF620, {}, owner, key, 0)
  if definition ~= 0xFFFF and definition < read(0x02527D6C) then
    return read(0x015B8800 + definition * 0x54 + 0xC)
  end
end

function M.has_state(p, name)
  if not G.playing(p) then return false end
  local owner = player_animation(p)
  local file = owner and named_file(owner, false, name)
  return file ~= nil and file < read(0x024E1864)
    and read(0x024F2F00 + file * 32 + 0x1C) ~= 0
end

-- The same on anyone (World > Everybody...): a person's own clip for the
-- state or action, else one borrowed from another human set. No checks that
-- are the player's alone.
function M.play_other(h, kind, name, loop)
  return M.play(h, kind, name, true, loop, true)
end

function M.play(p, kind, name, quiet, loop, other)
  if (kind ~= "Action" and kind ~= "State" and kind ~= "Clip") or type(name) ~= "string" or name == "" then
    return nil, "Unknown animation kind or name"
  end
  if not other and not M.can_play(p) then return nil, "Emotes need a player on foot and in control" end
  local owner, id, player = player_animation(p)
  if not player or read(player + 0x240) ~= INVALID then
    return nil, "The player is busy with another animation"
  end

  if kind == "Clip" then
    local token = start_track(p, owner, id, player, clip_file(name), loop)
    if token then return token end
    return nil, "No playable clip is loaded for this preview"
  end

  local file = named_file(owner, kind == "Action", name)
  if file then
    local token = start_track(p, owner, id, player, file, loop)
    if token then return token end
  end

  for _, clip in ipairs((clips[kind] or {})[name:lower()] or {}) do
    local file = clip_file(clip)
    -- Only registered, resident clips. Loading a borrowed file through a
    -- fabricated cutscene descriptor is not a safe general animation loader.
    local token = start_track(p, owner, id, player, file, loop)
    if token then
      if not quiet then wml.log("emote: borrowed " .. clip .. " for " .. name) end
      return token
    end
  end
  if not quiet then wml.log("emote: no playable clip for " .. name) end
  return nil, "No playable clip is loaded for this emote"
end

return M


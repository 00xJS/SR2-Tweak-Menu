-- LB kick, as Saints Row 1 has it: the game's own melee attack, asked for
-- with the attack kinds the PC controls never send.
--
-- The game's attack function 0x0097EB90(human, kind) picks the move, turns
-- the attacker, sets the lunge and starts the strike; the same call serves
-- the player's punches (kinds 1 and 2) and the NPCs' kick (kind 5, from
-- 0x00414910). Its moves come from the melee style's table (0x0215FEF8,
-- 48 bytes a style): 2 = kick1, 7-9 = prone_kick_short/med/long.
--   kind 5: the standing kick (kick1), with its step forward.
--   kind 2 with someone on the ground in reach: the prone kick, picked by
--           distance by the game (0x009CC540).
-- The move, its damage, the combo state and the end of the strike are all
-- the game's: nothing of the strike is written into the player here.
local G = require("game")
local K = { button = 0x0100 }
local ATTACK = 0x0097EB90
local FIND_TARGET, PRONE_TARGET, CAN_ATTACK = 0x00974FB0, 0x009777C0, 0x00977CB0
local KIND_SECONDARY, KIND_KICK = 2, 5
local NO_SEARCH = 0xFFFFFFFF
local last_said

local function say(text)
  if last_said == text then return end   -- (once per change, not once per press)
  last_said = text
  wml.log("kick: " .. text)
end

-- For 1.2 s after a kick: a grab (melee grapple, +0x590 == 2) the player
-- didn't ask for is ended with the game's own call (0x00993BD0(human, 0),
-- what the attack itself uses to end one), and logged.
function K.watch(p)
  if not K.until_clock or os.clock() > K.until_clock or p == 0 then K.until_clock = nil return end
  if wml.read_u8(p + 0x590) == 2 then
    local ok = pcall(wml.callx, 0x00993BD0, {}, p, 0)
    say(ok and "a grab started with the kick; ended it" or "a grab started with the kick; couldn't end it")
    K.until_clock = nil
  end
end

function K.available(p)
  return G.playing(p) and wml.read_u32(ATTACK) == 0x533CEC83
end

function K.try(p)
  -- On foot, standing, with an animation owner; never while down or dead.
  if wml.read_u32(p + 0x18D4) ~= 0 or wml.read_u8(p + 0x595) ~= 0
    or wml.read_u32(p + 0x5E0) == 0 then return end
  local _, ready = G.lua("tweak_out(not character_is_dead(LOCAL_PLAYER)"
    .. " and not character_is_ragdolled(LOCAL_PLAYER))")
  if ready ~= true then return end

  -- The melee lock field (+0xAF4): 0 = the game looks for someone in reach,
  -- -1 = it doesn't (No melee lock). The kick always looks, for this one
  -- call; the field goes back afterwards if the game left it alone.
  local lock = wml.read_u32(p + 0xAF4)
  local actor = wml.read_u32(p + 0x44)
  if lock == NO_SEARCH then wml.write_u32(p + 0xAF4, 0) end
  local ok, result = pcall(function()
    if (wml.callx(CAN_ATTACK, { esi = p }) & 0xFF) == 0 then return "not now (the game allows no melee attack)" end
    -- Not while sprinting (current state +0x1130 is the "sprint" state).
    local sprint = wml.callx(0x006EF510, {}, wml.buffer(14, "sprint"))
    if sprint ~= 0xFFFFFFFF and wml.read_u32(p + 0x1130) == sprint then return "not while sprinting" end
    -- Someone on the ground in reach gets the prone kick; anything else the
    -- standing kick. The game makes the same test inside its attack.
    local target = wml.callx(FIND_TARGET, {}, p)
    local prone = target ~= 0 and target ~= p and wml.read_u32(target + 0x4C) == 1
      and (wml.callx(PRONE_TARGET, { eax = target, ecx = p }) & 0xFF) ~= 0
    if prone then
      -- On someone down: only the prone kick. Two kicks on the same person,
      -- then the third is the long kick (prone_kick_long), started the way the
      -- game's attack starts a chosen move (0x0097EA80, then +0xB20 = kind and
      -- 0x00960A80(1, 0) with esi = the attacker, as at 0x0097EDCE).
      if K.combo and K.combo.target == target and os.clock() - K.combo.at < 3 then
        K.combo.count = K.combo.count + 1
      else
        K.combo = { target = target, count = 1 }
      end
      K.combo.at = os.clock()
      if K.combo.count >= 3 then
        K.combo = nil
        local long = wml.callx(0x00980390, { edi = wml.buffer(14, "prone_kick_long") }) & 0xFF
        if long ~= 0xFF and (wml.callx(0x0097EA80, { esi = p, edi = target }, long) & 0xFF) ~= 0 then
          wml.write_u32(p + 0xB20, KIND_SECONDARY)
          wml.callx(0x00960A80, { esi = p }, 1, 0)
          K.until_clock = os.clock() + 1.2
          return "prone kick (long, third in a row)"
        end
      end
      if (wml.callx(ATTACK, {}, p, KIND_SECONDARY) & 0xFF) == 0 then return "not now (busy with another move)" end
      K.until_clock = os.clock() + 1.2
      return "prone kick"
    end
    -- Standing: on the spot. No target search for this call (+0xAF4 = -1),
    -- so the kick neither turns to nor latches onto the person beside you -
    -- that latch was the grab the log saw start with every kick.
    wml.write_u32(p + 0xAF4, NO_SEARCH)
    if (wml.callx(ATTACK, {}, p, KIND_KICK) & 0xFF) == 0 then
      return "not now (busy with another move)"
    end
    -- The NPC kick (kind 5) aims its lunge at a point 1.0 m above the target
    -- (+0xB30 += 1.0 at 0x0097ED11): that lift is the float. The punches'
    -- path zeroes the lunge (0x0097EDA8); the kick gets the same, so it
    -- lands flat on the ground as Saints Row 1's does.
    wml.write_u32(p + 0xB2C, 0) wml.write_u32(p + 0xB30, 0) wml.write_u32(p + 0xB34, 0)
    K.until_clock = os.clock() + 1.2
    return "kick"
  end)
  -- (the lock field goes back to what it was, whichever way the call went)
  if G.player() == p and wml.read_u32(p + 0x44) == actor then wml.write_u32(p + 0xAF4, lock) end
  say(ok and result or tostring(result))
  return ok and type(result) == "string" and result:find("^kick") ~= nil or (ok and type(result) == "string" and result:find("^prone kick") ~= nil)
end

return K

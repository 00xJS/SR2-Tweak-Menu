-- SR Tweak Menu (Saints Row 2) - self-test, for development (mod.ini:
-- selftest = true). Once a game is loaded it runs every row the way the menu
-- would, without keys, and writes what happened to TweakMenu/wml.log; the
-- game's own debug_print lines go to Juiced's debug.txt. Changes it makes:
-- God mode on then off, +$50,000, and a 3 m step sideways.

local G = require("game")
local F = require("features")

local T = { done = false }
local seen, step, at = 0, 0, 0
local start

local function log(...) wml.log("selftest: " .. string.format(...)) end
local function pos(p) return G.vec(p + G.P.POS) end

function T.frame()
  if T.done then return end
  local p = G.player()
  if p == 0 then seen = 0 return end
  seen = seen + 1
  if seen < 300 then return end   -- ~5 s in game first
  at = at + 1
  if step == 0 then
    local x, y, z = pos(p)
    log("player %08X at %.2f %.2f %.2f, cutscene %s, waypoint %s", p, x, y, z, tostring(G.in_cutscene()), tostring(G.waypoint() ~= nil))
    log("game script ran: %s", tostring(G.script(nil, 'debug_print("tweak selftest: LOCAL_PLAYER = " .. tostring(LOCAL_PLAYER))')))
    log("god: %s", tostring(F.activate(nil, F.items.god)))
    step, at = 1, 0
  elseif step == 1 and at > 60 then
    log("money: %s", tostring(F.activate(nil, F.items.money)))
    start = { pos(p) }
    G.teleport(start[1] + 3, start[2], start[3])
    log("teleport asked for %.2f %.2f %.2f", start[1] + 3, start[2], start[3])
    step, at = 2, 0
  elseif step == 2 and at > 30 then
    local x, y, z = pos(p)
    log("after teleport: %.2f %.2f %.2f (moved %.2f m)", x, y, z, math.sqrt((x - start[1]) ^ 2 + (z - start[3]) ^ 2))
    log("god off: %s", tostring(F.activate(nil, F.items.god)))
    step, at = 3, 0
  elseif step == 3 and at > 30 then
    log("done")
    T.done = true
  end
end

return T

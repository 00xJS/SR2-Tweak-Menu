-- SR Tweak Menu (Saints Row 2) - Locked Cars.
--
-- SR1's Locked Cars locks the cars of the street until you break in. SR2's
-- scripts can't do that: their vehicle calls take a script name, the menu
-- has no way to name a car nobody it knows sits in, and no call refuses
-- one car to the player. What the scripts do have is the lock missions put
-- on their own cars, set_unjackable_flag(vehicle, on): nobody can be pulled
-- out of it. So this is the lock the other way round: your car is locked
-- against everybody else.
--
-- The car is known by the name get_char_vehicle_name gives while you sit in
-- it. That name is kept in the game's Lua (T.locked_car), so the car stays
-- locked after you step out and is unlocked when you take another car or
-- switch the row off.

local L = {}

-- Locks the car you're in (v); the one locked before it is let go first.
local LOCK = "if T.locked_car and T.locked_car ~= v and vehicle_exists(T.locked_car) then "
  .. "set_unjackable_flag(T.locked_car, false) end "
  .. "set_unjackable_flag(v, true) T.locked_car = v"
-- Unlocks the kept car, if the game still has it.
local UNLOCK = "if T.locked_car then local c = T.locked_car T.locked_car = nil "
  .. "if vehicle_exists(c) then set_unjackable_flag(c, false) end end"

function L.rows(F, G)
  return {
    { id = "locked_cars", label = "Locked Cars", kind = "toggle", needs = "player", every = 30,
      help = "Your car is locked: nobody can pull you out of it or take it. The last car you drove stays locked until you get into another or switch this off.",
      -- Only in a vehicle: on foot there is no name to ask for, and the car
      -- you left keeps its lock by itself.
      update = function(ctx, p)
        if G.vehicle_handle(p) then G.vehicle_lua(LOCK) end
      end,
      off = function() G.lua(UNLOCK) end },
  }
end

return L

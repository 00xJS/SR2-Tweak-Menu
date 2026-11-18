-- From the repo root: build/lua.exe tools/test_locked_cars.lua
-- Locked Cars against a fake game: the code the row sends is run in a fake
-- of the game's Lua (its script functions record what they were asked), so
-- the test sees which cars end up locked.
package.path = "SRTweakMenu/?.lua"

local mem = {}
local function rd(a, n) local v = 0 for i = n - 1, 0, -1 do v = (v << 8) | (mem[a + i] or 0) end return v end
local function wr(a, n, v) for i = 0, n - 1 do mem[a + i] = v & 0xFF; v = v >> 8 end end

-- The game's side: the car the player sits in, the cars that exist, the
-- locks, and every call made.
local seat, exists, locked, calls = "", {}, {}, {}
local game = { LOCAL_PLAYER = "#PLAYER1#", rawget = rawget, rawset = rawset }
game._G = game
function game.get_char_vehicle_name(who)
  assert(who == game.LOCAL_PLAYER)
  assert(seat ~= "", "asked for the vehicle's name on foot")
  return seat
end
function game.vehicle_exists(name) return exists[name] == true end
function game.set_unjackable_flag(name, on)
  assert(exists[name], "set_unjackable_flag on a vehicle that is gone: " .. tostring(name))
  assert(type(on) == "boolean")
  calls[#calls + 1] = name .. (on and "+" or "-")
  locked[name] = on or nil
end
-- As the game does: a new global can't be made by assignment.
setmetatable(game, { __newindex = function(_, k) error("new global " .. tostring(k)) end })

local P = 0x10000000
wml = {
  log = function() end,
  read_u8 = function(a) return rd(a, 1) end, read_u16 = function(a) return rd(a, 2) end,
  read_u32 = function(a) return rd(a, 4) end, read_f32 = function() return 0 end,
  script = function(code)
    local fn = assert(load(code, "game", "t", game))
    fn()
    return true
  end,
}
wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, P)
local function sit(name)   -- "" = on foot
  seat = name
  wr(P + 0xD74, 4, name == "" and 0 or 0x1234)
  if name ~= "" then exists[name] = true end
end
local function said() local s = table.concat(calls, " ") calls = {} return s end

local G = require("game")
local rows = require("locked_cars").rows({}, G)
assert(#rows == 1)
local row = rows[1]
assert(row.id == "locked_cars" and row.kind == "toggle" and row.label == "Locked Cars" and row.needs == "player")
assert(type(row.help) == "string" and row.every == 30)

-- On foot: nothing is asked of the game.
sit("")
row.update(nil, P, true, row)
assert(said() == "")
-- In a car: it is locked, and stays so on later updates.
sit("car_a")
row.update(nil, P, true, row)
assert(said() == "car_a+" and locked.car_a)
row.update(nil, P, true, row)
assert(said() == "car_a+" and locked.car_a)
-- Stepping out unlocks it (the lock keeps the player out too), once.
sit("")
row.update(nil, P, true, row)
assert(said() == "car_a-" and not locked.car_a)
row.update(nil, P, true, row)
assert(said() == "")
-- Another car straight from this one: the first is let go, the new one locked.
sit("car_a")
row.update(nil, P, true, row)
said()
sit("car_b")
row.update(nil, P, true, row)
assert(said() == "car_a- car_b+" and not locked.car_a and locked.car_b)
-- A locked car the game has removed is left alone.
exists.car_b = nil; locked.car_b = nil
sit("car_c")
row.update(nil, P, true, row)
assert(said() == "car_c+" and locked.car_c)
-- Off: unlocked, on foot or not, and only once.
sit("")
row.off(nil, P, false, row)
assert(said() == "car_c-" and not next(locked))
row.off(nil, P, false, row)
assert(said() == "")
-- Off after the car is gone: no call on it.
sit("car_d")
row.update(nil, P, true, row)
exists.car_d = nil; locked.car_d = nil; said()
sit("")
row.off(nil, P, false, row)
assert(said() == "")
-- The state lives in TWEAK, not in new globals.
assert(rawget(game, "TWEAK") and rawget(game, "TWEAK").locked_car == nil)
print("locked cars: ok")

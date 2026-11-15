-- From the repo root: build/lua.exe tools/test_limited.lua
-- Limited Weapons against a fake game: the code the rows send is run in a
-- fake of the game's Lua whose inventory and sprint calls record what they
-- were asked, so the test sees which guns are taken and given back.
package.path = "SRTweakMenu/?.lua"

local mem = {}
local function rd(a, n) local v = 0 for i = n - 1, 0, -1 do v = (v << 8) | (mem[a + i] or 0) end return v end
local function wr(a, n, v) for i = 0, n - 1 do mem[a + i] = v & 0xFF; v = v >> 8 end end

-- The game's side: a weapon per slot, the one in hand, the sprint override.
local SLOT_OF = { ak47 = "rifle", m16 = "rifle", twelve_gauge = "shotgun", rpg_launcher = "launcher", glock = "pistol",
  tec9 = "smg", baseball_bat = "melee", grenade = "thrown" }
local inv, equipped, sprint, calls, out = {}, nil, nil, {}, {}
local game = { LOCAL_PLAYER = "#PLAYER1#", rawget = rawget, rawset = rawset }
game._G = game
function game.tweak_out(...) for i = 1, select("#", ...) do out[#out + 1] = (select(i, ...)) end end
function game.inv_item_in_slot(who, slot)
  assert(who == game.LOCAL_PLAYER and WEIGHT_SLOTS[slot], "inv_item_in_slot(" .. tostring(who) .. ", " .. tostring(slot) .. ")")
  return inv[slot] or "none"
end
function game.inv_item_get_equipped_item(who) assert(who == game.LOCAL_PLAYER) return equipped end
function game.inv_item_remove_in_slot(slot, who)
  assert(who == game.LOCAL_PLAYER and WEIGHT_SLOTS[slot])
  calls[#calls + 1] = "-" .. slot
  if equipped == inv[slot] then equipped = nil end
  inv[slot] = nil
end
function game.inv_item_add_do(name, count, who, equip)
  assert(who == game.LOCAL_PLAYER and count == 1 and equip == true and SLOT_OF[name])
  calls[#calls + 1] = "+" .. name
  inv[SLOT_OF[name]] = name; equipped = name
end
function game.sprint_set_local_use_override(ms) assert(type(ms) == "number") sprint = ms end
function game.sprint_reset_local_overrides() calls[#calls + 1] = "reset" sprint = nil end
WEIGHT_SLOTS = { melee = 1, pistol = 1, smg = 1, shotgun = 1, rifle = 1, launcher = 1, thrown = 1 }
game.WEIGHT_SLOTS = WEIGHT_SLOTS; game.assert = assert; game.tostring = tostring
-- As the game does: a new global can't be made by assignment.
setmetatable(game, { __newindex = function(_, k) error("new global " .. tostring(k)) end })

local P = 0x10000000
wml = {
  log = function() end,
  read_u8 = function(a) return rd(a, 1) end, read_u16 = function(a) return rd(a, 2) end,
  read_u32 = function(a) return rd(a, 4) end, read_f32 = function() return 0 end,
  script = function(code)
    out = {}
    assert(load(code, "game", "t", game))()
    return true, table.unpack(out)
  end,
}
wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, P)
local function said() local s = table.concat(calls, " ") calls = {} return s end

local G = require("game")
local rows = require("limited").rows({}, G)
assert(#rows == 2)
local row, swap = rows[1], rows[2]
assert(row.id == "loadout" and row.kind == "toggle" and row.label == "Limited Weapons" and row.needs == "player" and row.every == 30)
assert(swap.id == "loadout_swap" and swap.kind == "action" and swap.label == "Swap big gun")
assert(type(row.help) == "string" and type(swap.help) == "string")

-- Nothing carried: nothing taken, the game's full sprint.
row.update(nil, P, true, row)
assert(said() == "" and sprint == 10000)
assert(swap.run(nil, P) == "No big gun in the stash")
-- A pistol, an SMG, a bat and one rifle are all allowed; they weigh 4 s.
inv = { pistol = "glock", smg = "tec9", melee = "baseball_bat", rifle = "ak47" }
row.update(nil, P, true, row)
assert(said() == "" and inv.rifle == "ak47" and sprint == 6000, tostring(sprint))
-- A shotgun picked up: the newer gun stays, the rifle goes to the stash.
inv.shotgun = "twelve_gauge"
row.update(nil, P, true, row)
assert(said() == "-rifle" and inv.shotgun == "twelve_gauge" and not inv.rifle and sprint == 6000)
row.update(nil, P, true, row)
assert(said() == "")
-- In a cutscene nothing is asked of the game.
wr(0x02527D14, 1, 1); inv.launcher = "rpg_launcher"
row.update(nil, P, true, row)
assert(said() == "" and inv.launcher)
wr(0x02527D14, 1, 0)
-- After it: the launcher is the new one, the shotgun is stashed; heavier.
row.update(nil, P, true, row)
assert(said() == "-shotgun" and inv.launcher and sprint == 5000)
-- Swap: the launcher goes in, the rifle (stashed longest) comes back, and
-- the next look does not take it for a pickup.
assert(swap.run(nil, P):find("^Took the ak47 %(2 in the stash%)"))
assert(said() == "-launcher +ak47" and inv.rifle == "ak47" and not inv.launcher)
row.update(nil, P, true, row)
assert(said() == "" and inv.rifle == "ak47" and sprint == 6000)
-- Off: the sprint override is dropped, once; no gun is touched.
row.off(nil, P, false, row)
assert(said() == "reset" and sprint == nil and inv.rifle == "ak47")
row.off(nil, P, false, row)
assert(said() == "")
-- Switched on holding two big guns: the one in your hand stays.
inv.shotgun = "twelve_gauge"; equipped = "twelve_gauge"
row.update(nil, P, true, row)
assert(said() == "-rifle" and inv.shotgun and not inv.rifle)
-- With neither in hand, the rifle is kept before the launcher.
inv = { rifle = "m16", launcher = "rpg_launcher" }; equipped = nil
row.off(nil, P, false, row); said()
row.update(nil, P, true, row)
assert(said() == "-launcher" and inv.rifle == "m16")
-- A weapon is stashed once however often it is taken: the launcher was in
-- already, so the stash is shotgun, launcher, rifle; the m16 takes the
-- shotgun's place.
assert(swap.run(nil, P) == "Took the twelve_gauge (3 in the stash)")
assert(said() == "-rifle +twelve_gauge")
-- A game that doesn't answer: nothing is done.
local script = wml.script
wml.script = function() return false end
inv = { rifle = "m16", shotgun = "twelve_gauge" }
row.update(nil, P, true, row)
assert(said() == "" and inv.rifle and inv.shotgun)
wml.script = script
-- Nothing was kept in the game's globals.
assert(rawget(game, "TWEAK") == nil)
print("limited: ok")

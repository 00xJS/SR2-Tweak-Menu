-- From the repo root: build/lua.exe tools/test_cash_safe.lua
-- The cash safe against a fake game: the cash in cents at player+0x1114,
-- cash_add / cash_remove, owned cribs, and a death with Limited Cash on.
package.path = "SRTweakMenu/?.lua"
local scratch = (os.getenv("TEMP") or ".") .. "\\sr2_tweak_menu_test"
os.execute('mkdir "' .. scratch .. '" 2>nul')
os.remove(scratch .. "\\saved_presets.lua")

local mem = {}
local function rd(a, n) local v = 0 for i = n - 1, 0, -1 do v = (v << 8) | (mem[a + i] or 0) end return v end
local function wr(a, n, v) for i = 0, n - 1 do mem[a + i] = v & 0xFF; v = v >> 8 end end
local function wf(a, f) wr(a, 4, string.unpack("<I4", string.pack("<f", f))) end
local P = 0x10000000
local cents, dead, owned = 2500000, false, { HE_Loft_Crib = true }
local function sync() wr(P + 0x1114, 4, cents & 0xFFFFFFFF) end
sync()
local game = setmetatable({}, { __index = function(_, k) error("game function " .. k) end })
local env = {
  cash_add = function(n) cents = cents + n * 100 sync() end,
  cash_remove = function(n) cents = math.max(0, cents - n * 100) sync() end,
  crib_is_unlocked = function(name) return owned[name] == true end,
  character_is_dead = function() return dead end,
  LOCAL_PLAYER = "#PLAYER#",
}
local out
env.tweak_out = function(...) out = table.pack(...) end
wml = {
  mod_folder = scratch, log = function() end,
  read_u8 = function(a) return rd(a, 1) end, read_u32 = function(a) return rd(a, 4) end,
  read_f32 = function(a) return string.unpack("<f", string.pack("<I4", rd(a, 4))) end,
  script = function(code)
    out = nil
    assert(load(code, "game", "t", env))()
    if out then return true, table.unpack(out, 1, out.n) end
    return true
  end,
}
local G = require("game")
local presets = require("presets")
local C = require("cash_safe")
local items = {}
local F = { enabled = true, items = items }
function F.page(id, label, help, rows) for _, r in ipairs(rows) do if r.id then items[r.id] = r end end return { id = id, rows = rows } end
function F.header(l) return { kind = "header", label = l } end
local page = C.rows(F, G)[1]
for _, r in ipairs(page.rows) do if r.id then items[r.id] = r end end
items.limited_cash.v = false
local amount, dep, wd = items.cash_safe_amount, items.cash_deposit, items.cash_withdraw

-- $25,000 carried, read through the $1 check (cents here).
assert(C.carried(P) == 25000)
amount.v = 2   -- $10,000
assert(dep.run(nil, P):find("Put %$10,000"), "deposit")
assert(C.carried(P) == 15000 and C.balance() == 10000)
amount.v = 4   -- all
assert(dep.run(nil, P):find("%$15,000"))
assert(C.carried(P) == 0 and C.balance() == 25000)
assert(dep.run(nil, P):find("No cash"))
amount.v = 1
assert(wd.run(nil, P):find("Took %$1,000"))
assert(C.carried(P) == 1000 and C.balance() == 24000)
-- Limited Cash: away from a crib the safe is shut; at an owned crib's spot it opens.
items.limited_cash.v = true
wf(P + 0x14, 0); wf(P + 0x18, 0); wf(P + 0x1C, 0)
assert(wd.run(nil, P):find("crib you own"))
wf(P + 0x14, -94.0); wf(P + 0x18, 70.3); wf(P + 0x1C, -1709.5)
assert(wd.run(nil, P):find("Took"))
-- not owned: shut
owned.HE_Loft_Crib = nil
assert(wd.run(nil, P):find("crib you own"))
-- Dying loses what you carry, once you're back; the safe keeps its money.
local before = C.balance()
dead = true; items.limited_cash.update(nil, P)
assert(C.carried(P) == 2000)
dead = false; items.limited_cash.update(nil, P)
assert(C.carried(P) == 0 and C.balance() == before)
-- The safe is kept in saved_presets.lua.
presets.reload()
assert(C.balance() == before)
print("cash safe: ok")

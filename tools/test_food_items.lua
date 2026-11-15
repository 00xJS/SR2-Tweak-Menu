-- From the repo root: build/lua.exe tools/test_food_items.lua
-- The Items page against a fake game: the rows must send the game's script
-- the right inv_item_add_do calls for one item, for Give all and for the list.
package.path = "SRTweakMenu/?.lua"

local sent = {}
wml = {
  log = function() end, mod_folder = ".",
  read_u8 = function() return 0 end, read_u32 = function() return 0 end, read_f32 = function() return 0 end,
  script = function(code) sent[#sent + 1] = code return true end,
}
local G = require("game")
local WEAPONS = require("data.weapons")
local F = { items = {}, fmtint = function(v) return string.format("%d", v) end,
  data = function(name) return name == "weapons" and WEAPONS or {} end }

local rows = require("food_items").rows(F, G)
local by_id = {}
for _, r in ipairs(rows) do
  assert(r.id and not by_id[r.id], "every row has its own id")
  by_id[r.id] = r
  F.items[r.id] = r
  if r.kind == "list" then r.v = r.v or 1 end
end
assert(#rows == 3 and by_id.items and by_id.give_item and by_id.give_item_count, "SR1's three ids")
assert(by_id.items.kind == "page" and by_id.give_item.kind == "list" and by_id.give_item_count.kind == "value")

local function row(page, label)
  for _, r in ipairs(page.rows) do if r.label == label then return r end end
end
local function call(name, n) return string.format('inv_item_add_do("%s", %d, LOCAL_PLAYER, false)', name, n) end

-- The page: Give food and Give drugs, a row per item and Give all.
local page = by_id.items.open(nil, 1)
assert(page.title == "Items" and #page.rows == 2)
local food, drugs = row(page, "Give food").open(), row(page, "Give drugs").open()
assert(food.title == "Food" and drugs.title == "Drugs")

assert(row(food, "The Fist").run() == "Given: The Fist")
assert(#sent == 1 and sent[1] == call("the_fist", 1), sent[1])
sent = {}
assert(row(drugs, "40 oz.").run() == "Given: 40 oz.")
assert(#sent == 1 and sent[1] == call("40oz", 1), sent[1])
-- pcp comes from data/weapons.lua's SPECIAL notes.
assert(row(drugs, "PCP"), "pcp is on the drugs page")
assert(not row(drugs, "Cellphone") and not row(drugs, "Large Soft Drink"), "only new drug/food entries are added")

-- Give all: one call per item on the page, each once, nothing else.
sent = {}
assert(row(food, "Give all").run() == "Given: all food")
assert(#sent == #food.rows - 1 and #sent == 16, #sent)
local seen = {}
for _, code in ipairs(sent) do
  local name, n = code:match('^inv_item_add_do%("([%w_]+)", (%d+), LOCAL_PLAYER, false%)$')
  assert(name and n == "1" and not seen[name], code)
  seen[name] = true
end
assert(seen.the_fist and seen.large_softdrink and seen.dong_tea and not seen.blunt)
sent = {}
row(drugs, "Give all").run()
assert(#sent == #drugs.rows - 1 and #sent == 9, #sent)

-- The list on the Weapons tab gives the picked item, How many times over.
local list = by_id.give_item
assert(#list.items == 25 and list.nosave)
for i, e in ipairs(list.items) do if e[1] == "blunt" then list.v = i end end
by_id.give_item_count.v = 3
sent = {}
assert(list.run(nil, 1, nil, list) == "Given: 3 x Blunt (weed)")
assert(#sent == 1 and sent[1] == call("blunt", 3), sent[1])

-- Nothing makes a global or needs the T table in the game's Lua.
assert(not sent[1]:find("TWEAK", 1, true))
-- A missing data file still leaves the store items.
F.data = function() return {} end
assert(#require("food_items").rows(F, G)[2].items == 24)
print("food_items: ok")

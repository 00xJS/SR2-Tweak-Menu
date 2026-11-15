-- SR Tweak Menu (Saints Row 2) - SR1's Items page: the food, drinks, weed
-- and booze the stores sell, one at a time or all of them.
--
-- The names are the game's drugs.xtbl (common.vpp_pc). Six more entries
-- there (the_fist1, burgera1, 40oz1, gin_n_juice1, hennessy1, krystal1) are
-- the same things as sold by another store, so they are left out.
--
-- Experimental: they are given with inv_item_add_do, the call the missions
-- use for weapons. The game's scripts never give food or drugs themselves
-- (the stores do it in code), so whether that call also looks a name up in
-- drugs.xtbl, as SR1's did, is not confirmed for SR2. "pcp" and "40oz" are
-- in items_inventory.xtbl as well, so the call knows those two names.

local I = {}

-- { drugs.xtbl name, "Shown name", kind }. Shown names follow the table's
-- own names; the ones SR1 had keep SR1's labels.
local FOOD = {
  { "the_fist", "The Fist", "food" }, { "burgera", "The Twins", "food" }, { "chicken_bazooms", "Chicken Bazooms", "food" },
  { "large_softdrink", "Big Swallow", "drink" },
  { "steaming_kabob", "Steaming Kabob", "food" }, { "hot_gyro", "Hot Gyro", "food" }, { "lil_gyro", "Lil' Gyro", "food" },
  { "grecian_juice", "Grecian Juice", "drink" },
  { "belly_jelly_donut", "Belly Jelly Donut", "food" }, { "brown_donut", "Brown Donut", "food" },
  { "donut_holes", "Donut Holes", "food" }, { "coffee", "Coffee", "drink" },
  { "sum_yung_guy", "Sum Yung Guy", "food" }, { "sum_old_guy", "Sum Old Guy", "food" },
  { "strange_egg_roll", "Strange Egg Roll", "food" }, { "dong_tea", "Dong Tea", "drink" },
}
local DRUGS = {
  { "spliff", "Spliff", "weed" }, { "blunt", "Blunt", "weed" }, { "pipe", "Pipe", "weed" }, { "bong", "Bong", "weed" },
  { "40oz", "40 oz.", "booze" }, { "gin_n_juice", "Gin N' Juice", "booze" }, { "hennessy", "Cognac", "booze" },
  { "krystal", "Bubbly", "booze" },
}

function I.rows(F, G)
  local food, drugs, known = {}, {}, {}
  for _, e in ipairs(FOOD) do food[#food + 1] = e; known[e[1]] = true end
  for _, e in ipairs(DRUGS) do drugs[#drugs + 1] = e; known[e[1]] = true end
  -- data/weapons.lua notes a few weapon-table entries as drug or food
  -- items: any not listed above (pcp) join the drugs.
  for _, w in ipairs(F.data("weapons").SPECIAL or {}) do
    local note = (w.note or ""):lower()
    if not known[w[1]] and (note:find("drug", 1, true) or note:find("food", 1, true)) then
      drugs[#drugs + 1] = { w[1], w[2], "drug" }
      known[w[1]] = true
    end
  end

  -- Never into your hand: these are carried, not held.
  local function give(e, count)
    G.lua("inv_item_add_do(%s, %s, LOCAL_PLAYER, false)", e[1], count or 1)
  end

  -- SR1's give page: a row per item, then Give all.
  local function give_page(title, list)
    return function()
      local rows = {}
      for _, e in ipairs(list) do
        rows[#rows + 1] = { label = e[2], kind = "action", help = "Gives you one: " .. e[2] .. " (" .. e[3] .. ").",
          run = function() give(e) return "Given: " .. e[2] end }
      end
      rows[#rows + 1] = { label = "Give all", kind = "action", help = "One of each on this page. You only carry a few kinds at a time.",
        run = function()
          for _, e in ipairs(list) do give(e) end
          return "Given: all " .. title:lower()
        end }
      return { title = title, rows = rows }
    end
  end

  -- SR1's Give item list on the Weapons tab: everything, with its kind.
  local all = {}
  for _, e in ipairs(drugs) do all[#all + 1] = { e[1], string.format("%s (%s)", e[2], e[3]) } end
  for _, e in ipairs(food) do all[#all + 1] = { e[1], string.format("%s (%s)", e[2], e[3]) } end

  return {
    { id = "items", label = "Items", kind = "page", needs = "player",
      help = "Food and drugs as the stores sell them, one at a time or all of them. Experimental.",
      open = function() return { title = "Items", rows = {
        { label = "Give food", kind = "page", help = #food .. " kinds of food and drink.", open = give_page("Food", food) },
        { label = "Give drugs", kind = "page", help = #drugs .. " kinds of weed and booze.", open = give_page("Drugs", drugs) },
      } } end },
    { id = "give_item", label = "Give item", kind = "list", items = all, nosave = true,
      help = "Weed, booze, drinks and food, as the stores sell them: Left / Right picks, Enter puts them in your inventory. Experimental.",
      run = function(ctx, p, v, it)
        local item = it.items[it.v]
        local count = F.items and F.items.give_item_count
        local n = count and count.v or 1
        give(item, n)
        return string.format("Given: %d x %s", n, item[2])
      end },
    { id = "give_item_count", label = "How many", kind = "value", needs = "none", default = 1, min = 1, max = 10, step = 1,
      v = 1, oneshot = true, nosave = true, fmt = F.fmtint, help = "How many of the item Give item hands you." },
  }
end

return I

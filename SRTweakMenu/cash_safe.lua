-- SR Tweak Menu (Saints Row 2) - Player > Cash safe, and Limited Cash.
--
-- SR1's Limited Cash: a safe in each crib keeps your cash, and what you
-- carry is lost when you die. Here the safe is a page of the menu: deposit
-- and withdraw anywhere, or, with Limited Cash on, only at the cash spot of a
-- crib you own (the spots cribs.xtbl names, cribs_sr2_city's $XX_crib_cash
-- navpoints). With Limited Cash on, dying empties your pockets; the safe
-- keeps its money. (Getting busted isn't caught yet.)
--
-- Cash you carry is the player's +0x1114 (signed); whether the game keeps it
-- in dollars or cents is found once, by adding $1 and taking it back. Money
-- moves with the game's own cash_add / cash_remove. The safe's money is kept
-- in saved_presets.lua, so it's shared by every save.
local G = require("game")
local presets = require("presets")
local C = {}

-- { crib, x, y, z of its cash spot }
local CRIBS = {
  { "HE_Loft_Crib", -94.0, 70.3, -1710.8 }, { "DT_Loft_Crib", -799.3, 22.9, -1094.3 },
  { "PI_Lighthouse_Crib", 1560.2, 10.1, -1267.1 }, { "SR_Mega_Crib", -1155.2, 20.8, 82.3 },
  { "RL_Brownstone_Crib", 83.2, -5.8, 106.1 }, { "SU_University_Crib", 1405.0, 12.9, -71.9 },
  { "AI_Hotel_Crib", 123.3, 80.4, 1457.4 }, { "SaintsHQ", 180.5, -18.7, -34.7 },
}
C.CRIBS = CRIBS
local REACH = 4.0
local CASH = 0x1114

local function store()
  local all = presets.all()
  if type(all.cash_safe) ~= "number" then all.cash_safe = 0 end
  return all
end
function C.balance() return store().cash_safe end

local unit
local function raw_cash(p)
  local v = wml.read_u32(p + CASH)
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
-- Dollars you carry, or nil if it can't be read.
function C.carried(p)
  if p == 0 then return nil end
  if not unit then
    local before = raw_cash(p)
    G.lua("cash_add(1)")
    local after = raw_cash(p)
    G.lua("cash_remove(1)")
    local d = after - before
    if d ~= 1 and d ~= 100 then
      wml.log("cash safe: adding $1 changed the cash by " .. d .. "; not used")
      return nil
    end
    unit = d
    wml.log("cash safe: the game keeps cash in " .. (d == 1 and "dollars" or "cents"))
  end
  return raw_cash(p) // unit
end

-- The owned crib whose cash spot you're at, or nil.
function C.at_crib(p)
  if p == 0 then return nil end
  local x, y, z = G.vec(p + G.P.POS)
  for _, c in ipairs(CRIBS) do
    local dx, dy, dz = x - c[2], y - c[3], z - c[4]
    if dx * dx + dy * dy + dz * dz <= REACH * REACH then
      local _, owned = G.lua("tweak_out(crib_is_unlocked(%s))", c[1])
      if owned then return c[1] end
    end
  end
end

local AMOUNTS = { 1000, 10000, 100000, false }
local function money(n) local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse() return "$" .. s:gsub("^,", "") end
C.money = money

function C.rows(F, G_)
  local amount = { id = "cash_safe_amount", label = "Amount", kind = "choice", needs = "none", nosave = true, v = 2,
    options = { "$1,000", "$10,000", "$100,000", "All" },
    help = "How much Deposit and Withdraw move." }
  local function where(p)
    if F.items.limited_cash.v and F.enabled and not C.at_crib(p) then
      return "Limited Cash: use the safe at a crib you own (where its cash pickup is)"
    end
  end
  local function moved()
    return " (safe " .. money(C.balance()) .. ")"
  end
  local deposit = { id = "cash_deposit", label = "Deposit", kind = "action", nosave = true,
    help = "Puts cash you carry in the safe.",
    note = function() return money(C.balance()) end,
    run = function(ctx, p)
      local why = where(p) if why then return why end
      local have = C.carried(p)
      if not have then return "Couldn't read your cash" end
      local n = AMOUNTS[amount.v] or have
      n = math.min(n, have)
      if n <= 0 then return "No cash on you" end
      G.lua("cash_remove(%s)", n)
      store().cash_safe = C.balance() + n
      return presets.write() or ("Put " .. money(n) .. " in the safe" .. moved())
    end }
  local withdraw = { id = "cash_withdraw", label = "Withdraw", kind = "action", nosave = true,
    help = "Takes cash out of the safe.",
    run = function(ctx, p)
      local why = where(p) if why then return why end
      local n = math.min(AMOUNTS[amount.v] or C.balance(), C.balance())
      if n <= 0 then return "The safe is empty" end
      store().cash_safe = C.balance() - n
      G.lua("cash_add(%s)", n)
      return presets.write() or ("Took " .. money(n) .. " from the safe" .. moved())
    end }

  -- Limited Cash: dying empties your pockets (once a death is seen, after you're back).
  local dead = false
  local limited = { id = "limited_cash", label = "Limited Cash", kind = "toggle", every = 15,
    help = "What you carry is lost when you die; the safe keeps its money. The safe then only opens at a crib you own, by its cash pickup.",
    update = function(ctx, p)
      local _, now = G.lua("tweak_out(character_is_dead(LOCAL_PLAYER))")
      if now then dead = true return end
      if dead then
        dead = false
        local have = C.carried(p)
        if have and have > 0 then
          G.lua("cash_remove(%s)", have)
          wml.log("limited cash: lost " .. money(have) .. " on death")
        end
      end
    end,
    off = function() dead = false end }

  return {
    F.page("cash_safe", "Cash safe", "Keep cash in a safe: deposit and withdraw, and Limited Cash.", {
      F.header("Safe"), amount, deposit, withdraw,
      F.header("Limited Cash"), limited,
    }),
  }
end

return C

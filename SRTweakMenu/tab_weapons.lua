-- SR Tweak Menu (Saints Row 2) - the Weapons tab.
--
-- Infinite ammo and no reload are the phone's cheats (Ammo, Unlimited
-- Clip); weapons are given with the game's inv_item_add_do, the call its
-- missions use. SR1's aiming rows (Precise Aim, Fine Aim, Weapon Switch)
-- are SR1 mods of their own and have no SR2 version; Juiced Patch has its
-- own aiming options for SR2.

return function(F, G)
  local WEAPONS = F.data("weapons")
  local ENGINE = require("engine")

  -- { xtbl name, "Shown name", slot }, alphabetical.
  local list = {}
  for _, w in ipairs(WEAPONS) do list[#list + 1] = w end
  table.sort(list, function(a, b) return a[2]:lower() < b[2]:lower() end)

  local function give(name, equip)
    G.lua("inv_item_add_do(%s, 9999, LOCAL_PLAYER, %s)", name, equip and true or false)
  end

  F.category("Weapons", {
    { id = "super_explosions", label = "Super explosions", kind = "toggle", cheat = "Super Explosions",
      help = "Every explosion is bigger (the phone's cheat)." },
    { id = "milk_bones", label = "Pimp strength", kind = "toggle", cheat = "MILK BONES",
      help = "The phone's MILK BONES cheat: super-strong melee." },

    { id = "give_weapon", label = "Give weapon", kind = "list", items = list, nosave = true,
      help = "Left/Right to choose, Enter gives it to you (with ammo) and puts it in your hand.",
      run = function(ctx, p, v, it) give(it.items[it.v][1], true) return "Gave " .. it.items[it.v][2] end },
    { id = "all_weapons", label = "Give every weapon", kind = "action",
      help = "One of every weapon. Each slot keeps only one, so the last one given wins.",
      run = function()
        for _, w in ipairs(list) do give(w[1], false) end
        return "Gave " .. #list .. " weapons"
      end },
    { id = "ammo_all", label = "Refill all ammo", kind = "action", help = "Full ammo for every weapon you carry.",
      run = function()
        for _, w in ipairs(list) do
          G.lua("if inv_has_item(%s, LOCAL_PLAYER) then inv_item_add_ammo(LOCAL_PLAYER, %s, 9999) end", w[1], w[1])
        end
        return "Ammo refilled"
      end },
  })
end

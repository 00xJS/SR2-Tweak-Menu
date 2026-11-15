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

  -- SR1's Give Weapon page: a page per kind (pistols, SMGs...), a row per
  -- weapon, and Give All; Remove Weapon: what you carry, a row each.
  local KIND = { pistol = "Pistols", smg = "SMGs", rifle = "Rifles", shotgun = "Shotguns", launcher = "Launchers & Specials",
    thrown = "Thrown", melee = "Melee", unarmed = "Unarmed & Other" }
  local ORDER = { "pistol", "smg", "rifle", "shotgun", "launcher", "thrown", "melee", "unarmed" }
  local by_kind = {}
  for _, w in ipairs(list) do
    local k = w[3] or "unarmed"
    by_kind[k] = by_kind[k] or {}
    table.insert(by_kind[k], w)
  end
  local function give_pages()
    local rows = {}
    for _, k in ipairs(ORDER) do
      local ws = by_kind[k]
      if ws then
        rows[#rows + 1] = { label = KIND[k] or k, kind = "page", help = #ws .. " weapons.", open = function()
          local r = {}
          for _, w in ipairs(ws) do
            r[#r + 1] = { label = w[2], kind = "action", help = "Gives you the " .. w[2] .. " with ammo, in your hand.",
              run = function() give(w[1], true) return "Gave " .. w[2] end }
          end
          r[#r + 1] = { label = "Give All", kind = "action", help = "Every weapon here (each slot keeps one: the last given wins).",
            run = function() for _, w in ipairs(ws) do give(w[1], false) end return "Gave " .. #ws .. " " .. (KIND[k] or k):lower() end }
          return { title = KIND[k] or k, rows = r }
        end }
      end
    end
    return { title = "Give Weapon", rows = rows }
  end
  local function remove_page()
    local checks = {}
    for i, w in ipairs(list) do checks[i] = string.format("if inv_has_item(%q, LOCAL_PLAYER) then tweak_out(%q) end", w[1], w[1]) end
    local res = table.pack(G.script(nil, table.concat(checks, " ")))
    local held, rows = {}, {}
    for i = 2, res.n do if type(res[i]) == "string" then held[res[i]] = true end end
    for _, w in ipairs(list) do
      if held[w[1]] then
        rows[#rows + 1] = { label = w[2], kind = "action", help = "Takes the " .. w[2] .. " away.",
          run = function()
            G.lua("local ok = pcall(inv_item_remove, %s, LOCAL_PLAYER)", w[1])
            return "Removed: " .. w[2]
          end }
      end
    end
    rows[#rows + 1] = { label = "Remove All", kind = "action", help = "Every weapon you carry.",
      run = function() G.lua("inv_item_remove_all(LOCAL_PLAYER)") return "All weapons removed" end }
    return { title = "Remove Weapon", rows = rows }
  end

  F.category("Weapons", {
    { id = "give_weapons", label = "Give Weapon", kind = "page", needs = "player", open = give_pages,
      help = "Every weapon in the game, by kind: a row each, and Give All." },
    { id = "remove_weapon", label = "Remove Weapon", kind = "page", needs = "player", open = remove_page,
      help = "The weapons you carry: take any of them away, or all." },
    { id = "super_explosions", label = "Super explosions", kind = "toggle", cheat = "Super Explosions",
      help = "Every explosion is bigger (the phone's cheat)." },
    { id = "milk_bones", label = "Pimp strength", kind = "toggle", cheat = "MILK BONES",
      help = "The phone's MILK BONES cheat: super-strong melee." },

    { id = "give_weapon", label = "Give weapon (list)", kind = "list", items = list, nosave = true,
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

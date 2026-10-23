-- SR Tweak Menu (Saints Row 2) - the Player tab.
--
-- SR1's rows, done with SR2's own mission-script functions (notoriety_*,
-- set_max_hit_points, character_allow_ragdoll...) and its phone cheats
-- (Infinite Sprint). Rows that need the engine (No Clip, bodyguards) come
-- from engine.lua when it can do them.

return function(F, G)
  local VARIANTS = F.data("variants")
  local ENGINE = require("engine")

  -- Notoriety, per team: 0-5 stars, set once per change.
  local function wanted_row(id, team, label)
    return { id = id, label = label, kind = "value", default = 0, min = 0, max = 5, step = 1, fmt = F.fmtint, oneshot = true, nosave = true,
      help = "Sets your " .. label:lower() .. " (0 to 5).",
      change = function(ctx, p, v, it) G.lua("notoriety_set(%s, %s)", team, it.v) end }
  end

  -- Movement variants from data/variants.lua (WALK, RUN, STAND: the names
  -- character_set_*_variant takes), with "Default" first.
  local function variant_list(names)
    local items = { { "", "Default" } }
    for _, n in ipairs(names or {}) do items[#items + 1] = { n[1], n[2] } end
    return items
  end

  local rows = {
    { id = "god", label = "God mode", kind = "toggle", every = 180,
      help = "You can't be hurt.",
      update = function() G.lua("turn_invulnerable(LOCAL_PLAYER)") end,
      off = function() G.lua("turn_vulnerable(LOCAL_PLAYER)") end },
    ENGINE.noclip_row(),
    { id = "health_mult", label = "Health multiplier", kind = "value", default = 1, min = 1, max = 10, step = 0.5, fmt = F.fmtx,
      help = "Multiplies your maximum health.",
      change = function(ctx, p, v, it)
        G.lua("if not T.base_hp then T.base_hp = get_max_hit_points(LOCAL_PLAYER) end "
          .. "set_max_hit_points(LOCAL_PLAYER, T.base_hp * %s) set_current_hit_points(LOCAL_PLAYER, T.base_hp * %s)", it.v, it.v)
      end,
      off = function() G.lua("if T.base_hp then set_max_hit_points(LOCAL_PLAYER, T.base_hp) end") end },
    { id = "heal", label = "Refill health", kind = "action", help = "Fills your health.",
      run = function() G.lua("set_current_hit_points(LOCAL_PLAYER, get_max_hit_points(LOCAL_PLAYER))") return "Health refilled" end },
    { id = "kill_self", label = "Kill Yourself", kind = "action", help = "You die (and wake up at the hospital).",
      run = function() G.lua("character_kill(LOCAL_PLAYER)") return "Bye" end },

    { id = "never_wanted", label = "Never wanted", kind = "toggle", every = 60,
      help = "Police and gangs never come after you.",
      update = function()
        for _, team in pairs(G.TEAMS) do G.lua("notoriety_set_max(%s, 0) notoriety_set(%s, 0)", team, team) end
      end,
      off = function() for _, team in pairs(G.TEAMS) do G.lua("notoriety_set_max(%s, 5)", team) end end },
    wanted_row("wanted_police", G.TEAMS.police, "Police notoriety"),
    wanted_row("wanted_brotherhood", G.TEAMS.brotherhood, "Brotherhood notoriety"),
    wanted_row("wanted_ronin", G.TEAMS.ronin, "Ronin notoriety"),
    wanted_row("wanted_samedi", G.TEAMS.samedi, "Sons of Samedi notoriety"),
    wanted_row("wanted_ultor", G.TEAMS.ultor, "Ultor notoriety"),
    { id = "max_wanted", label = "Max notoriety", kind = "action", help = "Every team at 5 stars.",
      run = function() for _, team in pairs(G.TEAMS) do G.lua("notoriety_set(%s, 5)", team) end return "Everyone wants you" end },
    { id = "no_cops", label = "No cops", kind = "toggle",
      help = "No police spawn, even with notoriety.",
      change = function(ctx, p, v, it)
        G.lua("notoriety_force_no_spawn(%s, %s) spawning_allow_cop_ambient_spawns(%s)", G.TEAMS.police, it.v, not it.v)
      end,
      off = function() G.lua("notoriety_force_no_spawn(%s, false) spawning_allow_cop_ambient_spawns(true)", G.TEAMS.police) end },
    { id = "no_gangs", label = "No gangs", kind = "toggle",
      help = "No gang members spawn, even with notoriety.",
      change = function(ctx, p, v, it)
        for _, team in ipairs(G.GANGS) do G.lua("notoriety_force_no_spawn(%s, %s)", team, it.v) end
        G.lua("ambient_gang_spawn_enable(%s)", not it.v)
      end,
      off = function()
        for _, team in ipairs(G.GANGS) do G.lua("notoriety_force_no_spawn(%s, false)", team) end
        G.lua("ambient_gang_spawn_enable(true)")
      end },
    { id = "no_bust", label = "Never busted", kind = "toggle", every = 300,
      help = "The police can't arrest you.",
      update = function() G.lua("set_player_can_be_busted(LOCAL_PLAYER, false)") end,
      off = function() G.lua("set_player_can_be_busted(LOCAL_PLAYER, true)") end },

    F.page("player_bodyguards", "Bodyguards", "Bodyguards and homies: spawn them, dismiss them, how many you can have.", {
      ENGINE.bodyguard_row(),
      { id = "dismiss_homies", label = "Dismiss all homies", kind = "action", help = "Sends every follower away.",
        run = function() G.lua("party_dismiss_all()") return "Homies dismissed" end },
      { id = "homies", label = "More homies", kind = "toggle",
        help = "Lets you have the most followers the game allows.",
        change = function(ctx, p, v, it) G.lua("party_allow_max_followers(%s)", it.v) end,
        off = function() G.lua("party_allow_max_followers(false)") end },
    }),

    { id = "no_ragdoll", label = "No ragdoll", kind = "toggle", every = 300,
      help = "You don't get knocked down.",
      update = function() G.lua("character_allow_ragdoll(LOCAL_PLAYER, false)") end,
      off = function() G.lua("character_allow_ragdoll(LOCAL_PLAYER, true)") end },
    { id = "perfect_aim", label = "Perfect aim", kind = "toggle", every = 300,
      help = "Every shot goes where you aim.",
      update = function() G.lua("set_perfect_aim(LOCAL_PLAYER, true)") end,
      off = function() G.lua("set_perfect_aim(LOCAL_PLAYER, false)") end },
    { id = "sprint", label = "Infinite sprint", kind = "toggle", cheat = "Sprint",
      help = "Sprint forever (the phone's cheat)." },
    { id = "walk_variant", label = "Walk style", kind = "list", items = variant_list(VARIANTS.WALK), nosave = true,
      help = "How you walk. Enter puts it on.",
      run = function(ctx, p, v, it)
        local name = it.items[it.v][1]
        G.lua("character_set_walk_variant(LOCAL_PLAYER, %s)", name ~= "" and name or "default")
        return "Walk: " .. it.items[it.v][2]
      end },
    { id = "run_variant", label = "Run style", kind = "list", items = variant_list(VARIANTS.RUN), nosave = true,
      help = "How you run. Enter puts it on.",
      run = function(ctx, p, v, it)
        local name = it.items[it.v][1]
        G.lua("character_set_run_variant(LOCAL_PLAYER, %s)", name ~= "" and name or "default")
        return "Run: " .. it.items[it.v][2]
      end },
    { id = "stand_variant", label = "Stand style", kind = "list", items = variant_list(VARIANTS.STAND), nosave = true,
      help = "How you stand. Enter puts it on.",
      run = function(ctx, p, v, it)
        local name = it.items[it.v][1]
        G.lua("character_set_stand_variant(LOCAL_PLAYER, %s)", name ~= "" and name or "default")
        return "Stand: " .. it.items[it.v][2]
      end },

    { id = "money", label = "Money +$50,000", kind = "action", help = "Adds $50,000 to your cash.",
      run = function() G.lua("cash_add(50000)") return "Added $50,000" end },
    ENGINE.respect_row(),
  }
  F.category("Player", rows)
end

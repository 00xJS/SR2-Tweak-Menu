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

  local GANG_TEAMS = { { "Playas", "The Saints" }, { "Brotherhood", "The Brotherhood" }, { "Ronin", "The Ronin" },
    { "Samedi", "Sons of Samedi" }, { "Ultor", "Ultor" }, { "Police", "The Police" }, { "Civilian", "Civilians" } }

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
      run = function(_, p)
        if F.stop_emote then F.stop_emote(p) end
        G.lua("character_kill(LOCAL_PLAYER)")
        return "Bye"
      end },

    { id = "never_wanted", label = "Never wanted", kind = "toggle", every = 60,
      help = "Police and gangs never come after you.",
      update = function()
        for _, team in pairs(G.TEAMS) do G.lua("notoriety_set_max(%s, 0) notoriety_set(%s, 0)", team, team) end
      end,
      off = function() for _, team in pairs(G.TEAMS) do G.lua("notoriety_set_max(%s, 5)", team) end end },
    -- SR1's gang rows on SR2's teams (set_team, as the missions move people
    -- between sides): Saints are enemies puts you on the gang picked in Join
    -- Gang, so that gang is on your side and the Saints and the rest aren't.
    { id = "saints_enemies", label = "Saints are enemies", kind = "toggle", every = 120,
      help = "The Saints treat you as a rival gang. You side with the gang picked in Join Gang.",
      update = function()
        local team = GANG_TEAMS[F.items.join_gang.v][1]
        if team == "Playas" then team = "Brotherhood" end
        G.lua("set_team(LOCAL_PLAYER, %s)", team)
      end,
      off = function() G.lua('set_team(LOCAL_PLAYER, "Playas")') end },
    { id = "join_gang", label = "Join Gang", kind = "choice", needs = "none", v = 1,
      options = (function() local t = {} for i, g in ipairs(GANG_TEAMS) do t[i] = g[2] end return t end)(),
      help = "Choose your side directly. Members of that side can be recruited from Bodyguards.",
      change = function(ctx, p, v, it)
        if not p or p == 0 then return "Load a game before joining a gang" end
        local team = GANG_TEAMS[it.v]
        local ok = G.lua("set_team(LOCAL_PLAYER, %s)", team[1])
        if not ok then return "Couldn't join " .. team[2] end
        -- Keep the legacy compatibility toggle synchronized so its periodic
        -- update cannot silently undo this direct affiliation choice.
        if F.items.saints_enemies then F.items.saints_enemies.v = it.v ~= 1 end
        return "You side with " .. team[2]
      end },
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
      ENGINE.recruit_row(),
      ENGINE.dismiss_homies_row(),
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

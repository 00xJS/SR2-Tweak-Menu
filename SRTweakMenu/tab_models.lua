-- SR Tweak Menu (Saints Row 2) - the Models and Customize tabs.
--
-- Models, as SR1's: Model Group picks a group (Story, Homies, DLC, Saints,
-- each gang, Police & Law, Activities, Store Clerks, Pedestrians, Zombies...),
-- Player Model browses that group, Enter (or Switch to Model) puts you in that
-- body, live, with the game's own character change (engine.lua), and Restore
-- puts you back in your own. Every character preset the game loads is there
-- (data/characters_all.lua: character_presets.xtbl and the DLC's).
-- Customize: SR2's own character creator (the plastic surgeon's), opened
-- where you stand; tab_customize.lua adds the rest.

return function(F, G)
  local ENGINE = require("engine")
  local GROUPS = F.data("characters_all")

  -- Models the game wouldn't put you in (the switch didn't take: you stayed
  -- yourself) are left out from then on (models_failed.txt, one name a line).
  local FAILED_FILE = wml.mod_folder .. "\\models_failed.txt"
  local failed = {}
  do
    local f = io.open(FAILED_FILE, "r")
    if f then for line in f:lines() do local n = line:match("^%s*(%S+)") if n then failed[n] = true end end f:close() end
  end
  local function save_failed()
    local f = io.open(FAILED_FILE, "w")
    if not f then return end
    for n in pairs(failed) do f:write(n, "\n") end
    f:close()
  end

  local names, by_group = {}, {}
  local function rebuild()
    names, by_group = {}, {}
    for _, g in ipairs(GROUPS) do
      local list = {}
      for _, e in ipairs(g[2]) do if not failed[e[1]] then list[#list + 1] = e end end
      if #list > 0 then
        names[#names + 1] = g[1] .. " (" .. #list .. ")"
        by_group[#by_group + 1] = list
      end
    end
    if #names == 0 then names, by_group = { "None" }, { {} } end
  end
  rebuild()

  -- After a switch: did you become them? The player's preset is at
  -- human+0xD4 (the game's own code reads it there).
  local pending, verified = nil, false
  local function switch(it)
    local e = it.items[it.v]
    if not e then return "Nothing to switch to" end
    local why = ENGINE.play_as(e[1])
    if why then return why end
    local ch = wml.callx(0x004A5A90, { ecx = wml.buffer(6, e[1]) })
    local player = G.player()
    pending = { name = e[1], shown = e[2], ch = ch, p = player, actor = wml.read_u32(player + 0x44), until_tick = F.tick + 300 }
    -- Their own voice comes with them (as on SR1), unless you picked one (Emotes > Voice Lines > Voice).
    F.model_voice = e.voice
    if not F.voice_chosen then
      if e.voice then
        G.lua("if not T.own_persona then T.own_persona = character_get_persona(LOCAL_PLAYER) end character_set_persona(LOCAL_PLAYER, %s)", e.voice)
      else
        G.lua("if T.own_persona then character_set_persona(LOCAL_PLAYER, T.own_persona) T.own_persona = nil end")
      end
    end
    return "You're " .. e[2] .. (e.voice and not F.voice_chosen and " (with their voice)" or "")
  end

  local model = { id = "player_model", label = "Player Model", kind = "list", items = by_group[1], nosave = true,
    help = "The character you play as, from the group above. Press A / Enter to switch.",
    run = function(ctx, p, v, it) return switch(it) end }

  F.category("Models", {
    { id = "model_group", label = "Model Group", kind = "choice", options = names, needs = "none", nosave = true,
      help = "Which characters Player Model shows: story characters, homies, DLC, gangs, police, activities, clerks, pedestrians and the rest.",
      change = function(ctx, p, v, it)
        model.items = by_group[it.v] or {}
        model.v = 1
      end },
    model,
    { id = "apply_player_model", label = "Switch to Model", kind = "action",
      help = "Puts you in the Player Model's body.",
      run = function() return switch(model) end },
    { id = "restore_player_model", label = "Restore Your Model", kind = "action",
      help = "Back to your own character.",
      run = function()
        pending = nil
        ENGINE.restore_player()
        F.model_voice = nil
        if not F.voice_chosen then G.lua("if T.own_persona then character_set_persona(LOCAL_PLAYER, T.own_persona) T.own_persona = nil end") end
        return "You're you again"
      end },
    { id = "models_forget_failed", label = "Bring Back Left-Out Models", kind = "action", needs = "none",
      help = "Models that didn't load when you switched to them are left out of the list. This puts them all back.",
      run = function()
        local n = 0
        for _ in pairs(failed) do n = n + 1 end
        failed = {}
        save_failed()
        rebuild()
        F.items.model_group.options = names
        F.items.model_group.v = 1
        model.items = by_group[1]
        model.v = 1
        return n > 0 and (n .. " models back in the list") or "None were left out"
      end },
  })

  F.after_updates[#F.after_updates + 1] = function(p)
    if not pending then return end
    if p == 0 or p ~= pending.p or wml.read_u32(p + 0x44) ~= pending.actor then
      pending = nil
      return
    end
    if wml.read_u32(p + 0xD4) == pending.ch then
      if not verified then wml.log("models: switching checked (" .. pending.name .. " took)") end
      verified = true
      pending = nil
      return
    end
    if F.tick < pending.until_tick then return end
    -- (only once a switch has been seen to take this session: the check itself is then known to work)
    if verified then
      failed[pending.name] = true
      save_failed()
      for i = #model.items, 1, -1 do if model.items[i][1] == pending.name then table.remove(model.items, i) end end
      if model.v > #model.items then model.v = math.max(1, #model.items) end
      wml.log("models: " .. pending.name .. " didn't load; left out of the list from now on")
    else
      wml.log("models: " .. pending.name .. " didn't seem to take (not left out: no switch confirmed yet)")
    end
    pending = nil
  end

  F.category("Customize", {
    { id = "open_creator", label = "Character creator", kind = "action",
      help = "Opens SR2's character creator (the plastic surgeon's) here, free.",
      run = function(_, p)
        if not G.playing(p) or wml.read_u32(p + 0x13B0) == 0 or wml.read_u32(0x025289CC) ~= 0 then
          return "Can't open the creator right now"
        end
        F.creator_requested = true
        return "Opening the character creator"
      end },
  })
end

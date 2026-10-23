-- SR Tweak Menu (Saints Row 2) - the Emotes tab.
--
-- The game's own actions (data/emotes.lua), played on you with
-- action_play_do, the native the mission scripts' action_play wraps (it
-- returns false if it couldn't start; the menu just tries once). Repeat
-- plays the chosen action again every few seconds.

return function(F, G)
  local EMOTES = F.data("emotes")

  local groups, order = {}, {}
  for _, e in ipairs(EMOTES) do
    local g = e[3] or "Actions"
    if not groups[g] then groups[g] = {}; order[#order + 1] = g end
    table.insert(groups[g], e)
  end

  local last  -- the last action played, for Repeat
  local function play(name)
    last = name
    G.lua("action_play_do(LOCAL_PLAYER, %s, nil, true, false)", name)
  end

  local lists = {}
  for i, g in ipairs(order) do
    lists[#lists + 1] = { id = "emotes_" .. i, label = g, kind = "list", items = groups[g], nosave = true,
      help = "Left/Right to choose, Enter plays it.",
      run = function(ctx, p, v, it) play(it.items[it.v][1]) return "Playing " .. it.items[it.v][2] end }
  end
  -- Poses: the game's stand states (data/variants.lua STAND), held with
  -- set_animation_state until Stop.
  local VARIANTS = F.data("variants")
  local pose_groups, pose_order = {}, {}
  for _, s in ipairs(VARIANTS.STAND or {}) do
    local g = s[3] or "Poses"
    if not pose_groups[g] then pose_groups[g] = {}; pose_order[#pose_order + 1] = g end
    table.insert(pose_groups[g], s)
  end
  local pose_lists = {}
  for i, g in ipairs(pose_order) do
    pose_lists[#pose_lists + 1] = { id = "poses_" .. i, label = g, kind = "list", items = pose_groups[g], nosave = true,
      help = "Left/Right to choose, Enter holds the pose (Stop lets go).",
      run = function(ctx, p, v, it)
        G.lua("set_animation_state(LOCAL_PLAYER, %s)", it.items[it.v][1])
        return "Posing: " .. it.items[it.v][2]
      end }
  end

  local rows = {
    F.page("poses", "Poses", "Stand and hold one of the game's poses.", pose_lists),
    F.page("actions", "Actions", "The game's own actions and taunts, by kind.", lists),
  }
  rows[#rows + 1] = { id = "stop_pose", label = "Stop", kind = "action",
    help = "Stops the action you're playing.",
    run = function()
      F.items.repeat_action.v = false
      G.lua('action_stop_custom(LOCAL_PLAYER) set_animation_state(LOCAL_PLAYER, "stand")')
      return "Stopped"
    end }
  rows[#rows + 1] = { id = "repeat_action", label = "Repeat action", kind = "toggle",
    help = "Plays the last action again every Repeat interval.",
    update = function()
      local every = math.floor((F.items.repeat_every.v or 5) * 60)
      if last and F.tick % every == 0 then play(last) end
    end }
  rows[#rows + 1] = { id = "repeat_every", label = "Repeat interval (s)", kind = "value", default = 5, min = 1, max = 30, step = 1,
    fmt = F.fmtint, oneshot = true, needs = "none", help = "How often Repeat action plays it again." }

  -- D-pad taunts: the game's three taunts on D-pad left / right (/ up).
  local TAUNT_MODES = { "Off", "Left and right", "Left, right and up" }
  rows[#rows + 1] = { id = "dpad_taunts", label = "D-pad taunts", kind = "value", default = 1, min = 1, max = #TAUNT_MODES, step = 1,
    fmt = function(v) return TAUNT_MODES[v] or "?" end,
    help = "Multiplayer's three taunts on foot: D-pad left and right (arrow keys), and up too if you like.",
    update = function(ctx, p, v, it)
      if v ~= 0 then return end
      if F.dpad_hit("LEFT") then play("Taunt 1")
      elseif F.dpad_hit("RIGHT") then play("Taunt 2")
      elseif it.v == 3 and F.dpad_hit("UP") then play("Taunt 3") end
    end }

  F.category("Emotes", rows)
end

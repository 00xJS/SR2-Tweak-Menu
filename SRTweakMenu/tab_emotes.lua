-- SR Tweak Menu (Saints Row 2) - the Emotes tab, laid out as SR1's: Poses,
-- Actions, Every Action and Voice Lines are pages of categories, each
-- category a page with one row per emote or line (SR1's F.page_emotes and
-- F.page_voice_lines); then Stop, Repeat and the interval.
--
-- Actions and poses preview the animation clip without entering scripted
-- player control. Voice lines are every persona
-- situation the game has (data/voices.lua), shown only when the voice you have
-- now has a line for it - your own, or the character you play as - as SR1 shows
-- only what the model's voice has: the persona at human+0x10E4, asked with the
-- game's own lookup 0x006AF860 (persona+8, the situation's number; 0xFFFF when
-- it has none), the situation's number from its name with the game's hash
-- (0x00BDCB30: CRC-32 of the lowercase name, from 0, not inverted) and table
-- (0x006ABCE0). Voice picks any persona for you (character_set_persona).

return function(F, G)
  local EMOTES = F.data("emotes")
  local VARIANTS = F.data("variants")
  local ALL = F.data("actions_all")
  local VOICES = F.data("voices")
  local PLAYBACK = require("emote_playback")

  -- ---------------------------------------------------------------- playing
  local last, active, next_repeat

  local function clear(p)
    local token = active
    active, F.posing = nil, nil
    if token then PLAYBACK.stop(p, token) end
  end

  function F.stop_emote(p)
    F.items.repeat_action.v = false
    last, next_repeat = nil, nil
    clear(p)
  end

  local function play(p, kind, name)
    clear(p)
    local loop = kind == "State"
    local token, why = PLAYBACK.play(p, kind, name, false, loop)
    if not token then
      F.stop_emote(p)
      return why
    end
    if not loop then token.until_tick = F.tick + 900 end
    active, F.posing = token, name
    if kind == "Action" then last = name end
    local interval = F.items.repeat_every.v
    next_repeat = F.tick + math.floor(interval * 60)
  end

  function F.update_emotes(p, viewing, navigating)
    if not active and not (last and F.items.repeat_action.v) then return end
    if not viewing or not F.enabled or not PLAYBACK.can_play(p)
      or (active and not PLAYBACK.same_actor(p, active)) then
      F.stop_emote(p)
      return
    end
    if navigating then
      if active then clear(p) end
      next_repeat = F.tick + math.floor(F.items.repeat_every.v * 60)
      return
    end
    if active and ((active.until_tick and F.tick >= active.until_tick) or not PLAYBACK.active(p, active)) then clear(p) end
    if not active and last and F.items.repeat_action.v and F.tick >= next_repeat then
      play(p, "Action", last)
    end
  end

  -- A page of category pages, each with one row per entry: SR1's emote pages.
  -- groups = { { "Category", { { name, "Shown" }, ... } }, ... }
  local function category_pages(title, groups, kind)
    return function()
      local rows = {}
      for _, g in ipairs(groups) do
        if #g[2] > 0 then
          rows[#rows + 1] = { label = g[1], kind = "page", help = #g[2] .. " in " .. g[1] .. ".",
            open = function()
              local r = {}
              for _, e in ipairs(g[2]) do
                r[#r + 1] = { label = e[2], kind = "action", help = g[1] .. ": " .. e[2] .. ".",
                  run = function(_, p) return play(p, kind, e[1]) or e[2] end }
              end
              return { title = g[1], rows = r }
            end }
        end
      end
      if #rows == 0 then return "Nothing here" end
      return { title = title, rows = rows }
    end
  end
  local function grouped(list, default)
    local by, order = {}, {}
    for _, e in ipairs(list) do
      local g = e[3] or default
      if not by[g] then by[g] = {}; order[#order + 1] = g end
      table.insert(by[g], e)
    end
    local out = {}
    for _, g in ipairs(order) do out[#out + 1] = { g, by[g] } end
    return out
  end
  -- Only what a person can play: a name no human animation set has a clip for
  -- (unused names, vehicle and prop actions) is left out (data/emote_clips.lua).
  local CLIPS = F.data("emote_clips")
  local function playable(list, kind)
    local out = {}
    for _, e in ipairs(list) do
      local c = CLIPS[kind] and CLIPS[kind][e[1]:lower()]
      if c and #c > 0 then out[#out + 1] = e end
    end
    return out
  end
  local POSE_GROUPS = grouped(playable(VARIANTS.STAND or {}, "State"), "Poses")
  local ACTION_GROUPS = grouped(playable(EMOTES, "Action"), "Actions")

  -- ---------------------------------------------------------------- voice lines
  local KIND = { combat = "Combat", cower = "Cowering", drug = "Drugs", drunk = "Drunk", escort = "Escort", flee = "Fleeing",
    group = "Group", hitman = "Hitman", hostage = "Hostage", misc = "Misc", observe = "Observing", special = "Special",
    threat = "Threats", voice = "Voice (pain, screams...)", ["player taunt"] = "Taunts", ["player compliment"] = "Compliments",
    fuzz = "FUZZ", ["septic avenger"] = "Septic Avenger", ["crowd control"] = "Crowd Control", dispatch = "Dispatch",
    snatch = "Snatch", heli = "Heli Assault", taxi = "Taxi", ["fight club"] = "Fight Club", streaking = "Streaking",
    ["guardian angel"] = "Guardian Angel", ["call police"] = "Calling the police", piracy = "Piracy", ["tow truck"] = "Tow Truck",
    ["clean sweep"] = "Clean Sweep", sing = "Singing" }
  local ORDER = { "player taunt", "player compliment", "combat", "threat", "voice", "observe", "misc", "special", "cower", "flee",
    "drug", "drunk", "group", "hostage", "sing" }

  -- CRC-32 table (the game's at 0x00E843B8 is the standard one).
  local CRC = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do c = (c & 1) ~= 0 and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
    CRC[i] = c
  end
  local function situation_hash(s)
    local h = 0
    for i = 1, #s do h = (h >> 8) ~ CRC[(h ~ s:lower():byte(i)) & 0xFF] end
    return h & 0xFFFFFFFF
  end
  local index = {}   -- situation name -> the game's number (false: not in the game's table)
  local function situation_number(name)
    local n = index[name]
    if n ~= nil then return n or nil end
    local buf = wml.buffer(13)
    wml.write_u32(buf, situation_hash(name))
    local r = wml.callx(0x006ABCE0, { eax = buf })
    n = (r ~= 0xFFFFFFFF and r < 0x295) and r or false
    index[name] = n
    return n or nil
  end
  -- Does this character's voice have a line for the situation? nil: can't tell.
  local function has_line(p, name)
    if p == 0 then return nil end
    local persona = wml.read_u32(p + 0x10E4)
    if persona == 0 then return nil end
    local n = situation_number(name)
    if not n then return false end
    local buf = wml.buffer(13)
    wml.write_u32(buf, n)
    local ok, r = pcall(wml.callx, 0x006AF860, { esi = persona + 8, eax = buf })
    if not ok then return nil end
    return (r & 0xFFFF) ~= 0xFFFF
  end
  F.voice_has_line = has_line

  local function say(name)
    F.menu_line = true
    G.lua("audio_play_persona_line(LOCAL_PLAYER, %s)", name)
    F.menu_line = nil
  end

  local function voice_lines(ctx, p)
    local by, kinds = {}, {}
    local unknown = false
    for _, s in ipairs(VOICES.SITUATIONS or {}) do
      local has = has_line(p, s)
      if has == nil then unknown = true end
      if has ~= false then
        local kind, what = s:match("^(.-) %- (.+)$")
        kind = kind or "misc"
        if not by[kind] then by[kind] = {}; kinds[#kinds + 1] = kind end
        by[kind][#by[kind] + 1] = { s, what or s }
      end
    end
    -- Taunts, compliments and the everyday kinds first, then the activities'.
    local rank = {}
    for i, k in ipairs(ORDER) do rank[k] = i end
    table.sort(kinds, function(a, b)
      local ra, rb = rank[a] or 100, rank[b] or 100
      if ra ~= rb then return ra < rb end
      return a < b
    end)
    local rows = { F.items.voice_persona }
    for _, kind in ipairs(kinds) do
      local list = by[kind]
      rows[#rows + 1] = { label = KIND[kind] or (kind:sub(1, 1):upper() .. kind:sub(2)), kind = "page",
        help = #list .. " lines this voice has.",
        open = function()
          local r = {}
          for _, e in ipairs(list) do
            r[#r + 1] = { label = e[2]:sub(1, 1):upper() .. e[2]:sub(2), kind = "action", help = "Says it: " .. e[1] .. ".",
              run = function(c, pp)
                if has_line(pp, e[1]) == false then return "No line for that in this voice" end
                say(e[1])
                return e[2]
              end }
          end
          return { title = KIND[kind] or kind, rows = r }
        end }
    end
    if #rows == 1 then return "No voice lines for this character" end
    return { title = unknown and "Voice Lines (all)" or "Voice Lines", rows = rows }
  end

  -- Voice: any persona the game has, on you (Your own voice puts yours back).
  local PERSONAS = { { "", "Own voice (yours, or the model's)" } }
  for _, v in ipairs(VOICES.PERSONAS or {}) do PERSONAS[#PERSONAS + 1] = v end
  local voice_row = { id = "voice_persona", label = "Voice", kind = "list", items = PERSONAS, nosave = true,
    help = "Whose voice you speak with: the player voices, every story character and everyone else. Enter puts it on; the lines below follow it.",
    run = function(ctx, p, v, it)
      local name = it.items[it.v][1]
      if name == "" then
        F.voice_chosen = false
        if F.model_voice then
          G.lua("if not T.own_persona then T.own_persona = character_get_persona(LOCAL_PLAYER) end character_set_persona(LOCAL_PLAYER, %s)", F.model_voice)
          return "The model's own voice"
        end
        G.lua("if T.own_persona then character_set_persona(LOCAL_PLAYER, T.own_persona) T.own_persona = nil end")
        return "Your own voice"
      end
      F.voice_chosen = true
      G.lua("if not T.own_persona then T.own_persona = character_get_persona(LOCAL_PLAYER) end character_set_persona(LOCAL_PLAYER, %s)", name)
      return "Voice: " .. it.items[it.v][2]
    end }
  F.register({ voice_row })

  -- ---------------------------------------------------------------- the tab
  local ALL_GROUPS = {}
  local all_count = 0
  for _, cat in ipairs(ALL) do
    local list = playable(cat[2], "Action")
    all_count = all_count + #list
    if #list > 0 then ALL_GROUPS[#ALL_GROUPS + 1] = { cat[1], list } end
  end

  local rows = {
    { id = "poses", label = "Poses", kind = "page", needs = "player", open = category_pages("Poses", POSE_GROUPS, "State"),
      help = "Preview the game's stand poses. Stop or leave Emotes to end the preview." },
    { id = "actions", label = "Actions", kind = "page", needs = "player", open = category_pages("Actions", ACTION_GROUPS, "Action"),
      help = "Taunts, gang signs, dances, reactions and the rest, by kind." },
    { id = "all_actions", label = "Every Action", kind = "page", needs = "player", open = category_pages("Every Action", ALL_GROUPS, "Action"),
      help = "Preview loaded clips from the game's action tables. Some clips only load during an activity or near certain characters." },
    { id = "player_voice_lines", label = "Voice Lines", kind = "page", needs = "player", open = voice_lines,
      help = "Every line your character's voice has, and any voice you like." },
    { id = "stop_pose", label = "Stop", kind = "action",
      help = "Stops the pose or action you're playing.",
      run = function(_, p)
        F.stop_emote(p)
        return "Stopped"
      end },
    { id = "repeat_action", label = "Repeat action", kind = "toggle", nosave = true,
      help = "Repeats the last action while Emotes is open. Stop or leave Emotes to cancel.",
      change = function(_, p)
        if not F.items.repeat_action.v and last then F.stop_emote(p) end
      end },
    { id = "repeat_every", label = "Repeat interval (s)", kind = "value", default = 3, min = 1, max = 15, step = 0.5,
      fmt = F.fmt1, oneshot = true, needs = "none", help = "How often Repeat action plays it again." },
  }
  F.category("Emotes", rows)
end

-- SR Tweak Menu (Saints Row 2) - runtime part.
--
-- The host (scripts\SRTweakMenu.asi or dinput8.dll) calls wml.on_frame's
-- functions once a frame on the game's main thread. From there, as SR1's
-- main.lua does it: the controller goes to the menu, and the menu's answer
-- (what the game mustn't see) to the host's wrap of the game's controller
-- read; the keys go to the menu; the rows are applied (features.lua); the
-- menu is drawn - in the game look with SR2's own interface (gameui.lua),
-- or as text the host prints.

local G = require("game")
local F = require("features")
-- SR1's layout (tabs, pages, row order) as it is, then the SR2-only rows
-- into the pages that fit them. SR1 rows SR2 hasn't got are counted, not
-- logged one by one.
do
  local log, missing = wml.log, 0
  wml.log = function(msg, ...)
    if tostring(msg):find("^layout: no row ") then missing = missing + 1 return end
    if tostring(msg):find("wasn't placed") then return end   -- (layout_sr2.lua places them)
    return log(msg, ...)
  end
  -- Show active tweaks as a page of what's changed, and SR1's two restores (defaults.lua).
  local DEFAULTS = require("defaults")
  DEFAULTS.setup(F, F.forget_tweaks)
  local ok, err = pcall(function() require("layout").apply(F) require("layout_sr2").apply(F) end)
  require("gangdots").setup(F, G)
  DEFAULTS.snapshot()   -- (how the menu starts, before saved tweaks)
  -- Saved tweaks (Settings > Save tweaks for next time) back on, as SR1 does.
  local okl, errl = pcall(F.load_tweaks)
  if not okl then log("saved tweaks not loaded: " .. tostring(errl)) end
  -- The Favorites tab (last) and the hotkeys: favorites.lua.
  local okf, errf = pcall(function() require("favorites").setup(F) end)
  if not okf then log("favorites failed to load: " .. tostring(errf)) end
  wml.log = log
  if not ok then wml.log("layout failed: " .. tostring(err)) end
  if missing > 0 then wml.log(string.format("layout: %d SR1 rows aren't on Saints Row 2 yet", missing)) end
end
local MENU = require("menu")
-- (menu.lua adds rows of its own - Menu background - after the saved tweaks were read)
do
  local ok, err = pcall(F.load_tweaks)
  if not ok then wml.log("saved tweaks not loaded: " .. tostring(err)) end
end
local GAMEUI = require("gameui")
local FREECAM = require("freecam")

-- SR1's Quick Camera opens the camera controls and starts the camera.
local PAD_LS, PAD_RS = 0x0040, 0x0080
local quick_prev, quick_session, hud_owned = false, false, false
local HUD_HIDE_COUNT = 0x02528518
local function quick_camera(buttons)
  local combo = (buttons & (PAD_LS | PAD_RS)) == (PAD_LS | PAD_RS)
  local ok, key = pcall(wml.key_pressed, "F7")
  local hit = (combo and not quick_prev) or (ok and key)
  quick_prev = combo
  if not hit or MENU.is_open() or MENU.locked or not F.on("camera_shortcut") or not G.playing(G.player()) then return end
  local it = F.items.free_cam
  if not FREECAM.on then
    FREECAM.set_mode(1)
    if F.items.cam_mode then F.items.cam_mode.v = 1 end
    if not FREECAM.enter() then return end
  end
  MENU.open_camera(nil)
  quick_session = true
  if it then it.v = FREECAM.on end
end

G.debug = wml.setting("debug", false)
F.debug = G.debug

local SELFTEST = wml.setting("selftest", false) and require("selftest")
local PROBE = wml.setting("dev_probe", false) and require("probe")
local PROBE_ENV = { G = G, F = F, MENU = MENU }

-- Actor-aware control ownership; never release a mission's existing lock.
local control_guard = require("menu_control_guard").new(G, wml)
local function hold_player(on) control_guard.update(on) end

local told_source
local leaks_told = 0
local map_hidden = false
local fitting_state
local function fitting_pose(p, name)
  local actor = p ~= 0 and wml.read_u32(p + 0x44) or 0
  if fitting_state and (fitting_state.p ~= p or fitting_state.actor ~= actor or fitting_state.name ~= name) then
    if fitting_state.p == p and fitting_state.actor == actor
      and wml.read_u32(p + 0x1130) == fitting_state.applied then
      local ptr = wml.buffer(15)
      wml.write_u32(ptr, fitting_state.previous)
      wml.callx(0x009695F0, { ecx = p }, ptr)
    end
    fitting_state = nil
  end
  if name and not fitting_state then
    local previous = wml.read_u32(p + 0x1130)
    local ok = G.lua("set_animation_state(LOCAL_PLAYER, %s)", name)
    if ok then
      fitting_state = { p = p, actor = actor, name = name, previous = previous, applied = wml.read_u32(p + 0x1130) }
    end
  end
end
local preview_weapon
local function preview_equipment(p, viewing)
  local actor = p ~= 0 and wml.read_u32(p + 0x44) or 0
  if preview_weapon and (not viewing or preview_weapon.actor ~= actor) then
    if p == preview_weapon.p and actor == preview_weapon.actor then
      G.lua('local equipped = inv_item_get_equipped_item(LOCAL_PLAYER) '
        .. 'if (not equipped or equipped == "") and inv_has_item(%s, LOCAL_PLAYER) then inv_item_equip(%s, LOCAL_PLAYER) end',
        preview_weapon.name, preview_weapon.name)
    end
    preview_weapon = nil
  end
  if viewing and not preview_weapon then
    local _, name = G.lua("tweak_out(inv_item_get_equipped_item(LOCAL_PLAYER))")
    if type(name) == "string" and name ~= "" then
      G.lua("inv_item_equip(nil, LOCAL_PLAYER)")
      preview_weapon = { p = p, actor = actor, name = name }
    end
  end
end
MENU.cleanup_preview = function()
  local p = G.player()
  local cleanup = {
    function() if F.stop_emote then F.stop_emote(p) end end,
    function() if F.update_style_preview then F.update_style_preview(p, nil) end end,
    function() fitting_pose(p, nil) end,
    function() preview_equipment(p, false) end,
    function() FREECAM.orbit(false) end,
    function() hold_player(false) end,
    function() if wml.preview_mode then wml.preview_mode(false, false) end end,
  }
  for _, release in ipairs(cleanup) do
    local ok, why = pcall(release)
    if not ok then wml.log("preview cleanup: " .. tostring(why)) end
  end
end
local tick = 0
wml.on_frame(function()
  if SELFTEST then SELFTEST.frame() end
  if PROBE then PROBE.frame(PROBE_ENV) end
  tick = tick + 1
  local buttons, lt, rt = wml.pad()
  F.pad_prev, F.pad = F.pad or 0, buttons or 0
  local was_open = MENU.is_open()
  local replay = MENU.controller(buttons or 0, lt or 0, rt or 0)
  local combo_hold, combo_press = MENU.combo_mask()
  local _, _, _, _, poll_hooks = wml.pad_debug()
  local partial_ok = (poll_hooks or 0) > 0
  if tick == 900 or tick == 3600 then
    local updates, polls, blocks, count, hooks = wml.pad_debug()
    wml.log(string.format("controller: %d input updates, %d with the pad device (%d buttons), %d blocked, %d polls through the wrap",
      updates, polls, count, blocks, hooks or 0))
  end
  local source = wml.pad_source()
  if source ~= told_source and (source == "game" or tick > 600) then
    told_source = source
    wml.log(source == "game" and "controller: read through the game's own call; the menu keeps it from the game while open"
      or "controller: the game's reads don't come through the wrap; using the script input hold")
  end
  MENU.input(nil, tick)
  do
    local ok, err = pcall(require("favorites").frame, MENU.is_open(), MENU.locked)
    if not ok then wml.log("hotkeys: " .. tostring(err)) end
  end
  quick_camera(buttons or 0)
  F.set_menu_open(MENU.is_open())
  -- The minimap drew over the menu: hidden while the menu is open (as SR2's own
  -- menus clear the HUD), shown again when it closes (re-hidden now and then:
  -- the HUD can bring it back by itself).
  local open = MENU.is_open()
  if open and (not map_hidden or tick % 30 == 0) then
    G.vint('local f = rawget(_G, "hud_hide_map") if f then f() end')
    map_hidden = true
  elseif not open and map_hidden then
    map_hidden = false
    G.vint('local f = rawget(_G, "hud_show_map") if f then f() end')
  end
  -- The host's hard lock: a held-back button that was still down after the
  -- game's input update had every action dropped with it. Said when the menu
  -- closes, so a log shows whether the lock was needed and held.
  if was_open and not open then
    local _, _, _, _, hooks, leaks = wml.pad_debug()
    if leaks and leaks ~= leaks_told then
      wml.log(string.format("controller: hard lock dropped %d held-back presses the poll wrap missed (%d polls through the wrap so far)",
        leaks - leaks_told, hooks or 0))
      leaks_told = leaks
    end
  end
  -- Evidence, once at the first menu open: which of the HUD script's globals
  -- the menu's interface code can see. "Hud_player_status missing" said it
  -- can't see hud.lua's tables; this shows whether it sees none of hud.lua
  -- (separate environment per document) or only some.
  if open and not was_open and not F.hud_env_logged then
    F.hud_env_logged = true
    local r = table.pack(pcall(G.vint, [[
      local names = { "Hud_player_status", "Hud_weapon_status", "hud_hide_map", "hud_hide", "Sui_hud_enable",
        "Sui_hud_modern_layout", "vint_document_find", "getfenv", "vint_set_global", "TWK_HUD" }
      for i = 1, 10 do tweak_out(names[i] .. "=" .. rawget(_G, "type")(rawget(_G, names[i]))) end
      -- Where hud.lua's environment is: any global table holding Hud_player_status,
      -- and what getfenv gives for a few levels.
      local nx, ty, ge = rawget(_G, "next"), rawget(_G, "type"), rawget(_G, "getfenv")
      local k, v = nx(_G)
      while k do
        if ty(v) == "table" and v ~= _G and rawget(v, "Hud_player_status") then tweak_out("env_in_global:" .. rawget(_G, "tostring")(k)) end
        k, v = nx(_G, k)
      end
      for lvl = 0, 3 do
        local ok, e = rawget(_G, "pcall")(ge, lvl)
        tweak_out("getfenv" .. lvl .. "=" .. (ok and (e == _G and "_G" or (ty(e) == "table" and (rawget(e, "Hud_player_status") and "HUD_ENV" or "other")) or "?") or "err"))
      end
    ]]))
    local parts = {}
    for i = 3, r.n do parts[#parts + 1] = tostring(r[i]) end
    wml.log("interface globals: " .. (r[1] and table.concat(parts, " ") or ("check failed: " .. tostring(r[2]))))
  end
  local emotes_open = open and MENU.tab_name() == "Emotes"
  local block_all, hide = MENU.game_input(was_open)
  local flying = FREECAM.flying()
  local all = block_all or flying or (hide ~= 0 and not partial_ok)
  local p = G.player()
  if wml.grab_remap then wml.grab_remap(false) end
  wml.pad_filter(all, hide, combo_hold, combo_press)
  if not all and replay ~= 0 and not MENU.locked then wml.pad_inject(replay, 4) end
  -- Customize, Emotes and a car being customized hold you (and the car's
  -- driver) with the game's own player_controls_disable too, not only by
  -- keeping the pad back: the pad block alone let the character and the car
  -- creep forward. Released the moment you leave them or the menu closes.
  hold_player(open)
  if F.update_emotes then F.update_emotes(p, emotes_open, MENU.navigating) end
  F.update(nil)
  -- SR1's fitting room: on Customize the camera in front of you (you on the
  -- right of the screen, the menu on the left; the sticks turn and slide it)
  -- and the clothing store's stand. Emotes uses the same camera.
  do
    local p = G.player()
    local tab = MENU.is_open() and MENU.tab_name()
    local car_preview = open and F.vehicle_preview
    if car_preview and not require("vehicle_customize").valid(car_preview) then
      F.vehicle_preview, car_preview = nil, nil
    end
    local viewing = p ~= 0 and (car_preview or ((tab == "Customize" or emotes_open)
      and require("emote_playback").can_play(p))) and not FREECAM.on
    if car_preview then require("vehicle_customize").hold(car_preview) end
    FREECAM.vehicle_preview = car_preview
    preview_equipment(p, viewing and not car_preview)
    local movement = viewing and tab == "Customize" and MENU.pages[1] and MENU.pages[1].from == "style_movement"
    FREECAM.orbit(viewing, viewing and FREECAM.facing_yaw(p) or 0, movement)
    local fitting = viewing and not car_preview and tab == "Customize" and not movement
    local pose = F.items.look_pose
    fitting_pose(p, fitting and ((pose and pose.pose_name and pose.pose_name()) or "Cust Stand") or nil)
    if wml.preview_mode then wml.preview_mode(open and F.enabled, fitting and F.on("customization_tpose")) end
    if F.update_style_preview then F.update_style_preview(p, movement and MENU.current()) end
  end
  FREECAM.update(MENU.is_open())
  -- (the camera can stop by itself: a cutscene, too far from you)
  if F.items.free_cam and F.items.free_cam.v ~= FREECAM.on then F.items.free_cam.v = FREECAM.on end
  if F.items.cam_mode and FREECAM.on and F.items.cam_mode.v ~= FREECAM.mode then F.items.cam_mode.v = FREECAM.mode end
  if not FREECAM.on then quick_session = false end
  local want_hud_hidden = G.player() ~= 0 and (F.on("hide_hud") or (quick_session and F.on("camera_hide_ui"))) and true or false
  -- Hide HUD hides only the "hud" document (its safe_frame), not with the
  -- engine's hud_hide: that one hides every HUD document, hud_msg too, which
  -- the menu is drawn under - so turning the HUD off turned the menu's game
  -- look into the terminal. Re-applied now and then (the HUD can re-show it).
  local hidden = wml.read_u32(HUD_HIDE_COUNT)
  if want_hud_hidden ~= hud_owned or (want_hud_hidden and tick % 30 == 0) then
    local ok = G.vint(([[
      local ok, d = pcall(vint_document_find, "hud")
      if ok and d and d ~= 0 then
        local found, f = pcall(vint_object_find, "safe_frame", nil, d)
        if found and f and f ~= 0 then vint_set_property(f, "visible", %s) tweak_out(true) end
      end]]):format(want_hud_hidden and "false" or "true"))
    hud_owned = want_hud_hidden
  end
  -- (only the game's own hides - cutscenes, its menus - move the menu to text)
  MENU.render(tick, hidden > 0)
  local ok, err = pcall(GAMEUI.present)
  if not ok then wml.log("menu (game look): " .. tostring(err)) GAMEUI.frame = nil end
end)

wml.log("SR Tweak Menu for Saints Row 2 ready: " .. tostring(wml.setting("menu_key", "F5")) .. " or "
  .. tostring(wml.setting("menu_pad", "RB+DOWN")) .. " opens it")

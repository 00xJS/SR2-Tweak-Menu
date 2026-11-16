-- SR Tweak Menu (Saints Row 2) - the on-screen menu: SR Tweak Menu 2.6's
-- menu.lua (Saints Reborn), brought over as it is, with the game look
-- rebuilt on Saints Row 2's own interface pieces.
--
-- Tabs across the top (one per feature category), a cursor down the rows.
-- Keys: F5 opens and closes, Up/Down move, Left/Right adjust a value or
-- browse a list, Enter toggles or runs, Backspace closes, PgUp/PgDn change
-- tab. Controller: RB + D-pad down opens and closes (menu_pad), D-pad moves,
-- A selects, B goes back, LB/RB change tab; holding Back opens it too.
--
-- The controller: the host wraps the game's own controller read
-- (XInputGetState, through which Juiced Patch hands the game every kind of
-- pad), so while the menu is open the game gets nothing from the pad that
-- the menu uses (main.lua passes M.controller's answer to wml.pad_filter).
-- The menu captures buttons while open. Sticks are available in gameplay
-- tabs, and reserved for the camera in Customize and Emotes. Buttons
-- still held when the menu closes stay hidden from the game until they are
-- let go, so the B that closed it doesn't also hit someone. The keyboard:
-- the menu's keys (and while you can't move, the game's own) are taken
-- from the game through the host's DirectInput wrap.
--
-- Drawing: two looks (Settings > Menu UI). Terminal: the text goes into the
-- mailbox the host draws with the game's text printer. Game: the menu is
-- built from SR2's own menu art and fonts (gameui.lua).

local G = require("game")
local F = require("features")
local S = wml.setting
-- Two looks (Settings > Menu UI, menu_style in mod.ini): the plain overlay
-- text, silent, or itsMJQ's game look - the menu drawn with the game's own
-- interface (gameui.lua: its fonts, menu pictures and sounds).
local GAMEUI = require("gameui")
-- Favorites and hotkeys: F / Y pins a row, H gives it a key (favorites.lua).
local FAV = require("favorites")
local style_game = require("menu_settings").style ~= "text"
local retry_at = 0
local UI = setmetatable({ sound = function(ctx, name) if style_game then GAMEUI.sound(ctx, name) end end }, { __index = GAMEUI })

local M = { open = false, tab = 1, cursor = {}, scroll = {}, status = "", status_until = 0, dll = false, pad = 0 }

local MAILBOX, MAGIC = 0x00F00000, 0x53524D55
local TEXT_OFFSET, TEXT_MAX = 0x40, 8192
local ROWS = S("menu_rows", 12)
local WINDOWS = package.config:sub(1, 1) == "\\"  -- the mailbox exists only in the Windows build
local use_overlay = S("menu_overlay", true) and WINDOWS

local KEY = {
  open = tostring(S("menu_key", "F5")), up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
  enter = "ENTER", back = "BACKSPACE", prev = "PAGEUP", next = "PAGEDOWN", fast = "SHIFT",
}
-- Taken while open: the menu's own keys, and every key Saints Reborn maps
-- onto the pad on foot or in a car (kbm.cpp), so they read as keys only.
local TAKEN = { "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACKSPACE", "PAGEUP", "PAGEDOWN",
  "Q", "E", "R", "F", "C", "V", "X", "Z", "H", "SPACE", "SHIFT", "CTRL", "TAB" }
local MOVE_KEYS = { "W", "A", "S", "D" }
-- XINPUT_GAMEPAD bits; LT and RT are analog and get bits of their own.
local PAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8, START = 0x10, BACK = 0x20, LS = 0x40, RS = 0x80,
  LB = 0x100, RB = 0x200, A = 0x1000, B = 0x2000, X = 0x4000, Y = 0x8000, LT = 0x10000, RT = 0x20000 }
M.PAD = PAD
M.TAKEN = TAKEN
local TRIGGER_PRESSED = 85  -- of 255: a trigger a third of the way in counts as pressed
local PAD_ALIAS = {
  R1 = "RB", L1 = "LB", R2 = "RT", L2 = "LT", R3 = "RS", L3 = "LS",
  CROSS = "A", CIRCLE = "B", SQUARE = "X", TRIANGLE = "Y",
  OPTIONS = "START", MENU = "START", SHARE = "BACK", SELECT = "BACK", VIEW = "BACK",
  DPAD_UP = "UP", DPAD_DOWN = "DOWN", DPAD_LEFT = "LEFT", DPAD_RIGHT = "RIGHT",
}
local PAD_LABEL = { UP = "D-pad Up", DOWN = "D-pad Down", LEFT = "D-pad Left", RIGHT = "D-pad Right" }

-- The controller combo (menu_pad): hold every button but the last, press the
-- last. While the held ones are down the last one is kept from the game, so
-- RB + D-pad down never reaches the game as Cancel Activity.
local combo_hold, combo_press, combo_text = 0, 0, ""
local function parse_combo(text)
  local hold, press, names = 0, 0, {}
  for raw in text:gmatch("[^+%s]+") do
    local name = raw:upper()
    name = PAD_ALIAS[name] or name
    if not PAD[name] then return nil, raw end
    hold = hold | press
    press = PAD[name]
    names[#names + 1] = PAD_LABEL[name] or name
  end
  if press == 0 then return 0, 0, "" end
  return hold, press, table.concat(names, " + ")
end
do
  local text = tostring(S("menu_pad", "RB+DOWN"))
  local hold, press, label = parse_combo(text)
  if not hold then
    wml.log("menu_pad: unknown button '" .. press .. "' in '" .. text .. "'; using RB+DOWN")
    hold, press, label = parse_combo("RB+DOWN")
  end
  combo_hold, combo_press, combo_text = hold, press, label
end
M.combo_text = combo_text
-- (for the host: it hides the last button itself while the held ones are down)
function M.combo_mask() return combo_hold, combo_press end
M.parse_combo = parse_combo
local HOLD = require("hold_button")
local back_hold = HOLD.new(math.max(0.3, tonumber(S("menu_hold_seconds", 0.8)) or 0.8))
local hold_enabled = S("menu_hold_back", false)   -- (SR2: off by default; a tap of Back can't be handed back to the game)
function M.reset_controller()
  M.pad, M.hold_toggle = 0, false
  back_hold.started, back_hold.fired, back_hold.tap, back_hold.blocked = nil, nil, nil, true
end

for i = 1, #F.categories do M.cursor[i] = 1; M.scroll[i] = 1 end

local swallow = 0   -- pad bits held when the menu closed, hidden until let go
local tap_armed, tapped = 0, 0  -- see track_taps
local device = "keys"  -- what the hints at the bottom name: "keys" or "pad"

local function say(text)
  if not text then return end
  M.status, M.status_until = text, M.tick + 150
  if not M.dll then G.hud(text) end
end

-- Rows and tabs that only apply sometimes (it.hidden / cat.hidden: the
-- Customize rows for someone else, or for you) are left out.
local function shown(x)
  if not x.hidden then return true end
  local ok, hidden = pcall(x.hidden)
  return not (ok and hidden)
end
local function rows(tab)
  local cat = F.categories[tab]
  F.rows_tab = cat.name   -- (a row in two tabs shows in the one that fits)
  local list = {}
  for _, it in ipairs(cat.items) do if shown(it) then list[#list + 1] = it end end
  return list, cat
end
M.rows = rows
local function step_tab(from, dir)
  local n = #F.categories
  local t = from
  for _ = 1, n do
    t = ((t - 1 + dir) % n) + 1
    if shown(F.categories[t]) then return t end
  end
  return from
end
M.step_tab = step_tab

-- Pages: a row of kind "page" opens one (it.open(ctx, p) gives { title,
-- rows, back }), like the stores' and the creator's menus: a list of
-- categories, then what's in one, then its colours. B goes back a page
-- (page.back runs first: a store puts back what you only tried on); LB / RB
-- and closing the menu leave them all. Each page keeps its own cursor.
M.pages = {}
local function page() return M.pages[#M.pages] end
local function view_rows()
  local pg = page()
  if not pg then return rows(M.tab) end
  F.rows_tab = "page"
  local list = {}
  for _, it in ipairs(pg.rows) do if shown(it) then list[#list + 1] = it end end
  return list, F.categories[M.tab]
end
M.view_rows = view_rows
local function cursor() local pg = page() if pg then return pg.cursor end return M.cursor[M.tab] end
local function scroll() local pg = page() if pg then return pg.scroll end return M.scroll[M.tab] end
local function set_view(c, s)
  local pg = page()
  if pg then pg.cursor, pg.scroll = c, s or pg.scroll else M.cursor[M.tab], M.scroll[M.tab] = c, s or M.scroll[M.tab] end
end
local function push_page(pg)
  pg.cursor, pg.scroll = pg.cursor or 1, 1
  M.pages[#M.pages + 1] = pg
  -- (headings aren't rows you can be on)
  local list = view_rows()
  local c = pg.cursor
  while list[c] and list[c].kind == "header" and c < #list do c = c + 1 end
  set_view(c, math.max(1, c - ROWS + 1))
end
local function pop_page(ctx, why)
  local pg = table.remove(M.pages)
  if pg and pg.back then pcall(pg.back, ctx, why) end
  return pg
end
local function leave_pages(ctx, why) while #M.pages > 0 do pop_page(ctx, why) end end
M.leave_pages = leave_pages
-- B on a page with something tried and not accepted asks first, like the
-- game's own customization screens: Yes keeps it, No puts back what you
-- had, B again stays.
local SAVE_TEXT = "Do you want to save your changes before exiting?"
local function confirm_leave(ctx, leave)
  local pg = page()
  if not pg or not pg.dirty or not pg.dirty() then return false end
  UI.sound(ctx, "popup")
  push_page({ title = "Save Changes", confirm = true, rows = {
    { label = "Yes", kind = "action", help = SAVE_TEXT, run = function(c)
        pop_page(c, "confirm")
        local why = pg.accept and pg.accept(c)
        if why then return why end
        leave(c)
        return "Changes saved"
      end },
    { label = "No", kind = "action", help = SAVE_TEXT, run = function(c)
        pop_page(c, "confirm")
        leave(c)
        return "Changes discarded"
      end },
  } })
  return true
end
local function back_page(ctx)
  if not confirm_leave(ctx, function(c) pop_page(c, "back") end) then
    pop_page(ctx, "back")
    UI.sound(ctx, "back")
  end
end
M.back_page = back_page

local function current_item()
  local list, cat = view_rows()
  local c = math.max(1, math.min(cursor(), #list))
  return list[c] or cat.items[1], cat
end

-- ------------------------------------------------------------- mailbox
local seq, last_text = 0, nil
local function mailbox_write(text)
  if text == last_text then return end
  last_text = text
  local n = math.min(#text, TEXT_MAX)
  local base = MAILBOX + TEXT_OFFSET
  local i = 1
  while i + 3 <= n do
    wml.write_u32(base + i - 1, (text:byte(i) << 24) | (text:byte(i + 1) << 16) | (text:byte(i + 2) << 8) | text:byte(i + 3))
    i = i + 4
  end
  while i <= n do wml.write_u8(base + i - 1, text:byte(i)); i = i + 1 end
  wml.write_u32(MAILBOX + 0x14, n)
  seq = seq + 1
  wml.write_u32(MAILBOX + 0x10, seq)
end

local function check_dll()
  if not use_overlay then M.dll = false return end
  local had = M.dll
  M.dll = wml.read_u32(MAILBOX) == MAGIC
  if M.dll ~= had then wml.log(M.dll and "menu: overlay DLL found" or "menu: overlay DLL not found; HUD messages instead") end
end

-- ------------------------------------------------------------- open/close
-- Closing remembers the pages you were on (by the rows that opened them) and
-- opening goes back to them, each with its cursor, as long as they still open.
local function remember_pages()
  local path = {}
  for _, pg in ipairs(M.pages) do
    if pg.confirm or not pg.from then break end
    path[#path + 1] = { from = pg.from, cursor = pg.cursor, scroll = pg.scroll }
  end
  M.resume = { tab = M.tab, path = path }
end
local function restore_pages(ctx)
  local r = M.resume
  M.resume = nil
  if not r or r.tab ~= M.tab or #M.pages > 0 then return end
  local p = G.player()
  if p == 0 then return end
  for _, step in ipairs(r.path) do
    local it
    for _, row in ipairs((view_rows())) do
      if row.kind == "page" and (row.id or row.label) == step.from then it = row break end
    end
    if not it then return end
    local ok, pg = pcall(it.open, ctx, p, it)
    if not ok or type(pg) ~= "table" then return end
    pg.from = step.from
    push_page(pg)
    local n = #(view_rows())
    pg.cursor = math.max(1, math.min(step.cursor or 1, math.max(1, n)))
    pg.scroll = math.max(1, math.min(step.scroll or 1, pg.cursor))
  end
end
M.remember_pages, M.restore_pages = remember_pages, restore_pages
local function set_open(open, how)
  if open == M.open then return end
  if not open and how ~= "confirmed" then
    if page() and page().confirm then return end
    if confirm_leave(M.ctx, function(c)
      pop_page(c, "back")
      set_open(false, "confirmed")
    end) then return end
  end
  M.open = open
  if wml.menu_capture then wml.menu_capture(open) end
  if not open and M.cleanup_preview then M.cleanup_preview() end
  for _, k in ipairs(TAKEN) do wml.take_key(k, open) end
  tap_armed = 0
  UI.sound(M.ctx, open and "pause" or (how == "back" and "back" or "resume"))
  if open then
    check_dll()
    restore_pages(M.ctx)
    M.refresh_now = true
    say(M.dll and "" or "Menu open (no overlay): " .. current_item().label)
  else
    remember_pages()
    leave_pages(M.ctx, "close")
    last_text = nil
    if M.dll then mailbox_write("") end
  end
end
M.close_for_game = function()
  set_open(false, "confirmed")
  M.resume = nil
end

function M.device() return device end

-- Open a particular section without replaying the remembered page stack.
function M.open_camera(ctx)
  if M.open or M.locked then return end
  M.ctx, M.resume = ctx, nil
  for i, cat in ipairs(F.categories) do
    if cat.name == "Visual" then M.tab = i break end
  end
  set_open(true)
  local it = F.items.visual_free_camera
  if it and it.open then
    local pg = it.open(ctx, G.player(), it)
    pg.from = it.id
    push_page(pg)
  end
end

-- ------------------------------------------------------------- navigation
local function move(dir)
  local list = view_rows()
  local n = math.max(1, #list)
  local c = math.min(cursor(), n)
  for _ = 1, n do
    c = ((c - 1 + dir) % n) + 1
    if not (list[c] and list[c].kind == "header") then break end
  end
  UI.sound(M.ctx, "scroll")
  local s = scroll()
  if c < s then s = c end
  if c >= s + ROWS then s = c - ROWS + 1 end
  -- (a heading just above the top row stays in sight)
  if c == s and c > 1 and list[c - 1] and list[c - 1].kind == "header" then s = c - 1 end
  set_view(c, s)
  -- A row that shows itself when you land on it (a store's piece tried on).
  local on = list[c]
  if on and on.hover then
    local ok, err = pcall(on.hover, M.ctx, G.player(), on)
    if not ok then wml.log("hover " .. tostring(on.label) .. ": " .. tostring(err)) end
  end
  if not M.dll then
    local it = current_item()
    say(it.label .. " " .. F.value_text(it))
  end
end

local function switch_tab(dir)
  if page() and page().confirm then return end
  if confirm_leave(M.ctx, function(c)
    pop_page(c, "back")
    switch_tab(dir)
  end) then return end
  leave_pages(M.ctx, "tab")
  if M.cleanup_preview then M.cleanup_preview() end
  M.tab = step_tab(M.tab, dir)
  UI.sound(M.ctx, "lr")
  if not M.dll then say("Tab: " .. F.categories[M.tab].name) end
end

local slide
local function adjust(ctx, dir)
  local it = current_item()
  if it.kind == "value" or it.kind == "choice" or it.kind == "list" then
    UI.sound(ctx, "lr")
    say(F.adjust(ctx, it, dir, wml.key_down(KEY.fast)))
  elseif it.kind == "toggle" then
    say(F.toggle(ctx, it))
    M.toggle_sound(ctx, it)
  end
end

-- A slider (Image As Designed's, the pause menu's): held, it glides - slowly
-- at first, faster the longer it's held - with one sound as it starts, none
-- for each step, and stops at either end.
local sliding = nil
function slide(ctx, it, dir)  -- (the local declared above)
  if dir == 0 or not it then sliding = nil return end
  local now = os.clock()
  if not sliding or sliding.it ~= it or sliding.dir ~= dir then
    sliding = { it = it, dir = dir, start = now, last = now }
    if (dir < 0 and it.v > it.min) or (dir > 0 and it.v < it.max) then UI.sound(ctx, "lr") end
  end
  local dt = math.min(0.05, now - sliding.last)
  sliding.last = now
  local held = now - sliding.start
  -- (a touch moves it one step; held, from 10 a second up to 90 after ~1.5 s)
  local range = it.max - it.min
  local speed = range * (0.10 + 0.80 * math.min(1, held / 1.5) ^ 2)
  if wml.key_down(KEY.fast) then speed = speed * 2 end
  local step = held == 0 and (it.step or 1) or speed * dt
  local nv = math.max(it.min, math.min(it.max, it.v + dir * step))
  -- (wrap rows, e.g. Time of Day: a press past the end starts over: 23 -> 0, 0 -> 23)
  if it.wrap and held == 0 and nv == it.v then nv = dir > 0 and it.min or it.max end
  if nv == it.v then return end
  it.v = nv
  local p = G.player()
  if it.change and (p ~= 0 or it.needs == "none") then pcall(it.change, ctx, p, 0, it) end
end
M.slide = function(ctx, it, dir) return slide(ctx, it, dir) end

-- Toggles answer like the pause menu's Yes / No; the master switch like Quit.
function M.toggle_sound(ctx, it)
  if it.id == "master" then UI.sound(ctx, it.v and "okay" or "quit")
  else UI.sound(ctx, it.v and "yes" or "no") end
end
local FAILED = { "^no ", "^can't", "^couldn't", "^not ", "^that ", "^too many", "^change into", "^get in", "^load a",
  "^already", "can't ", "isn't ", " first$", "won't ", "didn't ", "^error", "^nothing", "^none" }
function M.failed(msg)
  if type(msg) ~= "string" then return false end
  local m = msg:lower()
  for _, p in ipairs(FAILED) do if m:find(p) then return true end end
  return false
end

local function activate(ctx, row)
  -- Lists act on the entry shown on the row (picked with Left/Right).
  local it = row or current_item()
  if it.kind == "header" then return end
  if it.kind == "page" then
    local p = G.player()
    if p == 0 then UI.sound(ctx, "error"); say("Load a game first") return end
    local ok, pg = pcall(it.open, ctx, p, it)
    if not ok then wml.log("page " .. tostring(it.id or it.label) .. ": " .. tostring(pg)); UI.sound(ctx, "error"); say("Error, see wml.log") return end
    if type(pg) == "string" then UI.sound(ctx, "error"); say(pg) return end
    UI.sound(ctx, "select")
    pg.from = it.id or it.label
    push_page(pg)
    return
  end
  if it.kind == "toggle" then
    say(F.activate(ctx, it))
    M.toggle_sound(ctx, it)
    return
  end
  UI.sound(ctx, "select")
  local result = F.activate(ctx, it)
  -- (a page that wants the cursor somewhere next: after a colour, its wear option)
  local pg = page()
  if pg and pg.focus then set_view(pg.focus, 1); pg.focus = nil end
  -- (an answer that closes pages: Yes / No on overwriting or deleting a preset)
  for i = #M.pages, 1, -1 do
    local q = M.pages[i]
    if q.close_after then
      local n = q.close_after
      q.close_after = nil
      for _ = 1, n do pop_page(ctx, "done") end
      break
    end
  end
  -- The pause menu's answers: an error beep when it couldn't be done, the
  -- shop's sound for money, weapons and ammo, OK for the rest that did something.
  if M.failed(result) then UI.sound(ctx, "error")
  elseif it.id and (it.id:find("cash") or it.id:find("respect") or it.id:find("weapon") or it.id:find("ammo") or it.id:find("refill")) then
    UI.sound(ctx, "purchase")
  elseif it.kind == "action" then UI.sound(ctx, "okay") end
  say(result)
end

-- ------------------------------------------------------------- input
-- Keys repeat while held: first after 14 updates, then every 4.
local held = {}
local function repeating(name, down)
  if not down then held[name] = nil return false end
  local h = held[name]
  if not h then held[name] = 14 return true end
  h = h - 1
  if h <= 0 then held[name] = 4 return true end
  held[name] = h
  return false
end

local pad_prev = 0
-- Buttons for menu actions: the combo's last button doesn't count while the
-- held ones are down, so the combo that closes the menu doesn't also move it.
local function nav()
  if combo_hold ~= 0 and (M.pad & combo_hold) == combo_hold then return M.pad & ~combo_press end
  return M.pad
end
local function nav_prev()
  if combo_hold ~= 0 and (pad_prev & combo_hold) == combo_hold then return pad_prev & ~combo_press end
  return pad_prev
end
local function pad_down(bit) return (nav() & bit) ~= 0 end
-- A button held for the combo (RB) acts when it is let go, and only if no
-- other button was pressed meanwhile; any other button acts when pressed.
local function track_taps()
  tap_armed = tap_armed | (M.pad & ~pad_prev & combo_hold)
  if (M.pad & ~combo_hold) ~= 0 then tap_armed = 0 end
  tapped = tap_armed & ~M.pad
  tap_armed = tap_armed & M.pad
end
local function pad_hit(bit)
  if (combo_hold & bit) ~= 0 then return (tapped & bit) ~= 0 end
  return (nav() & bit) ~= 0 and (nav_prev() & bit) == 0
end

local DEVICE_KEYS = { "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACKSPACE", "PAGEUP", "PAGEDOWN" }
local function prompt_label(pr) return (type(pr.label) == "function" and pr.label() or pr.label):upper() end
M.prompt_label = prompt_label
local function track_device()
  if KEY.open ~= "" and wml.key_down(KEY.open) then device = "keys" return end
  for _, k in ipairs(DEVICE_KEYS) do
    if wml.key_down(k) then device = "keys" return end
  end
  if (M.pad & ~pad_prev) ~= 0 then device = "pad" end
end

function M.input(ctx, tick)
  M.tick, M.ctx = tick, ctx
  M.navigating = false
  FAV.refresh()
  -- A tab that stopped applying (Customize as someone with no options) is
  -- left; rows that came and went keep the cursor on one that's there.
  if not shown(F.categories[M.tab]) then M.tab = step_tab(M.tab, 1) end
  if #M.pages > 0 and not shown(F.categories[M.tab]) then leave_pages(ctx, "gone") end
  local n_rows = math.max(1, #view_rows())
  if cursor() > n_rows then set_view(n_rows) end
  if scroll() > cursor() then set_view(cursor(), cursor()) end
  -- What your character can do right now, for the Pose and Action counts.
  if M.open and (M.refresh_now or tick % 50 == 1) then M.refresh_now = false; pcall(F.refresh_usable, ctx) end
  if tick % 100 == 0 then check_dll() end
  track_taps()
  track_device()
  local was_open = M.open
  -- Open / close. (M.locked: the game's safe, trunk or cache is up; it has the controls.)
  local toggle = M.hold_toggle or (KEY.open ~= "" and wml.key_pressed(KEY.open))
    or (combo_press ~= 0 and (M.pad & combo_hold) == combo_hold
      and (M.pad & combo_press) ~= 0 and (pad_prev & combo_press) == 0)
  M.hold_toggle = false
  if toggle and not M.locked then set_open(not M.open) end
  if M.open and was_open and FAV.binding then
    -- Waiting for the key to give a row (H): nothing else moves meanwhile.
    M.navigating = true
    local msg = FAV.poll_bind(pad_hit(PAD.B))
    if msg then UI.sound(ctx, M.failed(msg) and "error" or "okay") say(msg) end
  elseif M.open and was_open then
    if (wml.key_pressed(KEY.back) or pad_hit(PAD.B)) and #M.pages > 0 then
      M.navigating = true
      back_page(ctx)
    elseif wml.key_pressed(KEY.back) or pad_hit(PAD.B) then
      M.navigating = true
      set_open(false, "back")
    elseif wml.key_pressed(KEY.prev) or pad_hit(PAD.LB) then
      M.navigating = true
      switch_tab(-1)
    elseif wml.key_pressed(KEY.next) or pad_hit(PAD.RB) then
      M.navigating = true
      switch_tab(1)
    else
      local u, d = wml.key_down(KEY.up) or pad_down(PAD.UP), wml.key_down(KEY.down) or pad_down(PAD.DOWN)
      if repeating("up", u) then move(-1) end
      if repeating("down", d) then move(1) end
      local it = current_item()
      local l, r = wml.key_down(KEY.left) or pad_down(PAD.LEFT), wml.key_down(KEY.right) or pad_down(PAD.RIGHT)
      M.navigating = u or d or l or r
      if it.kind == "value" and it.bar then
        slide(ctx, it, (r and 1 or 0) - (l and 1 or 0))
      else
        slide(ctx, nil, 0)
        if repeating("left", l) then adjust(ctx, -1) end
        if repeating("right", r) then adjust(ctx, 1) end
      end
      if not M.navigating and (wml.key_pressed(KEY.enter) or pad_hit(PAD.A)) then activate(ctx) end
      -- F / Y pins the row to Favorites (or unpins it), H gives it a hotkey.
      local here = page()
      if not M.navigating and not (here and here.confirm) then
        local pin = wml.key_pressed("F") or pad_hit(PAD.Y)
        if pin or wml.key_pressed("H") then
          local msg = pin and FAV.toggle_pin(current_item()) or FAV.start_bind(current_item())
          UI.sound(ctx, M.failed(msg) and "error" or "select")
          say(msg)
        end
      end
      -- A page's button prompts (pg.prompts: { pad = "X", key = "R",
      -- label = "RANDOMIZE" or a function, run = function(ctx, p) }), shown
      -- next to MOVE / CHANGE.
      local pg = page()
      for _, pr in ipairs(not M.navigating and pg and pg.prompts or {}) do
        if (pr.key and wml.key_pressed(pr.key)) or (pr.pad and pad_hit(PAD[pr.pad])) then
          local p = G.player()
          if p == 0 then UI.sound(ctx, "error") break end
          local ok, msg = pcall(pr.run, ctx, p)
          if not ok then wml.log("prompt: " .. tostring(msg)); UI.sound(ctx, "error")
          else UI.sound(ctx, "select"); if type(msg) == "string" then say(msg) end end
          break
        end
      end
    end
  end
  pad_prev = M.pad
end

-- Called from the controller-read hook with the buttons word and the two
-- triggers. Returns true when the game should see no input at all (menu
-- open), else a mask of PAD bits to hide from the game: the combo's last
-- button while the held ones are down, and whatever was still held when the
-- menu closed, until it is let go.
-- True while the menu combo is being pressed (its held buttons and its last one).
function M.combo_down(buttons)
  return combo_hold ~= 0 and (buttons & combo_hold) == combo_hold and (buttons & combo_press) ~= 0
end
function M.controller(buttons, lt, rt)
  local pad = buttons | ((lt or 0) >= TRIGGER_PRESSED and PAD.LT or 0) | ((rt or 0) >= TRIGGER_PRESSED and PAD.RT or 0)
  M.pad = pad
  local replay, held_back = 0, false
  if hold_enabled then
    local toggle, tap, hide = HOLD.update(back_hold, (pad & PAD.BACK) ~= 0, os.clock(),
      M.open or G.playing(G.player()), M.open)
    if toggle then M.hold_toggle = true end
    replay, held_back = tap and PAD.BACK or 0, hide
  end
  if held_back then swallow = swallow | PAD.BACK end
  return replay
end

-- Resolve ownership after processing open/close/tab changes, before the game
-- polls this frame. Keep menu buttons hidden until they are released.
function M.game_input(was_open)
  local tab = M.open and M.tab_name()
  local fitting_room = M.open -- gameplay movement is captured on every menu page
  if fitting_room ~= M.move_keys_taken then
    M.move_keys_taken = fitting_room
    for _, k in ipairs(MOVE_KEYS) do wml.take_key(k, fitting_room) end
  end
  if was_open ~= M.open or fitting_room then
    swallow = M.pad
    return true, swallow
  end
  if M.open then
    swallow = M.pad
    -- A fresh press can arrive during the next poll, so mask every button.
    return true, 0x3FFFF
  end
  swallow = swallow & M.pad
  if M.combo_down(M.pad) then swallow = swallow | M.pad end
  return false, swallow
end

-- ------------------------------------------------------------- drawing
local function pad_right(s, n)
  if #s >= n then return s end
  return s .. string.rep(" ", n - #s)
end

-- Help text goes under the rows a whole sentence at a time, up to
-- HELP_WIDTH characters a line; a sentence longer than that breaks at a
-- space.
local HELP_WIDTH = 90
local function help_text(value)
  if type(value)=="table" then
    local lines={}
    for _,v in ipairs(value) do if type(v)=="string" or type(v)=="number" then lines[#lines+1]=tostring(v) end end
    return table.concat(lines," ")
  end
  return (type(value)=="string" or type(value)=="number") and tostring(value) or ""
end
local STATUS_LINES = 4
-- `fits(line)` (optional) measures a line on screen instead of counting
-- characters, so the game-look box never cuts a line off.
local function wrap_help(text, fits)
  text=help_text(text)
  fits = fits or function(l) return #l <= HELP_WIDTH end
  local out, line = {}, ""
  local function flush() if line ~= "" then out[#out + 1] = line; line = "" end end
  for sentence in (text:gsub("([%.!?])%s+", "%1\n") .. "\n"):gmatch("(.-)\n") do
    if sentence ~= "" then
      if not fits(sentence) then
        flush()
        for word in sentence:gmatch("%S+") do
          if line ~= "" and not fits(line .. " " .. word) then flush() end
          line = line == "" and word or (line .. " " .. word)
        end
        flush()
      elseif line ~= "" and not fits(line .. " " .. sentence) then
        flush()
        line = sentence
      else
        line = line == "" and sentence or (line .. " " .. sentence)
      end
    end
  end
  flush()
  return out
end
M.wrap_help = wrap_help

-- ------------------------------------------------------------- game look
--
-- The menu built the way Saints Row 2's own menus are (menu_base.lua and
-- its art on the interface-backend sheets): LB / RB and the tabs above the
-- menu like its horizontal menus; the menu itself a sheet of grey paper
-- (ui_menu_tmp_box_b_bg) with rough painted sides (_mid_side_a), the title
-- in white on the dark brush stroke across its top (_frm_cap_m) over the
-- header rule (_hr), rows 32 high on alternating grey stripes (_row_a /
-- _row_b) in dark text (tint 0.2, as menu_base.lua sets every label), the
-- torn yellow bar on the row you're on (_sel_l / _sel_r), the menus'
-- arrows round what you can change, the yellow-on-grey slider, the scroll
-- bar, the chrome swirl under it all (_mid_trm_a); then the description in
-- one of its black dialogs with the chrome swirls (_dialog_*), and the
-- buttons the way its menus show them (ui_ctrl_360_btn_*). Laid out in
-- 1280 x 720 units from the top left (menu_x, menu_y), times menu_scale.
local MX, MY = S("menu_x", 36), S("menu_y", 36)
local K = math.max(0.5, math.min(2.0, S("menu_scale", 1.0)))
local W = math.max(400, math.min(640, S("menu_width", 500)))
-- Volition's own type, read out of menu_base.vint_doc (every text object's
-- font, text_scale, force_case and tint) and menu_base.lua:
--   the horizontal menu   header_n_overlay, capitals; the one you're on 0.5 in gold (0.898, 0.749, 0.051),
--                         the others 0.4 in grey
--   menu_header_text      header_n_overlay, capitals, 0.45, tint (0.773, 0.796, 0.812)
--   menu_option_label     thin_overlay 0.68 (rows 32 high: MENU_ITEM_HEIGHT)
--   menu_sel_bar_label    thin 0.68, black (the label on the yellow bar; value_text the same)
--   menu_btn_tip_label    header_n_overlay 0.4, tint (0.624, 0.635, 0.643), beside the button's picture
-- Font keys here: "thin" = thin_overlay, "ink" = thin (no shadow, for the bar), "giant" = header_n_overlay.
local GOLD = { 229, 191, 13, 255 }
local INK = { 0, 0, 0, 255 }
local HEAD = { 197, 203, 207, 255 }
local TIP = { 159, 162, 164, 255 }
local WHITE = { 255, 255, 255, 255 }
local LIGHT = { 230, 230, 230, 255 }
local TYPE = { tab = 0.5, tab_side = 0.4, title = 0.45, row = 0.68, section = 0.4, tip = 0.4, help = 0.55 }
-- Where the letters sit in each font's cell (measured in fnt_body_n / fnt_head_n: the cell's height, the
-- line the letters stand on, the height of a capital, the blank before a letter), at size 1.
local FACE = {
  thin = { cell = 47, base = 33, cap = 21, bear = 4 },
  ink = { cell = 47, base = 33, cap = 21, bear = 4 },
  giant = { cell = 66, base = 50, cap = 34, bear = 5 },
}

-- The text, shortened with "..." to fit `room` layout units, and its width.
local function fit(ctx, font, size, text, room)
  local w = UI.width(ctx, font, text) * size
  if w <= room then return text, w end
  while #text > 1 do
    text = text:sub(1, -2)
    w = UI.width(ctx, font, text .. "...") * size
    if w <= room then return text .. "...", w end
  end
  return text, w
end

function M.build_frame(ctx)
  -- (Settings > Menu background: how solid the paper and boxes are; 60% is their own look)
  local bg = F.items.menu_background and F.items.menu_background.v or 60
  local function alpha(base) return math.min(255, math.floor(base * math.max(bg, 10) / 60 + 0.5)) end
  local fr = {}
  local function quad(image, x, y, w, h, colour)
    fr[#fr + 1] = { image = image, x = x, y = y, w = w, h = h, colour = colour }
  end
  local function text(font, size, s, x, y, colour)
    fr[#fr + 1] = { text = s, font = font, size = size, x = x, y = y, colour = colour }
  end
  -- Text by its letters, not its cell: `x` is where the letters start ("left"), end ("right") or are centred,
  -- `mid` the height of the middle of their capitals. Returns the width.
  local function put(font, size, s, x, mid, colour, align)
    local f = FACE[font] or FACE.thin
    local wd = UI.width(ctx, font, s) * size
    local bear = f.bear * size
    if align == "right" then x = x - wd - size
    elseif align == "centre" then x = x - (bear + wd + size) / 2
    else x = x - bear end
    text(font, size, s, x, mid - (f.base - f.cap / 2) * size, colour)
    return wd
  end
  -- (the same, standing on a line: `base` is where the letters stand)
  local function stand(font, size, s, x, base, colour, align)
    local f = FACE[font] or FACE.thin
    return put(font, size, s, x, base - f.cap * size / 2, colour, align)
  end
  -- One of SR2's black dialogs: its nine pieces (the swirls are in the corners).
  local function dialog(x, y, w, h, a)
    local s = 0.5 * K
    local col = { 255, 255, 255, a }
    local lw, rw, th, bh = 34 * s, 47 * s, 44 * s, 59 * s
    local nw, ne, sw, se = 113 * s, 119 * s, 119 * s, 119 * s
    if h < th + bh then th, bh = h / 2, h / 2 end
    quad("ui_menu_tmp_dialog_c", x + lw, y + th, w - lw - rw, h - th - bh, col)
    quad("ui_menu_tmp_dialog_w", x, y + th, lw, h - th - bh, col)
    quad("ui_menu_tmp_dialog_e", x + w - rw, y + th, rw, h - th - bh, col)
    quad("ui_menu_tmp_dialog_n", x + nw, y, w - nw - ne, th, col)
    quad("ui_menu_tmp_dialog_s", x + sw, y + h - bh, w - sw - se, bh, col)
    quad("ui_menu_tmp_dialog_nw", x, y, nw, th, col)
    quad("ui_menu_tmp_dialog_ne", x + w - ne, y, ne, th, col)
    quad("ui_menu_tmp_dialog_sw", x, y + h - bh, sw, bh, col)
    quad("ui_menu_tmp_dialog_se", x + w - se, y + h - bh, se, bh, col)
  end
  local pad = device == "pad"
  local row_size, help_size, tip_size = TYPE.row * K, TYPE.help * K, TYPE.tip * K
  local w = W * K
  local x0, y = MX, MY
  local cx = x0 + w / 2
  local cat = F.categories[M.tab]
  local list = view_rows()

  -- The horizontal menu: LB, the tab before, the one you're on, the one after, RB - three even columns
  -- between the buttons, each name centred in its own, all standing on one line; a name too wide for its
  -- column shrinks to fit.
  local nav_h = 34 * K
  local nav_base = y + nav_h - 7 * K
  local col = (w - 2 * 46 * K) / 3
  local function tab_name(name, size, centre, colour)
    local tw = UI.width(ctx, "giant", name) * size
    if tw > col - 12 * K then size = size * (col - 12 * K) / tw end
    stand("giant", size, name, centre, nav_base, colour, "centre")
  end
  tab_name(F.categories[step_tab(M.tab, -1)].name:upper(), TYPE.tab_side * K, cx - col, TIP)
  tab_name(cat.name:upper(), TYPE.tab * K, cx, GOLD)
  tab_name(F.categories[step_tab(M.tab, 1)].name:upper(), TYPE.tab_side * K, cx + col, TIP)
  local nav_mid = nav_base - FACE.giant.cap * TYPE.tab * K / 2
  if pad then
    quad("ui_ctrl_360_btn_lb", x0, nav_mid - 13.5 * K, 37 * K, 27 * K)
    quad("ui_ctrl_360_btn_rb", x0 + w - 37 * K, nav_mid - 13.5 * K, 37 * K, 27 * K)
  else
    stand("giant", tip_size, "PGUP", x0, nav_base, TIP, "left")
    stand("giant", tip_size, "PGDN", x0 + w, nav_base, TIP, "right")
  end
  y = y + nav_h + 12 * K

  -- The menu: a frame of the menus' grey paper, scratched all round (painted sides, rough trims along the top
  -- and bottom) round a black inside; the brush stroke and the header across its top, the rule under it.
  local rows_shown = math.min(ROWS, #list)
  local row_h = 32 * K
  local head_h = 52 * K
  local body_h = head_h + rows_shown * row_h + 14 * K
  local paper_y = y + 30 * K
  local frame_h = body_h - 30 * K
  quad("ui_blank", x0, paper_y, w, frame_h, { 168, 168, 166, alpha(235) })
  quad("ui_menu_tmp_box_b_bg", x0, paper_y, w, 22 * K, { 255, 255, 255, alpha(235) })
  quad("ui_blank", x0 + 7 * K, paper_y + 7 * K, w - 14 * K, frame_h - 14 * K, { 0, 0, 0, alpha(230) })
  quad("ui_menu_tmp_mid_side_a", x0 - 6 * K, paper_y, 10 * K, frame_h)
  quad("ui_menu_tmp_mid_side_a", x0 + w - 4 * K, paper_y, 10 * K, frame_h)
  quad("ui_menu_tmp_frm_trm_a", x0 - 6 * K, paper_y + frame_h - 5 * K, w + 12 * K, 9 * K)
  quad("ui_menu_tmp_frm_trm_b", x0 - 6 * K, paper_y + frame_h - 1 * K, w + 12 * K, 6 * K)
  quad("ui_menu_tmp_frm_cap_m", x0 - 10 * K, y - 2 * K, w + 20 * K, 40 * K)
  quad("ui_menu_tmp_frm_trm_a", x0 - 6 * K, paper_y - 3 * K, w + 12 * K, 8 * K)
  local box = (cat.title or cat.name):upper()
  local title = page() and page().title:upper() or (F.enabled and box or (box .. " (ALL OFF)"))
  local tsize = TYPE.title * K
  local tw = UI.width(ctx, "giant", title) * tsize
  if tw > w - 44 * K then tsize = tsize * (w - 44 * K) / tw end
  put("giant", tsize, title, x0 + 20 * K, y + 18 * K, HEAD, "left")
  quad("ui_menu_tmp_hr", x0 + 6 * K, y + head_h - 10 * K, w - 12 * K, 5 * K)

  local s, e = scroll(), math.min(#list, scroll() + ROWS - 1)
  local ry = y + head_h - 4 * K
  local scrolling = #list > ROWS
  local inner = w - (scrolling and 46 or 28) * K
  local lx = x0 + 14 * K
  local aw, ah = 12 * K, 17 * K   -- the menus' arrows (22 x 30)
  for i = s, e do
    local it = list[i]
    local selected = i == cursor()
    local mid = ry + row_h / 2
    local stripe = ((i - s) % 2 == 0) and "ui_menu_tmp_row_a" or "ui_menu_tmp_row_b"
    quad(stripe, lx, ry + 2 * K, inner, row_h - 4 * K, { 255, 255, 255, 55 })
    if it.kind == "header" then
      -- A heading inside a page: the header font in gold, centred, over a rule.
      local hs = TYPE.section * K
      local hw = UI.width(ctx, "giant", it.label:upper()) * hs
      if hw > inner - 16 * K then hs = hs * (inner - 16 * K) / hw end
      put("giant", hs, it.label:upper(), lx + inner / 2, mid - 2 * K, GOLD, "centre")
      quad("ui_menu_tmp_hr", lx + 30 * K, ry + row_h - 6 * K, inner - 60 * K, 4 * K)
    else
      if selected then
        quad("ui_menu_tmp_sel_l", lx - 4 * K, ry + 1 * K, inner + 2 * K, row_h - 2 * K)
        quad("ui_menu_tmp_sel_r", lx + inner - 2 * K, ry + 1 * K, 6 * K, row_h - 2 * K)
      end
      local value = F.value_text(it)
      if it.kind == "action" then value = it.note and it.note() or "" end
      if it.kind == "list" then
        value = (it.ok and #it.ok == 0) and "none available" or (it.items[it.v][2] .. "  " .. F.list_position(it))
      elseif it.kind == "toggle" then
        value = it.v and "ON" or "OFF"
      elseif value:sub(1, 2) == "< " then
        value = value:sub(3, -3)
      end
      local changeable = it.kind == "value" or it.kind == "choice" or it.kind == "list" or it.kind == "toggle"
      -- (white on the black inside - the shadowed face; black on the yellow bar - the plain one)
      local font = selected and "ink" or "thin"
      local ink = selected and INK or WHITE
      local arrow_col = selected and INK or TIP
      local left = lx + 10 * K
      if it.kind == "page" then
        -- More under it: the menus' arrow pointing on.
        local label = fit(ctx, font, row_size, it.label, inner - 20 * K - aw - 12 * K)
        put(font, row_size, label, left, mid, ink, "left")
        quad("ui_menu_tmp_arrow_e", lx + inner - aw - 8 * K, mid - ah / 2, aw, ah, arrow_col)
      elseif it.kind == "value" and it.bar then
        -- A slider: grey, filled yellow to the value.
        local frac = (it.v - it.min) / math.max(1e-9, it.max - it.min)
        if it.live and it.read then
          local ok, r = pcall(it.read, G.player())
          if ok and r then frac = (r - it.min) / math.max(1e-9, it.max - it.min) end
        end
        frac = math.max(0, math.min(1, frac))
        local bw, bh = inner * 0.36, 11 * K
        local bx, by = lx + inner - bw - (aw + 12 * K), mid - bh / 2
        local label = fit(ctx, font, row_size, it.label, bx - left - (aw + 16 * K))
        put(font, row_size, label, left, mid, ink, "left")
        quad("ui_menu_tmp_slider_bg_c", bx, by, bw, bh)
        quad("ui_menu_tmp_slider_bg_a", bx, by, bw * frac, bh)
        if selected then
          quad("ui_menu_tmp_arrow_w", bx - aw - 5 * K, mid - ah / 2, aw, ah, arrow_col)
          quad("ui_menu_tmp_arrow_e", bx + bw + 5 * K, mid - ah / 2, aw, ah, arrow_col)
        end
      else
        -- The value on the right (between the arrows on the row you're on), the label in what's left.
        local arrows = selected and changeable and value ~= ""
        local right = lx + inner - (arrows and (aw + 12 * K) or 10 * K)
        local v, vw = "", 0
        if value ~= "" then v, vw = fit(ctx, font, row_size, value, (inner - 20 * K) * 0.6) end
        local taken = value ~= "" and (vw + (arrows and (aw + 22 * K) or 16 * K)) or 0
        local label = fit(ctx, font, row_size, it.label, right - left - taken)
        put(font, row_size, label, left, mid, ink, "left")
        if value ~= "" then
          -- (a tweak that's off reads quieter than one that's on)
          local vink = (not selected and it.kind == "toggle" and not it.v) and TIP or ink
          put(font, row_size, v, right, mid, vink, "right")
          if arrows then
            quad("ui_menu_tmp_arrow_w", right - vw - aw - 7 * K, mid - ah / 2, aw, ah, arrow_col)
            quad("ui_menu_tmp_arrow_e", right + 5 * K, mid - ah / 2, aw, ah, arrow_col)
          end
        end
      end
    end
    ry = ry + row_h
  end
  -- The scroll bar, inside the right edge, when the rows don't all fit.
  if scrolling then
    local sx, sy, sh = x0 + w - 26 * K, y + head_h, rows_shown * row_h - 6 * K
    quad("ui_menu_tmp_scrl_line", sx + 4 * K, sy, 4 * K, sh, { 255, 255, 255, 200 })
    local th = math.max(16 * K, sh * ROWS / #list)
    local pos = (scroll() - 1) / math.max(1, #list - ROWS)
    quad("ui_menu_tmp_scrl_bar_1", sx, sy + (sh - th) * pos, 12 * K, th)
  end
  -- The chrome swirl closing the menu.
  quad("ui_menu_tmp_mid_trm_a", cx - 90 * K, y + body_h - 10 * K, 180 * K, 24 * K)
  y = y + body_h + 20 * K

  -- The buttons, where SR2's menus keep theirs (under the menu, always in the same place): the button's
  -- picture, then what it does in the header font. A is the game's own button tag (drawn as the pad's
  -- button), B and Y their pictures; on the keyboard the key's name in gold.
  local tx, tmid = x0 + 2 * K, y + 13 * K
  local function tip(s) tx = tx + put("giant", tip_size, s, tx, tmid, TIP, "left") + 20 * K end
  local function key(s) tx = tx + put("giant", tip_size, s:upper(), tx, tmid, GOLD, "left") + 8 * K end
  local function button(name)
    if name == "A" or name == "X" then
      local tag = name == "A" and "{MENU_SELECT_IMG}" or "{MENU_ALT_SELECT_IMG}"
      text("thin", row_size, tag, tx, tmid - FACE.thin.cell * row_size / 2, WHITE)
      tx = tx + 30 * K
    elseif name == "B" or name == "Y" then
      quad("ui_ctrl_360_btn_" .. name:lower(), tx, tmid - 12 * K, 24 * K, 24 * K)
      tx = tx + 30 * K
    else
      key(name)
    end
  end
  if pad then
    button("A") tip(page() and "ACCEPT" or "SELECT")
    button("B") tip(page() and "RETURN" or "CLOSE")
    for _, pr in ipairs(page() and page().prompts or {}) do button(pr.pad) tip(prompt_label(pr)) end
    if FAV.can_pin(current_item()) then button("Y") tip(FAV.pinned(current_item()) and "UNPIN" or "PIN") end
  else
    key("ENTER") tx = tx + 2 * K tip(page() and "ACCEPT" or "SELECT")
    key("BACKSPACE") tx = tx + 2 * K tip(page() and "RETURN" or "CLOSE")
    for _, pr in ipairs(page() and page().prompts or {}) do key(pr.key) tx = tx + 2 * K tip(prompt_label(pr)) end
    if FAV.can_pin(current_item()) then key("F") tx = tx + 2 * K tip(FAV.pinned(current_item()) and "UNPIN" or "PIN") end
  end
  y = y + 26 * K + 8 * K

  -- The description (and messages, in gold first) in a black dialog; as many lines as the screen has room for.
  local it = current_item()
  local help = help_text(it.help)
  if it.kind == "value" and help ~= "" and not it.bar then help = help .. "  Default " .. it.fmt(it.default) .. "." end
  help = help .. FAV.note(it)
  local room = w - 44 * K
  local function fits(l) return #l <= HELP_WIDTH and UI.width(ctx, "thin", l) * help_size <= room end
  local lines = wrap_help(help, fits)
  local status_n = 0
  if M.status ~= "" and M.tick < M.status_until then
    local wrapped = wrap_help(M.status, fits)
    status_n = math.min(#wrapped, STATUS_LINES)
    for k = status_n, 1, -1 do table.insert(lines, 1, wrapped[k]) end
  end
  local line_h = 23 * K
  local most = math.max(1, math.floor((712 - y - 30 * K) / line_h))
  if #lines > most then
    for k = #lines, most + 1, -1 do lines[k] = nil end
    lines[most] = fit(ctx, "thin", help_size, lines[most] .. " ...", room)
  end
  if #lines > 0 then
    local help_h = #lines * line_h + 30 * K
    dialog(x0, y, w, help_h, alpha(235))
    local hmid = y + 15 * K + line_h / 2
    for li, l in ipairs(lines) do
      put("thin", help_size, (fit(ctx, "thin", help_size, l, room)), x0 + 22 * K, hmid, li <= status_n and GOLD or LIGHT, "left")
      hmid = hmid + line_h
    end
  end
  return fr
end

-- "game" (the game's interface) or "text" (plain overlay text); live.
function M.set_style(name)
  style_game = name ~= "text"
  retry_at = 0
  GAMEUI.ok = true
  if not style_game then GAMEUI.frame = nil end
  UI.retry()
end
function M.style() return style_game and "game" or "text" end

-- The plain text menu's box. The text is drawn by Saints Reborn's overlay at
-- (40, 120) x S pixels in a font 26 x S tall (S = window height / 1080, at
-- least 0.75), white with a shadow and no box; in the game's 1280 x 720
-- layout that is (26.7, 80) and 17.3 tall. The box is drawn under it in
-- the game's own frame (gameui.lua), as wide as the longest line, measured
-- with Segoe UI Bold's character widths (in ems).
local function em_width(line)
  local w = 0
  for c in line:gmatch(".") do
    if c == " " then w = w + 0.27
    elseif c:match("[ilj|!.,:;'`]") then w = w + 0.27
    elseif c:match("[ftrI%[%]%(%)%-/]") then w = w + 0.38
    elseif c:match("[mwMW]") then w = w + 0.86
    elseif c:match("%u") then w = w + 0.66
    elseif c:match("%d") then w = w + 0.56
    elseif c:match("[<>=+_~]") then w = w + 0.58
    else w = w + 0.55 end
  end
  return w
end
local TEXT_X, TEXT_Y, TEXT_SIZE = 40 * 2 / 3, 120 * 2 / 3, 26 * 2 / 3
local function backdrop(lines)
  local opacity = F.items.menu_background and F.items.menu_background.v or 0
  if opacity <= 0 then return nil end
  local widest = 0
  for _, l in ipairs(lines) do widest = math.max(widest, em_width(l)) end
  local pad = TEXT_SIZE * 0.7
  return { image = "ui_menu_box_base_c", x = TEXT_X - pad, y = TEXT_Y - pad * 0.7,
    w = widest * TEXT_SIZE + pad * 2, h = #lines * TEXT_SIZE + pad * 1.6,
    colour = { 128, 128, 128, math.floor(opacity / 100 * 255 + 0.5) } }
end

function M.render(tick, hud_hidden)
  if M.logged_open ~= (M.open == true) then
    M.logged_open = M.open == true
    GAMEUI.logged_menu_draw = false
    if wml.log then wml.log("Menu: " .. (M.logged_open and "opened" or "closed") .. "; tick=" .. tostring(tick) .. "; game look=" .. tostring(style_game)) end
  end
  GAMEUI.backdrop = nil
  if M.open and style_game and tick >= retry_at and UI.ready() and (not hud_hidden or UI.independent or not M.dll) then
    local ok, fr = pcall(M.build_frame, M.ctx)
    if ok then
      GAMEUI.frame = fr
      if M.dll and last_text ~= "" then mailbox_write("") end
      return
    end
    wml.log("menu (game look): " .. tostring(fr) .. "; temporary text fallback; retrying")
    retry_at = tick + 60
  end
  GAMEUI.frame = nil
  if not M.dll then return end
  if not M.open then return end
  local lines = {}
  local tabs = {}
  for i, cat in ipairs(F.categories) do
    if shown(cat) then tabs[#tabs + 1] = (i == M.tab) and ("[" .. cat.name .. "]") or cat.name end
  end
  -- (tight, so all ten tabs fit the same 90 characters as the help)
  lines[#lines + 1] = "SR TWEAK MENU" .. (F.enabled and "" or "   (all tweaks OFF)")
  local tab_line = table.concat(tabs, "  ")
  if #tab_line > HELP_WIDTH then tab_line = table.concat(tabs, " ") end   -- (eleven tabs, with Favorites)
  lines[#lines + 1] = tab_line
  lines[#lines + 1] = ""
  local cat = F.categories[M.tab]
  local list = view_rows()
  if page() then lines[#lines + 1] = "> " .. page().title:upper() end
  local s = scroll()
  local e = math.min(#list, s + ROWS - 1)
  if s > 1 then lines[#lines + 1] = "    ..." end
  for i = s, e do
    local it = list[i]
    local mark = (i == cursor()) and "> " or "  "
    local value = F.value_text(it)
    if it.kind == "action" then value = it.note and it.note() or "" end
    if it.kind == "list" then
      value = (it.ok and #it.ok == 0) and "< none available >" or (F.value_text(it) .. "   " .. F.list_position(it))
    end
    if it.kind == "page" then value = ">" end
    if it.kind == "header" then lines[#lines + 1] = "  -- " .. it.label:upper() .. " --"
    else lines[#lines + 1] = mark .. pad_right(it.label, 32) .. value end
  end
  if e < #list then lines[#lines + 1] = "    ..." end
  lines[#lines + 1] = ""
  local it = current_item()
  local help = help_text(it.help)
  if it.kind == "value" and help ~= "" and not it.bar then help = help .. "  Default " .. it.fmt(it.default) .. "." end
  help = help .. FAV.note(it)
  for _, l in ipairs(wrap_help(help)) do lines[#lines + 1] = l end
  if device == "pad" then
    lines[#lines + 1] = "D-pad move   Left/Right adjust   A select   LB/RB tab   B close" .. (combo_text ~= "" and ("   " .. combo_text .. " close") or "")
  else
    lines[#lines + 1] = "Up/Down move   Left/Right adjust   Enter select   PgUp/PgDn tab   " .. KEY.open .. " close"
  end
  local extra = {}
  for _, pr in ipairs(page() and page().prompts or {}) do extra[#extra + 1] = (device == "pad" and pr.pad or pr.key) .. " " .. prompt_label(pr):lower() end
  if FAV.can_pin(it) then
    extra[#extra + 1] = (device == "pad" and "Y " or "F ") .. (FAV.pinned(it) and "unpin" or "pin")
    if device ~= "pad" then extra[#extra + 1] = "H hotkey" end
  end
  if #extra > 0 then lines[#lines + 1] = table.concat(extra, "   ") end
  -- Messages wrap like the help (a long "Show active tweaks" list ran off
  -- the screen), at most STATUS_LINES lines.
  if M.status ~= "" and tick < M.status_until then
    local wrapped = wrap_help(M.status)
    for i = 1, math.min(#wrapped, STATUS_LINES) do
      lines[#lines + 1] = (i == STATUS_LINES and #wrapped > STATUS_LINES) and (wrapped[i]:sub(1, HELP_WIDTH - 4) .. " ...") or wrapped[i]
    end
  end
  GAMEUI.backdrop = backdrop(lines)
  mailbox_write(table.concat(lines, "\n"))
end


F.add_rows("Settings", "master", {
  require("menu_settings").row(),
  { id = "menu_background", label = "Menu background", kind = "value", needs = "none", default = 0, min = 0, max = 100, step = 10,
    v = S("menu_background", 60),
    fmt = function(v) return v <= 0 and "Off" or string.format("%d%%", v) end,
    help = "How solid the box behind the menu is (Off = none). Plain text: a dark box so it reads on any background. Game style: its own boxes (60% is their usual look)." },
})

function M.is_open() return M.open end
function M.current() if not M.open then return nil end local it = current_item() return it end
function M.tab_name() return F.categories[M.tab].name end

return M

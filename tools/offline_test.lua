-- Offline test: runs the menu with a fake wml (memory, keys, settings) and
-- checks what the host would do. Usage (from the repo root):
--   build\lua.exe tools\offline_test.lua [-v]
-- It opens the menu, goes through every tab, switches every toggle on and
-- off, steps every value and list, and presses every action, then reports
-- each row's game calls. -v also prints every screen and log line.
local root = "SRTweakMenu"
package.path = root .. "/?.lua"
local verbose = arg[1] == "-v"

local mem, mailbox = {}, {}
local MAILBOX = 0x00F00000
local keys_now, keys_prev = {}, {}
local frames = {}
local calls = {}   -- every script / vint / call, in order
local logs = {}
local hair_style, hair_ready = 0, true
local morph = 0.5
local voice = 0
local taken = {}
local hud_hides = 0
local hud_doc_hidden = false
local pad, pad_all, pad_hide = 0, false, 0
local function rd(a, n)
  if a >= MAILBOX and a < MAILBOX + 0x40 + 8192 then
    if a == MAILBOX and n == 4 then return 0x53524D55 end
    local v = 0 for i = 0, n - 1 do v = (v << 8) | (mailbox[a + i] or 0) end return v
  end
  local v = 0 for i = n - 1, 0, -1 do v = (v << 8) | (mem[a + i] or 0) end return v
end
local function wr(a, n, v)
  if a >= MAILBOX and a < MAILBOX + 0x40 + 8192 then
    for i = n - 1, 0, -1 do mailbox[a + i] = v & 0xFF; v = v >> 8 end return
  end
  for i = 0, n - 1 do mem[a + i] = v & 0xFF; v = v >> 8 end
end
-- (mod.ini and saved tweaks are written to a scratch copy, not the repo's)
local scratch = (os.getenv("TEMP") or ".") .. "\\sr2_tweak_menu_test"
os.execute('mkdir "' .. scratch .. '" 2>nul')
do
  local src = io.open(root .. "/mod.ini", "rb"); local data = src:read("a"); src:close()
  local dst = io.open(scratch .. "\\mod.ini", "wb"); dst:write(data); dst:close()
  os.remove(scratch .. "\\saved_tweaks.txt")
  os.remove(scratch .. "\\saved_presets.lua")
end
wml = {
  mod_folder = scratch, mod_name = "test", game = "sr2",
  log = function(...) local t = table.concat({ ... }, " ") logs[#logs + 1] = t if verbose then print("[log]", t) end end,
  setting = function(_, d) return d end,
  read_u8 = function(a) return rd(a, 1) end, read_u16 = function(a) return rd(a, 2) end,
  read_u32 = function(a) return rd(a, 4) end,
  read_f32 = function(a) return string.unpack("<f", string.pack("<I4", rd(a, 4))) end,
  write_u8 = function(a, v) wr(a, 1, v) end, write_u16 = function(a, v) wr(a, 2, v) end,
  write_u32 = function(a, v) wr(a, 4, v) end,
  write_f32 = function(a, v) wr(a, 4, string.unpack("<I4", string.pack("<f", v))) end,
  key_down = function(k) return keys_now[tostring(k):upper()] == true end,
  key_pressed = function(k) k = tostring(k):upper() return keys_now[k] == true and not keys_prev[k] end,
  take_key = function(k, on) taken[k] = on end, force_key = function() end,
  on_frame = function(fn) frames[#frames + 1] = fn end,
  hook = function() error("no hooks") end,
  script = function(code)
    calls[#calls + 1] = "script: " .. code
    return true, (code:find("tweak_out(true)", 1, true)
      or code:find("tweak_out(not character_is_dead", 1, true)) and true or nil
  end,
  vint = function(code)
    calls[#calls + 1] = "vint: " .. code
    if code:find('vint_document_find, "hud"', 1, true) then
      hud_doc_hidden = code:find('"visible", false', 1, true) ~= nil
      return true, true
    end
    if code == "hud_hide(true)" then hud_hides = hud_hides + 1 wr(0x02528518, 4, hud_hides) return true end
    if code == "hud_hide(false)" then hud_hides = math.max(0, hud_hides - 1) wr(0x02528518, 4, hud_hides) return true end
    if code:find("pcr_get_hair_info", 1, true) then return true, hair_style, 5, 6 end
    if code:find("pcr_report_hair_items", 1, true) then return true, 2 end
    if code:find("tweak_out(list[i][1]", 1, true) then return true, 0, nil, "Current hair", 1, nil, "Next hair" end
    if code:find("pcu_is_streaming_done", 1, true) then return true, hair_ready end
    if code:find("pcr_get_morph_value", 1, true) then return true, morph end
    if code:find("pcr_apply_morph_value", 1, true) then
      morph = tonumber(code:match(", ([%d.]+)%)")) or morph
      return true
    end
    if code:find("pcr_report_avail_morphs", 1, true) then return true, "width", "Width" end
    if code:find("pcr_get_current_voice_number", 1, true) then return true, voice end
    if code:find('pcr_set_voice("MALE_BLACK", false)', 1, true) then voice = 1 return true end
    local id = code:match("^pcr_change_hair%(%d+, (%-?%d+), 5, 6%)")
    if id then hair_style = tonumber(id) return true, true end
    return true
  end,
  call = function(a) calls[#calls + 1] = string.format("call %08X", a) return 0 end,
  callx = function(a) calls[#calls + 1] = string.format("callx %08X", a) return 0 end,
  buffer = function(slot)
    assert(slot >= 0 and slot <= 15, "buffer: slot 0-15")
    return 0x7F000000 + slot * 1024
  end,
  read_string = function() return "" end,
  patch = function(a) calls[#calls + 1] = string.format("patch %08X", a) end,
  f2u = function(f) return string.unpack("<I4", string.pack("<f", f)) end,
  u2f = function(u) return string.unpack("<f", string.pack("<I4", u)) end,
  pad = function() return pad end,
  pad_filter = function(all, hide) pad_all, pad_hide = all, hide end,
  pad_inject = function() end, pad_debug = function() return 0, 0, 0, 0, 1 end, sticks = function() return 0, 0, 0, 0, "xinput" end, pad_source = function() return "game" end,
  set_fov = function(m) calls[#calls + 1] = string.format("set_fov %.2f", m) return true end,
}

-- A loaded single-player game with the player at 0x10000000, in a car,
-- with a waypoint set.
wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, 0x10000000); wr(0x10000000 + 0xD74, 4, 0x1234)
wr(0x01F7A418, 4, 1)

-- (any global the menu makes is reported: rows should keep to locals)
local stray = {}
setmetatable(_G, { __newindex = function(g, k, v) stray[#stray + 1] = tostring(k); rawset(g, k, v) end })
dofile(root .. "/main.lua")
local function frame(pressed, buttons)
  keys_prev = keys_now; keys_now = {}
  pad = buttons or 0
  if pressed then keys_now[pressed] = true end
  for _, fn in ipairs(frames) do fn() end
end
local function screen()
  local n = rd(MAILBOX + 0x14, 4)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(mailbox[MAILBOX + 0x40 + i]) end
  return table.concat(t)
end
local function press(k) frame(k); frame() end

local F = require("features")
local MENU = require("menu")
frame()
press("F5")
if arg[1] == "--controls" then
  local P = MENU.PAD
  assert(MENU.is_open() and pad_all and taken.W)
  local fired = 0
  F.categories[MENU.tab].items = {
    { label = "One", kind = "action", run = function() fired = fired + 1 end },
    { label = "Two", kind = "action", run = function() fired = fired + 1 end },
  }
  frame(nil, P.DOWN | P.A)
  assert(MENU.current().label == "Two" and pad_all and fired == 0)
  frame(nil, P.A)
  assert(fired == 0)
  frame()
  frame(nil, P.A)
  assert(fired == 1)

  local p = 0x10000000
  assert(F.items.prone_kick == nil and F.items.sr1_movement == nil,
    "experimental kick and SR1 movement must not be active menu features")
  frame("F5", P.LB)
  assert(not MENU.is_open() and pad_all)
  frame(nil, P.LB)
  frame()
  frame(nil, P.LB)
  assert(not pad_all and (pad_hide & P.LB) == 0, "LB must return to the game outside the menu")
  frame(nil, P.RB | P.DOWN | P.A)
  assert(MENU.is_open() and pad_all and fired == 1)
  while MENU.tab_name() ~= "Customize" do press("PAGEDOWN") end
  assert(pad_all and taken.W)
  press("PAGEDOWN")
  assert(pad_all and taken.W) -- ordinary menu pages also capture gameplay movement

  local playback = require("emote_playback")
  local names, stopped = {}, 0
  playback.play = function(_, _, name) names[#names + 1] = name return {} end
  playback.stop = function() stopped = stopped + 1 end
  playback.active = function() return true end
  local style = F.items.run_variant
  F.update_style_preview(p, style)
  assert(names[1] == "run")
  style.v = 2
  F.update_style_preview(p, style)
  assert(names[2] == style.items[2][1] and stopped == 1)
  F.update_style_preview(p, nil)
  assert(stopped == 2)
  print("Menu transition lock, navigation, inactive SR1 combat/movement and movement focus passed")
  return
end
-- The self-test (Settings > Run self-test) runs to the end and writes its
-- report; Export then Import settings brings the same tweaks back.
if arg[1] == "--selftest" then
  local H = require("healthcheck")
  local names = H.called_names({ 'G.lua("inv_item_add_do(%s) tweak_out(type(rawget(_G, x)))") s.cash_add(1)',
    'G.vint([[local function own_fn(a) end own_fn(1) pcr_set_voice("x", false) Help (here) rawset(_G, "TWK_a", nil)]])' })
  assert(table.concat(names, " ") == "inv_item_add_do pcr_set_voice tweak_out", table.concat(names, " "))
  wr(0x10000000 + 0xD74, 4, 0)
  local report = H.REPORT
  os.remove(report)
  assert(H.start(F):find("running"))
  local n = 0
  while H.status():find("^RUNNING") and n < 5000 do frame() n = n + 1 end
  assert(not H.status():find("^RUNNING"), "the self-test never finished")
  local f = assert(io.open(report, "r"), "no report")
  local text = f:read("a") f:close()
  assert(text:find("== Game functions the menu calls ==", 1, true) and text:find("== Pages ==", 1, true)
    and text:find("pages opened", 1, true) and text:find("Try by hand", 1, true), text)
  local listed = tonumber(text:match("(%d+) names found"))
  assert(listed and listed > 50, "too few game functions found: " .. tostring(listed))
  print("self-test: " .. n .. " frames, " .. listed .. " game functions, " .. H.status())

  local B = require("backup")
  F.items.jump.v = true
  assert(B.export(F):find("^Exported"))
  F.items.jump.v = false
  local imp = F.items.import_settings
  assert(imp.run():find("Press again"))
  assert(imp.run():find("^Imported"))
  assert(F.items.jump.v == true, "import brought the tweak back")
  print("Self-test report, export and import passed")
  return
end
-- Favorites: F pins the row, the tab shows it, F there unpins it; H then a
-- key gives a row a hotkey that works with the menu closed.
if arg[1] == "--favorites" then
  local FAV = require("favorites")
  local presets = require("presets")
  assert(F.categories[#F.categories].name == "Favorites")
  assert(MENU.tab_name() == "Player")
  local first = MENU.current()
  press("F")
  assert(FAV.pinned(first), "F pins the row")
  press("PAGEUP")
  assert(MENU.tab_name() == "Favorites" and MENU.current() == first, "the pinned row is on Favorites")
  press("F")
  assert(not FAV.pinned(first) and MENU.current().id == "favorites_help", "F on Favorites unpins it")
  assert(FAV.toggle_pin(F.items.god):find("pinned"))
  frame()
  assert(MENU.current() == F.items.god)
  press("H")
  assert(FAV.binding == F.items.god)
  press("F9")   -- (quick_save_key: the menu's own)
  assert(FAV.binding and MENU.status:find("own keys"), MENU.status)
  press("BACKSPACE")
  assert(not FAV.binding and MENU.is_open(), "Backspace cancels the binding, not the menu")
  press("H") press("F3")
  assert(presets.all().hotkeys.F3 == "god" and taken.F3 == true, MENU.status)
  assert(MENU.status:find("F3 now switches God mode"), MENU.status)
  press("H") press("NUM_4")
  press("BACKSPACE")
  press("F5")
  assert(not MENU.is_open())
  local god = F.items.god.v
  local before = #calls
  press("F3")
  assert(F.items.god.v ~= god, "the hotkey switched the row")
  local told = false
  for i = before + 1, #calls do if calls[i]:find("mission_help_table", 1, true) then told = true end end
  assert(told, "the hotkey's answer is shown")
  press("F3")
  assert(F.items.god.v == god)
  -- kept: a fresh read of the store has both
  presets.reload()
  FAV.refresh()
  assert(FAV.pinned(F.items.god) and FAV.key_of(F.items.god) == "F3")
  local pg = F.items.hotkeys.open()
  assert(pg.rows[1].label == "F3: God mode", pg.rows[1].label)
  assert(pg.rows[1].run():find("cleared") and taken.F3 == false and not presets.all().hotkeys.F3)
  local fav = F.items.god
  assert(FAV.toggle_pin(fav):find("unpinned"))
  print("Favorites pin and unpin, hotkey binding, reserved keys, cancel, hotkey use and clearing passed")
  return
end
if arg[1] == "--customize" then
  wr(0x10000000 + 0xD74, 4, 0)
  while MENU.tab_name() ~= "Customize" do press("PAGEDOWN") end
  local function select_row(label)
    local count = #MENU.view_rows()
    for _ = 1, count do
      if MENU.current().label == label then press("ENTER") return end
      press("DOWN")
    end
    error("Missing row " .. label)
  end
  local function open_item()
    select_row("Clothing")
    select_row("Tops")
    select_row("Undershirt")
    press("ENTER")
    assert(MENU.current().label == "Variant")
    press("RIGHT")
  end
  local function wear_calls()
    local n = 0
    for _, code in ipairs(calls) do
      if code:find("customization_item_wear(", 1, true) then n = n + 1 end
    end
    return n
  end
  open_item()
  press("BACKSPACE")
  assert(MENU.pages[#MENU.pages].title == "Save Changes" and wear_calls() == 0)
  select_row("Yes")
  assert(wear_calls() == 1 and #MENU.pages == 3)
  press("ENTER")
  press("PAGEDOWN")
  assert(MENU.pages[#MENU.pages].title == "Save Changes" and MENU.tab_name() == "Customize")
  select_row("No")
  assert(wear_calls() == 1 and MENU.tab_name() ~= "Customize")
  press("PAGEUP")
  open_item()
  press("F5")
  assert(MENU.is_open() and MENU.pages[#MENU.pages].title == "Save Changes")
  select_row("No")
  assert(wear_calls() == 1 and not MENU.is_open())
  press("F5")
  assert(#MENU.pages == 3)
  press("BACKSPACE")
  press("BACKSPACE")
  press("BACKSPACE")
  wr(0x10000000 + 0x13B0, 4, 0x11000000)
  select_row("Hair")
  select_row("Head Hair")
  assert(MENU.current().label == "Current hair")
  press("DOWN")
  assert(MENU.current().label == "Next hair" and hair_style == 1)
  press("BACKSPACE")
  assert(MENU.pages[#MENU.pages].title == "Save Changes")
  select_row("No")
  assert(hair_style == 0)
  select_row("Head Hair")
  hair_ready = false
  press("DOWN")
  assert(hair_style == 0)
  hair_ready = true
  frame()
  assert(hair_style == 1)
  press("ENTER")
  press("BACKSPACE")
  assert(hair_style == 1 and MENU.pages[#MENU.pages].title == "Hair")
  press("BACKSPACE")
  select_row("Face & Body")
  select_row("Body Type")
  local before = morph
  press("RIGHT")
  assert(morph > before and MENU.is_open() and not MENU.locked)
  press("BACKSPACE")
  select_row("No")
  assert(morph == before)
  select_row("Body Type")
  press("RIGHT")
  local changed = morph
  press("BACKSPACE")
  select_row("Yes")
  assert(morph == changed)
  select_row("Voice")
  press("RIGHT")
  select_row("Apply voice")
  assert(voice == 1)
  print("Customize saves, discards, live hair, streaming retry, built-in morphs and native voice passed")
  return
end
if arg[1] == "--native" then
  local p, target = 0x10000000, 0x12000000
  wr(p + 0xD74, 4, 0)
  press("F5")
  assert(not MENU.is_open())
  local shots, hit_handles, bills, ignitions = 0, {}, 0, 0
  local old_callx = wml.callx
  wml.gun_shots = function(enabled)
    local count = enabled and shots or 0
    shots = 0
    return count
  end
  wml.fire_hits = function(enabled)
    local result = enabled and hit_handles or {}
    hit_handles = {}
    return result
  end
  wml.callx = function(address, regs, ...)
    if address == 0x00931F20 then bills = bills + 1 return 0 end
    if address == 0x0098D3C0 then
      assert(regs.ecx == p and (...) == target)
      ignitions = ignitions + 1
      return 0
    end
    if address == 0x004800C0 then
      local handle = rd(regs.ecx, 4)
      wr(0x00EEB8F8 + (handle & 0xFF) * 0x19C + 0x28, 4, (...))
      return 0
    end
    if address == 0x007B9200 then
      assert(regs.eax == 0)
      wr(0x00E8CF7C, 4, 4)
      return 0
    end
    return old_callx(address, regs, ...)
  end
  wml.write_f32(0x0279748C, 65) -- native Fire_Damage_Per_second tuning
  F.items.money_gun.v, F.items.fire_ammo.v = true, true
  local handle = 0x1002
  wr(0x02149C64 + (handle & 0xFFF) * 16, 4, target)
  wr(target + 0x44, 4, handle)
  wr(target + 0x4C, 4, 1)
  wml.write_f32(target + 0x1124, 50)
  shots, hit_handles = 5, { handle }
  frame()
  assert(bills == 5 and ignitions == 1)
  shots, hit_handles = 3, { handle }
  wr(target + 0xC0, 4, 0x400)
  frame()
  assert(bills == 8 and ignitions == 1)
  -- Hide HUD hides the hud document only; the engine-wide hud_hide (which
  -- also hid the menu's hud_msg and forced the text look) is never used.
  F.items.hide_hud.v = true
  for _ = 1, 300 do frame() end
  assert(hud_doc_hidden and hud_hides == 0)
  F.items.hide_hud.v = false
  frame()
  assert(not hud_doc_hidden and hud_hides == 0)
  F.items.camera_shortcut.v = true
  frame("F7")
  assert(MENU.is_open() and MENU.tab_name() == "Visual" and MENU.pages[#MENU.pages].from == "visual_free_camera")
  assert(require("freecam").on)
  require("freecam").exit()
  MENU.close_for_game()
  local body = require("face_body")
  wr(p + 0x44, 4, 0x1001)
  wr(p + 0x13B0, 4, 0x11000000)
  local voice_page = body.voice_page(F, p)
  local pitch_row = voice_page.rows[2]
  local sound, channel = 0x203, 0x00EEB8F8 + 3 * 0x19C
  wr(0x01450408, 4, 1)
  wr(0x027D83C8, 4, 0x1001)
  wr(0x027D83D0, 4, sound)
  wr(0x00EEB9AC + 3 * 0x19C, 4, 2)
  wr(channel + 0xA4, 4, 1)
  pitch_row.v = -6
  pitch_row.change(nil, p, 0, pitch_row)
  body.update(p)
  assert(wml.read_f32(channel + 0x28) == -0.5)
  wr(0x01450408, 4, 0)
  body.update(p)
  assert(wml.read_f32(channel + 0x28) == 0)
  assert(F.items.vehicle_custom.kind == "page" and F.items.vehicle_custom.open)
  print("Automatic bursts, fire queue, HUD ownership, camera entry, pitch cleanup and in-place vehicle handoff passed")
  return
end
local problems = {}
local total = 0
-- Presses every row on the current page (or tab); opens pages and does
-- their rows too, then comes back.
local function sweep(where, depth)
  local seen = {}
  local here = #MENU.pages
  while MENU.is_open() and #MENU.pages == here do
    local it = MENU.current()
    if not it or seen[it] then break end
    seen[it] = true
    total = total + 1
    local before = #calls
    if it.kind == "toggle" then press("ENTER"); for _ = 1, 3 do frame() end; press("ENTER"); for _ = 1, 3 do frame() end
    elseif it.kind == "value" or it.kind == "choice" then press("RIGHT"); frame(); press("LEFT"); frame()
    elseif it.kind == "list" then press("RIGHT"); press("ENTER")
    elseif it.kind == "action" and it.label ~= "Open Face & Body Editor" then press("ENTER") end
    local made = {}
    for i = before + 1, #calls do made[#made + 1] = calls[i] end
    print(string.format("%s%-7s %-28s %s", string.rep("  ", depth), it.kind, it.label:sub(1, 28), made[1] or ""))
    for i = 2, math.min(#made, 2) do print(string.rep(" ", 37 + depth * 2) .. made[i]) end
    if (MENU.status or ""):find("Error") then problems[#problems + 1] = where .. " / " .. it.label .. ": " .. MENU.status end
    if it.kind == "page" and depth < 3 then
      local pages = #MENU.pages
      press("ENTER")
      if #MENU.pages > pages then
        sweep(where .. " > " .. it.label, depth + 1)
        if #MENU.pages > pages then
          press("BACKSPACE")
          if MENU.pages[#MENU.pages] and MENU.pages[#MENU.pages].confirm then
            press("DOWN")
            press("ENTER")
          end
        end
      else
        problems[#problems + 1] = where .. " / " .. it.label .. ": page didn't open (" .. tostring(MENU.status) .. ")"
      end
    end
    press("DOWN")
  end
end

for tab = 1, #F.categories do
  local cat = F.categories[tab]
  wr(0x10000000 + 0xD74, 4, cat.name == "Customize" and 0 or 0x1234)
  wr(0x10000000 + 0x13B0, 4, 0x11000000)
  if verbose then print("==== " .. cat.name .. "\n" .. screen()) end
  print(cat.name)
  sweep(cat.name, 1)
  press("PAGEDOWN")
end
press("F5")
for _, k in ipairs(stray) do problems[#problems + 1] = "global made: " .. k end
for _, l in ipairs(logs) do if not l:find("^row: ") and (l:find("fail") or l:find("rror")) then problems[#problems + 1] = "log: " .. l end end
print(total .. " rows; " .. (#problems == 0 and "no errors" or ("PROBLEMS:\n  " .. table.concat(problems, "\n  "))))




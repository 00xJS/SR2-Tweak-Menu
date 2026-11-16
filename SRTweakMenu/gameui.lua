-- SR Tweak Menu (Saints Row 2) - the game look: the menu drawn with Saints
-- Row 2's own interface (itsMJQ's look from SR1, rebuilt on SR2's pieces).
--
-- SR1's gameui.lua drew each frame with the game's 2D calls. SR2's 2D calls
-- go through a deferred render queue, so here the menu is made of the
-- interface's own objects instead, the way SR2's menus build theirs
-- (vint_object_create "bitmap" / "text", as pause_menu.lua and hud_gsi.lua
-- do): a group under the HUD message document's safe frame, a pool of
-- bitmaps and texts, and every update only what changed is sent
-- (wml.vint). The pictures are the menu templates and button icons on the
-- interface-backend sheets (ui_bms_00..10: ui_menu_tmp_dialog_*, _sel_l,
-- _box_a_bg, ui_ctrl_360_btn_*), the fonts SR2's (thin, header_n_overlay),
-- the sounds its menus' (Menu_sound_* in vint_lib.lua).
--
-- menu.lua builds UI.frame (a list of things to draw, in 1280 x 720 layout
-- units from the top left, like SR1's): { image = name, x, y, w, h, colour
-- = { r, g, b, a } } and { text = s, font = "thin" | "giant", size, x, y,
-- colour }. main.lua calls UI.present() once an update.

local S = wml.setting

local UI = { frame = nil, ok = true, backdrop = nil }

-- The menu's font keys to SR2's fonts, as its own menus use them
-- (menu_base.vint_doc): rows in thin_overlay (the shadowed body face), the
-- label on the yellow bar in thin (the plain one), tabs, header and button
-- tips in header_n_overlay (capitals only).
local FONTS = {
  thin = tostring(S("menu_font_text", "thin_overlay")),
  ink = tostring(S("menu_font_bar", "thin")),
  giant = tostring(S("menu_font_heading", "header_n_overlay")),
}
UI.FONTS = FONTS

-- Native sizes of the pieces (bitmap_sheets.xtbl), to scale them to a size.
UI.SIZE = {
  ui_blank = { 16, 16 }, ui_menu_box_base_c = { 18, 18 },
  ui_menu_tmp_dialog_nw = { 113, 44 }, ui_menu_tmp_dialog_n = { 374, 44 }, ui_menu_tmp_dialog_ne = { 119, 44 },
  ui_menu_tmp_dialog_w = { 34, 373 }, ui_menu_tmp_dialog_c = { 16, 16 }, ui_menu_tmp_dialog_e = { 47, 373 },
  ui_menu_tmp_dialog_sw = { 119, 59 }, ui_menu_tmp_dialog_s = { 368, 59 }, ui_menu_tmp_dialog_se = { 119, 59 },
  ui_menu_tmp_box_a_bg = { 836, 45 }, ui_menu_tmp_box_b_bg = { 836, 28 },
  ui_menu_tmp_sel_l = { 769, 34 }, ui_menu_tmp_sel_r = { 11, 34 }, ui_menu_tmp_hr = { 812, 10 },
  ui_menu_tmp_arrow_w = { 22, 30 }, ui_menu_tmp_arrow_e = { 22, 30 },
  ui_menu_tmp_slider_bg_a = { 192, 17 }, ui_menu_tmp_slider_bg_c = { 192, 17 },
  ui_menu_tmp_scrl_line = { 10, 470 }, ui_menu_tmp_scrl_bar_1 = { 32, 47 }, ui_menu_tmp_scrl_end = { 38, 14 },
  ui_menu_tmp_frm_cap_m = { 481, 33 }, ui_menu_tmp_mid_side_a = { 17, 624 }, ui_menu_tmp_mid_trm_a = { 207, 28 },
  ui_menu_tmp_row_a = { 492, 28 }, ui_menu_tmp_row_b = { 257, 28 },
  ui_menu_tmp_frm_trm_a = { 640, 8 }, ui_menu_tmp_frm_trm_b = { 640, 8 },
  ui_menu_tmp_check = { 31, 24 }, ui_menu_tmp_checkbox = { 28, 28 }, ui_menu_tmp_style_fleur = { 91, 97 },
  ui_ctrl_360_btn_a = { 60, 40 }, ui_ctrl_360_btn_b = { 34, 34 }, ui_ctrl_360_btn_x = { 60, 40 },
  ui_ctrl_360_btn_y = { 34, 34 }, ui_ctrl_360_btn_lb = { 44, 32 }, ui_ctrl_360_btn_rb = { 44, 32 },
  ui_ctrl_360_btn_back = { 40, 32 }, ui_ctrl_360_btn_start = { 40, 32 },
  ui_ctrl_360_dpad_n = { 42, 42 }, ui_ctrl_360_dpad_ud = { 42, 42 }, ui_ctrl_360_dpad_lr = { 73, 44 },
}

-- ------------------------------------------------------------- the interface side (Lua 5.0)
-- Put in the interface's globals once (TWK_UI): the root group, the pools,
-- one call per bitmap / text, measuring. Every name through rawget/rawset:
-- the game's globals are guarded.
local LIB = [==[
local U = rawget(_G, "TWK_UI")
if not U then U = { b = {}, t = {}, ox = 0, oy = 0 } rawset(_G, "TWK_UI", U) end
-- (the interface state has no table library and guards its globals: only
-- base functions, each looked up with rawget)
local TS = rawget(_G, "tostring") or function(x) if x == nil then return "nil" end return "?" end
-- (the interface state's pcall, or a plain call if it has none)
local PC = rawget(_G, "pcall") or function(f, a, b, c, d, e, g) return true, f(a, b, c, d, e, g) end
U.PC = PC
U.TS = TS
-- Every property set is guarded: one the game refuses is noted (U.err), not fatal.
local function note(k, e) U.err = TS(k) .. ": " .. TS(e) end
function U.P1(o, k, a) local ok, e = PC(vint_set_property, o, k, a) if not ok then note(k, e) end end
function U.P2(o, k, a, b) local ok, e = PC(vint_set_property, o, k, a, b) if not ok then note(k, e) end end
function U.P3(o, k, a, b, c) local ok, e = PC(vint_set_property, o, k, a, b, c) if not ok then note(k, e) end end
function U.G2(o, k) local ok, a, b = PC(vint_get_property, o, k) if ok then return a, b end note(k, a) end
function U.make(name, kind, parent)
  local ok, h = PC(vint_object_create, name, kind, parent)
  if ok and h and h ~= 0 then return h end
  note("create " .. kind, h)
end
function U.parent()
  local c = { { "hud_msg", "safe_frame" }, { "hud", "safe_frame" }, { "hud_msg", "msg_debug_anchor" } }
  for i = 1, 3 do
    local okd, d = PC(vint_document_find, c[i][1])
    if okd and d and d ~= 0 then
      local okh, h = PC(vint_object_find, c[i][2], nil, d)
      if okh and h and h ~= 0 then return h, c[i][1] .. "/" .. c[i][2] end
    end
  end
  note("parent", "no hud_msg or hud safe_frame")
end
function U.root()
  if U.r then return U.r end
  local p, where = U.parent()
  if not p then return nil end
  U.safe_parent = p
  local px, py = U.G2(p, "anchor")
  local parent
  local get_parent = rawget(_G, "vint_object_parent")
  if get_parent then
    local ok, value = PC(get_parent, p)
    if ok and value and value ~= 0 and value ~= p then parent = value end
  end
  U.independent = false
  U.px, U.py, U.where = px or 0, py or 0, where
  local r = U.make("twk_menu_root", "group", parent or p)
  -- SR2's interface is laid out on an SD canvas (640 x 480) or an HD one
  -- (1280 x 720) - vint_hack_is_std_res(), as hud.lua asks; the menu is laid
  -- out in 1280 x 720, so on SD its group is scaled down to match.
  local std = false
  local f = rawget(_G, "vint_hack_is_std_res")
  if f then local ok, v = PC(f) if ok then std = v and true or false end end
  if U.force == "sd" then std = true elseif U.force == "hd" then std = false end
  U.std = std
  if r then
    U.owned_root = true
    U.independent = parent ~= nil
    U.P2(r, "anchor", parent and 0 or -U.px, parent and 0 or -U.py)
    if std then U.P2(r, "scale", 640 / 1280, 480 / 720) end
    U.ox, U.oy = 0, 0
  else
    -- (no group: everything goes straight under the safe frame, offset by hand)
    r = p
    U.ox, U.oy = -U.px, -U.py
    U.where = where .. " (no group)"
  end
  U.r = r
  local b = U.make("twk_probe_b", "bitmap", r)
  local sw
  if b then
    U.P1(b, "image", "ui_blank")
    U.P2(b, "scale", 10, 1)
    U.P1(b, "alpha", 0)
    sw = U.G2(b, "screen_size")
  end
  U.k = (sw and sw > 0) and (sw / 160) or 1
  local t = U.make("twk_probe_t", "text", r)
  if t then
    U.P1(t, "alpha", 0)
    U.P1(t, "auto_offset", "nw")
  end
  U.mt = t
  return r
end
function U.B(i, d, img, x, y, sx, sy, r, g, b, a)
  local o = U.b[i]
  if not o then o = U.make("twk_b" .. i, "bitmap", U.r) if not o then return end U.b[i] = o end
  U.P1(o, "image", img)
  U.P2(o, "anchor", x + U.ox, y + U.oy)
  U.P2(o, "scale", sx, sy)
  U.P3(o, "tint", r, g, b)
  U.P1(o, "alpha", a)
  U.P1(o, "depth", d)
  U.P1(o, "visible", true)
end
function U.T(i, d, s, font, x, y, sc, r, g, b, a)
  local o = U.t[i]
  if not o then
    o = U.make("twk_t" .. i, "text", U.r) if not o then return end
    U.t[i] = o
    U.P1(o, "auto_offset", "nw")
  end
  U.P1(o, "font", font)
  U.P1(o, "text_tag", s)
  U.P2(o, "anchor", x + U.ox, y + U.oy)
  U.P2(o, "scale", sc, sc)
  U.P3(o, "tint", r, g, b)
  U.P1(o, "alpha", a)
  U.P1(o, "depth", d)
  U.P1(o, "visible", true)
end
function U.H(nb, nt)
  for i, o in U.b do if i > nb then U.P1(o, "visible", false) end end
  for i, o in U.t do if i > nt then U.P1(o, "visible", false) end end
end
function U.S(on)
  if U.r and U.ox == 0 and U.oy == 0 then U.P1(U.r, "visible", on) return end
  for i, o in U.b do U.P1(o, "visible", on and o ~= nil) end
  for i, o in U.t do U.P1(o, "visible", on and o ~= nil) end
end
function U.M(font, s)
  if not U.mt then return 0, 0 end
  U.P1(U.mt, "font", font)
  U.P2(U.mt, "scale", 1, 1)
  U.P1(U.mt, "text_tag", s)
  local w, h = U.G2(U.mt, "screen_size")
  return (w or 0) / U.k, (h or 0) / U.k
end
]==]
UI.LIB = LIB

local installed = false   -- TWK_UI is in the interface state we last talked to
local root_ok = false
local logged = nil

-- ------------------------------------------------------------- drawing state
local sent_b, sent_t, nb_sent, nt_sent = {}, {}, -1, -1
local shown = false
function UI.reset_pools() sent_b, sent_t, nb_sent, nt_sent, shown = {}, {}, -1, -1, false end

-- Makes sure the interface side is there (the interface state can be rebuilt).
local function ensure()
  local ok, have = wml.vint('local U = rawget(_G, "TWK_UI") '
    .. 'if U and U.parent then local p = U.parent() '
    .. 'if p ~= U.safe_parent then rawset(_G, "TWK_UI", nil) U = nil end end '
    .. 'tweak_out(U ~= nil)')
  if not ok then installed, root_ok = false, false return false end
  if have ~= true then
    installed, root_ok = false, false
    if not wml.vint(LIB) then return false end
    local _, now = wml.vint('tweak_out(rawget(_G, "TWK_UI") ~= nil)')
    if now ~= true then return false end
    UI.reset_pools()
  end
  installed = true
  if not root_ok then
    local canvas = tostring(S("menu_canvas", "auto")):lower()
    local _, r, where, px, py, k, err, std, independent = wml.vint(string.format('local U = rawget(_G, "TWK_UI") U.err = nil U.force = %q ', canvas)
      .. 'local ok, r = U.PC(U.root) '
      .. 'if not ok then U.err = U.TS(r) r = nil end tweak_out(r ~= nil, U.where or "none", U.px or 0, U.py or 0, U.k or 0, U.err or "", U.std == true, U.independent == true)')
    root_ok = r == true
    UI.independent = independent == true
    local line = string.format("menu (game look): %s under %s (anchor %s, %s; %s units a unit; %s canvas)%s",
      root_ok and "ready" or "no place to draw yet", tostring(where), tostring(px), tostring(py), tostring(k),
      std and "SD 640 x 480" or "HD 1280 x 720", (err and err ~= "") and ("; the interface said: " .. tostring(err)) or "")
    if line ~= logged then logged = line wml.log(line) end
  end
  return root_ok
end

-- ------------------------------------------------------------- what menu.lua asks
local next_try = 0
function UI.ready()
  if not UI.ok then return false end
  if os.clock() < next_try then return root_ok and installed end
  next_try = os.clock() + 1
  local ok, res = pcall(ensure)
  if not ok then
    wml.log("menu (game look): " .. tostring(res))
    installed, root_ok = false, false
    return false
  end
  return res
end
-- (what's on screen is hidden first: switching to the plain text look used to leave it up)
function UI.hide()
  if shown then wml.vint('local U = rawget(_G, "TWK_UI") if U and U.S then U.S(false) end') shown = false end
end
function UI.retry() UI.hide() UI.ok = true root_ok = false installed = false next_try = 0 end

-- Text sizes from SR2's own font files (data/font_metrics.lua, built from
-- fnt_body_n / fnt_head_n.vf3_pc): asking the interface ("screen_size") right
-- after setting a text gave the size of the one before. A {..._IMG} button tag
-- or an [image:...] counts as a picture about one cell wide; [format] codes as nothing.
local METRICS = (function()
  local ok, t = pcall(require, "data.font_metrics")
  return ok and type(t) == "table" and t or {}
end)()
local widths = {}
function UI.width(ctx, font, s)
  s = tostring(s)
  local m = METRICS[font] or METRICS.thin
  if not m then return #s * 9.5 end
  local key = font .. "|" .. s
  local w = widths[key]
  if w then return w end
  w = 0
  local plain = s:gsub("{[%u%d_]+_IMG[%u%d_]*}", function() w = w + m.cell * 1.15 return "" end)
  plain = plain:gsub("%[image:[^%]]*%]", function() w = w + m.cell * 1.15 return "" end)
  plain = plain:gsub("%[/?[%a_]+[^%]]*%]", "")
  for i = 1, #plain do w = w + (m.adv[plain:byte(i)] or m.adv[63] or 15) end
  widths[key] = w
  return w
end
function UI.line_height(font)
  local m = METRICS[font] or METRICS.thin
  return m and m.cell or 20
end
local function measure_pending() end

-- Sounds: the pause menu's (vint_lib.lua Menu_sound_*), by SR1's names.
local SOUNDS = {
  scroll = "Menu_sound_item_nav", lr = "Menu_sound_value_nav", select = "Menu_sound_select",
  back = "Menu_sound_back", okay = "Menu_sound_select", yes = "Menu_sound_select", no = "Menu_sound_back",
  purchase = "Menu_sound_purchase", resume = "Menu_sound_close", quit = "Menu_sound_close",
  pause = "Menu_sound_open", unpause = "Menu_sound_close", popup = "Menu_sound_warning", error = "Menu_sound_warning",
}
function UI.sound(ctx, name)
  local var = SOUNDS[name]
  if not var then return end
  wml.vint(string.format('local s = rawget(_G, %q) if s then audio_play(s) end', var))
end

local function c01(v) return math.max(0, math.min(1, (v or 255) / 255)) end

-- Once an update: what menu.lua put in UI.frame goes on screen (or the menu
-- is hidden when there's none).
function UI.present()
  -- (the plain text look has only its box, Menu background, to draw)
  local fr = UI.frame
  if not fr and UI.backdrop and UI.ok and UI.ready() then fr = { UI.backdrop } end
  if not fr then UI.hide() end
  if not (installed and root_ok) then return end
  measure_pending()
  if not fr then
    if shown then wml.vint('local U = rawget(_G, "TWK_UI") if U then U.S(false) end') shown = false end
    return
  end
  local out, nb, nt = {}, 0, 0
  for i, op in ipairs(fr) do
    local col = op.colour or { 255, 255, 255, 255 }
    local d = -i
    if op.image then
      nb = nb + 1
      local size = UI.SIZE[op.image] or { 16, 16 }
      local line = string.format("U.B(%d,%d,%q,%.1f,%.1f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f)", nb, d, op.image, op.x, op.y,
        op.w / size[1], op.h / size[2], c01(col[1]), c01(col[2]), c01(col[3]), c01(col[4]))
      if sent_b[nb] ~= line then sent_b[nb] = line out[#out + 1] = line end
    elseif op.text then
      nt = nt + 1
      local line = string.format("U.T(%d,%d,%q,%q,%.1f,%.1f,%.4f,%.3f,%.3f,%.3f,%.3f)", nt, d, op.text, FONTS[op.font] or op.font,
        op.x, op.y, op.size or 1, c01(col[1]), c01(col[2]), c01(col[3]), c01(col[4]))
      if sent_t[nt] ~= line then sent_t[nt] = line out[#out + 1] = line end
    end
  end
  if nb ~= nb_sent or nt ~= nt_sent then
    out[#out + 1] = string.format("U.H(%d,%d)", nb, nt)
    for i = nb + 1, #sent_b do sent_b[i] = nil end
    for i = nt + 1, #sent_t do sent_t[i] = nil end
    nb_sent, nt_sent = nb, nt
  end
  if not shown then out[#out + 1] = "U.S(true)" shown = true end
  if #out == 0 then return end
  local ok, err = wml.vint('local U = rawget(_G, "TWK_UI") if U and U.r then U.err = nil ' .. table.concat(out, " ")
    .. ' tweak_out(U.err or "") end')
  if not ok or err == nil or err ~= "" then
    UI.hide()
    wml.vint('local U = rawget(_G, "TWK_UI") '
      .. 'if U and U.owned_root and U.r then U.PC(vint_object_destroy, U.r) end '
      .. 'rawset(_G, "TWK_UI", nil)')
    installed, root_ok = false, false
    next_try = os.clock() + 1
    UI.reset_pools()
  end
  if err and err ~= "" and err ~= UI.last_err then UI.last_err = err wml.log("menu (game look): the interface said: " .. err) end
  if not UI.logged_menu_draw then
    UI.logged_menu_draw = true
    wml.log(string.format("menu (game look): drew %d pictures, %d texts", nb, nt))
  end
end

return UI

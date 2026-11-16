-- SR Tweak Menu (Saints Row 2) - Favorites and hotkeys.
--
-- Favorites: F (keyboard) or Y (controller) on a row pins it to the
-- Favorites tab, the last tab (one PgUp / LB from Player). The same button
-- on a pinned row, there or in its own tab, unpins it. A pinned row is the
-- row itself, not a copy: switched on in Favorites, it is on in its tab too.
--
-- Hotkeys: H on a row, then a key, gives the row that key. With the menu
-- closed the key switches the toggle, steps the choice to its next option,
-- or presses the action (a list: picks the entry the row shows). The keys
-- are F1-F12, Num 0-9, Insert, Home, End and Delete, less the menu's own
-- (menu_key, F7 for the quick camera, quick_save_key). A key given to a row
-- is kept from the game. Keyboard only.
--
-- Both are kept in saved_presets.lua, so Settings > Export takes them along.
local presets = require("presets")
local G = require("game")

local FAV = { binding = nil }
local F, cat, howto, hotkeys_row, keys_header

-- { name kept in the file, what the host is given, name shown }
local KEYS = {}
for i = 1, 12 do KEYS[#KEYS + 1] = { "F" .. i, "F" .. i, "F" .. i } end
for i = 0, 9 do KEYS[#KEYS + 1] = { "NUM" .. i, 0x60 + i, "Num " .. i } end   -- (VK_NUMPAD0..9)
for _, k in ipairs({ { "INSERT", "Insert" }, { "HOME", "Home" }, { "END", "End" }, { "DELETE", "Delete" } }) do
  KEYS[#KEYS + 1] = { k[1], k[1], k[2] }
end
local BY_NAME = {}
for _, k in ipairs(KEYS) do BY_NAME[k[1]] = k end
FAV.KEYS = KEYS
local reserved = {}
local function key_label(name) return BY_NAME[name] and BY_NAME[name][3] or tostring(name) end
FAV.key_label = key_label

local function store()
  local all = presets.all()
  if type(all.favorites) ~= "table" then all.favorites = {} end
  if type(all.hotkeys) ~= "table" then all.hotkeys = {} end
  return all
end

-- A row can be pinned when it is one of the menu's own rows (not one made
-- for a page each time it opens: those belong to that page).
local function own(it) return F and it and it.id and F.items[it.id] == it and it.kind ~= "header" and not it.nopin end
FAV.can_pin = own
local function bindable(it)
  return own(it) and (it.kind == "toggle" or it.kind == "choice" or it.kind == "list" or it.kind == "action")
end
function FAV.pinned(it)
  if not own(it) then return false end
  for _, id in ipairs(store().favorites) do if id == it.id then return true end end
  return false
end
function FAV.key_of(it)
  if not it or not it.id then return nil end
  for name, id in pairs(store().hotkeys) do if id == it.id then return name end end
end

-- The keys given to rows are kept from the game; a key let go is handed back.
local taken = {}
local function sync_keys()
  local want = {}
  for name, id in pairs(store().hotkeys) do
    if BY_NAME[name] and not reserved[name] and type(id) == "string" then want[name] = true end
  end
  for name in pairs(taken) do
    if not want[name] then pcall(wml.take_key, BY_NAME[name][2], false) taken[name] = nil end
  end
  for name in pairs(want) do
    if not taken[name] then pcall(wml.take_key, BY_NAME[name][2], true) taken[name] = true end
  end
end
local function set_key(name, id)
  store().hotkeys[name] = id
  sync_keys()
end

-- The tab's rows: the pinned ones in the order pinned, then the hotkeys page.
local built_store, built_n
function FAV.refresh(force)
  if not cat then return end
  local all = store()
  if not force and all == built_store and #all.favorites == built_n then return end
  if all ~= built_store then sync_keys() end   -- (a new store: an import)
  built_store, built_n = all, #all.favorites
  local items = {}
  for _, id in ipairs(all.favorites) do
    local it = F.items[id]
    if own(it) then items[#items + 1] = it end
  end
  if #items == 0 then items[1] = howto end
  items[#items + 1] = keys_header
  items[#items + 1] = hotkeys_row
  cat.items = items
end

function FAV.toggle_pin(it)
  if not own(it) then return "This row can't be pinned" end
  local list = store().favorites
  for i, id in ipairs(list) do
    if id == it.id then
      table.remove(list, i)
      FAV.refresh(true)
      return presets.write() or (it.label .. " unpinned from Favorites")
    end
  end
  list[#list + 1] = it.id
  FAV.refresh(true)
  return presets.write() or (it.label .. " pinned to Favorites")
end

-- H on a row: the next key pressed (FAV.poll_bind) becomes its hotkey.
function FAV.start_bind(it)
  if not bindable(it) then
    return own(it) and "Only switches, choices, lists and actions can have a hotkey" or "This row can't have a hotkey"
  end
  FAV.binding = it
  local now = FAV.key_of(it)
  return "Press a key for " .. it.label .. ": F1-F12, Num 0-9, Insert, Home, End or Delete. "
    .. (now and ("H again clears " .. key_label(now) .. ". ") or "") .. "Backspace cancels."
end

local function what(it)
  if it.kind == "toggle" then return "switches" end
  if it.kind == "choice" then return "steps" end
  return "presses"
end

-- While binding: a message once it's done (or cancelled), nil while waiting.
function FAV.poll_bind(cancel)
  local it = FAV.binding
  if not it then return nil end
  if cancel or wml.key_pressed("BACKSPACE") or wml.key_pressed("ESCAPE") then
    FAV.binding = nil
    return "No key given"
  end
  if wml.key_pressed("H") then
    FAV.binding = nil
    local old = FAV.key_of(it)
    if not old then return it.label .. " has no hotkey" end
    set_key(old, nil)
    return presets.write() or ("Hotkey " .. key_label(old) .. " cleared")
  end
  for _, k in ipairs(KEYS) do
    if wml.key_pressed(k[2]) then
      if reserved[k[1]] then
        return key_label(k[1]) .. " is one of the menu's own keys; pick another"
      end
      FAV.binding = nil
      local old = FAV.key_of(it)
      if old then set_key(old, nil) end
      local before = store().hotkeys[k[1]]
      set_key(k[1], it.id)
      local msg = key_label(k[1]) .. " now " .. what(it) .. " " .. it.label
      if before and before ~= it.id and F.items[before] then msg = msg .. " (it was " .. F.items[before].label .. ")" end
      return presets.write() or msg
    end
  end
  return nil
end

-- What a hotkey does to its row; the answer to show.
function FAV.press(it)
  if it.kind == "toggle" then return F.toggle(nil, it) end
  if it.kind == "choice" then return F.adjust(nil, it, 1) end
  if it.kind == "action" or it.kind == "list" then return F.activate(nil, it) end
end

-- Shown with the menu closed: the game's help message (top left). (Its text
-- normally names a line of the game's string table; plain text is shown as
-- it is, if at all - unconfirmed.)
local function tell(msg)
  if type(msg) ~= "string" or msg == "" then return end
  wml.log("hotkey: " .. msg)
  G.lua('local f = rawget(_G, "mission_help_table") if f then pcall(f, %s) end', msg)
end

-- Every frame, with the menu closed: the hotkeys.
function FAV.frame(open, locked)
  if open then return end
  FAV.binding = nil
  if locked or not F then return end
  local p = G.player()
  if p == 0 or G.in_cutscene() then return end
  for name, id in pairs(store().hotkeys) do
    local k = BY_NAME[name]
    if k and taken[name] and wml.key_pressed(k[2]) then
      local it = F.items[id]
      if bindable(it) then
        local ok, msg = pcall(FAV.press, it)
        if not ok then wml.log("hotkey " .. name .. ": " .. tostring(msg)) msg = "Error, see wml.log" end
        tell(msg)
      end
    end
  end
end

-- After a row's help: its hotkey, if it has one.
function FAV.note(it)
  local name = FAV.key_of(it)
  return name and ("  Hotkey: " .. key_label(name) .. ".") or ""
end

-- Settings > Hotkeys (also at the foot of Favorites): the keys given, Enter clears one.
local function hotkeys_page()
  local rows = {}
  local list = {}
  for _, k in ipairs(KEYS) do
    local id = store().hotkeys[k[1]]
    if id then list[#list + 1] = { k[1], id } end
  end
  if #list == 0 then
    rows[1] = { label = "No hotkeys yet", kind = "action", needs = "none",
      help = "On any switch, choice, list or action, press H, then a key (F1-F12, Num 0-9, Insert, Home, End or Delete).",
      run = function() return "Press H on a row to give it a key" end }
  end
  for _, e in ipairs(list) do
    local name, id = e[1], e[2]
    local it = F.items[id]
    local row = { kind = "action", needs = "none" }
    row.label = key_label(name) .. ": " .. (it and it.label or (id .. " (gone)"))
    row.help = reserved[name] and (key_label(name) .. " is now one of the menu's own keys, so it does nothing here. Enter clears it.")
      or "Enter clears this hotkey."
    row.run = function()
      if store().hotkeys[name] ~= id then return "Already cleared" end
      set_key(name, nil)
      row.label = key_label(name) .. ": (cleared)"
      return presets.write() or ("Hotkey " .. key_label(name) .. " cleared")
    end
    rows[#rows + 1] = row
  end
  if #list > 0 then
    local armed = false
    rows[#rows + 1] = { label = "Clear all hotkeys", kind = "action", needs = "none", help = "Press twice.",
      run = function()
        if not armed then armed = true return "Press again to clear every hotkey" end
        armed = false
        for name in pairs(store().hotkeys) do store().hotkeys[name] = nil end
        sync_keys()
        for _, r in ipairs(rows) do if r.label:find(": ") then r.label = r.label:gsub(": .*$", ": (cleared)") end end
        return presets.write() or "Every hotkey cleared"
      end }
  end
  return { title = "Hotkeys", rows = rows }
end

function FAV.setup(features)
  F = features
  local function reserve(name)
    name = tostring(name or ""):upper()
    if BY_NAME[name] then reserved[name] = true end
  end
  reserve(wml.setting("menu_key", "F5"))
  reserve("F7")   -- (Quick Camera)
  reserve(wml.setting("quick_save_key", "F9"))
  howto = { id = "favorites_help", label = "How to pin rows here", kind = "action", needs = "none", nosave = true, nopin = true,
    help = "On any row, press F (keyboard) or Y (controller) to pin it here, and again to unpin it. "
      .. "Press H on a row, then a key, to give it a hotkey that works with the menu closed.",
    run = function() return "F or Y on any row pins it here" end }
  hotkeys_row = { id = "hotkeys", label = "Hotkeys", kind = "page", needs = "none", nosave = true, nopin = true,
    help = "The keys you gave rows (H on a row, then a key). Enter on one clears it.",
    open = hotkeys_page }
  keys_header = F.header("Keys")
  F.register({ howto, hotkeys_row })
  cat = { name = "Favorites", items = {} }
  F.categories[#F.categories + 1] = cat
  F.add_rows("Settings", "import_settings", { hotkeys_row })
  FAV.refresh(true)
  sync_keys()
end

return FAV

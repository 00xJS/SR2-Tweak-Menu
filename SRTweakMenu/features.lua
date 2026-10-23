-- SR Tweak Menu (Saints Row 2) - the features, as the menu sees them.
--
-- The row engine is SR1's features.lua (the same kinds of row, the same
-- update rules) so menu.lua runs unchanged; the rows themselves are SR2's,
-- one file per tab (tab_*.lua), in SR1's tab order.
--
-- Every menu row is an item here. An item is one of:
--   toggle   on/off; `update` runs every game update while on, `off` once
--            when switched off.
--   value    a number; `update` runs while it differs from `default`, `off`
--            when it returns to it, `change` once per adjustment.
--   choice   one of `options`; `change` runs when it changes, `run` on Enter.
--   list     a long list (`items` of { id, "Shown name", ... }); Left/Right
--            browse, Enter picks (`run`).
--   action   `run` on Enter.
--   header   a heading line.
-- `needs` says what must be loaded: "player" (default), "vehicle", or "none".
--
-- Shorthand the SR2 rows use (handled here):
--   cheat = "Name"   a toggle that switches the phone cheat of that name
--                    (data/cheats.lua) on and off with the row.
--   every = n        run `update` only every n updates, not every update.

local G = require("game")
local S = wml.setting

local F = { categories = {}, items = {}, enabled = true, debug = false }

-- Optional data files: a missing or broken one leaves its list empty.
function F.data(name)
  local ok, t = pcall(require, "data." .. name)
  if ok and type(t) == "table" then return t end
  wml.log("data/" .. name .. ".lua not loaded: " .. tostring(t):match("^[^\n]*"))
  return {}
end

-- Registers rows (their defaults and needs) under F.items.
function F.register(items)
  for _, it in ipairs(items) do
    it.needs = it.needs or "player"
    if it.kind == "toggle" then it.v = it.v == true
    elseif it.kind == "value" then it.v = it.v or it.default
    elseif it.kind == "choice" or it.kind == "list" then it.v = it.v or 1 end
    if it.id then F.items[it.id] = it end
  end
end
function F.category(name, items)
  F.categories[#F.categories + 1] = { name = name, items = items }
  F.register(items)
end
-- More rows for a tab defined earlier, after the row `after`.
function F.add_rows(name, after, items)
  F.register(items)
  for _, cat in ipairs(F.categories) do
    if cat.name == name then
      local at = #cat.items + 1
      for i, it in ipairs(cat.items) do if it.id == after then at = i + 1 end end
      for k, it in ipairs(items) do table.insert(cat.items, at + k - 1, it) end
      return
    end
  end
end

-- ---------------------------------------------------------------- helpers for the tabs
F.fmt1 = function(v) return string.format("%.1f", v) end
F.fmtint = function(v) return string.format("%d", v) end
F.fmtx = function(v) return string.format("x%.1f", v) end

-- Phone cheats by name (data/cheats.lua: { index, "Name", "Category", "action", code = number }).
local CHEATS = F.data("cheats")
local cheat_number = {}
for _, c in ipairs(CHEATS) do if c.code then cheat_number[c[2]:lower()] = c.code end end
function F.cheat_number(name) return cheat_number[name:lower()] end
-- Switches the named cheat on or off; returns a message if it can't.
function F.cheat(name, on)
  local n = cheat_number[name:lower()]
  if not n then return "The game has no cheat called " .. name end
  if G.cheat_set(n, on ~= false) == nil then return "The game didn't take the cheat " .. name end
end
-- A cheat that acts once (gives a vehicle, sets the weather): on, then off
-- again so it can be used again.
function F.cheat_once(name)
  local msg = F.cheat(name, true)
  if not msg then F.cheat(name, false) end
  return msg
end

-- The controller (XInput bits, as menu.lua's PAD) and D-pad helpers for
-- rows that act on a button: held, or pressed this update. The arrow keys
-- count as the D-pad, as in SR1. Nothing reaches rows while the menu is open.
F.pad, F.pad_prev = 0, 0
local DPAD = { UP = 0x1, DOWN = 0x2, LEFT = 0x4, RIGHT = 0x8 }
function F.dpad_down(name)
  if F.menu_open() then return false end
  return (F.pad & DPAD[name]) ~= 0 or wml.key_down(name)
end
function F.dpad_hit(name)
  if F.menu_open() then return false end
  return ((F.pad & DPAD[name]) ~= 0 and (F.pad_prev & DPAD[name]) == 0) or wml.key_pressed(name)
end

-- A page row (SR1's kind "page"): Enter opens `rows` on a page of its own.
-- The rows are registered, so their toggles apply like any other.
function F.page(id, label, help, rows)
  F.register(rows)
  return { id = id, label = label, kind = "page", needs = "none", help = help,
    open = function() return { title = label, rows = rows } end }
end

-- A header row.
local heads = 0
function F.header(label)
  heads = heads + 1
  return { id = "header_" .. heads, kind = "header", label = label, needs = "none" }
end

-- ---------------------------------------------------------------- the tabs
require("engine").attach(F)
for _, tab in ipairs({ "player", "models", "emotes", "weapons", "vehicles", "world", "visual", "teleport", "settings" }) do
  local ok, err = pcall(function() require("tab_" .. tab)(F, G) end)
  if not ok then wml.log("tab " .. tab .. " failed to load: " .. tostring(err)) end
end
-- The quality-of-life rows (SR1's juiced.lua rows), into the tabs above.
do
  local ok, err = pcall(function()
    local QOL = require("qol")
    QOL.setup(F)
    F.after_update = QOL.after_update
  end)
  if not ok then wml.log("qol failed to load: " .. tostring(err)) end
end

-- ---------------------------------------------------------------- updates

-- Items whose state is active right now.
local function active(it)
  if not F.enabled then return false end
  if it.kind == "toggle" then return it.v end
  if it.kind == "value" and not it.oneshot then return it.v ~= it.default end
  return false
end

-- Items that were active last update and need their `off` run.
local was_active = {}
-- Cheat toggles currently switched on in the game, by row id.
local cheat_on = {}

function F.on(id) return F.enabled and F.items[id] and F.items[id].v end

-- Called every game update, after the menu has read its input.
F.tick = 0
local update_errors = {}
local function safe(it, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not update_errors[it.id] then
    update_errors[it.id] = true
    wml.log("feature " .. it.id .. " failed: " .. tostring(err))
  end
end

local menu_open = false
function F.set_menu_open(open) menu_open = open end
function F.menu_open() return menu_open end

local last_player = 0
function F.update(ctx)
  F.tick = F.tick + 1
  local p = G.player()
  if p ~= last_player then
    -- A new game (or none): what we put on the old player is gone.
    last_player = p
    for id in pairs(was_active) do was_active[id] = nil end
  end
  local v = G.vehicle_handle(p) or 0
  for _, it in pairs(F.items) do
    local on = active(it)
    local ok = it.needs == "none" or (it.needs == "player" and p ~= 0) or (it.needs == "vehicle" and v ~= 0)
    if on and ok then
      if it.cheat and not cheat_on[it.id] then
        cheat_on[it.id] = true
        safe(it, F.cheat, it.cheat, true)
      end
      if it.update and (not it.every or not was_active[it.id] or F.tick % it.every == 0) then
        safe(it, it.update, ctx, p, v, it)
      end
      was_active[it.id] = true
    elseif not on and (was_active[it.id] or cheat_on[it.id]) then
      -- Switched off (or back to default): put things back once.
      was_active[it.id] = nil
      if it.cheat and cheat_on[it.id] then
        cheat_on[it.id] = nil
        if p ~= 0 then safe(it, F.cheat, it.cheat, false) end
      end
      if it.off and p ~= 0 then safe(it, it.off, ctx, p, v, it) end
    end
  end
  if F.after_update then safe({ id = "after_update" }, F.after_update, p) end
end

-- ---------------------------------------------------------------- the menu's calls
--
-- All of these run in the frame hook (they may call the game).

local function context(it)
  local p = G.player()
  if it.needs ~= "none" and p == 0 then return nil, "Load a single-player game first" end
  local v = G.vehicle_handle(p) or 0
  if it.needs == "vehicle" and v == 0 then return nil, "Get in a vehicle first" end
  return p, v
end

function F.toggle(ctx, it)
  if it.kind ~= "toggle" then return end
  it.v = not it.v
  if it.id == "master" then F.enabled = it.v end
  local p, v = context(it)
  local msg = it.change and (p or it.needs == "none") and it.change(ctx, p or 0, v or 0, it)
  return msg or (it.label .. (it.v and " on" or " off"))
end

function F.adjust(ctx, it, dir, fast)
  if it.kind == "value" then
    local step = it.step * (fast and 10 or 1)
    local nv = it.v + dir * step
    nv = math.max(it.min, math.min(it.max, nv))
    nv = math.floor(nv / it.step + 0.5) * it.step
    if math.abs(nv - it.v) < 1e-9 then return end
    it.v = nv
    local p, v = context(it)
    if it.change and p then it.change(ctx, p, v, it) end
    return it.label .. " " .. it.fmt(it.v)
  elseif it.kind == "choice" then
    local n = #it.options
    it.v = ((it.v - 1 + dir) % n) + 1
    local p, v = context(it)
    if it.change and p then it.change(ctx, p, v, it) end
    return it.label .. ": " .. it.options[it.v]
  elseif it.kind == "list" then
    local n = #it.items
    if n == 0 then return it.label .. ": nothing to choose" end
    it.v = ((it.v - 1 + dir * (fast and 10 or 1)) % n) + 1
    if it.change then
      local p, v = context(it)
      if p and p ~= 0 then it.change(ctx, p, v, it) end
    end
    return it.label .. ": " .. it.items[it.v][2]
  end
end

function F.activate(ctx, it)
  if it.kind == "toggle" then return F.toggle(ctx, it) end
  if it.kind == "value" then return F.adjust(ctx, it, 1) end
  if it.kind == "list" and #it.items == 0 then return "Nothing to choose" end
  if it.run then
    local p, v = context(it)
    if not p and it.needs ~= "none" then return v end  -- v holds the reason
    local ok, result = pcall(it.run, ctx, p or 0, v or 0, it)
    if not ok then wml.log("feature " .. it.id .. ": " .. tostring(result)); return "Error, see wml.log" end
    return result
  end
end

-- (SR1 keeps the list entries usable right now here; SR2's lists are all usable.)
function F.refresh_usable(ctx) end

function F.list_position(it)
  if #it.items == 0 then return "none" end
  return it.v .. "/" .. #it.items
end

-- Text shown for an item's current value.
function F.value_text(it)
  if it.kind == "toggle" then return it.v and "[ON]" or "[OFF]" end
  if it.kind == "value" then return "< " .. it.fmt(it.v) .. " >" end
  if it.kind == "choice" then return "< " .. it.options[it.v] .. " >" end
  if it.kind == "list" then return #it.items > 0 and ("< " .. it.items[it.v][2] .. " >") or "< none >" end
  return ""
end

function F.status_line()
  local parts = {}
  for _, it in pairs(F.items) do
    if it.kind == "toggle" and it.v and it.id ~= "master" then parts[#parts + 1] = it.label end
  end
  table.sort(parts)
  return (F.enabled and "On: " or "Tweaks OFF. Would be on: ") .. (#parts > 0 and table.concat(parts, ", ") or "nothing")
end

-- ---------------------------------------------------------------- mod.ini
-- Rows that act while the game starts (skip intro, load last save) keep
-- their value in mod.ini at once: `name = value` replaced, or added under
-- [settings].
F.INI = wml.mod_folder .. "\\mod.ini"
function F.save_setting(name, value)
  local f = io.open(F.INI, "r")
  if not f then return end
  local lines, found = {}, false
  for line in f:lines() do
    if line:match("^%s*" .. name .. "%s*=") then line = name .. " = " .. tostring(value); found = true end
    lines[#lines + 1] = line
  end
  f:close()
  if not found then
    for i, line in ipairs(lines) do
      if line:match("^%[settings%]") then table.insert(lines, i + 1, name .. " = " .. tostring(value)); found = true break end
    end
  end
  if not found then return end
  f = io.open(F.INI, "w")
  if not f then return end
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

-- ---------------------------------------------------------------- saved tweaks
-- Settings > Save tweaks for next time: every row's value, one per line
-- (id=value), in saved_tweaks.txt next to mod.ini. Rows marked nosave, and
-- actions, aren't saved.
F.SAVE_FILE = wml.mod_folder .. "\\saved_tweaks.txt"
function F.save_tweaks()
  local f = io.open(F.SAVE_FILE, "w")
  if not f then return "Couldn't write " .. F.SAVE_FILE end
  local n = 0
  for id, it in pairs(F.items) do
    if not it.nosave and (it.kind == "toggle" or it.kind == "value" or it.kind == "choice") then
      f:write(id, "=", tostring(it.v), "\n"); n = n + 1
    end
  end
  f:close()
  return "Saved " .. n .. " tweaks for next time"
end
function F.load_tweaks()
  local f = io.open(F.SAVE_FILE, "r")
  if not f then return end
  for line in f:lines() do
    local id, v = line:match("^([%w_]+)=(.*)$")
    local it = id and F.items[id]
    if it and not it.nosave then
      if it.kind == "toggle" then it.v = v == "true"
      elseif it.kind == "value" then it.v = tonumber(v) or it.v
      elseif it.kind == "choice" then local n = tonumber(v) if n and it.options[n] then it.v = n end end
    end
  end
  f:close()
  F.enabled = F.items.master.v
end
function F.forget_tweaks()
  os.remove(F.SAVE_FILE)
  return "Saved tweaks forgotten: the menu starts with everything off"
end

return F

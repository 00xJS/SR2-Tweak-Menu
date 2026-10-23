-- SR Tweak Menu (Saints Row 2) - the features, as the menu sees them.
--
-- The row engine is SR1's features.lua (the same kinds of row, the same
-- update rules) so menu.lua runs unchanged; the rows themselves are SR2's.
--
-- Every menu row is an item here. An item is one of:
--   toggle   on/off; `update` runs every game update while on, `off` once
--            when switched off.
--   value    a number; `update` runs while it differs from `default`, `off`
--            when it returns to it, `change` once per adjustment.
--   choice   one of `options`; `change` runs when it changes, `run` on Enter.
--   list     a long list; Left/Right browse, Enter picks.
--   action   `run` on Enter.
-- `needs` says what must be loaded: "player" (default), "vehicle", or "none".

local G = require("game")
local S = wml.setting

local F = { categories = {}, items = {}, enabled = true, debug = false }

-- Registers rows (their defaults and needs) under F.items.
function F.register(items)
  for _, it in ipairs(items) do
    it.needs = it.needs or "player"
    if it.kind == "toggle" then it.v = it.v == true
    elseif it.kind == "value" then it.v = it.v or it.default
    elseif it.kind == "choice" or it.kind == "list" then it.v = it.v or 1 end
    F.items[it.id] = it
  end
end
local function category(name, items)
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

-- ---------------------------------------------------------------- rows
--
-- God mode: the game's own invulnerability (turn_invulnerable, what the
-- missions use), put on again every few seconds and after a load, since
-- missions and cutscenes switch it themselves.
local god_on_player, god_tick = 0, 0
local function god_apply(p)
  G.script(nil, "turn_invulnerable(LOCAL_PLAYER)")
  god_on_player, god_tick = p, F.tick
end

category("Player", {
  { id = "god", label = "God mode", kind = "toggle",
    help = "You can't be hurt.",
    update = function(ctx, p)
      if p ~= god_on_player or F.tick - god_tick > 180 then god_apply(p) end
    end,
    off = function(ctx, p)
      if p ~= 0 then G.script(nil, "turn_vulnerable(LOCAL_PLAYER)") end
      god_on_player = 0
    end },
  { id = "money", label = "Money +$50,000", kind = "action",
    help = "Adds $50,000 to your cash.",
    run = function()
      G.script(nil, "cash_add(50000)")
      return "Added $50,000"
    end },
})

category("Teleport", {
  { id = "waypoint_go", label = "Teleport to waypoint", kind = "action",
    help = "Takes you (and your car) to the waypoint set on the pause map.",
    run = function()
      local x, y, z = G.waypoint()
      if not x then return "Set a waypoint on the map first" end
      G.teleport(x, y, z)
      return "Teleported to the waypoint"
    end },
})

category("Settings", {
  { id = "master", label = "All tweaks", kind = "toggle", needs = "none", v = true, help = "Turns every tweak on or off." },
  { id = "status", label = "Show active tweaks", kind = "action", needs = "none", help = "",
    run = function() return F.status_line() end },
})

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

function F.on(id) return F.enabled and F.items[id].v end

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

function F.update(ctx)
  F.tick = F.tick + 1
  local p = G.player()
  local v = 0   -- (no vehicle rows yet)
  for _, it in pairs(F.items) do
    local on = active(it)
    local ok = it.needs == "none" or (it.needs == "player" and p ~= 0) or (it.needs == "vehicle" and v ~= 0)
    if on and ok then
      if it.update then safe(it, it.update, ctx, p, v, it) end
      was_active[it.id] = true
    elseif was_active[it.id] and not on then
      -- Switched off (or back to default): put things back once.
      was_active[it.id] = nil
      if it.off then safe(it, it.off, ctx, p, v, it) end
    end
  end
end

-- ---------------------------------------------------------------- the menu's calls
--
-- All of these run in the frame hook (they may call the game).

local function context(it)
  local p = G.player()
  local v = 0
  if it.needs == "player" and p == 0 then return nil, "Load a single-player game first" end
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
    if it.live and it.read then
      local ok, r = pcall(it.read, G.player())
      if ok and type(r) == "number" then it.v = r end
    end
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
  if it.run then
    local p, v = context(it)
    if not p and it.needs ~= "none" then return v end  -- v holds the reason
    local ok, result = pcall(it.run, ctx, p or 0, v or 0, it)
    if not ok then wml.log("feature " .. it.id .. ": " .. tostring(result)); return "Error, see wml.log" end
    return result
  end
end

-- (SR1 keeps the list entries usable right now here; SR2 has no such lists yet.)
function F.refresh_usable(ctx) end

function F.list_position(it)
  if it.ok then
    if #it.ok == 0 then return "none available" end
    for k, i in ipairs(it.ok) do if i == it.v then return k .. "/" .. #it.ok end end
    return "?/" .. #it.ok
  end
  return it.v .. "/" .. #it.items
end

-- Text shown for an item's current value.
function F.value_text(it)
  if it.kind == "toggle" then return it.v and "[ON]" or "[OFF]" end
  if it.kind == "value" then
    local shown = it.v
    if it.live and it.read then
      local p = G.player()
      if p ~= 0 or it.needs == "none" then
        local ok, r = pcall(it.read, p)
        if ok and r then shown = r end
      end
    end
    return "< " .. it.fmt(shown) .. " >"
  end
  if it.kind == "choice" then return "< " .. it.options[it.v] .. " >" end
  if it.kind == "list" then return "< " .. it.items[it.v][2] .. " >" end
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

return F

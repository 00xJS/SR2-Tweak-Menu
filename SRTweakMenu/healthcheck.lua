-- SR Tweak Menu (Saints Row 2) - Settings > Run self-test: checks what can
-- be checked without changing anything in the game, a few steps a frame,
-- and writes TweakMenu\selftest_report.txt (a summary goes to wml.log too).
--
--   1. Every game function the menu's code calls exists in the game's Lua
--      or the interface's (the names are read from the menu's own source).
--   2. Every page opens, or says why not (each is closed again at once).
--   3. What the Customize, weapon and vehicle rows read back from the game.
--   4. Rows that have failed since the game started.
-- It gives nothing, spawns nothing and changes no setting.
local G = require("game")
local H = {}

local ROOT = wml.mod_folder:match("^(.*)[/\\][^/\\]+$") or wml.mod_folder
local GAME_DIR = ROOT:match("^(.*)[/\\][^/\\]+$") or ROOT
H.REPORT = ROOT .. "\\selftest_report.txt"

local job, last

-- ---------------------------------------------------------------- 1. names
-- Lua's own functions, and the menu's helpers inside its code strings.
local SKIP = {}
for name in ([[assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile loadstring
  next pairs pcall print rawequal rawget rawlen rawset require select setfenv setmetatable tonumber
  tostring type unpack xpcall]]):gmatch("%S+") do SKIP[name] = true end

-- The text of every string literal in a Lua source file.
local function literals(src)
  local out, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i, i + 1) == "--" then
      local eq = src:match("^%-%-%[(=*)%[", i)
      if eq then
        local _, e = src:find("]" .. eq .. "]", i, true)
        i = (e or n) + 1
      else
        i = (src:find("\n", i, true) or n) + 1
      end
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1) j = j + 2
        elseif d == c or d == "\n" then break
        else buf[#buf + 1] = d j = j + 1 end
      end
      out[#out + 1] = table.concat(buf)
      i = j + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local s = i + #eq + 2
      local e1, e2 = src:find("]" .. eq .. "]", s, true)
      out[#out + 1] = src:sub(s, (e1 or n + 1) - 1)
      i = (e2 or n) + 1
    else
      i = i + 1
    end
  end
  return out
end

-- Game function names the menu's code strings call: snake_case names
-- followed straight by "(", not after "." or ":", not defined in the code
-- itself, and not the menu's own TWK_ callbacks.
function H.called_names(sources)
  local found, defined = {}, {}
  for _, src in ipairs(sources) do
    for _, text in ipairs(literals(src)) do
      for name in text:gmatch("function%s+([%a_][%w_]*)") do defined[name] = true end
      for pos, name in text:gmatch("()([%a_][%w_]*)%(") do
        local before = pos > 1 and text:sub(pos - 1, pos - 1) or ""
        if name:find("_", 1, true) and before ~= "." and before ~= ":" and not before:match("[%w_]")
          and not SKIP[name] and not name:find("^TWK_") then
          found[name] = true
        end
      end
    end
  end
  local list = {}
  for name in pairs(found) do if not defined[name] then list[#list + 1] = name end end
  table.sort(list)
  return list
end

local function module_sources()
  local names, sources = {}, {}
  for name in pairs(package.loaded) do
    if type(name) == "string" and not name:find("^data%.") then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = package.searchpath(name, package.path)
    local f = path and io.open(path, "rb")
    if f then sources[#sources + 1] = f:read("a") f:close() end
  end
  return sources
end

-- type() of each name as a plain global of one Lua state; up to 100 a call
-- (the host passes back at most 128 values).
local function global_types(run, names)
  local types = {}
  for first = 1, #names, 100 do
    local quoted = {}
    for i = first, math.min(first + 99, #names) do quoted[#quoted + 1] = string.format("%q", names[i]) end
    local res = table.pack(run("local n = { " .. table.concat(quoted, ", ") .. " } local i = 1 "
      .. "while n[i] do tweak_out(type(rawget(_G, n[i]))) i = i + 1 end"))
    for k = 1, #quoted do types[names[first + k - 1]] = res[1] and res[k + 1] or nil end
  end
  return types
end

-- ---------------------------------------------------------------- report
local function report() return job.lines end
local function say(fmt, ...) local r = report() r[#r + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
local function problem(fmt, ...)
  job.problems = job.problems + 1
  say("  PROBLEM: " .. fmt, ...)
end
local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end
local function ini_version()
  local f = io.open(wml.mod_folder .. "\\mod.ini", "r")
  if not f then return "?" end
  for line in f:lines() do
    local v = line:match("^%s*version%s*=%s*(.-)%s*$")
    if v then f:close() return v end
  end
  f:close()
  return "?"
end

-- ---------------------------------------------------------------- steps
local function steps(F)
  local list = {}
  local function add(fn) list[#list + 1] = fn end
  local p = G.player()

  add(function()
    local dfengine = file_size(GAME_DIR .. "\\DFEngine.dll")
    say("SR Tweak Menu %s self-test, %s", ini_version(), os.date("%Y-%m-%d %H:%M"))
    say("Juiced Patch: %s", dfengine == nil and "DFEngine.dll not found"
      or (dfengine == 676464 and "off (the game's own DFEngine.dll)" or ("on (DFEngine.dll " .. dfengine .. " bytes)")))
    say("Player %08X, actor %08X, %s, %s", p, p ~= 0 and wml.read_u32(p + 0x44) or 0,
      G.vehicle_handle(p) and ("in vehicle " .. string.format("%08X", G.vehicle_handle(p))) or "on foot",
      G.in_cutscene() and "in a cutscene" or "no cutscene")
    if G.in_cutscene() then problem("a cutscene is playing: run the self-test again in free roam") end
    local data = {}
    for name, t in pairs(package.loaded) do
      if type(name) == "string" and name:find("^data%.") then
        local n = 0
        if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
        data[#data + 1] = name:sub(6) .. " " .. n
      end
    end
    table.sort(data)
    say("Data files loaded: %s", #data > 0 and table.concat(data, ", ") or "none")
  end)

  -- 1. Game functions.
  add(function()
    say("")
    say("== Game functions the menu calls ==")
    local names = H.called_names(module_sources())
    job.names = names
    job.in_game = global_types(function(code) return G.script(nil, code) end, names)
    job.in_vint = global_types(G.vint, names)
    job.unsure, job.unsure_at = {}, 1
    for _, name in ipairs(names) do
      if not job.in_game[name] and not job.in_vint[name] then job.unsure[#job.unsure + 1] = name end
    end
  end)
  -- Names neither state has as a plain global may still be reachable
  -- through the state's guard: ask each one on its own, a few a frame.
  add(function()
    local stop = math.min(job.unsure_at + 7, #job.unsure)
    for i = job.unsure_at, stop do
      local name = job.unsure[i]
      local ok, kind = G.script(nil, "tweak_out(type(" .. name .. "))")
      if ok and kind ~= "nil" then job.in_game[name] = kind end
      ok, kind = G.vint("tweak_out(type(" .. name .. "))")
      if ok and kind ~= "nil" then job.in_vint[name] = kind end
    end
    job.unsure_at = stop + 1
    if job.unsure_at <= #job.unsure then return "again" end
    local missing, only_vint = {}, {}
    for _, name in ipairs(job.names) do
      if not job.in_game[name] and not job.in_vint[name] then missing[#missing + 1] = name
      elseif not job.in_game[name] then only_vint[#only_vint + 1] = name end
    end
    say("%d names found in the menu's code; %d in the game's Lua, %d only in the interface's.",
      #job.names, #job.names - #missing - #only_vint, #only_vint)
    for _, name in ipairs(missing) do problem("%s() is in neither Lua state", name) end
  end)

  -- 3. What the rows read back.
  add(function()
    say("")
    say("== Character ==")
    if p == 0 or not G.playing(p) then say("  skipped: needs your character on foot") return end
    local body, barber = require("face_body"), require("hair")
    if not body.record(p) then problem("no customization record on the player (player + 0x13B0)") return end
    say("  streaming done: %s", tostring(body.ready()))
    local _, voice = G.vint("tweak_out(pcr_get_current_voice_number())")
    say("  voice: %s", tostring(voice))
    if type(voice) ~= "number" then problem("the voice number couldn't be read") end
    local skin = body.skin_current()
    say("  skin color: %s", tostring(skin))
    if skin == nil then problem("the skin color couldn't be read") end
    local total = 0
    for _, set in ipairs({ "global gender", "global body", "crown", "forehead", "brow", "eyes", "nose",
      "cheekbones", "ears", "chin", "mouth", "jaw" }) do
      local n = #body.morph_values(set)
      total = total + n
      say("  morph set %-13s %d controls", set, n)
    end
    if total == 0 then problem("no face or body controls could be read (Saved Looks would save nothing)") end
    for area, label in pairs({ [0] = "head hair", "mustache", "beard", "sideburns", "eyebrows" }) do
      local style = barber.current(p, area)
      say("  %-9s %s", label, style and string.format("style %d, colors %d / %d", style.id, style.primary, style.secondary)
        or "couldn't be read")
    end
  end)
  add(function()
    say("")
    say("== Walk style ==")
    local ptr, count = wml.read_u32(0x025274D4), wml.read_u32(0x025274D8)
    say("  catalog %08X, %d entries; current state %08X", ptr, count, p ~= 0 and wml.read_u32(p + 0x1138) or 0)
    if ptr == 0 or count == 0 or count > 256 then problem("the walk-style catalog isn't loaded (Walk Style and Keep walk style won't work)") end
    local kept = require("native_walk").kept()
    say("  kept walk style: %s", type(kept) == "string" and kept or "none")
  end)
  add(function()
    say("")
    say("== Weapons ==")
    if p == 0 then say("  skipped: no player") return end
    local res = table.pack(G.lua('local function s(n) local w = inv_item_in_slot(LOCAL_PLAYER, n) tweak_out(n, tostring(w)) end '
      .. 's("melee") s("pistol") s("smg") s("shotgun") s("rifle") s("launcher") s("thrown") '
      .. 'tweak_out("in hand", tostring(inv_item_get_equipped_item(LOCAL_PLAYER)))'))
    if not res[1] then problem("inv_item_in_slot failed (Limited Weapons can't see your weapons)") return end
    for i = 2, res.n, 2 do say("  %-9s %s", tostring(res[i]), tostring(res[i + 1])) end
  end)
  add(function()
    say("")
    say("== Vehicle paint colors ==")
    local pool = wml.read_u32(0x0252A084)
    local colors = require("data.vehicle_colors")
    local first = colors[1] and colors[1][1]
    local found = first and wml.callx(0x00AC9F40, { eax = wml.buffer(12, first) }) or 0
    say("  pool %08X; %q -> %08X", pool, tostring(first), found)
    if pool == 0 or found ~= pool then
      problem("paint colors don't line up with data/vehicle_colors.lua (Vehicle Presets may restore the wrong paint)")
    end
  end)

  -- 2. Pages, three levels down from each tab.
  add(function()
    job.pages, job.page_at = {}, 1
    local function walk(rows, path, depth)
      for _, row in ipairs(rows) do
        if row.kind == "page" and row.open then
          job.pages[#job.pages + 1] = { row = row, path = path .. " > " .. tostring(row.label), depth = depth }
        end
      end
    end
    for _, cat in ipairs(F.categories) do walk(cat.items, cat.name, 1) end
    say("")
    say("== Pages ==")
  end)
  add(function()
    for _ = 1, 3 do
      local entry = job.pages[job.page_at]
      if not entry then break end
      job.page_at = job.page_at + 1
      local row, needs = entry.row, entry.row.needs
      if needs == "vehicle" and not G.vehicle_handle(p) then
        say("  %s: skipped (needs a vehicle)", entry.path)
      else
        local ok, pg = pcall(row.open, nil, p, row)
        if not ok then
          problem("%s: error opening: %s", entry.path, tostring(pg))
        elseif type(pg) == "string" then
          say("  %s: refused: %s", entry.path, pg)
        elseif type(pg) ~= "table" or type(pg.rows) ~= "table" then
          problem("%s: opened nothing", entry.path)
        else
          job.opened = (job.opened or 0) + 1
          if entry.depth < 3 and #job.pages < 400 then
            for _, sub in ipairs(pg.rows) do
              if sub.kind == "page" and sub.open then
                job.pages[#job.pages + 1] = { row = sub, path = entry.path .. " > " .. tostring(sub.label), depth = entry.depth + 1 }
              end
            end
          end
          -- Closed straight away, as Back would: pages that preview put things back here.
          if pg.back then pcall(pg.back, nil, "selftest") end
        end
      end
    end
    if job.pages[job.page_at] then return "again" end
    say("  %d pages opened of %d listed.", job.opened or 0, #job.pages)
  end)

  -- 4. Row failures.
  add(function()
    say("")
    say("== Rows that failed since the game started ==")
    local ids = {}
    for id in pairs(F.errors or {}) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    if #ids == 0 then say("  none") end
    for _, id in ipairs(ids) do problem("%s failed (its error is in wml.log)", id) end
    say("")
    say("== Try by hand (the self-test can't tell) ==")
    say("  Items: give The Fist, then check your inventory has it.")
    say("  Locked Cars: switch it on in a car, then let a gang member try to pull you out.")
    say("  Limited Weapons: pick up a second big gun; the first should go to the stash, Swap big gun brings it back.")
    say("  Saved Looks: save, change your hair, load. Vehicle Presets: save, change a part and the paint, load.")
    say("  Bodyguard weapon: pick the AR-200, spawn a bodyguard, see what they hold.")
  end)
  return list
end

-- ---------------------------------------------------------------- run
function H.start(F)
  if job then return "The self-test is already running" end
  job = { lines = {}, problems = 0, at = 1 }
  job.steps = steps(F)
  last = nil
  wml.log("selftest: started")
  return "Self-test running: stay where you are for a few seconds"
end

function H.update()
  if not job then return end
  local fn = job.steps[job.at]
  local ok, again = pcall(fn)
  if not ok then
    job.problems = job.problems + 1
    job.lines[#job.lines + 1] = "  PROBLEM: the self-test step itself failed: " .. tostring(again)
    again = nil
  end
  if again ~= "again" then job.at = job.at + 1 end
  if job.at <= #job.steps then return end
  table.insert(job.lines, 2, job.problems == 0 and "Result: no problems found"
    or ("Result: " .. job.problems .. " problems (lines marked PROBLEM)"))
  local text = table.concat(job.lines, "\n") .. "\n"
  local f = io.open(H.REPORT, "w")
  if f then f:write(text) f:close() end
  for line in text:gmatch("[^\n]+") do
    if line:find("PROBLEM", 1, true) or line:find("^Result") then wml.log("selftest: " .. line) end
  end
  last = (job.problems == 0 and "NO PROBLEMS" or (job.problems .. " PROBLEMS")) .. (f and "" or ", REPORT NOT WRITTEN")
  job = nil
end

function H.status()
  if job then return ("RUNNING %d%%"):format(math.floor((job.at - 1) * 100 / math.max(1, #job.steps))) end
  return last or ""
end

function H.row(F)
  F.after_updates[#F.after_updates + 1] = H.update
  return { id = "selftest_run", label = "Run self-test", kind = "action", needs = "player", nosave = true,
    help = "Checks every game function and page the menu uses and what it reads back, without changing anything. The result is in TweakMenu\\selftest_report.txt.",
    note = H.status,
    run = function() return H.start(F) end }
end

return H

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
  take_key = function() end, force_key = function() end,
  on_frame = function(fn) frames[#frames + 1] = fn end,
  hook = function() error("no hooks") end,
  script = function(code) calls[#calls + 1] = "script: " .. code return true end,
  vint = function(code) calls[#calls + 1] = "vint: " .. code return true end,
  call = function(a) calls[#calls + 1] = string.format("call %08X", a) return 0 end,
  callx = function(a) calls[#calls + 1] = string.format("callx %08X", a) return 0 end,
  buffer = function(slot) return 0x7F000000 + slot * 1024 end,
  read_string = function() return "" end,
  patch = function(a) calls[#calls + 1] = string.format("patch %08X", a) end,
  f2u = function(f) return string.unpack("<I4", string.pack("<f", f)) end,
  u2f = function(u) return string.unpack("<f", string.pack("<I4", u)) end,
  pad = function() return nil end,
}

-- A loaded single-player game with the player at 0x10000000, in a car,
-- with a waypoint set.
wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, 0x10000000); wr(0x10000000 + 0xD74, 4, 0x1234)
wr(0x01F7A418, 4, 1)

dofile(root .. "/main.lua")
local function frame(pressed)
  keys_prev = keys_now; keys_now = {}
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
local problems = {}
local total = 0
-- Presses every row on the current page (or tab); opens pages and does
-- their rows too, then comes back.
local function sweep(where, depth)
  local seen = {}
  while true do
    local it = MENU.current()
    if not it or seen[it] then break end
    seen[it] = true
    total = total + 1
    local before = #calls
    if it.kind == "toggle" then press("ENTER"); for _ = 1, 3 do frame() end; press("ENTER"); for _ = 1, 3 do frame() end
    elseif it.kind == "value" or it.kind == "choice" then press("RIGHT"); frame(); press("LEFT"); frame()
    elseif it.kind == "list" then press("RIGHT"); press("ENTER")
    elseif it.kind == "action" then press("ENTER") end
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
        press("BACKSPACE")
      else
        problems[#problems + 1] = where .. " / " .. it.label .. ": page didn't open (" .. tostring(MENU.status) .. ")"
      end
    end
    press("DOWN")
  end
end

for tab = 1, #F.categories do
  local cat = F.categories[tab]
  if verbose then print("==== " .. cat.name .. "\n" .. screen()) end
  print(cat.name)
  sweep(cat.name, 1)
  press("PAGEDOWN")
end
press("F5")
for _, l in ipairs(logs) do if l:find("fail") or l:find("rror") then problems[#problems + 1] = "log: " .. l end end
print(total .. " rows; " .. (#problems == 0 and "no errors" or ("PROBLEMS:\n  " .. table.concat(problems, "\n  "))))

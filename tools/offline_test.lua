-- Offline test: runs the menu with a fake wml (memory, keys, settings) and
-- prints what the host would draw. Usage (from the repo root):
--   build\lua.exe tools\offline_test.lua
local root = "SRTweakMenu"
package.path = root .. "/?.lua"

local mem, mailbox = {}, {}
local MAILBOX = 0x00F00000
local keys_now, keys_prev = {}, {}
local frames = {}
local scripts, calls = {}, {}
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
wml = {
  mod_folder = root, mod_name = "test", game = "sr2",
  log = function(...) print("[log]", ...) end,
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
  script = function(code) scripts[#scripts + 1] = code return true end,
  call = function(a) calls[#calls + 1] = string.format("%08X", a) return 0 end,
  pad = function() return nil end,
}

-- A loaded single-player game with the player at 0x10000000.
wr(0x00E94D3E, 1, 1); wr(0x00E8B210, 1, 0xFF); wr(0x021703D4, 4, 0x10000000)

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

frame()
press("F5")
print("---- menu open (Player tab)\n" .. screen())
press("ENTER")                -- God mode on
for _ = 1, 3 do frame() end
press("DOWN"); press("ENTER") -- +$50,000
print("---- after God mode + money\n" .. screen())
press("PAGEDOWN"); press("ENTER")  -- Teleport tab: no waypoint yet
print("---- teleport without a waypoint\n" .. screen())
wr(0x01F7A418, 4, 1)
wml.write_f32(0x029B9CD0, 100.5); wml.write_f32(0x029B9CD4, 20.25); wml.write_f32(0x029B9CD8, -300)
press("ENTER")
print("---- teleport with a waypoint: pos " .. wml.read_f32(0x027B305A) .. ", " .. wml.read_f32(0x027B305E) .. ", " .. wml.read_f32(0x027B3062))
press("PAGEUP"); press("UP"); press("ENTER")    -- God mode off
press("F5")
print("---- closed: '" .. screen() .. "'")
print("scripts: " .. table.concat(scripts, " | "))
print("calls: " .. table.concat(calls, " "))

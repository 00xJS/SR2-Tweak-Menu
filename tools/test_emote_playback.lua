-- From the repo root: build/lua.exe tools/test_emote_playback.lua
package.path = "SRTweakMenu/?.lua"
local p, owner, id = 0x10000000, 0x11000000, 2
local player = 0x0340D240 + id * 0x5E8
local count, exclusive, track = player + 0x23C, player + 0x240, player + 0x254
local invalid, definition, file = 0xFFFFFFFF, 12, 40
local clip_data = 0x024F2F00 + 32 * file + 0x1C
local mem = {
  [p + 0x5E0] = owner, [owner] = id, [exclusive] = invalid,
  [0x024E1864] = 100, [0x02527D6C] = 20, [0x015B8800 + definition * 0x54 + 0xC] = file,
}
local ready, lookup, starts, stops = true, 0xFFFF, 0, 0
local scratch, log, looping
package.loaded.game = {
  playing = function(who) return who == p end,
  lua = function() return true, ready end,
}
wml = {
  read_u32 = function(a) return mem[a] or 0 end,
  buffer = function(_, s) scratch = s return 0x12000000 end,
  f2u = function(f) return string.unpack("<I4", string.pack("<f", f)) end,
  log = function(s) log = s end,
  callx = function(a, regs, ...)
    if a == 0x006EF580 then return 5 end
    if a == 0x006EF6A0 then
      local who, slot = ...
      assert(who == owner and slot == 5)
      return lookup
    end
    if a == 0x00CEC2A0 then
      return scratch == "pml1_bs_sd_idle_hair.anim" and file or invalid
    end
    if a == 0x00CE6D20 then
      local who, clip, flags = ...
      assert(who == player and clip == file and flags == (looping and 0x42 or 0x40))
      starts = starts + 1
      mem[count], mem[track], mem[track + 4] = 1, starts + 100, file
      return (starts + 100) << 4
    end
    assert(a == 0x00CE72A0 and (...) == player and regs.eax == mem[track] << 4)
    stops = stops + 1
    mem[count] = 0
  end,
}
local A = require("emote_playback")
assert(not A.play(p, "Action", "Idle Fix Hair") and starts == 0)
mem[clip_data] = 1
local borrowed = assert(A.play(p, "Action", "Idle Fix Hair"))
assert(log:find("borrowed pml1_bs_sd_idle_hair", 1, true))
assert(A.active(p, borrowed))
local already_playing = assert(A.play(p, "Action", "Idle Fix Hair"))
assert(already_playing.external and starts == 1)
A.stop(p, already_playing)
assert(stops == 0 and A.active(p, borrowed))
A.stop(p + 4, borrowed)
assert(stops == 0 and A.active(p, borrowed))
mem[track] = mem[track] + 1
A.stop(p, borrowed)
assert(stops == 0)
mem[count] = 0
looping = true
local loop = assert(A.play(p, "Action", "Idle Fix Hair", true, true))
A.stop(p, loop)
assert(not A.active(p, loop))
looping = false
starts, stops = 1, 0

lookup = definition
local F = { items = {}, enabled = true, tick = 0, fmt1 = tostring }
function F.data(name)
  if name == "emotes" then return { { "Idle Fix Hair", "Fix Hair", "Idles" } } end
  if name == "emote_clips" then return require("data.emote_clips") end
  return {}
end
function F.register(rows)
  for _, row in ipairs(rows) do
    F.items[row.id] = row
    row.v = row.default
  end
end
function F.category(_, rows) F.register(rows) end
require("tab_emotes")(F, package.loaded.game)
local action = F.items.actions.open().rows[1].open().rows[1]
assert(action.run(nil, p) == "Fix Hair")
assert(F.posing and starts == 2)
F.items.repeat_action.v = true
mem[count] = 0
F.tick = 181
F.update_emotes(p, true)
assert(starts == 3)
ready = false
F.update_emotes(p, true)
assert(stops == 1 and not F.posing and not F.items.repeat_action.v)
ready = true
F.update_emotes(p, true)
assert(starts == 3)
action.run(nil, p)
F.update_emotes(p, false)
assert(stops == 2 and not F.posing)
action.run(nil, p)
F.tick = F.tick + 900
F.update_emotes(p, true)
assert(stops == 3 and not F.posing)
print("Emote fallback, ownership, repeat, death, menu exit and timeout passed")

-- From the repo root: build/lua.exe tools/test_sr1_gait.lua
-- SR1 movement outside a cutscene: the game's load-by-name reads one byte of
-- the cutscene object (*0x02527D10 + 0xAFF). With no cutscene the pointer is
-- null; the load must run with a stand-in for that one call and leave the
-- pointer null again, and must leave a real cutscene's object alone.
package.path = "SRTweakMenu/?.lua"
local p, owner, actor, identity = 0x10000000, 0x11000000, 0x55, 7
local SCENE, LOADER, COUNT, FILES = 0x02527D10, 0x006D3EB0, 0x024E1864, 0x024F2F00
local BUFFERS = 0x20000000
local mem = {
  [p + 0x5E0] = owner, [p + 0x44] = actor, [owner] = identity, [p + 0x1138] = 100,
  [LOADER] = 0x00E8EC81, [COUNT] = 50,
}
local names, loads, seen, gait = {}, 0, {}, nil
local fail_load = false
package.loaded.game = { playing = function(who) return who == p end, player = function() return p end }
wml = {
  read_u32 = function(a) return mem[a] or 0 end,
  read_u16 = function(a) return (mem[a] or 0) & 0xFFFF end,
  read_u8 = function(a) return (mem[a] or 0) & 0xFF end,
  write_u8 = function(a, v) mem[a] = v end,
  write_u32 = function(a, v) mem[a] = v end,
  buffer = function(slot, text) if text then names[slot] = text end return BUFFERS + slot * 1024 end,
  log = function() end,
  sr1_gait = function(on, ...) if on == true then gait = { ... } return true end return true end,
  callx = function(a, regs, ...)
    if a == 0x006EF510 then return ({ walk = 100, run = 101, sprint = 102 })[names[14]] end
    if a == 0x00CEC2A0 then return 0xFFFFFFFF end            -- (not registered yet)
    assert(a == LOADER, string.format("unexpected call %08X", a))
    local scene = mem[SCENE] or 0
    assert(scene ~= 0, "the loader would read a null cutscene object")
    seen[#seen + 1] = { scene = scene, heap = mem[scene + 0xAFF] }
    if fail_load then error("callx 006D3EB0 crashed") end
    loads = loads + 1
    local id = 10 + loads
    mem[FILES + id * 32 + 0x1C] = 0x30000000                 -- (resident)
    return id
  end,
}
local M = require("sr1_gait")

-- Free roam: no cutscene object.
local ok, why = M.apply(package.loaded.game, p, true)
assert(ok, why)
assert(loads == 3 and #seen == 3, loads .. " loads, " .. #seen .. " seen")
for _, s in ipairs(seen) do
  assert(s.scene == BUFFERS + 11 * 1024 and s.heap == 1, "stand-in must select the general heap")
  assert(s.scene + 0xAFF >= BUFFERS + 13 * 1024 and s.scene + 0xAFF < BUFFERS + 14 * 1024, "the byte must not land on the name or out slots")
end
assert((mem[SCENE] or 0) == 0, "the pointer must be null again after the load")
assert(gait and gait[1] == p and gait[8] == 11 and gait[9] == 12 and gait[10] == 13)

-- In a cutscene: the game's own object is used and left as it is.
local real = 0x40000000
mem[SCENE], mem[real + 0xAFF] = real, 0
loads, seen = 0, {}
for id = 11, 13 do mem[FILES + id * 32 + 0x1C] = nil end
assert(M.apply(package.loaded.game, p, true))
assert(#seen == 3 and seen[1].scene == real and seen[1].heap == 0 and mem[SCENE] == real and mem[real + 0xAFF] == 0)

-- A load that fails: reported, and the pointer still put back.
mem[SCENE] = 0
fail_load, seen = true, {}
for id = 11, 16 do mem[FILES + id * 32 + 0x1C] = nil end
local ok2, why2 = M.apply(package.loaded.game, p, true)
assert(not ok2 and why2:find("Couldn't load"), tostring(why2))
assert((mem[SCENE] or 0) == 0)

-- Another build of the game: refused before anything is called.
fail_load, mem[LOADER] = false, 0x12345678
local ok3, why3 = M.apply(package.loaded.game, p, true)
assert(not ok3 and why3:find("not the one this was written for"))
print("SR1 movement loader: free roam stand-in, cutscene, failed load and other builds passed")

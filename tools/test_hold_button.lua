-- From the repo root: build/lua.exe tools/test_hold_button.lua
-- Holding Back (menu_hold_back): a hold that began on foot stays hidden from
-- the game if you get in a car before letting go; a new press doesn't.
package.path = "SRTweakMenu/?.lua"
local H = require("hold_button")
local h = H.new(0.8)
local _, _, hide = H.update(h, true, 0, true, false) assert(hide)
_, _, hide = H.update(h, true, 0.2, false, false) assert(hide == true, "held into a car: still hidden")
_, _, hide = H.update(h, true, 0.3, false, false) assert(hide == true)
local _, tap
_, tap, hide = H.update(h, false, 0.4, false, false) assert(hide == false and not tap)
_, _, hide = H.update(h, true, 0.5, false, false) assert(hide == false, "a fresh press in a car reaches the game")
print("hold button: ok")

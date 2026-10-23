-- SR Tweak Menu (Saints Row 2) - runtime part.
--
-- The host (dinput8.dll) calls wml.on_frame's functions once a frame on the
-- game's main thread. From there: the controller and keys go to the menu
-- (menu.lua, SR1's, unchanged), the rows are applied (features.lua), and the
-- menu's text goes to the host, which draws it.

local G = require("game")
local F = require("features")
local MENU = require("menu")

G.debug = wml.setting("debug", false)
F.debug = G.debug

-- The game look (Settings > Menu look) needs gameui.lua, which SR2 hasn't got
-- yet: the row stays hidden.
F.items.menu_look.hidden = function() return true end

local SELFTEST = wml.setting("selftest", false) and require("selftest")

local tick = 0
wml.on_frame(function()
  if SELFTEST then SELFTEST.frame() end
  tick = tick + 1
  local buttons, lt, rt = wml.pad()
  if buttons then MENU.controller(buttons, lt, rt) end
  MENU.input(nil, tick)
  F.set_menu_open(MENU.is_open())
  F.update(nil)
  MENU.render(tick)
end)

wml.log("SR Tweak Menu for Saints Row 2 ready: " .. tostring(wml.setting("menu_key", "F5")) .. " opens it")

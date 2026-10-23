-- SR Tweak Menu (Saints Row 2) - runtime part.
--
-- The host (dinput8.dll) calls wml.on_frame's functions once a frame on the
-- game's main thread. From there: the controller and keys go to the menu
-- (menu.lua, SR1's, unchanged), the rows are applied (features.lua), and the
-- menu's text goes to the host, which draws it.

local G = require("game")
local F = require("features")
-- SR1's layout (tabs, pages, row order) as it is, then the SR2-only rows
-- into the pages that fit them. SR1 rows SR2 hasn't got are counted, not
-- logged one by one.
do
  local log, missing = wml.log, 0
  wml.log = function(msg, ...)
    if tostring(msg):find("^layout: no row ") then missing = missing + 1 return end
    if tostring(msg):find("wasn't placed") then return end   -- (layout_sr2.lua places them)
    return log(msg, ...)
  end
  local ok, err = pcall(function() require("layout").apply(F) require("layout_sr2").apply(F) end)
  wml.log = log
  if not ok then wml.log("layout failed: " .. tostring(err)) end
  if missing > 0 then wml.log(string.format("layout: %d SR1 rows aren't on Saints Row 2 yet", missing)) end
end
local MENU = require("menu")

G.debug = wml.setting("debug", false)
F.debug = G.debug

-- The game look (Settings > Menu look) needs gameui.lua, which SR2 hasn't got
-- yet: the row stays hidden.
F.items.menu_look.hidden = function() return true end

local SELFTEST = wml.setting("selftest", false) and require("selftest")
local PROBE = wml.setting("dev_probe", false) and require("probe")
local PROBE_ENV = { G = G, F = F, MENU = MENU }

local tick = 0
wml.on_frame(function()
  if SELFTEST then SELFTEST.frame() end
  if PROBE then PROBE.frame(PROBE_ENV) end
  tick = tick + 1
  local buttons, lt, rt = wml.pad()
  F.pad_prev, F.pad = F.pad or 0, buttons or 0
  if buttons then MENU.controller(buttons, lt, rt) end
  MENU.input(nil, tick)
  F.set_menu_open(MENU.is_open())
  F.update(nil)
  MENU.render(tick)
end)

wml.log("SR Tweak Menu for Saints Row 2 ready: " .. tostring(wml.setting("menu_key", "F5")) .. " opens it")

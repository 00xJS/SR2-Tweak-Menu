-- SR Tweak Menu (Saints Row 2) - the game look's interface calls.
--
-- SR1's gameui.lua draws the menu with the game's own fonts, pictures and
-- sounds (itsMJQ's look). Not on SR2 yet: never ready, so menu.lua keeps to
-- the plain text look, drawn by the host.

return {
  ok = false,
  ready = function() return false end,
  sound = function() end,
  width = function() return 0 end,
}

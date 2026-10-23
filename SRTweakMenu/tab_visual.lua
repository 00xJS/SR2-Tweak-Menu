-- SR Tweak Menu (Saints Row 2) - the Visual tab.
--
-- Hide HUD is the interface's own hud_hide (the call the stores make);
-- the camera rows come from engine.lua. SR1's filters, saturation and
-- render modes were SR1 shader tricks with no SR2 counterpart yet; Juiced
-- Patch's VanillaFX+ and X360 gamma do the colour work on SR2.

return function(F, G)
  local ENGINE = require("engine")

  F.category("Visual", {
    { id = "hide_hud", label = "Hide HUD", kind = "toggle", needs = "player", every = 120,
      help = "No HUD: just the game (the menu still shows).",
      update = function() G.vint("hud_hide(true)") end,
      off = function() G.vint("hud_hide(false)") end },
    ENGINE.free_cam_row(),
    ENGINE.fov_row(),
    ENGINE.no_fog_row(),

    { id = "giant", label = "Giant player", kind = "toggle", cheat = "Giant Player", help = "You're huge (the phone's cheat)." },
    { id = "tiny", label = "Tiny player", kind = "toggle", cheat = "Tiny Player", help = "You're tiny (the phone's cheat)." },
    { id = "pratfall", label = "Pratfall", kind = "toggle", cheat = "Pratfall", help = "You trip over everything (the phone's cheat)." },
    { id = "heaven", label = "Elevator to heaven", kind = "toggle", cheat = "Elevator to Heaven",
      help = "Dead people float up to heaven (the phone's cheat)." },
  })
end

-- SR Tweak Menu (Saints Row 2) - the Visual tab.
--
-- Hide HUD is the interface's own hud_hide (the call the stores make);
-- the camera rows come from engine.lua. SR1's filters, saturation and
-- render modes were SR1 shader tricks with no SR2 counterpart yet; Juiced
-- Patch's VanillaFX+ and X360 gamma do the colour work on SR2.

return function(F, G)
  local ENGINE = require("engine")

  F.category("Visual", {
    { id = "hide_hud", label = "Hide HUD", kind = "toggle", needs = "player",
      help = "Hide the game HUD and keep the tweak menu visible." },
    -- SR1's free camera (freecam.lua): fly it with both sticks and the
    -- triggers, or play from a fixed or tracking shot.
    { id = "camera_shortcut", label = "Quick Camera shortcut", kind = "toggle", needs = "none", v = true,
      help = "Press L3 + R3 (both stick clicks) or F7 to open the Free Camera menu." },
    { id = "camera_hide_ui", label = "Quick Camera hides HUD", kind = "toggle", needs = "none", v = true,
      help = "The shortcut hides the HUD while the camera flies; it comes back when the camera stops." },
    { id = "free_cam", label = "Free Camera", kind = "toggle", needs = "player", nosave = true,
      help = "Move: left stick / WASD. Look: right stick / IJKL. Up / down: right / left trigger (E / Q). Zoom: RB / LB (X / Z). Faster: L3 or Shift. A / Enter plays from this shot.",
      change = function(ctx, p, v, it)
        local FC = require("freecam")
        if it.v then
          if not FC.enter() then it.v = false return "Free camera needs normal play (no cutscene)" end
          FC.set_mode(F.items.cam_mode and F.items.cam_mode.v or 1)
          if FC.mode > 1 then return "Camera held here: close the menu to play" end
          return "Free camera on: close the menu to fly"
        end
        FC.exit()
      end,
      off = function() require("freecam").exit() end },
    { id = "cam_mode", label = "Free Camera Mode", kind = "choice", needs = "none", nosave = true,
      options = require("freecam").MODES,
      help = "Fly: move the camera freely. Fixed shot: the camera holds still while you play. Tracking shot: it holds still and follows you.",
      change = function(ctx, p, v, it)
        local FC = require("freecam")
        FC.set_mode(it.v)
        if FC.on then return it.v == 1 and "Flying the camera" or "Playing from the shot" end
        return "Used when Free Camera is on"
      end },
    ENGINE.no_fog_row(),

    { id = "giant", label = "Giant player", kind = "toggle", cheat = "Giant Player", help = "You're huge (the phone's cheat)." },
    { id = "tiny", label = "Tiny player", kind = "toggle", cheat = "Tiny Player", help = "You're tiny (the phone's cheat)." },
    { id = "pratfall", label = "Pratfall", kind = "toggle", cheat = "Pratfall", help = "You trip over everything (the phone's cheat)." },
    { id = "heaven", label = "Elevator to heaven", kind = "toggle", cheat = "Elevator to Heaven",
      help = "Dead people float up to heaven (the phone's cheat)." },
  })
end

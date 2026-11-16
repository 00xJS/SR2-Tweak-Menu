-- SR Tweak Menu (Saints Row 2) - the Settings tab.
--
-- The master switch, saving the menu's setup, and unlocks the game's own
-- scripts can do. SR1's start-up rows (skip intro, load last save, pause
-- cutscenes, no tutorials) are Juiced Patch options on SR2.

return function(F, G)
  F.category("Settings", {
    { id = "master", label = "All tweaks", kind = "toggle", needs = "none", v = true, help = "Turns every tweak on or off." },
    { id = "status", label = "Show active tweaks", kind = "action", needs = "none", help = "",
      run = function() return F.status_line() end },
    { id = "save_tweaks", label = "Save tweaks for next time", kind = "action", needs = "none",
      help = "The menu starts the way it is now next time (in saved_tweaks.txt).",
      run = function() return F.save_tweaks() end },
    { id = "forget_tweaks", label = "Forget saved tweaks", kind = "action", needs = "none",
      help = "The menu starts with every tweak off again.",
      run = function() return F.forget_tweaks() end },

    require("healthcheck").row(F),
    require("backup").export_row(F),
    require("backup").import_row(F),

    { id = "unlock_cribs", label = "Unlock buying cribs", kind = "action",
      help = "Lets you buy cribs (the game's own crib unlock).",
      run = function() G.lua("crib_purchasing_unlock()") return "Cribs can be bought" end },
  })
end

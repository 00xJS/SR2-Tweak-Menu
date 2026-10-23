-- SR Tweak Menu (Saints Row 2) - the Models and Customize tabs.
--
-- Models: play as any character preset, live, with the game's own
-- character change (engine.lua), and back to your own character.
-- Customize: SR2's own character creator (the plastic surgeon's), opened
-- where you stand.

return function(F, G)
  local ENGINE = require("engine")

  F.category("Models", {
    ENGINE.play_as_row(),
    { id = "restore_player_model", label = "Restore your character", kind = "action",
      help = "Back to your own character.",
      run = function() ENGINE.restore_player() return "You're you again" end },
  })

  F.category("Customize", {
    { id = "open_creator", label = "Character creator", kind = "action",
      help = "Opens SR2's character creator (the plastic surgeon's) here, free.",
      run = function() G.lua("player_creation_open_do()") return "Character creator" end },
  })
end

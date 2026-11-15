-- SR Tweak Menu (Saints Row 2) - the World tab.
--
-- Weather comes from the phone's weather cheats (the game's own named
-- conditions); time and traffic from the mission-script calls
-- (set_time_of_day, spawning_pedestrians...); the crowd effects SR1 built
-- by hand (everybody dance, ragdoll all) from SR2's own world cheats.

return function(F, G)
  local ENGINE = require("engine")

  -- The weather stages of weather.xtbl (set_weather(n, true), as the
  -- missions set them; -1 gives the game's own back), and the phone's Wrath of God.
  local SHOWN = { "Game's own", "Clear skies", "Partly cloudy", "Light rain", "Medium rain", "Heavy rain", "Overcast", "Thunderstorm", "Wrath of God" }
  -- SR1's Sky: one part of the day's light whatever the time (the clock set and held).
  local SKIES = { { "Default", nil }, { "Dawn", 6 }, { "Morning", 9 }, { "Midday", 13 }, { "Evening", 18 }, { "Dusk", 20 }, { "Night", 0 } }

  -- The world cheats that stay on until switched off.
  local function world_cheat(id, cheat, label, help)
    return { id = id, label = label, kind = "toggle", cheat = cheat, help = help .. " (the phone's cheat)." }
  end

  F.category("World", {
    { id = "weather", label = "Weather", kind = "choice", options = SHOWN, v = 1, nosave = true,
      help = "Sets the weather. Game's own lets it change by itself again.",
      change = function(ctx, p, v, it)
        F.cheat("Wrath of God", false)
        if it.v == 1 then G.lua("set_weather(-1, false)") return "The game's own weather" end
        if it.v == #SHOWN then return F.cheat("Wrath of God", true) end
        G.lua("set_weather(%s, true)", it.v - 2)
        return "Weather: " .. SHOWN[it.v]
      end },
    { id = "sky_type", label = "Sky", kind = "choice", options = (function() local t = {} for i, s in ipairs(SKIES) do t[i] = s[1] end return t end)(),
      v = 1, nosave = true,
      help = "The sky and lighting of one part of the day, whatever the time. Default follows the clock.",
      change = function(ctx, p, v, it)
        local h = SKIES[it.v][2]
        if not h then G.lua("set_time_of_day_scale(1.0)") return "The clock runs again" end
        G.lua("set_time_of_day(%s, 0) set_time_of_day_scale(0.0)", h)
        return "Sky: " .. SKIES[it.v][1]
      end,
      off = function() G.lua("set_time_of_day_scale(1.0)") end },
    { id = "hour", label = "Time of day", kind = "value", default = -1, min = -1, max = 23, step = 1, oneshot = true, nosave = true,
      fmt = function(v) return v < 0 and "game's" or string.format("%02d:00", v) end,
      help = "Sets the clock to this hour.",
      change = function(ctx, p, v, it) if it.v >= 0 then G.lua("set_time_of_day(%s, 0)", math.floor(it.v)) end end },
    { id = "freeze_clock", label = "Freeze time", kind = "toggle",
      help = "The clock stops.",
      change = function(ctx, p, v, it) G.lua("set_time_of_day_scale(%s)", it.v and 0.0 or 1.0) end,
      off = function() G.lua("set_time_of_day_scale(1.0)") end },

    { id = "clear", label = "Clear streets", kind = "toggle",
      help = "No people or traffic spawn.",
      change = function(ctx, p, v, it) G.lua("spawning_pedestrians(%s) spawning_vehicles(%s)", not it.v, not it.v) end,
      off = function() G.lua("spawning_pedestrians(true) spawning_vehicles(true)") end },
    { id = "ped_density", label = "Crowd density", kind = "value", default = 1, min = 0, max = 3, step = 0.25, fmt = F.fmtx,
      help = "How many people walk the streets.",
      change = function(ctx, p, v, it) G.lua("set_ped_density(%s)", it.v) end,
      off = function() G.lua("set_ped_density(1.0)") end },
    { id = "traffic_density", label = "Traffic density", kind = "value", default = 1, min = 0, max = 3, step = 0.25, fmt = F.fmtx,
      help = "How many cars drive the streets.",
      change = function(ctx, p, v, it) G.lua("set_traffic_density(%s)", it.v) end,
      off = function() G.lua("set_traffic_density(1.0)") end },
    { id = "restore_traffic", label = "Restore streets", kind = "action",
      help = "People and traffic spawn again (Clear streets off).",
      run = function() F.items.clear.v = false G.lua("spawning_pedestrians(true) spawning_vehicles(true)") return "Streets restored" end },
    ENGINE.spawn_person_row(),
    ENGINE.crowd_small_row(),
    ENGINE.crowd_big_row(),
    ENGINE.remove_people_row(),
    ENGINE.drop_row(),
    ENGINE.everybody_row(),

    world_cheat("ped_war", "Ped War", "Everybody fights", "Pedestrians fight each other"),
    world_cheat("drunk", "Drunk", "Drunk pedestrians", "People stagger about drunk"),
    world_cheat("evil_cars", "Evil Cars", "Evil cars", "Traffic tries to run you down"),
    world_cheat("raining_peds", "Raining Peds", "Raining pedestrians", "People fall from the sky"),
    world_cheat("low_gravity", "Low Gravity", "Low gravity", "Everything floats"),
    world_cheat("super_saints", "Super Saints", "Super Saints", "Your homies are much tougher"),
    world_cheat("bushwick", "Bushwick Bill", "Bushwick Bill", "Bushwick Bill's cheat"),
  })
end

-- SR Tweak Menu (Saints Row 2) - the Vehicles tab.
--
-- Everything works on the vehicle you're in, by the name the game's
-- scripts know it by (get_char_vehicle_name), with the calls its missions
-- use on their own cars: vehicle_repair, vehicle_infinite_mass,
-- vehicle_set_bulletproof_glass... SR1's driving-camera rows are Juiced
-- Patch's own options on SR2 (juiced.ini [Gameplay]).

return function(F, G)
  local ENGINE = require("engine")

  -- A toggle that puts a vehicle property on whatever you drive.
  local function car_toggle(id, label, help, on_code, off_code)
    return { id = id, label = label, kind = "toggle", needs = "vehicle", every = 60, help = help,
      update = function() G.vehicle_lua(on_code) end,
      off = function() if off_code then G.vehicle_lua(off_code) end end }
  end

  F.category("Vehicles", {
    car_toggle("bulletproof", "Bulletproof glass", "Bullets don't go through your windows.",
      "vehicle_set_bulletproof_glass(v, true)", "vehicle_set_bulletproof_glass(v, false)"),
    car_toggle("never_flat", "Bulletproof tires", "Your tires never go flat.",
      "vehicle_never_flatten_tires(v, true)", "vehicle_never_flatten_tires(v, false)"),
    car_toggle("no_fling", "No explosion fling", "Explosions don't throw your vehicle.",
      "vehicle_prevent_explosion_fling(v, true)", "vehicle_prevent_explosion_fling(v, false)"),
    { id = "sirens", label = "Sirens", kind = "toggle", needs = "vehicle",
      help = "Siren and lights on a police car, ambulance or fire truck.",
      change = function(ctx, p, v, it) G.vehicle_lua("vehicle_set_sirens(v, %s) vehicle_set_sirenlights(v, %s)", it.v, it.v) end,
      off = function() G.vehicle_lua("vehicle_set_sirens(v, false) vehicle_set_sirenlights(v, false)") end },
    { id = "boom", label = "Destroy vehicle", kind = "action", needs = "vehicle", help = "Blows up the vehicle you're in.",
      run = function() G.vehicle_lua("vehicle_detonate(v)") return "Boom" end },

    ENGINE.spawn_vehicle_row(),
    ENGINE.remove_vehicles_row(),
    { id = "vehicle_cheats", label = "Vehicle cheat", kind = "list", items = ENGINE.cheat_vehicles(), nosave = true,
      help = "The phone's vehicle cheats: Enter drops that vehicle next to you.",
      run = function(ctx, p, v, it) return F.cheat_once(it.items[it.v][1]) or ("Delivered: " .. it.items[it.v][2]) end },
    { id = "infinite_mass", label = "Vehicle smash", kind = "toggle", cheat = "InfiniteMass", needs = "player",
      help = "Every vehicle you drive is unstoppable (the phone's cheat)." },
  })
end

-- SR Tweak Menu (Saints Row 2) - the Teleport tab.
--
-- Places are the navpoints the game's own scripts warp the player to
-- (data/places.lua), visited with the game's teleport(); the waypoint
-- rows use the map waypoint and the console teleport (game.lua).

return function(F, G)
  local PLACES = F.data("places")

  -- Each category opens a vertical list of its destinations.
  local groups, order = {}, {}
  for _, pl in ipairs(PLACES) do
    local g = pl[3] or "Places"
    if not groups[g] then groups[g] = {}; order[#order + 1] = g end
    table.insert(groups[g], pl)
  end

  local rows = {}
  for i, g in ipairs(order) do
    local destinations = {}
    for _, pl in ipairs(groups[g]) do
      destinations[#destinations + 1] = { label = pl[2], kind = "action",
        help = "Accept to teleport to " .. pl[2] .. ".",
        run = function()
          if pl.x then G.teleport(pl.x, pl.y, pl.z) else G.lua('teleport("#PLAYER#", %s)', pl[1]) end
          return "Teleported to " .. pl[2]
        end }
    end
    rows[#rows + 1] = F.page("places_" .. i, g, "Choose a destination.", destinations)
  end
  if #rows == 0 then
    rows[1] = { id = "places_none", label = "Places", kind = "action", needs = "none", help = "data/places.lua is missing.",
      run = function() return "No places list" end }
  end

  local last_wp
  rows[#rows + 1] = { id = "waypoint_go", label = "Teleport to waypoint", kind = "action",
    help = "Takes you (and your car) to the waypoint set on the pause map.",
    run = function()
      local x, y, z = G.waypoint()
      if not x then return "Set a waypoint on the map first" end
      G.teleport(x, y, z)
      return "Teleported to the waypoint"
    end }
  rows[#rows + 1] = { id = "waypoint_auto", label = "Auto-teleport to waypoint", kind = "toggle", every = 15,
    help = "Whenever you set a waypoint on the map, you're taken there.",
    update = function()
      local x, y, z = G.waypoint()
      local key = x and string.format("%.1f,%.1f,%.1f", x, y, z)
      if key and key ~= last_wp and last_wp ~= nil then G.teleport(x, y, z) end
      last_wp = key or false
    end,
    off = function() last_wp = nil end }

  F.category("Teleport", rows)
end

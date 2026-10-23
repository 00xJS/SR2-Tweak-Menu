-- SR Tweak Menu (Saints Row 2) - where the SR2-only rows go, after SR1's
-- layout.lua has placed every row it knows (same ids, same tabs and pages).
-- The rows SR2 has and SR1 hasn't join the page or tab that fits them;
-- SR1 pages SR2 has no rows for (yet) are left out.

local L = {}

-- Page id or tab name -> SR2 rows to add there, in order. `after`: put them
-- after that row instead of at the end.
local PLACE = {
  { page = "player_notoriety", after = "wanted_police", rows = { "wanted_brotherhood", "wanted_ronin", "wanted_samedi", "wanted_ultor" } },
  { page = "settings_unlocks", rows = { "unlock_cribs" } },
  { page = "weapons_special", rows = { "super_explosions", "milk_bones" } },
  { page = "vehicles_toughness", rows = { "infinite_mass" } },
  { page = "vehicles_look", rows = { "sirens" } },
  { page = "vehicles_handling", rows = { "acceleration", "higher_max_speed" } },
  { tab = "World", after = "low_gravity", rows = { "gravity", "game_speed" } },
  { page = "settings_unlocks", rows = { "reward_fireproof" } },
  { tab = "Vehicles", after = "spawn_vehicle", rows = { "vehicle_cheats" } },
  { page = "world_people", rows = { "ped_density", "traffic_density", "ped_war", "drunk", "evil_cars", "raining_peds", "super_saints", "bushwick" } },
  { tab = "World", after = "freeze_clock", rows = { "low_gravity" } },
  { page = "player_movement", after = "crouch_moving", rows = { "sprint_on_fire" } },
  { page = "player_health", after = "no_ragdoll", rows = { "disarm_ragdoll" } },
  { tab = "Weapons", after = "car_reload", rows = { "reload_sprint", "switch_any" } },
  { page = "visual_camera", rows = { "no_climb_cam", "no_sprint_shake" } },
  { tab = "Visual", after = "map_arrow", rows = { "no_black_bars", "no_screen_blur", "no_vignette" } },
  { new_page = "style_movement", tab = "Customize", label = "Movement", help = "How you walk, run and stand.",
    rows = { "walk_variant", "run_variant", "stand_variant" } },
}

local function tab_of(F, name)
  for _, cat in ipairs(F.categories) do if cat.name == name then return cat end end
end
-- Takes a row out of wherever layout.lua left it (a tab's end).
local function lift(F, it)
  for _, cat in ipairs(F.categories) do
    for i = #cat.items, 1, -1 do if cat.items[i] == it then table.remove(cat.items, i) end end
  end
end
local function insert(list, rows, after)
  local at = #list + 1
  if after then for i, r in ipairs(list) do if r.id == after then at = i + 1 end end end
  for k, r in ipairs(rows) do table.insert(list, at + k - 1, r) end
end

function L.apply(F)
  for _, spec in ipairs(PLACE) do
    local rows = {}
    for _, id in ipairs(spec.rows) do
      local it = F.items[id]
      if it then lift(F, it); rows[#rows + 1] = it end
    end
    if #rows > 0 then
      if spec.new_page then
        local cat = tab_of(F, spec.tab)
        if cat then
          local pg = F.page(spec.new_page, spec.label, spec.help, rows)
          F.items[spec.new_page] = pg
          cat.items[#cat.items + 1] = pg
        end
      elseif spec.page then
        local pg = F.items[spec.page]
        if pg and pg.open then insert(pg.open().rows, rows, spec.after) end
      else
        local cat = tab_of(F, spec.tab)
        if cat then insert(cat.items, rows, spec.after) end
      end
    end
  end
  -- SR1 pages with nothing on them in SR2.
  for _, cat in ipairs(F.categories) do
    for i = #cat.items, 1, -1 do
      local it = cat.items[i]
      if it.kind == "page" and it.open then
        local ok, pg = pcall(it.open)
        if ok and type(pg) == "table" and pg.rows and #pg.rows == 0 then table.remove(cat.items, i) end
      end
    end
  end
end

return L

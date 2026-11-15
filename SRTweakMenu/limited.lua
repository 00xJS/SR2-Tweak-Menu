-- SR Tweak Menu (Saints Row 2) - Limited Weapons.
--
-- SR1's Limited Weapons & Cash Storage: a pistol, an SMG, one big gun and
-- one melee weapon, with weight that shortens your sprint; trunks and crib
-- caches hold the rest, a safe holds your cash.
--
-- SR2 already keeps one weapon per slot, so the limit here is the big gun:
-- of the shotgun, rifle and launcher slots only one stays filled. The gun
-- you got last is the one you keep. Everything is done with calls the
-- game's missions make:
--   inv_item_in_slot(character, slot)      -> the weapon's name, or "none"
--   inv_item_remove_in_slot(slot, character)
--   inv_item_get_equipped_item(character)
--   inv_item_add_do(name, count, character, equip_now)
--   sprint_set_local_use_override(ms), sprint_reset_local_overrides()
--
-- There are no trunks, caches or prompts: a big gun that is taken goes to
-- a stash the menu keeps (names only, until the game is closed), and Swap
-- big gun hands the oldest one back. Its ammo is not kept. The cash safe
-- is left out: the scripts can add and remove cash but not read it.

local L = {}

local SLOTS = { "melee", "pistol", "smg", "shotgun", "rifle", "launcher", "thrown" }
-- Which big gun stays when nothing says which is newer.
local BIG = { "rifle", "shotgun", "launcher" }
-- Seconds each filled slot takes off the game's 10 seconds of sprint.
local WEIGHT = { melee = 0.5, pistol = 0.5, smg = 1, shotgun = 2, rifle = 2, launcher = 3, thrown = 0.5 }
local SPRINT_MS, SPRINT_MIN_MS = 10000, 3000

-- One tweak_out per slot, in SLOTS order, then the weapon in your hand.
local READ = 'local function s(n) local w = inv_item_in_slot(LOCAL_PLAYER, n) '
  .. 'if w == nil or w == "" then w = "none" end tweak_out(w) end '
  .. 's("melee") s("pistol") s("smg") s("shotgun") s("rifle") s("launcher") s("thrown") '
  .. 'local e = inv_item_get_equipped_item(LOCAL_PLAYER) if e == nil or e == "" then e = "none" end tweak_out(e)'

function L.rows(F, G)
  local stash = {}   -- big guns taken away, oldest first
  local last         -- slot -> weapon at the last look, to tell which is new
  local sprint_ms    -- the sprint length set, nil while it is the game's own

  -- What you carry: slot -> weapon name (nil when empty), and what is in
  -- your hand. Nothing when the game didn't answer in full.
  local function carried()
    local res = table.pack(G.lua(READ))
    if not res[1] or res.n < #SLOTS + 2 then return nil end
    local cur = {}
    for i, s in ipairs(SLOTS) do
      local w = res[i + 1]
      if type(w) == "string" and w ~= "none" then cur[s] = w end
    end
    return cur, res[#SLOTS + 2]
  end

  local function stashed(name)
    for _, w in ipairs(stash) do if w == name then return end end
    stash[#stash + 1] = name
  end

  -- The big-gun slot to keep: one filled since the last look (a pickup or
  -- a mission's gun), else the one in your hand, else by BIG's order.
  local function keeper(cur, equipped)
    if last then
      for _, s in ipairs(BIG) do if cur[s] and cur[s] ~= last[s] then return s end end
    end
    for _, s in ipairs(BIG) do if cur[s] and cur[s] == equipped then return s end end
    for _, s in ipairs(BIG) do if cur[s] then return s end end
  end

  local function weigh(cur)
    local w = 0
    for s in pairs(cur) do w = w + (WEIGHT[s] or 0) end
    return math.max(SPRINT_MIN_MS, math.floor(SPRINT_MS - w * 1000))
  end

  local function update(ctx, p)
    -- Cutscenes and missions' scenes swap weapons about: leave them be.
    if G.in_cutscene() then return end
    local cur, equipped = carried()
    if not cur then return end
    local keep = keeper(cur, equipped)
    for _, s in ipairs(BIG) do
      if cur[s] and s ~= keep then
        G.lua("inv_item_remove_in_slot(%s, LOCAL_PLAYER)", s)
        stashed(cur[s])
        cur[s] = nil
      end
    end
    last = cur
    -- Set again on every look: a mission (or a load) can reset it.
    sprint_ms = weigh(cur)
    G.lua("sprint_set_local_use_override(%s)", sprint_ms)
  end

  return {
    { id = "loadout", label = "Limited Weapons", kind = "toggle", needs = "player", every = 30,
      help = "One big gun: of shotgun, rifle and launcher you keep the one you got last, the others go to the menu's stash (Swap big gun). What you carry weighs on your sprint. The stash keeps no ammo and is lost when the game closes.",
      update = update,
      off = function()
        last = nil
        if sprint_ms then G.lua("sprint_reset_local_overrides()") end
        sprint_ms = nil
      end },
    { id = "loadout_swap", label = "Swap big gun", kind = "action", needs = "player", nosave = true,
      help = "Puts the big gun you carry in the stash and hands you the one stashed longest. It comes back with the ammo of a new one.",
      run = function()
        if #stash == 0 then return "No big gun in the stash" end
        local cur = carried()
        if not cur then return "Can't reach your weapons right now" end
        local name = table.remove(stash, 1)
        for _, s in ipairs(BIG) do
          if cur[s] then
            G.lua("inv_item_remove_in_slot(%s, LOCAL_PLAYER)", s)
            stashed(cur[s])
            cur[s] = nil
          end
        end
        G.lua("inv_item_add_do(%s, 1, LOCAL_PLAYER, true)", name)
        -- The next look takes what it finds as it is, so the gun just
        -- given is not read as a new pickup.
        last = nil
        return "Took the " .. name .. " (" .. #stash .. " in the stash)"
      end },
  }
end

return L

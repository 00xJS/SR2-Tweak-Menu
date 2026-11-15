-- Use SR2's party system for follow, combat, vehicle boarding and dismissal.
-- Never copy SR1's follower offsets or force past SR2's three physical slots.
local G = require("game")
local B = {}
local owned, joining = {}, {}
local session
local epoch = 0
local function handle(o) return wml.read_u32(o + 0x44) end
local function object(h)
  if not h or h == 0 or h == 0xFFFFFFFF then return end
  local o = wml.read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if o ~= 0 and handle(o) == h and wml.read_u32(o + 0x4C) == 1 then return o end
end
function B.alive(o)
  return o ~= 0 and object(handle(o)) == o and (wml.call(0x00985630, o) & 0xFF) == 0
end
local function sync(p)
  local key = p ~= 0 and { p = p, handle = handle(p) } or nil
  if not key or not session or key.p ~= session.p or key.handle ~= session.handle then
    -- Loading/unloading or a replacement player abandons old ownership.
    -- 0x033D630C is a name sentinel, not a level-generation counter.
    epoch = epoch + 1
    if key then key.epoch = epoch end
    owned, joining, session = {}, {}, key
  end
  return key
end
local function valid(entry)
  local o = session and entry.epoch == session.epoch and object(entry.handle)
  if o and wml.read_u32(o + 0xD4) == entry.model then return o end
end
local function following(p, o)
  return wml.read_u32(o + 0x2A4) == handle(p)
end
local function follower(o)
  local leader = wml.read_u32(o + 0x2A4)
  return leader ~= 0 and leader ~= 0xFFFFFFFF
end
local function count(p) return wml.read_u32(p + 0xC3C) end
local function limit(p)
  return math.max(0, math.min(3, wml.callx(0x0098E640, { eax = p })))
end
function B.room(p)
  sync(p)
  if G.player() ~= p or not G.playing(p) or not B.alive(p) then return nil, "Can't recruit right now" end
  local max = limit(p)
  if max == 0 then return nil, "Recruiting is locked; enable More homies or unlock followers" end
  local pending = 0
  for _, entry in pairs(joining) do
    local o = valid(entry)
    if o and not following(p, o) then pending = pending + 1 end
  end
  local free = max - count(p) - pending
  if free <= 0 then return nil, "Your party is full (" .. max .. " followers)" end
  return free
end
local function dismiss_one(p, o)
  if following(p,o) then wml.call(0x0098F1B0, p, o) end
end
local function destroy(entry, p)
  local o = valid(entry)
  if not o or o == p then return false end
  if follower(o) and not following(p,o) then return false end
  dismiss_one(p,o)
  -- Party removal can destroy or replace a character; resolve its full handle again.
  o = valid(entry)
  if o then wml.callx(0x00960240, { ecx = o }, 0) return true end
  return false
end
local function arm(o)
  local weapon = wml.call(0x00B716E0, wml.buffer(2, "glock"))
  if weapon == 0 then return false end
  -- Same native calls and arguments as inv_item_add_do, inv_item_add_ammo
  -- and npc_unholster_best_weapon, operating on this human's own inventory.
  wml.callx(0x00559890, { ecx = weapon }, o + 0x10C4, 1, 0, 1)
  wml.callx(0x00A34140, { edx = wml.read_u32(weapon + 0x3C) }, o, 999)
  wml.call(0x0055A930, o + 0x10C4, 0xB, 1, 0)
  return true
end
local function join(p,o)
  if not B.alive(o) or follower(o) or count(p) >= limit(p) or count(p) >= 3 then return false end
  local result = wml.call(0x0098EC10, p, o, 0, 1)
  return (result & 0xFF) ~= 0 and following(p,o)
end
function B.track(p,o,bodyguard,model)
  sync(p)
  local h = handle(o)
  if o == p or object(h) ~= o then return nil, "The spawned character is not ready" end
  local entry = { handle = h, model = model, epoch = session.epoch, elapsed = 0, retry = 0 }
  if wml.read_u32(o + 0xD4) ~= model then return nil, "The spawned model changed" end
  owned[h] = entry
  if not bodyguard then return true end
  wml.write_u8(o + 0x111C, wml.read_u8(p + 0x111C))
  if join(p,o) then
    arm(o)
    return true, "Bodyguard joined your party"
  end
  joining[h] = entry
  return true, "Bodyguard spawned; waiting to join your party"
end
function B.update(p)
  sync(p)
  if p == 0 or not G.playing(p) then return end
  local step = wml.read_f32(0x00E84384)
  if step ~= step or step <= 0 or step > 0.25 then step = 1 / 60 end
  for h, entry in pairs(owned) do
    if not valid(entry) then owned[h], joining[h] = nil, nil end
  end
  for h, entry in pairs(joining) do
    local o = valid(entry)
    if not o then joining[h], owned[h] = nil, nil
    elseif not B.alive(p) or not B.alive(o) then
      destroy(entry,p) joining[h], owned[h] = nil, nil
    elseif following(p,o) then arm(o) joining[h] = nil
    elseif follower(o) then joining[h] = nil
    else
      entry.elapsed, entry.retry = entry.elapsed + step, entry.retry - step
      if G.playing(p) and entry.retry <= 0 then
        entry.retry = 0.1
        if join(p,o) then arm(o) joining[h] = nil end
      end
      if joining[h] and entry.elapsed >= 3 then
        destroy(entry,p) joining[h], owned[h] = nil, nil
        wml.log("bodyguard: couldn't join; removed the unjoined spawned character")
      end
    end
  end
end
function B.recruit(p,candidates)
  local room, why = B.room(p)
  if not room then return why end
  local team = wml.read_u8(p + 0x111C)
  if team == 0xFF then return "You're on no side" end
  local best, best_d
  for _,o in ipairs(candidates) do
    local control = wml.read_u8(o + 0x3CC)
    if o ~= p and control ~= 1 and control ~= 2 and B.alive(o) and not follower(o) and not joining[handle(o)]
      and wml.read_u8(o + 0x111C) == team then
      local dx = wml.read_f32(o+0x14)-wml.read_f32(p+0x14)
      local dy = wml.read_f32(o+0x18)-wml.read_f32(p+0x18)
      local dz = wml.read_f32(o+0x1C)-wml.read_f32(p+0x1C)
      local d = dx*dx+dy*dy+dz*dz
      if d < 400 and (not best_d or d < best_d) then best,best_d = o,d end
    end
  end
  if not best then return "No living, unassigned gang member within 20 metres" end
  if not join(p,best) then return "They couldn't join your party" end
  return string.format("Recruited (%.0f m away)", math.sqrt(best_d))
end
function B.dismiss(p)
  sync(p)
  if p == 0 or G.player() ~= p then return "Load a game first" end
  -- A dismissed party must not have pending menu guards silently rejoin it.
  for h, entry in pairs(joining) do destroy(entry,p) owned[h], joining[h] = nil,nil end
  local before = count(p)
  wml.callx(0x0098F460, { edi = p }, 0)
  return count(p) < before and "Homies dismissed" or (before == 0 and "No homies are following you" or "Couldn't dismiss the party right now")
end
function B.remove(p)
  sync(p)
  local n = 0
  for h,entry in pairs(owned) do
    if destroy(entry,p) then n = n + 1 end
    owned[h], joining[h] = nil,nil
  end
  return "Removed " .. n
end
function B.remove_one(p,h)
  sync(p)
  local entry = owned[h]
  if not entry then return false end
  local removed = destroy(entry,p)
  owned[h], joining[h] = nil,nil
  return removed
end
return B

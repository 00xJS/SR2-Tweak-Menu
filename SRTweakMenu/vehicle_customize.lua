-- Fit the current car's own components directly, using the garage's native
-- component installer without entering its interface or moving the vehicle.
local G = require("game")
local V = {}
local read = wml.read_u32
local FIT, REMOVE, REFRESH = 0x00AC7AE0, 0x00AC7DF0, 0x00AC9470
local CURRENT, COLOUR, SET_COLOUR = 0x00AC8080, 0x00AC80B0, 0x00AC7C60

local function label(pointer, fallback)
  if pointer == 0 then return fallback end
  local chars, index = {}, 0
  while index < 160 do
    local code = wml.read_u16(pointer + index * 2)
    if code == 0 then break end
    index = index + 1
    if code >= 0xD800 and code <= 0xDBFF then
      local low = wml.read_u16(pointer + index * 2)
      if low >= 0xDC00 and low <= 0xDFFF then
        code = 0x10000 + (code - 0xD800) * 0x400 + low - 0xDC00
        index = index + 1
      else
        code = 0xFFFD
      end
    elseif code >= 0xDC00 and code <= 0xDFFF then
      code = 0xFFFD
    end
    chars[#chars + 1] = utf8.char(code)
  end
  return #chars > 0 and table.concat(chars) or fallback
end

function V.valid(session)
  if not session or G.player() ~= session.p or G.in_cutscene() then return false end
  local p, car = session.p, session.vehicle
  return read(p + 0x44) == session.actor and G.vehicle_handle(p) == session.handle
    and read(0x02149C64 + (session.handle & 0xFFF) * 16) == car
    and read(car + 0x44) == session.handle and read(car + 0x4C) == 5
    and read(car + 0x84D4) == session.instance and read(car + 0x84E4) == session.info
end

-- The native script vehicle_stop_do reaches this routine with the full
-- vehicle handle and immediate=true. It clears linear/angular velocity,
-- throttle and applies the native brake; no position or garage UI changes.
function V.hold(session)
  if not V.valid(session) then return false end
  if read(0x00AB0D60) ~= 0x83EC8B55 then return false end
  wml.call(0x00AB0D60, session.handle, 1)
  return true
end

local function current(session, slot)
  return wml.callx(CURRENT, { eax = session.instance, edx = slot })
end

local function snapshot(session)
  local state = {}
  for _, slot in ipairs(session.slots) do
    local component = current(session, slot.address)
    local colours = {}
    if component ~= 0 then
      local count = wml.read_u8(component + 0x10)
      for i = 0, count - 1 do
        colours[i + 1] = wml.callx(COLOUR,
          { eax = session.instance, esi = component, edx = i })
      end
    end
    state[#state + 1] = { component = component, colours = colours }
  end
  return state
end

local function differs(session, saved)
  if not V.valid(session) then return false end
  for i, slot in ipairs(session.slots) do
    local component = current(session, slot.address)
    local entry = saved[i]
    if component ~= entry.component then return true end
    for colour, value in ipairs(entry.colours) do
      if wml.callx(COLOUR, { eax = session.instance, esi = component, edx = colour - 1 }) ~= value then
        return true
      end
    end
  end
  return false
end

local function fit(session, component)
  if not V.valid(session) then return "Get back in the vehicle to customize it" end
  wml.call(FIT, session.instance, component, 0)
  wml.callx(REFRESH, { eax = session.vehicle })
end

local function restore(session, saved)
  if not V.valid(session) then return end
  -- A component can add or replace parts in other slots. Restore the whole
  -- catalog, including originally empty slots and each fitted paint choice.
  for i, slot in ipairs(session.slots) do
    local component = current(session, slot.address)
    if component ~= 0 and component ~= saved[i].component then
      wml.callx(REMOVE, { ecx = 0 }, session.instance, component)
    end
  end
  for _, entry in ipairs(saved) do
    if entry.component ~= 0 then wml.call(FIT, session.instance, entry.component, 0) end
  end
  for i, slot in ipairs(session.slots) do
    local entry = saved[i]
    if entry.component == 0 then
      local component = current(session, slot.address)
      if component ~= 0 then wml.callx(REMOVE, { ecx = 0 }, session.instance, component) end
    else
      for colour, value in ipairs(entry.colours) do
        wml.call(SET_COLOUR, session.instance, entry.component, colour - 1, value)
      end
    end
  end
  wml.callx(REFRESH, { eax = session.vehicle })
end

local function parts_page(session, slot)
  if not V.valid(session) then return "This vehicle is no longer available" end
  local saved, why = snapshot(session)
  if not saved then return why end
  local rows, cursor, error_message = {}, 1, nil
  local worn = current(session, slot.address)
  for i = 0, slot.count - 1 do
    local component = slot.components + i * 0x38
    if (wml.read_u8(component + 0x34) & 2) ~= 0 or component == worn then
      local name = label(read(component + 4), "Option " .. (i + 1))
      local function preview()
        if not V.valid(session) or current(session, slot.address) == component then return end
        local ok, failure = pcall(fit, session, component)
        if ok then error_message = failure else error_message = "Couldn't preview this part" end
        if error_message then pcall(restore, session, saved) end
      end
      rows[#rows + 1] = { label = name, kind = "action", needs = "vehicle",
        help = "Highlight to preview. Accept keeps the part. Return offers Save Changes.",
        note = function()
          return V.valid(session) and current(session, slot.address) == component and "FITTED" or ""
        end,
        hover = preview,
        run = function()
          preview()
          if error_message then return error_message end
          if not V.valid(session) or current(session, slot.address) ~= component then
            return "Couldn't fit this part"
          end
          local accepted, failure = snapshot(session)
          if not accepted then return failure end
          saved = accepted
          return "Fitted " .. name
        end }
      if component == worn then cursor = #rows end
    end
  end
  if #rows == 0 then return "No parts are available for this slot" end
  return { title = slot.label, rows = rows, cursor = cursor,
    dirty = function() return differs(session, saved) end,
    accept = function()
      if not V.valid(session) then return "This vehicle is no longer available" end
      if error_message then return error_message end
      local accepted, failure = snapshot(session)
      if not accepted then return failure end
      saved = accepted
    end,
    back = function() if differs(session, saved) then restore(session, saved) end end }
end

function V.page(F, p)
  if p == 0 or G.player() ~= p or G.in_cutscene() then return "Get in a vehicle first" end
  local handle = G.vehicle_handle(p)
  if not handle then return "Get in a vehicle first" end
  local car = read(0x02149C64 + (handle & 0xFFF) * 16)
  if car == 0 or read(car + 0x44) ~= handle or read(car + 0x4C) ~= 5
    or wml.read_u8(car + 0x84D8) ~= 1 then return "This vehicle can't be customized" end
  local info, instance = read(car + 0x84E4), read(car + 0x84D4)
  if info == 0 or instance == 0 or wml.read_u8(info + 0x7C) ~= 1 then
    return "This vehicle has no customization catalog"
  end
  local catalog = read(info + 0x78)
  if catalog == 0 then return "This vehicle has no customization catalog" end
  local count, array = read(catalog), read(catalog + 4)
  if count == 0 or count > 200 or array == 0 then return "This vehicle has no customization slots" end
  local session = { p = p, actor = read(p + 0x44), vehicle = car, handle = handle,
    instance = instance, info = info, slots = {} }
  local rows = {}
  for i = 0, count - 1 do
    local address = array + i * 16
    local kind, components, part_count = read(address), read(address + 8), wml.read_u8(address + 0xC)
    if kind ~= 0 and components ~= 0 and part_count > 0 and part_count <= 128 then
      local slot = { address = address, components = components, count = part_count,
        label = label(read(kind), "Slot " .. (i + 1)) }
      session.slots[#session.slots + 1] = slot
      -- Paint slots use the color rows in Look, rather than a list containing
      -- their single paintable placeholder component.
      if read(kind + 8) ~= 1 then
        local worn, available = current(session, address), false
        for component_index = 0, part_count - 1 do
          local component = components + component_index * 0x38
          if (wml.read_u8(component + 0x34) & 2) ~= 0 or component == worn then
            available = true
            break
          end
        end
        if available then
          rows[#rows + 1] = { label = slot.label, kind = "page", needs = "vehicle",
            help = "Browse this vehicle's parts with live previews.",
            open = function() return parts_page(session, slot) end }
        end
      end
    end
  end
  if #rows == 0 then return "This vehicle has no customizable parts" end
  F.vehicle_preview = session
  return { title = "Customize Vehicle", rows = rows, vehicle = car,
    back = function() if F.vehicle_preview == session then F.vehicle_preview = nil end end }
end

return V

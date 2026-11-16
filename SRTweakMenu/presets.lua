-- SR Tweak Menu (Saints Row 2) - saved presets: looks (looks.lua) and vehicle
-- setups (vehicle_customize.lua), kept in saved_presets.lua next to mod.ini
-- as a Lua table, and the page both use: pick a slot, then save, load or
-- delete it.
local S = {}
S.FILE = wml.mod_folder .. "\\saved_presets.lua"

local data

local function quote(value, out, depth)
  local kind = type(value)
  if kind == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for key in pairs(value) do
      if type(key) == "number" or type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    for _, key in ipairs(keys) do
      out[#out + 1] = "\n" .. ("  "):rep(depth + 1) .. "["
        .. (type(key) == "number" and string.format("%d", key) or string.format("%q", key)) .. "] = "
      quote(value[key], out, depth + 1)
      out[#out + 1] = ","
    end
    out[#out + 1] = (#keys > 0 and "\n" .. ("  "):rep(depth) or "") .. "}"
  elseif kind == "string" then
    out[#out + 1] = string.format("%q", value)
  elseif kind == "number" then
    out[#out + 1] = math.type(value) == "integer" and string.format("%d", value) or string.format("%.5f", value)
  else
    out[#out + 1] = value == true and "true" or "false"
  end
end

-- The whole store: { looks = { [slot] = look }, vehicles = { [model] = { [slot] = setup } } }.
function S.all()
  if data then return data end
  data = {}
  local f = io.open(S.FILE, "r")
  if f then
    local text = f:read("a")
    f:close()
    -- (the file is data: it is loaded with no access to any function)
    local chunk = load(text, "saved_presets", "t", {})
    local ok, t = pcall(chunk or error)
    if ok and type(t) == "table" then data = t
    else wml.log("saved_presets.lua couldn't be read; starting with no presets") end
  end
  return data
end

function S.reload() data = nil end

function S.write()
  local out = { "-- SR Tweak Menu: saved looks and vehicle presets. Written by the menu.\nreturn " }
  quote(S.all(), out, 0)
  out[#out + 1] = "\n"
  local f = io.open(S.FILE, "w")
  if not f then return "Couldn't write " .. S.FILE end
  f:write(table.concat(out))
  f:close()
end

function S.stamp() return os.date("%b %d %H:%M") end

-- A page of `spec.slots` slots kept in the table `spec.store()`.
--   capture() -> entry, or nil and why; apply(entry) -> a message, failed?
--   status(): text for the Load row while something is still being applied.
-- Saving over or deleting a filled slot asks for the same button again.
function S.page(spec)
  local slot = { label = "Slot", kind = "choice", options = {}, v = 1,
    help = "Left and Right choose a slot." }
  local armed
  local function label(i)
    local entry = spec.store()[i]
    return entry and (spec.noun .. " " .. i .. " - saved " .. (entry.saved or "earlier"))
      or (spec.noun .. " " .. i .. " - empty")
  end
  local function relabel()
    for i = 1, spec.slots do slot.options[i] = label(i) end
  end
  relabel()
  slot.change = function() armed = nil end
  local function confirmed(what)
    local key = what .. slot.v
    if armed == key then armed = nil return true end
    armed = key
    return false
  end
  local rows = { slot,
    { label = "Save to this slot", kind = "action", help = spec.save_help,
      run = function()
        if spec.store()[slot.v] and not confirmed("save") then
          return "This slot is in use. Press again to replace it."
        end
        local entry, why = spec.capture()
        if not entry then armed = nil return why or "Couldn't save" end
        entry.saved = S.stamp()
        spec.store()[slot.v] = entry
        relabel()
        return S.write() or ("Saved to " .. spec.noun:lower() .. " " .. slot.v)
      end },
    { label = "Load this slot", kind = "action", help = spec.load_help,
      note = function() return spec.status and spec.status() or "" end,
      run = function()
        armed = nil
        local entry = spec.store()[slot.v]
        if not entry then return "This slot is empty" end
        return spec.apply(entry)
      end },
    { label = "Delete this slot", kind = "action", help = "Empties the slot.",
      run = function()
        if not spec.store()[slot.v] then armed = nil return "This slot is empty" end
        if not confirmed("delete") then return "Press again to delete it." end
        spec.store()[slot.v] = nil
        relabel()
        return S.write() or (spec.noun .. " " .. slot.v .. " deleted")
      end },
  }
  return { title = spec.title, rows = rows }
end

return S

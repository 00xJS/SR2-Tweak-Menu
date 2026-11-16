-- SR Tweak Menu (Saints Row 2) - Settings > Export / Import settings: every
-- tweak (as they are now), the saved looks, vehicle presets, kept walk
-- style and weapon stash, and the menu style, in one file,
-- TweakMenu\SRTweakMenu-backup.lua, to keep a copy or give to someone.
-- mod.ini isn't in it: a newer version of the menu brings a newer mod.ini.
local presets = require("presets")
local B = {}

local ROOT = wml.mod_folder:match("^(.*)[/\\][^/\\]+$") or wml.mod_folder
B.FILE = ROOT .. "\\SRTweakMenu-backup.lua"
local MENU_UI = wml.mod_folder .. "/menu_ui.txt"

local function read(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local text = f:read("a")
  f:close()
  return text
end
local function write(path, text)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(text)
  f:close()
  return true
end

function B.export(F)
  local tweaks, n = F.tweaks_text()
  presets.all()   -- (makes sure the store on disk is the one in use)
  local parts = {
    "-- SR Tweak Menu settings, exported " .. os.date("%Y-%m-%d %H:%M") .. ". Settings > Import settings reads it.\n",
    "return {\n",
    "  saved_tweaks = ", string.format("%q", tweaks), ",\n",
    "  saved_presets = ", string.format("%q", read(presets.FILE) or ""), ",\n",
    "  menu_ui = ", string.format("%q", read(MENU_UI) or ""), ",\n",
    "}\n",
  }
  if not write(B.FILE, table.concat(parts)) then return "Couldn't write " .. B.FILE end
  return "Exported " .. n .. " tweaks and your presets to SRTweakMenu-backup.lua"
end

-- The backup's three texts, or nil and why. It is read as data only.
function B.read()
  local text = read(B.FILE)
  if not text then return nil, "No SRTweakMenu-backup.lua in the TweakMenu folder" end
  local chunk = load(text, "backup", "t", {})
  local ok, t = pcall(chunk or error)
  if not ok or type(t) ~= "table" then return nil, "SRTweakMenu-backup.lua couldn't be read" end
  for _, key in ipairs({ "saved_tweaks", "saved_presets", "menu_ui" }) do
    if type(t[key]) ~= "string" then return nil, "SRTweakMenu-backup.lua is missing " .. key end
  end
  if t.saved_presets ~= "" then
    local presets_chunk = load(t.saved_presets, "saved_presets", "t", {})
    local good, store = pcall(presets_chunk or error)
    if not good or type(store) ~= "table" then return nil, "The presets in the backup are damaged" end
  end
  return t
end

function B.import(F)
  local t, why = B.read()
  if not t then return why end
  if not write(F.SAVE_FILE, t.saved_tweaks) then return "Couldn't write " .. F.SAVE_FILE end
  if t.saved_presets ~= "" then write(presets.FILE, t.saved_presets) else os.remove(presets.FILE) end
  presets.reload()
  F.load_tweaks()
  local style = t.menu_ui:match("^%s*(%a+)")
  if style == "game" or style == "text" then
    local settings = require("menu_settings")
    settings.set(style)
    if F.items.specialized_menu_ui then F.items.specialized_menu_ui.v = style == "game" and 2 or 1 end
  end
  return "Imported. Some values take effect after a restart, as at start-up"
end

function B.export_row(F)
  return { id = "export_settings", label = "Export settings", kind = "action", needs = "none", nosave = true,
    help = "Writes your tweaks as they are now, saved looks, vehicle presets and menu style to TweakMenu\\SRTweakMenu-backup.lua.",
    run = function() return B.export(F) end }
end

function B.import_row(F)
  local armed = false
  return { id = "import_settings", label = "Import settings", kind = "action", needs = "none", nosave = true,
    help = "Replaces your tweaks, saved looks and vehicle presets with the ones in TweakMenu\\SRTweakMenu-backup.lua. Press twice.",
    run = function()
      if not armed then
        local t, why = B.read()
        if not t then return why end
        armed = true
        return "This replaces your tweaks and presets. Press again to import."
      end
      armed = false
      return B.import(F)
    end }
end

return B

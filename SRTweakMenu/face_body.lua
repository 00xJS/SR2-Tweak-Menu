-- Use the stock character editor's live customization record without opening its UI.
local G = require("game")
local B = {}
local restore
local preview_skin
-- Stock player_creation and skin-color display names, resolved from static_US.le_strings.
local LABELS = {
  [0x008EA690] = "face age",
  [0x01B367E2] = "average head",
  [0x02A91E81] = "bridge width",
  [0x0342CCF1] = "SKC1",
  [0x042F08E8] = "SKC5",
  [0x0647AFE2] = "Pierce",
  [0x066CCC7F] = "jowls elevation",
  [0x0A13BE1E] = "Sunshine",
  [0x0DFE004D] = "OvrSizeLjacket",
  [0x0F755B77] = "septum width",
  [0x0FBFD6AA] = "ears width",
  [0x11FBC314] = "judge",
  [0x12B5D9A0] = "forehead depth",
  [0x14B4067F] = "face gender",
  [0x14DC3898] = "upper lip sides elevation",
  [0x160F5B88] = "double chin elevation",
  [0x17631452] = "neck back depth",
  [0x18F9519C] = "eyeballs spacing",
  [0x1A59FDB0] = "SKB1",
  [0x1AB3CDA1] = "Dane",
  [0x1C6920B0] = "ears length",
  [0x1CBB0AA1] = "ears height",
  [0x1D3439A9] = "SKB5",
  [0x1E085E54] = "Jessica",
  [0x1FE3F222] = "jaw depth",
  [0x207A6087] = "old",
  [0x215CBEB7] = "Anna",
  [0x219BD18D] = "cheeks spacing",
  [0x22B35429] = "Child",
  [0x234ADAB3] = "double chin depth",
  [0x281B99B7] = "skull top elevation",
  [0x29922F50] = "Donnie",
  [0x29A0E888] = "lobes elevation",
  [0x2A0DA47A] = "lower eyelids roll",
  [0x2B4E07D9] = "Shaundi",
  [0x30628F17] = "Carlos",
  [0x3095413E] = "nostrils width",
  [0x3174AE73] = "SKA1",
  [0x32F8BF5A] = "Shogo",
  [0x33A15EB8] = "ears pitch",
  [0x36196A6A] = "SKA5",
  [0x411E5AFC] = "SKA4",
  [0x426A0873] = "chin width",
  [0x45893160] = "temples depth",
  [0x50054403] = "cmGla_uShogo01",
  [0x50673455] = "mouth depth",
  [0x54D937EE] = "black",
  [0x58CDE3EB] = "Translator",
  [0x59D0BBAF] = "Tobias",
  [0x59D0EA19] = "Troy",
  [0x59E53FD6] = "jaw spacing",
  [0x630A5D77] = "skull back depth",
  [0x6686E76C] = "body gender",
  [0x67AAA0B1] = "nose elevation",
  [0x6825304C] = "upper lip middle size",
  [0x6A33093F] = "SKB4",
  [0x6BFA82A8] = "cheeks elevation",
  [0x6CC69380] = "bridge elevation",
  [0x6CFC1D36] = "Laura",
  [0x6D2C1B96] = "slope depth",
  [0x6FDBC99B] = "ears roll",
  [0x70DA8FDD] = "General_S",
  [0x7227124B] = "cheekbones spacing",
  [0x7328387E] = "SKC4",
  [0x7342CF66] = "upper lip middle elevation",
  [0x7507B136] = "jaw elevation",
  [0x759FA556] = "JaneV",
  [0x768FF779] = "ball depth",
  [0x7A1C9CCE] = "ears yaw",
  [0x7B32910A] = "lobes size",
  [0x7BE3B962] = "cmbod_dup03",
  [0x7D793DDB] = "Kazuo",
  [0x7E403DDC] = "brow width",
  [0x7ED2FB4C] = "JanV",
  [0x7F86E5CF] = "body muscle",
  [0x820729A1] = "tips spacing",
  [0x823BC27B] = "mouth width",
  [0x8324F4CB] = "white",
  [0x8350AC0A] = "SKB2",
  [0x842DF701] = "Julius",
  [0x843D6813] = "SKB6",
  [0x87D8C13E] = "brow spacing",
  [0x8F7383A8] = "jowls spacing",
  [0x9036FE5D] = "chin depth",
  [0x92E60629] = "ball elevation",
  [0x941FE0E8] = "forehead elevation",
  [0x97013769] = "Sampson",
  [0x9957EB74] = "Gat",
  [0x99C7DB31] = "temples spacing",
  [0x9A4B9D4B] = "SKC2",
  [0x9B3F8EBD] = "eyeballs size",
  [0x9BDEE163] = "Lee",
  [0x9C3086E0] = "body fat",
  [0x9D265952] = "SKC6",
  [0x9F24180A] = "LegalLee",
  [0xA20E7C8D] = "outer brow elevation",
  [0xA4D30157] = "ball width",
  [0xA87DFFC9] = "SKA2",
  [0xAA02BAF1] = "Maero",
  [0xABC84AE2] = "middle brow elevation",
  [0xAC1CCBF2] = "brow depth",
  [0xAC3F5F9D] = "upper eyelids roll",
  [0xACB9ABA6] = "Tera",
  [0xAF103BD0] = "SKA6",
  [0xAF41C2AF] = "mouth elevation",
  [0xB156AB59] = "skull back width",
  [0xB2232392] = "nostrils spacing",
  [0xB34D5845] = "slope elevation",
  [0xB4ADD862] = "cheekbones depth",
  [0xB5E1561F] = "Jyunichi",
  [0xBC8E2EF5] = "eyeballs depth",
  [0xBC8F79F6] = "Wong",
  [0xBD265802] = "Matt",
  [0xBE5D4BDA] = "lower lip sides elevation",
  [0xBF70EDB8] = "slope width",
  [0xC0E92F8E] = "forehead width",
  [0xC20FA135] = "eye folds elevation",
  [0xC35F325E] = "temples elevation",
  [0xC37C3EA8] = "iris size",
  [0xC53FE27C] = "neck back width",
  [0xC9655541] = "ears spacing",
  [0xCE095773] = "chin elevation",
  [0xCE29364A] = "General",
  [0xCEC4A6AA] = "cmBot_wShaundi_L",
  [0xD04BBC8B] = "tips size",
  [0xD0F0EC03] = "inner brow elevation",
  [0xD0F5E8AF] = "bridge depth",
  [0xD59B1BFA] = "eyeballs elevation",
  [0xD5F434F0] = "cheekbones size",
  [0xD8209A62] = "asian",
  [0xDA011F1B] = "upper eyelids pitch",
  [0xDB6B93A2] = "mouth sides elevation",
  [0xDD162608] = "upper lip sides size",
  [0xDDE32084] = "ears depth",
  [0xDF1CE8D7] = "ball height",
  [0xDF2800CE] = "cmBod_Pierce",
  [0xDF7ACF5F] = "SKA3",
  [0xDF7E34C8] = "jowls depth",
  [0xE1AD30B4] = "tips elevation",
  [0xE2C9B710] = "nostrils depth",
  [0xE3F9B50F] = "chin height",
  [0xE4885B55] = "chin dimple",
  [0xE4A21E2B] = "cheeks depth",
  [0xE4E95A3B] = "lower eyelids pitch",
  [0xE5787701] = "Aisha",
  [0xE646EE85] = "lower lip sides size",
  [0xE660B52D] = "ears elevation",
  [0xE9AEEFD9] = "mouth sides size",
  [0xEAA6637E] = "septum elevation",
  [0xEAC04570] = "skull top width",
  [0xEB3A6EA9] = "lower lip middle elevation",
  [0xEBE6776B] = "nostrils height",
  [0xED4CADDD] = "SKC3",
  [0xF1162C9D] = "double chin width",
  [0xF43732D6] = "cheekbones elevation",
  [0xF4579C9C] = "SKB3",
  [0xF5138CBE] = "nostrils elevation",
  [0xF5E5098A] = "Kazuo01",
  [0xF6231AD5] = "mouth sides depth",
  [0xF63F4263] = "nose depth",
  [0xFA532513] = "mouth bite",
  [0xFB179F19] = "lower lip middle size",
  [0xFD7861F9] = "cmSho_mPierce",
}
local pitch = 0
local pitched = {}
local VOICES = {
  { "MALE_WHITE", "Male 1" }, { "MALE_BLACK", "Male 2" }, { "MALE_LATINO", "Male 3" },
  { "FEMALE_WHITE", "Female 1" }, { "FEMALE_BLACK", "Female 2" }, { "FEMALE_LATINO", "Female 3" },
}

local function record(p)
  if p ~= 0 and G.player() == p then
    local ptr = wml.read_u32(p + 0x13B0)
    if ptr ~= 0 then return ptr end
  end
end

local function ready()
  local _, done = G.vint("tweak_out(pcu_is_streaming_done())")
  return done == true
end

local function argument(id)
  return type(id) == "number" and tostring(id) or string.format("%q", id)
end

local function morph_value(set, id)
  local _, value = G.vint(("tweak_out(pcr_get_morph_value(%q, %s))"):format(set, argument(id)))
  return type(value) == "number" and value >= 0 and value <= 1 and value or nil
end

local function put(set, id, value)
  local ok = G.vint(("pcr_apply_morph_value(%q, %s, %.5f)"):format(set, argument(id), value))
  local actual = ok and morph_value(set, id)
  return actual and math.abs(actual - value) < 0.005
end

local function pitch_channel(handle)
  local slot, generation = handle & 0xFF, handle >> 8
  if slot >= 128 or generation == 0 then return end
  local channel = 0x00EEB8F8 + slot * 0x19C
  if wml.read_u32(0x00EEB9AC + slot * 0x19C) == generation
    and wml.read_u32(channel) ~= 0xFFFFFFFF then return channel end
end

local function restore_pitch(handle, own)
  local channel = pitch_channel(handle)
  if channel and math.abs(wml.read_f32(channel + 0x28) - own.last) < 0.001 then
    local ptr = wml.buffer(15)
    wml.write_u32(ptr, handle)
    wml.callx(0x004800C0, { ecx = ptr }, wml.f2u(own.original))
  end
end

function B.update(p)
  local wanted = p ~= 0 and pitch ~= 0 and B.enabled ~= false
  local actor = p ~= 0 and wml.read_u32(p + 0x44) or 0
  local active = {}
  local count = math.min(wml.read_u32(0x01450408), 32)
  local function apply_pitch(speaker, pointer)
    local handle = wml.read_u32(pointer)
    local channel = pitch_channel(handle)
    if channel then
      local own = pitched[handle]
      if wanted and speaker == actor and wml.read_u32(channel + 0xA4) == 1 then
        if own and own.actor ~= actor then restore_pitch(handle, own) own = nil end
        own = own or { original = wml.read_f32(channel + 0x28), actor = actor }
        local value = math.max(-1, math.min(1, own.original + pitch / 12))
        wml.callx(0x004800C0, { ecx = pointer }, wml.f2u(value))
        own.last, pitched[handle], active[handle] = value, own, true
      end
    end
  end
  for i = 0, count - 1 do
    local row = 0x027D83C8 + i * 0x18
    apply_pitch(wml.read_u32(row), row + 8)
  end
  for i = 0, 15 do
    local row = 0x02E7CC60 + i * 0x24
    if (wml.read_u8(row + 0x1C) & 1) ~= 0 and wml.read_u32(row + 4) == 1 then
      apply_pitch(wml.read_u32(row), row + 0x10)
    end
  end
  for handle, own in pairs(pitched) do
    if not active[handle] then restore_pitch(handle, own) pitched[handle] = nil end
  end
  if preview_skin then preview_skin() end
  if not restore then return end
  if record(p) ~= restore.owner or p ~= restore.p or wml.read_u32(p + 0x44) ~= restore.actor then restore = nil return end
  if not G.playing(p) or not ready() then return end
  if restore.skin ~= nil then
    local ok = G.vint(("pcr_change_skin_color(%d)"):format(restore.skin))
    if ok then restore = nil end
    return
  end
  for i, entry in pairs(restore.values) do
    if not put(entry.set, entry.id, entry.value) then return end
    restore.values[i] = nil
    if not ready() then return end
  end
  restore = nil
end

local function catalog(set)
  local report = set and ("pcr_report_avail_morphs(%q, \"TWK_body_add\")"):format(set)
    or 'pcr_report_skin_colors("TWK_body_add")'
  local args = set and "id, crc, name, value" or "id, swatch, crc, name, current"
  local _, count = G.vint(([[
    local list, count = {}, 0
    rawset(_G, "TWK_body_add", function(%s)
      count = count + 1
      list[count] = { id, crc or false, name or false, %s }
    end)
    %s
    rawset(_G, "TWK_body_add", nil)
    rawset(_G, "TWK_body_list", list)
    tweak_out(count)
  ]]):format(args, set and "false" or "current == true", report))
  if type(count) ~= "number" then return {} end
  local entries = {}
  -- Keep each bridge call below its 128-result limit, including nil labels.
  for first = 1, count, 30 do
    local batch = table.pack(G.vint(([[
      local list = rawget(_G, "TWK_body_list")
      for i = %d, %d do
        local row = list[i]
        tweak_out(row[1], row[2], row[3], row[4])
      end
    ]]):format(first, math.min(first + 29, count))))
    for i = 2, batch.n, 4 do
      local id, crc, name, current = batch[i], batch[i + 1], batch[i + 2], batch[i + 3]
      if (type(id) == "number" and id >= 0 and id % 1 == 0) or type(id) == "string" then
        local label = type(name) == "string" and name
          or (type(crc) == "number" and LABELS[crc & 0xFFFFFFFF])
          or ((set and "Control " or "Skin color ") .. tostring(type(id) == "number" and id + 1 or id))
        entries[#entries + 1] = { id, label, current == true }
      end
    end
  end
  G.vint('rawset(_G, "TWK_body_list", nil)')
  return B.display_names(entries)
end

-- The names the plastic surgeon shows: each control's DisplayName key
-- (player_creation.xtbl, data/morph_display.lua) turned into text by the
-- game's own string table (vint_insert_values_in_string, as cellphone.lua
-- does). A key the game can't resolve falls back to the control name in
-- Title Case, never the raw internal name.
local DISPLAY = require("data.morph_display")
local shown = {}
local function title_case(text)
  return (text:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
function B.display_names(entries)
  local want, keys = {}, {}
  for _, entry in ipairs(entries) do
    local key = type(entry[2]) == "string" and DISPLAY[entry[2]]
    if key and key:find("^[%u%d_]+$") and shown[key] == nil and not want[key] then
      want[key] = true
      keys[#keys + 1] = key
    end
  end
  for first = 1, #keys, 40 do
    local parts = {}
    for i = first, math.min(first + 39, #keys) do
      parts[#parts + 1] = string.format("%q", keys[i])
    end
    local got = table.pack(G.vint(([[
      local f, try, kind = rawget(_G, "vint_insert_values_in_string"), rawget(_G, "pcall"), rawget(_G, "type")
      local keys = { %s }
      for i = 1, %d do
        local ok, text = false, nil
        if f then ok, text = try(f, "{0}", { [0] = keys[i] }) end
        tweak_out(ok and kind(text) == "string" and text or false)
      end
    ]]):format(table.concat(parts, ", "), #parts)))
    for i = first, math.min(first + 39, #keys) do
      local text = got[i - first + 2]
      shown[keys[i]] = type(text) == "string" and text ~= "" and text ~= keys[i]
        and not text:find("^[%u%d_]+$") and text or false
    end
  end
  for _, entry in ipairs(entries) do
    local name = entry[2]
    if type(name) == "string" then
      local key = DISPLAY[name]
      entry[2] = (key and shown[key]) or (key and not key:find("^[%u%d_]+$") and key) or title_case(name)
    end
  end
  return entries
end

function B.morph_page(p, set, title, entries)
  local owner = record(p)
  local actor = wml.read_u32(p + 0x44)
  if not owner or not G.playing(p) or restore or not ready() then return "Wait until your character is ready" end
  local rows, saved, applied, specs = {}, {}, {}, {}
  for _, entry in ipairs(entries or catalog(set)) do
    local id, label, group = entry[1], entry[2], entries and entry[3] or set
    group = type(group) == "string" and group or set
    local initial = morph_value(group, id)
    if initial then
      local index = #specs + 1
      specs[index] = { id = id, set = group }
      saved[index], applied[index] = initial, initial
      rows[#rows + 1] = { label = label, kind = "value", min = 0, max = 100,
        v = initial * 100, default = initial * 100, step = 1,
        fmt = function(v) return string.format("%.0f", v) end,
        help = "Adjust to preview. Return offers Save Changes.",
        change = function(_, _, _, row)
          local value = row.v / 100
          if record(p) == owner and wml.read_u32(p + 0x44) == actor and G.playing(p) and ready() and put(group, id, value) then
            applied[index] = value
          else
            row.v = applied[index] * 100
          end
        end }
    end
  end
  if #rows == 0 then return "No controls are available for this part of the character" end
  local function changes()
    local changed = {}
    for i, value in ipairs(applied) do
      if math.abs(value - saved[i]) > 0.0001 then
        changed[i] = { set = specs[i].set, id = specs[i].id, value = saved[i] }
      end
    end
    return changed
  end
  return { title = title, rows = rows, dirty = function() return next(changes()) ~= nil end,
    accept = function()
      if record(p) ~= owner or wml.read_u32(p + 0x44) ~= actor or not G.playing(p) or not ready() then return "Wait for the preview to finish" end
      for i, value in ipairs(applied) do saved[i] = value end
    end,
    back = function()
      local values = changes()
      if next(values) then
        restore = { p = p, owner = owner, actor = actor, values = values }
        B.update(p)
      end
    end }
end

function B.skin_page(p)
  local owner = record(p)
  local actor = wml.read_u32(p + 0x44)
  if not owner or not G.playing(p) or restore or not ready() then return "Wait until your character is ready" end
  local entries, kept, cursor = catalog(), nil, 1
  for i, entry in ipairs(entries) do
    if entry[3] then kept, cursor = entry[1], i end
  end
  if kept == nil then return "Couldn't read the current skin color" end
  local wanted, submitted, closed = kept, kept, false
  local function valid()
    return record(p) == owner and wml.read_u32(p + 0x44) == actor and G.playing(p)
  end
  local function preview()
    if not closed and wanted ~= submitted and valid() and ready() then
      if G.vint(("pcr_change_skin_color(%d)"):format(wanted)) then submitted = wanted end
    end
  end
  local function accept()
    preview()
    if not valid() then return "Can't apply skin color right now" end
    if wanted ~= submitted or not ready() then return "Wait for the skin color to finish loading" end
    for _, entry in ipairs(catalog()) do
      if entry[1] == wanted and entry[3] then kept = wanted return end
    end
    return "Couldn't apply this skin color"
  end
  local rows = {}
  for i, entry in ipairs(entries) do
    local function choose() wanted = entry[1] preview() end
    rows[i] = { label = entry[2], kind = "action", hover = choose,
      help = "Up and Down preview. Accept keeps this color. Back offers Save Changes.",
      run = function() choose() return accept() or "Skin color applied" end }
  end
  preview_skin = preview
  return { title = "Skin Color", rows = rows, cursor = cursor,
    dirty = function() return wanted ~= kept or submitted ~= kept end,
    accept = accept,
    back = function()
      closed = true
      if preview_skin == preview then preview_skin = nil end
      if submitted ~= kept and valid() then
        restore = { p = p, owner = owner, actor = actor, skin = kept }
        B.update(p)
      end
    end }
end

function B.type_page(p)
  local page = B.morph_page(p, "global body", "Body Type", {
    { "body gender", "Gender", "global gender" },
    { "body fat", "Fat" }, { "body muscle", "Muscle" }, { "old", "Age" },
  })
  if type(page) == "table" then
    page.rows[#page.rows + 1] = { label = "Skin Color", kind = "page", help = "Preview skin colors live.",
      open = function() return B.skin_page(p) end }
  end
  return page
end

-- For saved looks (looks.lua): the live record's values, read and written
-- with the same calls the pages above use.
B.VOICES, B.record, B.ready, B.morph_value, B.put = VOICES, record, ready, morph_value, put
function B.busy() return restore ~= nil end
-- Every control of a morph set with its value: { { id, value }, ... }.
function B.morph_values(set)
  local _, count = G.vint(([[
    local list, count = {}, 0
    rawset(_G, "TWK_body_add", function(id)
      count = count + 1
      list[count] = id
    end)
    pcr_report_avail_morphs(%q, "TWK_body_add")
    rawset(_G, "TWK_body_add", nil)
    rawset(_G, "TWK_body_list", list)
    tweak_out(count)
  ]]):format(set))
  local values = {}
  if type(count) ~= "number" then return values end
  for first = 1, count, 40 do
    local batch = table.pack(G.vint(([[
      local list = rawget(_G, "TWK_body_list")
      for i = %d, %d do tweak_out(list[i], pcr_get_morph_value(%q, list[i]) or false) end
    ]]):format(first, math.min(first + 39, count), set)))
    for i = 2, batch.n, 2 do
      local id, value = batch[i], batch[i + 1]
      if (type(id) == "number" or type(id) == "string") and type(value) == "number" and value >= 0 and value <= 1 then
        values[#values + 1] = { id, value }
      end
    end
  end
  G.vint('rawset(_G, "TWK_body_list", nil)')
  return values
end
function B.skin_current()
  for _, entry in ipairs(catalog()) do
    if entry[3] then return entry[1] end
  end
end
function B.skin_put(id)
  return G.vint(("pcr_change_skin_color(%d)"):format(id)) and true or false
end

function B.voice_page(F, p)
  local owner = record(p)
  local actor = wml.read_u32(p + 0x44)
  local _, current = G.vint("tweak_out(pcr_get_current_voice_number())")
  if not owner or not G.playing(p) or type(current) ~= "number" or not VOICES[current + 1] then
    return "No stock voice is available for this character"
  end
  local options = {}
  for i, voice in ipairs(VOICES) do options[i] = voice[2] end
  local choice = { label = "Character voice", kind = "choice", options = options, v = current + 1,
    help = "Choose from the six stock voices. Preview or apply the selected voice." }
  return { title = "Voice", rows = { choice,
    { label = "Voice pitch", kind = "value", min = -12, max = 12, default = 0, v = pitch, step = 1,
      fmt = function(v) return string.format("%+.0f semitones", v) end,
      -- (The patched voice banks this needed are out: SR2_VOC_WM/WF/BM/BF/HM/HF hold every
      -- pedestrian of that type too, and with them installed pedestrians went quiet.)
      help = "Not working yet: the voice banks it needed muted pedestrians, so they are removed. Needs a player-only rework.",
      change = function(_, _, _, row) pitch = row.v end },
    { label = "Preview voice", kind = "action", run = function()
        if record(p) ~= owner or wml.read_u32(p + 0x44) ~= actor or not G.playing(p) then return "Voice preview needs your character on foot" end
        local _, live = G.lua("tweak_out(character_get_persona(LOCAL_PLAYER))")
        G.vint(("pcr_set_voice(%q, true)"):format(VOICES[choice.v][1]))
        if type(live) == "string" and live ~= "" then
          G.lua("character_set_persona(LOCAL_PLAYER, %s)", live)
        end
      end },
    { label = "Apply voice", kind = "action", run = function()
        if record(p) ~= owner or wml.read_u32(p + 0x44) ~= actor or not G.playing(p) then return "Voice selection needs your character on foot" end
        local voice = VOICES[choice.v]
        local ok = G.vint(("pcr_set_voice(%q, false)"):format(voice[1]))
        local _, applied = G.vint("tweak_out(pcr_get_current_voice_number())")
        if not ok or applied ~= choice.v - 1 then return "Couldn't apply this voice" end
        G.lua("T.own_persona = character_get_persona(LOCAL_PLAYER)")
        F.voice_chosen = nil
        return voice[2] .. " applied"
      end },
  } }
end

return B

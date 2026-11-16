-- SR Tweak Menu (Saints Row 2) - looks and people: screen filters and
-- saturation (the game's own colour-grading request, written every frame
-- with the top priority, so the time of day's look comes back by itself when
-- off), the drunk / high screen effects, low-detail rendering, letterbox, no
-- camera swing getting in, voice lines, staged scenes and the customization
-- pose. Addresses and conventions were read in the game's code.

local G = require("game")
local ENGINE = require("engine")
local read_u8, read_u32, read_f32 = wml.read_u8, wml.read_u32, wml.read_f32
local write_u8, write_u32, write_f32 = wml.write_u8, wml.write_u32, wml.write_f32

local V = {}
local F

-- ---------------------------------------------------------------- colour grading
-- The tone-map request: priority, enable, tint R G B, brightness, contrast,
-- saturation, bleach (1.0 / 0.0 = neutral). The game resets it every frame
-- and takes the highest priority it was given (the time of day uses 1).
local GRADE = 0x0276CFD8
local function grade(r, g, b, bright, contrast, sat, bleach)
  write_u32(GRADE, 0x7FFFFFFF)
  write_u8(GRADE + 0x04, 1)
  write_f32(GRADE + 0x08, r); write_f32(GRADE + 0x0C, g); write_f32(GRADE + 0x10, b)
  write_f32(GRADE + 0x14, bright); write_f32(GRADE + 0x18, contrast)
  write_f32(GRADE + 0x1C, sat); write_f32(GRADE + 0x20, bleach)
end
-- { "Shown name", r, g, b, brightness, contrast, saturation, bleach } or a drug effect { name, booze = , weed = }.
local FILTERS = {
  { "Off" },
  { "Greyscale", 1, 1, 1, 1, 1, 0, 0 },
  { "Noir", 1, 1, 1, 1, 1.6, 0, 0.3 },
  { "Sepia", 1.10, 0.95, 0.75, 1, 1.05, 0, 0 },
  { "Vivid", 1, 1, 1, 1.05, 1.15, 1.6, 0 },
  { "Cold", 0.85, 0.95, 1.15, 1, 1.05, 0.85, 0 },
  { "Warm", 1.12, 1.0, 0.82, 1, 1.05, 1.05, 0 },
  { "Washed out", 1, 1, 1, 1.05, 0.7, 0.5, 0 },
  { "Overexposed", 1, 1, 1, 1.4, 0.9, 0.9, 0 },
  { "Night vision", 0.35, 1.6, 0.35, 1.2, 1.2, 0, 0 },
  { "Drunk", booze = 0.75, weed = 0 },
  { "High", booze = 0, weed = 0.7 },
}
local FILTER_NAMES = {}
for i, f in ipairs(FILTERS) do FILTER_NAMES[i] = f[1] end
local DRUG = 0x00989C30   -- cdecl (player 0, f32 booze, f32 weed, sync 1 = local)
local drug_on = false
local function drug(booze, weed)
  wml.call(DRUG, 0, wml.f2u(booze), wml.f2u(weed), 1)
  drug_on = booze > 0 or weed > 0
end

local function grade_frame()
  local f = F.on("filter") and FILTERS[F.items.filter.v] or FILTERS[1]
  local sat = F.on("saturation") and F.items.saturation.v or 1.0
  if f.booze then
    if not drug_on then drug(f.booze, f.weed) end
  elseif drug_on then drug(0, 0) end
  if f[2] then
    grade(f[2], f[3], f[4], f[5], f[6], f[7] * sat, f[8])
  elseif sat ~= 1.0 then
    -- (the time of day's own look, saturation scaled)
    grade(read_f32(0x00E9D7C8), read_f32(0x00E9D7CC), read_f32(0x00E9D7D0), 1 + read_f32(0x025273A0),
      read_f32(0x00E98964), 1.0 * sat, 0)
  end
end

-- ---------------------------------------------------------------- vehicle entry
-- With the camera switch at the start of getting in left out (0x00B0CB81),
-- the menu makes it once the seat's state reaches 15 (in), as the game's end
-- of entering does.
local ENTRY_CAM = { 0x00B0CB81, "\xE8\xBA\xD3\x00\x00", "\x90\x90\x90\x90\x90" }
local entry_patched, entry_done = false, false
local function seat_record(p)
  local ix = read_u32(p + 0x10E0)
  if ix == 0 then return nil end
  local h = read_u32(p + 0x44)
  for s = 0, 7 do
    local rec = ix + 0x34C + s * 0xA8
    if read_u32(rec) == h then return rec, ix end
  end
end
local function entry_frame(p)
  local rec, ix = seat_record(p)
  if not rec then entry_done = false return end
  local st = read_u32(rec + 8)
  if st == 15 and not entry_done then
    local h = read_u32(ix)
    local veh = read_u32(0x02149C64 + (h & 0xFFF) * 16)
    if veh ~= 0 and read_u32(veh + 0x44) == h then wml.call(0x00B19F40, p, veh, 0) end
    entry_done = true
  elseif st ~= 15 then entry_done = false end
end

-- ---------------------------------------------------------------- voice lines
local TAUNTS = { "arm flex", "ass slap", "chest bump", "flip off", "hulkster", "matrix", "na na", "no you didnt", "oh yeah",
  "pee", "poop", "ride the donkey", "roar", "smooth criminal", "spit and flick", "teabag", "throat slit", "vomit", "wanker",
  "you crazy" }
local COMPLIMENTS = { "arsenio", "blow kiss", "bow", "fonz collar", "fonz point", "jig", "laugh", "number one", "ok", "salute",
  "thumbs up" }
local VOICES = { "boo", "cheer", "cough", "death scream", "fall", "fire scream", "laugh", "pain shout", "panicked scream",
  "startled line", "struggling", "whimper", "aggressive scream", "grunts", "panting" }
local function situations(prefix, names)
  local list = {}
  for _, n in ipairs(names) do list[#list + 1] = { prefix .. n, n:sub(1, 1):upper() .. n:sub(2) } end
  return list
end
local function say_row(id, label, items)
  return { id = id, label = label, kind = "list", items = items, nosave = true,
    help = "Left/Right to choose, Enter: you say it (in your character's voice, if it has that line).",
    run = function(ctx, p, v, it)
      G.lua("audio_play_persona_line(LOCAL_PLAYER, %s)", it.items[it.v][1])
      return "Saying: " .. it.items[it.v][2]
    end }
end

-- ---------------------------------------------------------------- the customization pose
local POSES = { { false, "Off" }, { "Cust Stand", "Stand" }, { "Cust Hair", "Hair" }, { "Cust Shoes", "Shoes" },
  { "Cust Legs", "Legs" }, { "Cust Wrist", "Wrists" }, { "Cust Rings", "Rings" } }
local POSE_NAMES = {}
for i, p in ipairs(POSES) do POSE_NAMES[i] = p[2] end

-- ---------------------------------------------------------------- draw distance
local DRAW_STEPS = { { "Game's own", 1.0 }, { "Far", 1.5 }, { "Farther", 2.0 }, { "Very far", 3.0 }, { "Furthest", 4.0 } }
local draw_base

-- ---------------------------------------------------------------- rows
function V.setup(features)
  F = features

  F.add_rows("Visual", nil, {
    { id = "filter", label = "Filter", kind = "choice", needs = "none", options = FILTER_NAMES, v = 1,
      help = "A colour filter over the game: greyscale, noir, sepia, vivid, cold, warm, washed out, overexposed, night vision, or the drunk and high effects." },
    { id = "saturation", label = "Saturation", kind = "value", needs = "none", default = 1.0, min = 0, max = 2, step = 0.1, fmt = F.fmtx,
      help = "How colourful the picture is (x1 = the game's own, 0 = black and white)." },
    { id = "render_mode", label = "Render mode", kind = "choice", needs = "none", options = { "Normal", "Low detail" }, v = 1,
      help = "Low detail: the game's own debug low-detail rendering and a short draw distance (faster, uglier).",
      change = function(ctx, p, v, it) V.render_mode(it.v) end },
    -- SR1's Draw Distance, on SR2's draw distance (f32 0x00E98988, the
    -- value the low-detail render mode shortens): the game's own times a step.
    { id = "draw_distance", label = "Draw Distance", kind = "value", needs = "none", default = 1, min = 1, max = #DRAW_STEPS, step = 1,
      fmt = function(n) return DRAW_STEPS[n][1] end,
      help = "How far away buildings, props and scenery still show before they fade out. Default is the game's own.",
      update = function()
        if F.items.render_mode and F.items.render_mode.v == 2 then return end   -- (low detail sets its own)
        local base = draw_base or read_f32(0x00E98988)
        draw_base = base
        write_f32(0x00E98988, base * DRAW_STEPS[F.items.draw_distance.v][2])
      end,
      off = function()
        -- (under Low detail the base comes back when Render mode goes back to Normal)
        local low = F.items.render_mode and F.items.render_mode.v == 2
        if draw_base and not low then write_f32(0x00E98988, draw_base) end
        draw_base = nil
      end },
    { id = "letterbox", label = "Letterbox", kind = "toggle", needs = "player",
      help = "Cutscene black bars in play. Not with No cutscene black bars.",
      change = function(ctx, p, v, it) wml.call(it.v and 0x0075A4F0 or 0x0075A540, 0) end,
      off = function() wml.call(0x0075A540, 0) end },
  })

  F.add_rows("Vehicles", nil, {
    { id = "no_entry_swing", label = "No camera swing getting in", kind = "toggle", needs = "none",
      v = wml.setting("no_car_entry_swing", false),
      help = "The camera doesn't swing round behind you as you get into a car.",
      update = function(ctx, p)
        if not entry_patched then wml.patch(ENTRY_CAM[1], ENTRY_CAM[3]); entry_patched = true end
        if p ~= 0 then entry_frame(p) end
      end,
      off = function()
        if entry_patched then wml.patch(ENTRY_CAM[1], ENTRY_CAM[2]); entry_patched = false end
        entry_done = false
      end },
  })

  -- (Voice Lines is tab_emotes.lua's now: every line the voice has, SR1's way.)
  F.add_rows("Emotes", "stop_pose", {
    ENGINE.scene_row(),
    ENGINE.clear_scene_row(),
  })

  F.add_rows("Customize", nil, {
    { id = "outfit_back", label = "Restore outfit", kind = "action",
      help = "Back to your own character and the outfit a mission changed.",
      run = function()
        ENGINE.restore_player()
        G.lua("customization_item_revert(SYNC_LOCAL)")
        return "Outfit restored"
      end },
    { id = "look_pose", label = "Customization pose", kind = "choice", options = POSE_NAMES, v = 1, nosave = true,
      help = "Strike the clothing store's poses to see your look: stand, hair, shoes, legs, wrists, rings.",
      pose_name = function() return POSES[F.items.look_pose.v][1] end },
    { id = "customization_tpose", label = "Customization T-pose", kind = "toggle", nosave = true,
      help = "Hold the rig's rest pose while inspecting your character in Customize.",
      change = function()
        if F.items.customization_tpose.v and (not wml.preview_mode or not wml.preview_mode(true, true)) then
          F.items.customization_tpose.v = false
          return "The native rest-pose hook is unavailable in this game build"
        end
      end },
  })
end

-- Low detail: the debug "ugly mode" byte and a short draw distance.
local saved_draw
function V.render_mode(n)
  if n == 2 then
    saved_draw = saved_draw or draw_base or read_f32(0x00E98988)   -- (the game's own, not Draw Distance's)
    write_u8(0x025273B4, 1); write_f32(0x00E98988, 400.0)
  else
    write_u8(0x025273B4, 0)
    if saved_draw then write_f32(0x00E98988, saved_draw); saved_draw = nil end
  end
end

-- Every frame.
function V.after_update(p)
  if F.enabled then grade_frame() elseif drug_on then drug(0, 0) end
end

return V

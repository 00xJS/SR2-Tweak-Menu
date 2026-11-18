-- SR Tweak Menu (Saints Row 2) - quality-of-life rows: SR1's juiced.lua rows
-- (after the SR2 Juiced Patch by Kobraworks Modding), done for SR2 itself so
-- they work with or without Juiced. The ideas are theirs; none of their
-- code is used: each row is a few bytes of the game's own code switched
-- live (and put back when off), a game global, or a value the menu keeps.
--
-- Values the game reads through a patched instruction ("cells") live in
-- the host's scratch buffer 15, which stays put for the whole session.
-- With Juiced installed, leave its own copy of a feature off in juiced.ini
-- (the two would patch the same bytes).

local G = require("game")
local read_u8, read_u32, read_f32 = wml.read_u8, wml.read_u32, wml.read_f32
local write_u8, write_u32, write_f32 = wml.write_u8, wml.write_u32, wml.write_f32
local S = wml.setting

local Q = {}
local F

-- ---------------------------------------------------------------- helpers
-- (the upper half of scratch slot 15: other modules use its start as scratch
-- for a moment, and these cells are read by the game's code every frame)
local CELL = wml.buffer(15) + 512
-- +0 f64 FOV factor | +8 f64 auto-center ms/s, moving | +16 f64 the same, stopped
-- +24 f32 swing-back speed | +28 f32 mouse X | +32 f32 mouse Y | +36 f32 minimap angle | +40 f32 pause map angle
-- +48 f32 bloom strength | +52 f32 bloom radius
local function a32(a) return string.pack("<I4", a) end
local function write_f64(a, x)
  local lo, hi = string.unpack("<I4I4", string.pack("<d", x))
  write_u32(a, lo); write_u32(a + 4, hi)
end

-- Patch sets: { address, original bytes, our bytes }. Applied once when a
-- row comes on, put back when it goes off.
local applied = {}
local function code_at(a, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = string.char(read_u8(a + i)) end
  return table.concat(t)
end
local refused = {}
local function apply(name, set, on)
  if (applied[name] or false) == on then return end
  if on then
    -- (code that isn't what the patch was made for - another mod's - is left alone)
    for _, e in ipairs(set) do
      local now = code_at(e[1], #e[2])
      if now ~= e[2] and now ~= e[3] then
        if not refused[name] then
          refused[name] = true
          wml.log(string.format("%s: the game's code at %08X isn't what the menu expects (another mod?); not changed", name, e[1]))
        end
        return
      end
    end
  end
  applied[name] = on
  for _, e in ipairs(set) do wml.patch(e[1], on and e[3] or e[2]) end
end
-- A game global switched by a row: its live value kept and put back.
local saved = {}
local function hold_u8(addr, on, value)
  if on then
    if saved[addr] == nil then saved[addr] = read_u8(addr) end
    write_u8(addr, value)
  elseif saved[addr] ~= nil then write_u8(addr, saved[addr]); saved[addr] = nil end
end
local function hold_u32(addr, on, value)
  if on then
    if saved[addr] == nil then saved[addr] = read_u32(addr) end
    write_u32(addr, value)
  elseif saved[addr] ~= nil then write_u32(addr, saved[addr]); saved[addr] = nil end
end

-- A row that is just a patch set.
local function patch_row(id, label, help, set, v)
  return { id = id, label = label, kind = "toggle", needs = "none", v = v, help = help,
    update = function() apply(id, set, true) end,
    off = function() apply(id, set, false) end }
end

-- ---------------------------------------------------------------- patch sets
local CROUCH = { { 0x004F9944, "\x7A\x64", "\x90\x90" } }
local MELEE = {
  { 0x0097C7BC, "\xE8\xEF\x87\xFF\xFF", "\x31\xC0\x90\x90\x90" },
  { 0x0097F29F, "\xE8\x0C\x5D\xFF\xFF", "\x31\xC0\x90\x90\x90" },
  { 0x00974D01, "\xE8\x5A\xE6\xFF\xFF", "\xB0\x01\x90\x90\x90" },
}
local CAR_RELOAD = { { 0x004F61DC, "\x00\x01\x82\x00", "\x00\x01\xC2\x00" } }
local DRIVEBY = { { 0x00498689, "\xD9\x1D\x58\x5C\x5F\x02", "\xDD\xD8\x90\x90\x90\x90" } }
local BARS = { { 0x0075A265, "\xE8\x16\xB9\xFF\xFF", "\x90\x90\x90\x90\x90" } }
local TUTORIALS = { { 0x006B7260, "\x55", "\xC3" } }
local SPRINT_FIRE = { { 0x004F8B45, "\xE8\x06\x57\x49\x00", "\x31\xC0\x90\x90\x90" } }
local SPRINT_RELOAD = {
  { 0x009F1A4C, "\x74\x14", "\x75\x14" },
  { 0x009F1A9C, "\xE8\x9F\x73\xFD\xFF", "\x90\x90\x90\x90\x90" },
  { 0x009F1ACE, "\xE8\xED\xEC\xF7\xFF", "\x90\x90\x90\x90\x90" },
}
local CLIMB_CAM = {
  { 0x0049BD70, "\xD9\x1D\x58\x5C\x5F\x02", "\xDD\xD8\x90\x90\x90\x90" },
  { 0x0049BD9C, "\xD9\x1D\x78\x5C\x5F\x02", "\xDD\xD8\x90\x90\x90\x90" },
}
local SWITCH_ANY = { { 0x004F7F1E, "\xF6\x86", "\xEB\x21" } }
local DISARM = {
  { 0x009AC517, "\x8B\xC6\xE8\x22\x70\xFB\xFF\x84\xC0\x75\x09", string.rep("\x90", 11) },
  { 0x009AC52B, "\x6A\x01\x56\xE8\xAD\x9C\xFB\xFF", string.rep("\x90", 8) },
  { 0x009C3AB8, "\x75\x0C", "\xEB\x0C" },
}
local VIGNETTE = { { 0x00E0C62C, "vignette\0", string.rep("\x90", 9) } }
local CUTSCENE_PAUSE = {
  { 0x0068CAA0, "\x75\x58", "\x90\x90" },
  { 0x006D8E0A, "\x0F\x85\x5F\x01\x00\x00", "\xE9\x60\x01\x00\x00\x90" },
}

-- ---------------------------------------------------------------- driving camera
-- How long the camera holds where you put it before swinging back behind the
-- car: the game's delay is the vehicle's own seconds (vehicle info +0x4AC
-- moving, +0x4A8 stopped) x 1000 ms; the patched multiplies read our cells,
-- set each frame so the delay comes out at the row's seconds.
local HOLD_ALWAYS = 10.5   -- (one step past 10 s: never resets)
local AUTOCENTER = {
  { 0x0049EA46, "\xD8\xC0\xE5\x00", a32(CELL + 8) },
  { 0x0049EA12, "\xD8\xC0\xE5\x00", a32(CELL + 16) },
}
local function fmthold(v) return v >= HOLD_ALWAYS and "Always" or string.format("%.1f s", v) end
local function vehicle_info()
  local p = G.player()
  local h = G.vehicle_handle(p)
  if not h then return nil end
  local veh = read_u32(0x02149C64 + (h & 0xFFF) * 16)
  if veh == 0 or read_u32(veh + 0x44) ~= h then return nil end
  local info = read_u32(veh + 0x84E4)
  return info ~= 0 and info or nil, veh
end
local function hold_cell(cell, seconds, own)
  if seconds >= HOLD_ALWAYS then write_f64(cell, 1e7)
  elseif own and own > 0 then write_f64(cell, seconds * 1000 / own)
  else write_f64(cell, 1000) end
end
local function camera_hold()
  local free = F.on("car_free_cam")
  local moving = free and HOLD_ALWAYS or (F.enabled and F.items.car_cam_reset.v or 3.0)
  local stopped = free and HOLD_ALWAYS or (F.enabled and F.items.car_cam_reset_stopped.v or 0.5)
  local info = vehicle_info()
  hold_cell(CELL + 8, moving, info and read_f32(info + 0x4AC))
  hold_cell(CELL + 16, stopped, info and read_f32(info + 0x4A8))
end
local function hold_wanted()
  return F.on("car_free_cam") or (F.enabled and (F.items.car_cam_reset.v ~= F.items.car_cam_reset.default
    or F.items.car_cam_reset_stopped.v ~= F.items.car_cam_reset_stopped.default))
end

-- ---------------------------------------------------------------- field of view
-- The game's FOV getter widens the camera's FOV for widescreen by a constant;
-- pointed at our cell, that constant becomes ours: the multiplier (and the
-- speed widening) on top of the game's.
local FOV = {
  { 0x00494047, "\x08\xC8\xE5\x00", a32(CELL) },
  { 0x004940AD, "\x74\x0C", "\x90\x90" },
}
local function fov_cell(mult)
  local base = (read_u8(0x025272DD) ~= 0) and 1.33333337306976 or 1.0
  write_f64(CELL, base * mult)
end
-- Vehicle speed (m/s) through the game's velocity call.
local function vehicle_speed(veh)
  local out = wml.buffer(14)
  wml.callx(0x00AA5150, { ecx = veh }, out, 0xFFFFFFFF)
  local x, y, z = read_f32(out), read_f32(out + 4), read_f32(out + 8)
  return math.sqrt(x * x + y * y + z * z)
end
local function fov_frame()
  local mult = F.on("fov") and F.items.fov.v or 1.0
  if F.on("first_person") and G.player() ~= 0 and not G.vehicle_handle(G.player()) then
    mult = F.items.first_person_fov.v or 1.0
  end
  if F.on("speed_fov") and F.items.speed_fov.v ~= 90 then
    local info, veh = vehicle_info()
    if info then
      local top = read_f32(info + 0x5B8)   -- top speed, m/s
      local s = top > 1 and math.min(1, vehicle_speed(veh) / top) or 0
      mult = mult * (1 + s * (F.items.speed_fov.v / 90 - 1))
    end
  end
  -- (the free camera's zoom, RB / LB, on top)
  local FC = package.loaded.freecam
  if FC and FC.on then mult = mult * (FC.zoom or 1) end
  return mult
end

-- ---------------------------------------------------------------- first person
-- The on-foot camera pulled into your chest (as Juiced Patch's first-person
-- camera does): the walking camera's zoom in its camera-state table
-- (0x025F6318, 0x2C a state; state 0 = on foot outside, whose zoom is
-- 0x025F6334) held at the row's depth, the state kept at 0 (the game
-- switches to running / indoor states, 1, 2, 0x10, 0x17, with their own
-- zooms), and the fade that hides you when the camera is close switched off.
-- Mouse look and aiming stay the game's own. On foot only: in a car the
-- game's own camera is left alone.
local FP_ZOOM, FP_STATE, FP_FADE = 0x025F6334, 0x00E9A5BC, 0x00E8825F
local FP_STATES = { [1] = true, [2] = true, [0x10] = true, [0x17] = true }
local function first_person_frame(p, depth)
  if read_f32(FP_ZOOM) ~= depth then hold_u32(FP_ZOOM, true, string.unpack("<I4", string.pack("<f", depth))) end
  if read_u8(FP_FADE) ~= 0 then hold_u8(FP_FADE, true, 0) end
  if FP_STATES[read_u32(FP_STATE)] then write_u32(FP_STATE, 0) end
end
local function first_person_off()
  hold_u32(FP_ZOOM, false); hold_u8(FP_FADE, false)
end

-- ---------------------------------------------------------------- camera turn speed
local MOUSE = {
  { 0x00C136A6, "\x98\x5C\x5F\x02", a32(CELL + 28) },
  { 0x00C136C4, "\x9C\x5C\x5F\x02", a32(CELL + 32) },
}
local function mouse_cells(k)
  write_f32(CELL + 28, read_f32(0x025F5C98) * k)
  write_f32(CELL + 32, read_f32(0x025F5C9C) * k)
end

-- ---------------------------------------------------------------- map arrow
local MAP = {
  { 0x007A3C0B, "\x0F\x84\x84\x00\x00\x00", "\x90\x90\x90\x90\x90\x90" },
  { 0x007A3C4B, "\x20\x86\x52\x02", a32(CELL + 36) },
  { 0x007704A0, "\xD9\x44\x24\x34\xDC\x05\x60\xC1\xE5\x00", "\xD9\x05" .. a32(CELL + 40) .. "\x90\x90\x90\x90" },
}
local TWO_PI = 2 * math.pi
local function wrap(a) a = math.fmod(a, TWO_PI); if a < 0 then a = a + TWO_PI end; return a end
local function map_cells()
  local p, M = read_u32(G.PLAYER), read_f32(0x02528620)
  if p == 0 then write_f32(CELL + 36, M); write_f32(CELL + 40, 0) return end
  local pA = math.pi - math.atan(read_f32(p + 0x38), read_f32(p + 0x40))
  if read_u8(0x02528615) ~= 0 then write_f32(CELL + 36, M) else write_f32(CELL + 36, -wrap(M - pA)) end
  write_f32(CELL + 40, wrap(-pA))
end

-- ---------------------------------------------------------------- cutscene pause
local cs_paused = false
local function cs_pause(on)
  if on == cs_paused then return end
  if on then
    apply("cutscene_pause_patch", CUTSCENE_PAUSE, true)
    wml.call(0x007540D0, 1, 0, 0, 0)
  else
    wml.call(0x00754270)
    apply("cutscene_pause_patch", CUTSCENE_PAUSE, false)
  end
  cs_paused = on
end
local BACK = 0x20   -- XInput Back
local function back_hit()
  return ((F.pad & BACK) ~= 0 and (F.pad_prev & BACK) == 0) or wml.key_pressed("TAB")
end

-- ---------------------------------------------------------------- load last save
local menu_since   -- when the main menu (no game loaded) was first seen
local last_save_done = false

-- ---------------------------------------------------------------- aiming, bloom, the shoulder camera
-- The camera mode (0x00E9A5BC): 0 on foot, 1/2/0x17 running/indoor/sprint,
-- 0x10 Fine Aim, 0x11 Fine Aim crouched. Each mode's camera row is
-- 0x025F6318 + mode * 0x2C (+0x04 height, +0x14 FOV in degrees, +0x28 side
-- offset); the game reads a row when it changes mode, so a change shows the
-- next time the camera changes mode. The camera's live copy (0x00E9A638, the
-- same layout) is read every frame.
local CAM_TABLE, CAM_LIVE, CAM_ROW = 0x025F6318, 0x00E9A638, 0x2C
local function cam_mode() return read_u32(FP_STATE) end
local function aiming() local m = cam_mode() return m == 0x10 or m == 0x11 end
local fsaved = {}
local function hold_f32(addr, on, value)
  if on then
    if fsaved[addr] == nil then fsaved[addr] = read_f32(addr) end
    write_f32(addr, value)
  elseif fsaved[addr] ~= nil then write_f32(addr, fsaved[addr]); fsaved[addr] = nil end
end
-- The game's own value of something held.
local function own_f32(addr) if fsaved[addr] ~= nil then return fsaved[addr] end return read_f32(addr) end
local function value_on(id)
  local it = F.items[id]
  return F.enabled and it and math.abs(it.v - it.default) > 1e-6 and it.v or nil
end

-- Fine Aim zoom: the two Fine Aim rows' FOV times the row (lower = closer).
local AIM_MODES = { 0x10, 0x11 }
local function aim_zoom_frame()
  local k = value_on("fine_aim_zoom")
  for _, m in ipairs(AIM_MODES) do
    local a = CAM_TABLE + m * CAM_ROW + 0x14
    hold_f32(a, k ~= nil, k and own_f32(a) * k)
  end
end

-- Fine Aim spread: the held gun's Fine Aim spread multiplier (its record
-- +0x1BC, scaling its min and max spread while you aim; the record as
-- gameplay.lua's held_weapon finds it). Only your aim uses it.
local spread_rec
local function held_record(p)
  if p == 0 then return nil end
  local item = read_u32(p + 0x10CC); if item == 0 then return nil end
  local w = read_u32(item + 0xC4); if w == 0 then return nil end
  local rec = read_u32(w + 8)
  return rec ~= 0 and rec or nil
end
local function aim_spread_frame(p)
  local k = value_on("fine_aim_spread")
  local rec = k and held_record(p) or nil
  if spread_rec and spread_rec ~= rec then hold_f32(spread_rec + 0x1BC, false) end
  spread_rec = rec
  if rec then hold_f32(rec + 0x1BC, true, own_f32(rec + 0x1BC) * k) end
end

-- Turn speed: Camera turn speed always, Fine Aim turn speed on top while you
-- aim. The mouse through the two cells; the stick through the camera's pan
-- speeds (horizontal 0x00E99978 / 0x00E99980, vertical 0x00E9997C /
-- 0x00E99984), scaled only while aiming.
local PAN = { 0x00E99978, 0x00E99980, 0x00E9997C, 0x00E99984 }
local function turn_frame()
  local cam = value_on("camera_turn") or 1
  local aim_k = value_on("fine_aim_turn")
  local aim = aim_k ~= nil and aiming()
  local k = cam * (aim and aim_k or 1)
  if k ~= 1 then mouse_cells(k) apply("camera_turn", MOUSE, true) else apply("camera_turn", MOUSE, false) end
  for _, a in ipairs(PAN) do hold_f32(a, aim, aim and own_f32(a) * aim_k) end
end

-- Bloom: the time of day's bloom strength and radius scales (0x00E99698,
-- 0x00E99690; worked out again every frame) are loaded by two instructions
-- that build the frame's bloom request; pointed at two cells, the row scales
-- them. 0 switches bloom off (no radius: the renderer skips it).
local BLOOM = {
  { 0x004DA3E4, "\xD9\x05\x98\x96\xE9\x00", "\xD9\x05" .. a32(CELL + 48) },
  { 0x004DA379, "\xD9\x05\x90\x96\xE9\x00", "\xD9\x05" .. a32(CELL + 52) },
}
local function bloom_frame()
  local k = value_on("bloom")
  if not k then apply("bloom", BLOOM, false) return end
  write_f32(CELL + 48, read_f32(0x00E99698) * k)
  write_f32(CELL + 52, k > 0 and read_f32(0x00E99690) or 0)
  apply("bloom", BLOOM, true)
end

-- Over the shoulder: the on-foot camera rows (standing, running, indoors,
-- sprinting) moved sideways and up; the live copy follows while in one.
local FOOT_MODES = { [0] = true, [1] = true, [2] = true, [0x17] = true }
local function shoulder_frame()
  local side, up = value_on("shoulder_offset"), value_on("camera_height")
  for m in pairs(FOOT_MODES) do
    local row = CAM_TABLE + m * CAM_ROW
    hold_f32(row + 0x28, side ~= nil, side and own_f32(row + 0x28) + side)
    hold_f32(row + 0x04, up ~= nil, up and own_f32(row + 0x04) + up)
  end
  local m = cam_mode()
  if FOOT_MODES[m] and (side or up or fsaved.shoulder_live) then
    local row = CAM_TABLE + m * CAM_ROW
    write_f32(CAM_LIVE + 0x28, read_f32(row + 0x28))
    write_f32(CAM_LIVE + 0x04, read_f32(row + 0x04))
    fsaved.shoulder_live = (side or up) and true or nil
  end
end

-- ---------------------------------------------------------------- the rows
function Q.setup(features)
  F = features

  F.add_rows("Player", nil, {
    patch_row("crouch_moving", "Crouch while moving",
      "Crouch while walking or running, on the keyboard too. (Not straight out of a sprint.)", CROUCH, S("crouch_while_moving", true)),
    patch_row("sprint_on_fire", "Sprint while on fire", "Sprint even when you're burning, as in SR1.", SPRINT_FIRE,
      S("sprint_while_on_fire", false)),
    patch_row("disarm_ragdoll", "Drop your weapon when knocked down", "Knocked over, you drop what you hold, like everyone else.",
      DISARM, S("disarm_on_ragdoll", false)),
  })

  F.add_rows("Weapons", nil, {
    patch_row("no_melee_lock", "No melee lock-on",
      "Punching no longer turns you to face someone standing close: you hit where you face. Takedowns need it, so they're off too, and so is everyone's lock-on.",
      MELEE, S("no_melee_lock_on", false)),
    patch_row("car_reload", "Reload in cars", "Reload while driving or riding, with your usual reload button. From the next time you get in.",
      CAR_RELOAD, S("reload_in_cars", false)),
    patch_row("reload_sprint", "Reload while sprinting", "Reload on the run, as in SR1.", SPRINT_RELOAD, S("reload_while_sprinting", false)),
    patch_row("switch_any", "Switch weapons any time", "Change weapons while sprinting and in other moves the game blocks.",
      SWITCH_ANY, S("weapon_switch_any_time", false)),
    -- (applied every frame in Q.after_update)
    { id = "fine_aim_zoom", label = "Fine Aim zoom", kind = "value", needs = "none", default = 1.0, min = 0.3, max = 1.5, step = 0.05,
      fmt = F.fmtx, help = "How close Fine Aim (the aim button) brings the camera: lower is closer (x1 = the game's own). Shows from your next aim." },
    { id = "fine_aim_spread", label = "Fine Aim spread", kind = "value", needs = "none", default = 1.0, min = 0, max = 1.5, step = 0.05,
      fmt = F.fmtx, help = "How much your gun's shots spread while you aim with it (x0 = dead on, x1 = the game's own). Your aim only." },
    { id = "fine_aim_turn", label = "Fine Aim turn speed", kind = "value", needs = "none", default = 1.0, min = 0.1, max = 2.0, step = 0.05,
      fmt = F.fmtx, help = "How fast the mouse and stick turn while you aim (x1 = as when not aiming). Lower steadies the aim." },
  })

  F.add_rows("Vehicles", nil, {
    { id = "car_free_cam", label = "Free camera in cars", kind = "toggle", needs = "none", v = S("car_free_camera", true),
      help = "Move the camera and it keeps looking that way: the car turns under it. Switches off follows the nose and the drive-by camera.",
      update = function() end },
    { id = "car_cam_reset", label = "Camera resets after", kind = "value", needs = "none", default = 3.0, min = 0.5, max = HOLD_ALWAYS,
      step = 0.5, fmt = fmthold, v = S("car_camera_reset_after", 3.0),
      help = "How long after you stop moving it before the camera follows the car again. Always: never, fully free (game: the car's own, about 3 s)." },
    { id = "car_cam_reset_stopped", label = "Camera resets after, stopped", kind = "value", needs = "none", default = 0.5, min = 0.5,
      max = HOLD_ALWAYS, step = 0.5, fmt = fmthold, v = S("car_camera_reset_after_stopped", 0.5),
      help = "The same while the car stands still (game: about 0.5 s)." },
    { id = "car_cam_follow", label = "Camera swing-back speed", kind = "value", needs = "none", default = 1.0, min = 0.25, max = 4,
      step = 0.25, fmt = F.fmtx, v = S("car_camera_swing_back", 1.0),
      help = "How fast the camera swings back behind the car (game: x1).",
      update = function(ctx, p, v, it)
        write_f32(CELL + 24, it.v)
        apply("car_cam_follow", { { 0x004974FD, "\xB0\x5C\x5F\x02", a32(CELL + 24) } }, true)
      end,
      off = function() apply("car_cam_follow", { { 0x004974FD, "\xB0\x5C\x5F\x02", a32(CELL + 24) } }, false) end },
    { id = "car_cam_nose", label = "Camera follows the nose", kind = "toggle", needs = "none", v = S("car_camera_follows_nose", false),
      help = "The camera stays behind the car in a handbrake slide instead of swinging towards the slide. Not with the free camera.",
      update = function() hold_u8(0x00E99886, not F.on("car_free_cam"), 0) end,
      off = function() hold_u8(0x00E99886, false) end },
    { id = "driveby_cam", label = "Free drive-by camera", kind = "toggle", needs = "none", v = S("drive_by_free_camera", false),
      help = "During a drive-by the camera stays where you aim instead of swinging back behind the car. Not with the free camera.",
      update = function() apply("driveby_cam", DRIVEBY, not F.on("car_free_cam")) end,
      off = function() apply("driveby_cam", DRIVEBY, false) end },
    { id = "higher_max_speed", label = "No 100 mph limit", kind = "toggle", needs = "none", v = S("higher_max_speed", false),
      saved_now = true,
      help = "The game caps every vehicle's top speed at 100 mph as it loads them: this lifts the cap. From the next start.",
      change = function(ctx, p, v, it) F.save_setting("higher_max_speed", it.v) end },
    { id = "speed_fov", label = "Field of view at top speed", kind = "value", needs = "none", default = 90, min = 60, max = 130, step = 5,
      fmt = F.fmtint, v = S("speed_fov", 90),
      help = "How wide the driving camera gets at top speed (game: 90, no change)." },
  })

  F.add_rows("Visual", nil, {
    { id = "fov", label = "Field of view", kind = "value", needs = "none", default = 1.0, min = 0.5, max = 2.0, step = 0.05,
      fmt = F.fmtx, v = S("field_of_view", 1.0),
      help = "Widens the normal camera, on foot and driving. Cutscenes keep the game's own." },
    { id = "first_person", label = "First-person view", kind = "toggle", v = S("first_person", false),
      help = "See through your own eyes on foot: aim, shoot and look about as usual. Experimental. Set the field of view and depth below.",
      update = function(ctx, p, v)
        if v ~= 0 or G.in_cutscene() then first_person_off() return end
        first_person_frame(p, F.items.first_person_depth.v or -0.6)
      end,
      off = function() first_person_off() end },
    { id = "first_person_fov", label = "First-person field of view", kind = "value", needs = "none", default = 1.2, min = 0.6, max = 2.0,
      step = 0.05, fmt = F.fmtx, oneshot = true, v = S("first_person_fov", 1.2),
      hidden = function() return not F.items.first_person.v end,
      help = "How wide you see in first person (x1 = the game's own; higher = zoomed out, more on screen)." },
    { id = "first_person_depth", label = "First-person camera depth", kind = "value", needs = "none", default = -0.6, min = -1.5, max = 0.5,
      step = 0.1, fmt = function(v) return string.format("%.1f", v) end, oneshot = true, v = S("first_person_depth", -0.6),
      hidden = function() return not F.items.first_person.v end,
      help = "Where the camera sits: lower is further into you (-0.6 = your eyes, about), higher pulls it back out over your shoulder." },
    { id = "camera_turn", label = "Camera turn speed", kind = "value", needs = "none", default = 1.0, min = 0.5, max = 2.0, step = 0.1,
      fmt = F.fmtx, v = S("camera_turn_speed", 1.0),
      help = "How fast the mouse turns the camera, on top of the game's own sensitivity (Options > Controls)." },
    { id = "shoulder_offset", label = "Camera side offset", kind = "value", needs = "none", default = 0, min = -1.5, max = 1.5, step = 0.05,
      fmt = function(v) return v == 0 and "game's own" or string.format("%+.2f m", v) end,
      help = "Moves the on-foot camera sideways, over your shoulder (right is +). Shows from the next camera change: start or stop running." },
    { id = "camera_height", label = "Camera height", kind = "value", needs = "none", default = 0, min = -1.0, max = 1.0, step = 0.05,
      fmt = function(v) return v == 0 and "game's own" or string.format("%+.2f m", v) end,
      help = "Raises or lowers the on-foot camera." },
    { id = "bloom", label = "Bloom", kind = "value", needs = "none", default = 1.0, min = 0, max = 2.0, step = 0.1,
      fmt = function(v) return v == 0 and "off" or string.format("x%.1f", v) end,
      help = "The glow round bright light: 0 is off, x1 the game's own, x2 twice as strong." },
    { id = "map_arrow", label = "Map arrow shows where you face", kind = "toggle", needs = "none", v = S("map_arrow_follows_player", false),
      help = "On the turning minimap and the pause map, the arrow points the way you face, not the camera.",
      update = function() map_cells(); apply("map_arrow", MAP, true) end,
      off = function() apply("map_arrow", MAP, false) end },
    patch_row("no_black_bars", "No cutscene black bars", "Cutscenes fill the screen.", BARS, S("no_black_bars", false)),
    patch_row("no_climb_cam", "No camera lock when climbing", "The camera stays yours when you climb or vault.", CLIMB_CAM,
      S("no_climb_camera_lock", false)),
    { id = "no_sprint_shake", label = "No sprint camera shake", kind = "toggle", needs = "none", v = S("no_sprint_shake", false),
      help = "The camera doesn't shake while you sprint.",
      update = function() hold_u32(0x00E997FC, true, 0) end,
      off = function() hold_u32(0x00E997FC, false) end },
    { id = "no_screen_blur", label = "No screen blur", kind = "toggle", needs = "none", v = S("no_screen_blur", false),
      help = "Turns off the game's soft blur over the whole picture.",
      update = function() hold_u8(0x02527297, true, 0) end,
      off = function() hold_u8(0x02527297, false) end },
    patch_row("no_vignette", "No vignette", "No dark corners on the screen (from the next time the game sets them up).",
      VIGNETTE, S("no_vignette", false)),
  })

  F.add_rows("Settings", nil, {
    { id = "skip_intro", label = "Skip intro", kind = "toggle", needs = "none", v = S("skip_intro", false), saved_now = true,
      help = "No logo movies and no legal screens. From the next start.",
      change = function(ctx, p, v, it) F.save_setting("skip_intro", it.v) end },
    { id = "load_last_save", label = "Load last save", kind = "toggle", needs = "none", v = S("load_last_save", false), saved_now = true,
      help = "The main menu loads your newest save after a few seconds. From the next start.",
      change = function(ctx, p, v, it) F.save_setting("load_last_save", it.v) end },
    { id = "load_wait", label = "Load last save after", kind = "value", needs = "none", default = 3, min = 0.5, max = 10, step = 0.5,
      fmt = function(v) return string.format("%.1f s", v) end, v = S("load_last_save_wait", 3), saved_now = true, oneshot = true,
      help = "How long the main menu waits before loading.",
      change = function(ctx, p, v, it) F.save_setting("load_last_save_wait", it.v) end },
    { id = "cutscene_pause", label = "Pause cutscenes", kind = "toggle", needs = "none", v = S("cutscene_pause", false),
      help = "Back (Tab) pauses a cutscene; again carries on.",
      update = function()
        local in_cs = G.in_cutscene()
        if cs_paused and not in_cs then cs_pause(false)
        elseif in_cs and not F.menu_open() and back_hit() and (wml.call(0x007F7AD0) & 0xFF) == 0 then cs_pause(not cs_paused) end
      end,
      off = function() cs_pause(false) end },
    patch_row("no_tutorials", "No tutorial popups", "No \"Press X to ...\" popups.", TUTORIALS, S("no_tutorials", false)),
  })
end

-- Every frame, after the rows: the camera cells and the start-up load.
function Q.after_update(p)
  -- Aiming, turn speed, bloom and the shoulder camera.
  aim_zoom_frame()
  aim_spread_frame(p)
  turn_frame()
  bloom_frame()
  shoulder_frame()
  -- Driving camera hold.
  if hold_wanted() then camera_hold(); apply("autocenter", AUTOCENTER, true) else apply("autocenter", AUTOCENTER, false) end
  -- Field of view (the multiplier and the speed widening together): through
  -- the host's wrap of the game's field of view getter. Juiced Patch
  -- (FOVMultiplier, FixUltrawideFOV) changes the instruction the old patch
  -- pointed at our cell, so that patch is only the fallback without the wrap.
  local mult = fov_frame()
  if wml.set_fov(mult) then apply("fov_patch", FOV, false)
  elseif mult ~= 1.0 then fov_cell(mult) apply("fov_patch", FOV, true)
  else apply("fov_patch", FOV, false) end
  -- Load last save: once, on the main menu, after the wait; any key or
  -- button meanwhile keeps the menu.
  if F.items.load_last_save.v and not last_save_done then
    if read_u8(G.GAME_LOADED) == 1 then last_save_done = true
    elseif menu_since or (F.tick % 30 == 0 and select(2, wml.vint("tweak_out(type(main_menu_continue_select))")) == "function") then
      -- (the main menu's script is loaded: the menu is up)
      menu_since = menu_since or os.clock()
      if F.pad ~= 0 then last_save_done = true end
      if not last_save_done and os.clock() - menu_since >= F.items.load_wait.v then
        last_save_done = true
        write_u8(0x025283BC, 1); write_u8(0x025283BD, 1); write_u8(0x025283BE, 1)
        wml.call(0x007790E0)
        wml.log("load last save: loading")
      end
    end
  end
end

return Q

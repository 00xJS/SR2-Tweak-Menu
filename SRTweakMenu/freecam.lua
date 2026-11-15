-- SR Tweak Menu (Saints Row 2) - free camera, SR1's (freecam.lua) on SR2's
-- camera.
--
-- SR2's camera mode 2 leaves the camera to its globals (position 0x025F5B20,
-- orientation 0x025F5B5C: rows right, up, forward, as every object's), so
-- flying is writing them every frame. Controls as on SR1:
--   look      right stick (I J K L on the keyboard)
--   move      left stick / W A S D, along where the camera faces
--   up, down  right trigger / left trigger (E or Space / Q or Ctrl)
--   zoom      RB in, LB out (X / Z)
--   faster    Shift x4 (left stick click on a pad), slower Alt x0.25
--   A / Enter play from this shot (Fixed shot)
-- Fixed shot: the camera stays where it is and you play on in front of it;
-- Tracking shot: it stays put and turns to keep you in frame. The world only
-- streams round the player, so the camera keeps within 150 m of them (and in
-- a shot, too far away gives the normal camera back). While flying the game
-- gets no pad (main.lua) and the keys above are taken from it.

local G = require("game")

local FC = { on = false, mode = 1, zoom = 1.0 }
FC.MODES = { "Fly", "Fixed shot", "Tracking shot" }
local FLY, FIXED, TRACK = 1, 2, 3

local CAM_MODE, CAM_POS, CAM_ORIENT = 0x025F5AE8, 0x025F5B20, 0x025F5B5C
-- (while a shot is held the world streams round the player, not the camera: the streaming centre's mode test)
local STREAM_TEST = { 0x009DF503, "\x0F\x85\xA6\x02\x00\x00", "\x90\x90\x90\x90\x90\x90" }
local KEYS = { "W", "A", "S", "D", "Q", "E", "I", "J", "K", "L", "Z", "X", "SPACE", "SHIFT", "CTRL", "ALT", "ENTER" }
local LEASH = 150
local PAD_A, PAD_LB, PAD_RB, PAD_LS = 0x1000, 0x0100, 0x0200, 0x0040

local read_f32, write_f32, read_u32, write_u32 = wml.read_f32, wml.write_f32, wml.read_u32, wml.write_u32
local function put(a, v) write_f32(a, v[1]); write_f32(a + 4, v[2]); write_f32(a + 8, v[3]) end
local function get(a) return { read_f32(a), read_f32(a + 4), read_f32(a + 8) } end

-- Rows from yaw (positive turns right) and pitch (positive looks up).
local function rows(yaw, pitch)
  local cp, sp, cy, sy = math.cos(pitch), math.sin(pitch), math.cos(yaw), math.sin(yaw)
  local f = { sy * cp, sp, cy * cp }
  local r = { cy, 0, -sy }
  local u = { f[2] * r[3] - f[3] * r[2], f[3] * r[1] - f[1] * r[3], f[1] * r[2] - f[2] * r[1] }
  return r, u, f
end
local function put_pose(pos, r, u, f)
  put(CAM_POS, pos)
  put(CAM_ORIENT, r); put(CAM_ORIENT + 12, u); put(CAM_ORIENT + 24, f)
end

local taken = false
local function take_keys(on)
  if taken == on then return end
  taken = on
  for _, k in ipairs(KEYS) do pcall(wml.take_key, k, on) end
end
local streaming_held = false
local function hold_streaming(on)
  if on == streaming_held then return end
  streaming_held = on
  wml.patch(STREAM_TEST[1], on and STREAM_TEST[3] or STREAM_TEST[2])
end

function FC.flying() return FC.on and FC.mode == FLY end
function FC.set_mode(m) FC.mode = m or FLY end

function FC.enter()
  local p = G.player()
  if p == 0 or G.in_cutscene() then return false end
  FC.pos = get(CAM_POS)
  local f = get(CAM_ORIENT + 24)
  FC.yaw = math.atan(f[1], f[3])
  FC.pitch = math.asin(math.max(-1, math.min(1, f[2])))
  FC.zoom = 1.0
  FC.clock = os.clock()
  FC.prev_a = true
  FC.on = true
  write_u32(CAM_MODE, 2)
  return true
end

function FC.exit(why)
  if not FC.on then return end
  FC.on = false
  FC.zoom = 1.0
  take_keys(false)
  hold_streaming(false)
  write_u32(CAM_MODE, G.in_cutscene() and 5 or 0)
  FC.why = why
end

local function key(k) local ok, d = pcall(wml.key_down, k) return ok and d end
local function axis(v) return math.abs(v) < 0.24 and 0 or v end

-- ---------------------------------------------------------------- the orbit (SR1's)
-- Customize and Emotes: the camera in front of you, you on the right of the
-- screen and the menu on the left. Right stick (I J K L) turns it round you and
-- raises or lowers it, left stick slides the view, the triggers (Z / X) move
-- it in and out. Where you slid it stays for next time.
FC.ORBIT = { dist = 2.4, height = 1.0, min_dist = 0.6, max_dist = 4.5, aside = 0.38, pan_max = 2.5 }
function FC.orbit(on, facing, movement)
  if on then
    movement = movement == true
    if not FC.orbiting then
      if FC.on or G.player() == 0 or G.in_cutscene() then return false end
      FC.saved_mode = read_u32(CAM_MODE)
      FC.orbit_yaw = facing or 0
      FC.oclock = os.clock()
      FC.orbiting = true
      write_u32(CAM_MODE, 2)
    end
    if FC.orbit_movement ~= movement then
      -- Reset the framing on entry so a close-up from Customize can't crop the feet.
      FC.orbit_dist = movement and 3.8 or FC.ORBIT.dist
      FC.orbit_h = movement and 0.9 or FC.ORBIT.height
      FC.pan_x, FC.pan_y = 0, 0
      FC.orbit_movement = movement
    end
  elseif FC.orbiting then
    FC.orbiting = false
    FC.orbit_movement = nil
    FC.zoom = 1.0
    if not FC.on then write_u32(CAM_MODE, G.in_cutscene() and 5 or 0) end
  end
  return FC.orbiting
end
local function update_orbit()
  local p = G.player()
  if p == 0 or G.in_cutscene() then FC.orbit(false) return end
  if read_u32(CAM_MODE) ~= 2 then write_u32(CAM_MODE, 2) end
  local now = os.clock()
  local dt = math.max(0, math.min(0.05, now - FC.oclock))
  FC.oclock = now
  local o = FC.ORBIT
  if FC.orbit_vehicle ~= FC.vehicle_preview then
    FC.orbit_vehicle = FC.vehicle_preview
    FC.orbit_dist = FC.vehicle_preview and 5.0 or o.dist
    FC.pan_x, FC.pan_y = 0, 0
  end
  local lx, ly, rx, ry = 0, 0, 0, 0
  local ok, a, b, c, d = pcall(wml.sticks)
  if ok then lx, ly, rx, ry = axis(a or 0), axis(b or 0), axis(c or 0), axis(d or 0) end
  local _, lt, rt = wml.pad()
  lt, rt = lt or 0, rt or 0
  lx = lx + (key("D") and 1 or 0) - (key("A") and 1 or 0)
  ly = ly + (key("W") and 1 or 0) - (key("S") and 1 or 0)
  rx = rx + (key("L") and 1 or 0) - (key("J") and 1 or 0)
  ry = ry + (key("I") and 1 or 0) - (key("K") and 1 or 0)
  FC.orbit_yaw = FC.orbit_yaw + rx * 2.0 * dt
  FC.orbit_h = math.max(0.15, math.min(1.85, FC.orbit_h + ry * 1.2 * dt))
  FC.pan_x = math.max(-o.pan_max, math.min(o.pan_max, FC.pan_x + lx * 1.5 * dt))
  FC.pan_y = math.max(-o.pan_max, math.min(o.pan_max, FC.pan_y + ly * 1.5 * dt))
  local zoom = lt / 255 - rt / 255 + ((key("Z") and 1 or 0) - (key("X") and 1 or 0))
  local near, far = FC.vehicle_preview and 1.0 or o.min_dist, FC.vehicle_preview and 12.0 or o.max_dist
  FC.orbit_dist = math.max(near, math.min(far, FC.orbit_dist + zoom * 2.5 * dt))
  local px, py, pz = G.vec(p + G.P.POS)
  if FC.vehicle_preview then
    local preview = FC.vehicle_preview
    if G.vehicle_handle(p) ~= preview.handle then FC.orbit(false) return end
    px, py, pz = G.vec(preview.vehicle + 0x14)
  end
  local target = { px, py + FC.orbit_h, pz }
  local sy, cy = math.sin(FC.orbit_yaw), math.cos(FC.orbit_yaw)
  local lift = 0.1 + FC.orbit_dist * 0.08   -- (a little above the point looked at, more the further back)
  local pos = { target[1] + sy * FC.orbit_dist, target[2] + lift, target[3] + cy * FC.orbit_dist }
  local dx, dy, dz = target[1] - pos[1], target[2] - pos[2], target[3] - pos[3]
  local r, u, f = rows(math.atan(dx, dz), math.atan(dy, math.sqrt(dx * dx + dz * dz)))
  -- Slid sideways (you on the right of the screen) and wherever you moved it.
  local side = o.aside * FC.orbit_dist - FC.pan_x
  for i = 1, 3 do pos[i] = pos[i] - r[i] * side + u[i] * FC.pan_y end
  put_pose(pos, r, u, f)
end

-- Which way a person faces (their forward row's x and z).
function FC.facing_yaw(p)
  local fx, fz = read_f32(p + 0x38), read_f32(p + 0x40)
  if fx * fx + fz * fz < 0.01 then return 0 end
  return math.atan(fx, fz)
end

-- Every frame while on. `paused`: the menu is open (the camera holds still).
function FC.update(paused)
  if FC.orbiting and not FC.on then update_orbit() return end
  if not FC.on then return end
  local p = G.player()
  if p == 0 then FC.exit("No player") return end
  if G.in_cutscene() then FC.exit("Cutscene") return end
  if read_u32(CAM_MODE) ~= 2 then write_u32(CAM_MODE, 2) end
  local now = os.clock()
  local dt = math.max(0, math.min(0.05, now - FC.clock))
  FC.clock = now
  local px, py, pz = G.vec(p + G.P.POS)
  local buttons, lt, rt = wml.pad()
  buttons, lt, rt = buttons or 0, lt or 0, rt or 0
  local lx, ly, rx, ry = 0, 0, 0, 0
  local ok, a, b, c, d = pcall(wml.sticks)
  if ok then lx, ly, rx, ry = axis(a or 0), axis(b or 0), axis(c or 0), axis(d or 0) end

  if FC.mode ~= FLY then
    -- Playing from the shot: the camera holds (and turns to you when tracking).
    take_keys(false)
    hold_streaming(true)
    local dx, dy, dz = px - FC.pos[1], py + 1.0 - FC.pos[2], pz - FC.pos[3]
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > LEASH then FC.exit("Too far from the camera: normal camera back") return end
    if FC.mode == TRACK and dist > 0.5 then
      local yaw, pitch = math.atan(dx, dz), math.asin(dy / dist)
      local turn = (yaw - FC.yaw + math.pi) % (2 * math.pi) - math.pi
      local k = paused and 0 or math.min(1, dt * 6)   -- eases round, not snapping
      FC.yaw = FC.yaw + turn * k
      FC.pitch = FC.pitch + (math.max(-1.5, math.min(1.5, pitch)) - FC.pitch) * k
    end
    local r, u, f = rows(FC.yaw, FC.pitch)
    put_pose(FC.pos, r, u, f)
    return
  end

  hold_streaming(false)
  take_keys(not paused)
  if paused then
    local r, u, f = rows(FC.yaw, FC.pitch)
    put_pose(FC.pos, r, u, f)
    return
  end
  -- A / Enter: play from this shot.
  local okk, enter = pcall(wml.key_pressed, "ENTER")
  local apress = (buttons & PAD_A) ~= 0
  if (okk and enter) or (apress and not FC.prev_a) then
    FC.prev_a = apress
    FC.mode = FIXED
    FC.shot_taken = true
    return FC.update(paused)
  end
  FC.prev_a = apress
  -- Look: right stick (I J K L).
  local turn = 2.2 * dt * math.max(0.3, FC.zoom)
  FC.yaw = FC.yaw + (rx + (key("L") and 1 or 0) - (key("J") and 1 or 0)) * turn
  FC.pitch = math.max(-1.5, math.min(1.5, FC.pitch + (ry + (key("I") and 1 or 0) - (key("K") and 1 or 0)) * turn * 0.75))
  local r, u, f = rows(FC.yaw, FC.pitch)
  -- Move: left stick / WASD; up and down: triggers / E, Space and Q, Ctrl.
  local mf = (key("W") and 1 or 0) - (key("S") and 1 or 0) + ly
  local mr = (key("D") and 1 or 0) - (key("A") and 1 or 0) + lx
  local mu = ((key("E") or key("SPACE")) and 1 or 0) - ((key("Q") or key("CTRL")) and 1 or 0) + rt / 255 - lt / 255
  local fast = key("SHIFT") or (buttons & PAD_LS) ~= 0
  local speed = 8 * (fast and 4 or 1) * (key("ALT") and 0.25 or 1)
  local s = speed * dt
  for i = 1, 3 do FC.pos[i] = FC.pos[i] + (f[i] * mf + r[i] * mr) * s end
  FC.pos[2] = FC.pos[2] + mu * s
  -- Zoom: RB in, LB out (X / Z): the field of view, through the host's wrap (qol.lua).
  local zoom = ((key("X") or (buttons & PAD_RB) ~= 0) and 1 or 0) - ((key("Z") or (buttons & PAD_LB) ~= 0) and 1 or 0)
  FC.zoom = math.max(0.15, math.min(2.5, FC.zoom * (1 - zoom * 0.9 * dt)))
  -- Stay within reach of the player, where the world is loaded.
  local dx, dy, dz = FC.pos[1] - px, FC.pos[2] - py, FC.pos[3] - pz
  local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
  if dist > LEASH then
    local k = LEASH / dist
    FC.pos = { px + dx * k, py + dy * k, pz + dz * k }
  end
  put_pose(FC.pos, r, u, f)
end

return FC

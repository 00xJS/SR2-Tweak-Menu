-- Reborn SR '22 presentation state, driven by SR2's sampled status values.
-- Pure: no hooks, memory writes, HUD ownership, inventory or invented impacts.
local M = {}
local PI = math.pi
local function finite(v) return type(v) == "number" and v == v and math.abs(v) < 1e12 end
local function clamp(v,a,b) return math.max(a,math.min(b,finite(v) and v or a)) end
local function ease(t) t=clamp(t,0,1) return t*t*(3-2*t) end
local function number(v) v=tonumber(v) return finite(v) and v or nil end
local function ammo(text)
  if type(text) ~= "string" or text == "" then return end
  local clip,reserve=text:match("^%s*(.-)%s*/%s*(.-)%s*$")
  clip=clip or text:match("^%s*(.-)%s*$")
  local function line(value)
    if value and value:find("ui_hud_infinity",1,true) then return nil,true end
    return value and value:match("^%d+$") and tonumber(value) or nil,false
  end
  local n,infinite=line(clip)
  local spare,reserve_infinite=line(reserve)
  return n,spare,infinite,reserve_infinite,reserve~=nil
end
function M.ammo_warning(s)
  local n,spare,infinite,reserve_infinite,has_reserve=ammo(s.ammo or s.ammo_text)
  if not n or infinite then return false,false end
  local data=s.weapon_data or {}
  if data.single or not has_reserve then return n+(spare or 0)<=1,false end
  local capacity,maximum=number(data.capacity) or 0,number(data.maximum) or 0
  local low=n==0 or (capacity>1 and n<=math.max(1,math.floor(capacity*.25)))
  local low_total=not reserve_infinite and spare~=nil
    and (spare==0 or (maximum>0 and n+spare<=math.max(1,math.floor(maximum*.1))))
  return low or low_total,low_total
end
local function light(fill,limit,phase,gain,recovery)
  local severity=clamp(1-fill/math.max(.001,limit),0,1)
  local period=1-.5*severity
  local pulse=recovery or (.5+.5*math.cos(phase*2*PI))^3
  return { pulse=pulse*gain, period=period,
    opacity=(44+24*severity+(70+50*severity)*pulse)*gain/255 }
end
local State={}
State.__index=State
function M.new() return setmetatable({},State) end
function State:reset() self.previous,self.camera=nil,nil end
function State:camera_pose(player,now,fx,fy,fz)
  if not finite(now) or not finite(fx) or not finite(fy) or not finite(fz) then self.camera=nil return 0,0 end
  local norm=math.sqrt(fx*fx+fy*fy+fz*fz)
  if norm<.2 or norm>2 then self.camera=nil return 0,0 end
  local yaw,pitch=math.atan(fx,fz),math.asin(clamp(fy/norm,-1,1))
  local c=self.camera
  if not c or c.player~=player or now<c.at or now-c.at>.25 then
    self.camera={player=player,at=now,yaw=yaw,pitch=pitch,x=0,y=0} return 0,0
  end
  local dt=now-c.at
  if dt<=0 then return c.x,c.y end
  local dyaw=math.atan(math.sin(yaw-c.yaw),math.cos(yaw-c.yaw))
  local dp=pitch-c.pitch
  local tx,ty=0,0
  if math.abs(dyaw)<.45 and math.abs(dp)<.4 then tx,ty=clamp(dyaw/dt*.3,-1,1),clamp(dp/dt*.3,-1,1) end
  local blend=1-math.exp(-dt*10)
  c.x,c.y=c.x+(tx-c.x)*blend,c.y+(ty-c.y)*blend
  c.at,c.yaw,c.pitch=now,yaw,pitch
  return c.x,c.y
end
-- Optional read-only adapter. CAM_ORIENT+24 is the forward row already used
-- by SR2 freecam.lua; callers provide the reader rather than a hidden hook.
function State:sample_camera(reader,player,now)
  local at=0x025F5B5C+24
  return self:camera_pose(player,now,reader(at),reader(at+4),reader(at+8))
end
function State:update(s,now)
  assert(type(s)=="table" and finite(now),"HUD state and finite time required")
  local hp,sp=clamp(s.health or 1,0,1),clamp(s.sprint or 1,0,1)
  local m=self.previous
  local discontinuity=not m or m.player~=s.player or m.generation~=s.generation
    or now<m.clock or now-m.clock>.5 or (m.health<=0 and hp>0)
  if discontinuity then
    m={player=s.player,generation=s.generation,clock=now,health=hp,sprint=sp,
      armed=s.armed,alpha=s.armed==false and 0 or 1,visible_until=-1}
    self.previous,self.camera=m,nil
  end
  local dt=clamp(now-m.clock,0,.1)
  local motion=s.motion~=false
  local hurt=not discontinuity and hp<m.health-.0001
  local draining=not discontinuity and sp<m.sprint-.0001
  local running=s.is_sprinting==true or s.sprinting==true or draining
  local health_low=hp>0 and hp<=clamp(s.low_health or .3,.001,1)
  -- SR2 hud_player_status_change flashes sprint while is_sprinting and
  -- delays cooldown by.2s. No unverified SR1 energy threshold is imported.
  local sprint_low=hp>0 and s.sprint_enabled~=false and (running or s.exhausted==true)
  if hurt or running or s.attacking then m.visible_until=now+3 end
  if s.impact_active then m.visible_until=math.max(m.visible_until,now+1) end
  if m.armed==true and s.armed==false then m.wait_for_walk=true m.x,m.z=s.x,s.z end
  if m.wait_for_walk and s.on_foot and finite(s.x) and finite(s.z) and finite(m.x) and finite(m.z)
    and (s.x-m.x)^2+(s.z-m.z)^2>.16 then m.wait_for_walk=false end
  if s.armed then m.wait_for_walk=false end
  if hp<=0 then
    m.health_glow,m.sprint_glow,m.health_release,m.sprint_release=0,0,nil,nil
    m.respect_change,m.shot,m.reloaded=nil,nil,nil
  end
  if health_low then m.health_glow,m.health_release=1,nil
  elseif (m.health_glow or 0)>0 then
    if not m.health_release then
      local beat=s.health_beat
      m.health_release=beat and finite(beat.audible_until) and math.max(now,beat.audible_until) or now
      m.release_pulse=(m.health_light and m.health_light.pulse) or 0
    end
    m.health_glow=1-ease((now-m.health_release)/.65)
  end
  if sprint_low then m.sprint_glow,m.sprint_release=1,nil m.last_sprint=now
  elseif (m.sprint_glow or 0)>0 then
    m.sprint_release=m.sprint_release or math.max(now,(m.last_sprint or now)+.2)
    m.sprint_glow=1-ease((now-m.sprint_release)/.65)
  end
  s.health_glow,s.sprint_glow=m.health_glow or 0,m.sprint_glow or 0
  s.health_warning,s.sprint_warning=s.health_glow>0,s.sprint_glow>0
  s.health_recovering=not health_low
  local severity=clamp(1-hp/(s.low_health or .3),0,1)
  local sprint_severity=1-sp
  m.health_phase=(m.health_phase or 0)+dt/(1-.5*severity)
  m.sprint_phase=(m.sprint_phase or 0)+dt/(1.4-.95*sprint_severity)
  local recovery=not health_low and m.health_release and (m.release_pulse or 0)*math.exp(-math.max(0,now-m.health_release)/.2) or nil
  s.health_light=light(hp,s.low_health or .3,m.health_phase,s.health_glow,recovery)
  local beat=s.health_beat
  if health_low and beat and finite(beat.at) and now>=beat.at then
    s.health_light.pulse=math.exp(-(now-beat.at)/(math.max(.35,beat.period or 1)*.2))*s.health_glow
    s.health_light.opacity=(44+24*severity+(70+50*severity)*s.health_light.pulse)/255
  end
  m.health_light=s.health_light
  local sprint_pulse=(.5+.5*math.cos(m.sprint_phase*2*PI))^3
  s.sprint_light={pulse=sprint_pulse*s.sprint_glow,period=1.4-.95*sprint_severity,
    opacity=(44+24*sprint_severity+(70+50*sprint_severity)*sprint_pulse)*s.sprint_glow/255}
  s.health_phase,s.sprint_phase=m.health_phase,m.sprint_phase
  local respect=number(s.level or s.respect_text)
  if respect and respect>=0 and respect<1e9 then
    respect=math.floor(respect)
    if not discontinuity and hp>0 and m.respect and respect>m.respect then
      m.respect_change={from=tostring(m.respect),at=now}
      m.visible_until=math.max(m.visible_until,now+2)
    elseif m.respect and respect<m.respect then m.respect_change=nil end
    m.respect=respect
  end
  if not motion or hp<=0 or (m.respect_change and now-m.respect_change.at>=1.6) then m.respect_change=nil end
  s.respect_from,s.respect_progress,s.respect_shine=nil,nil,nil
  if m.respect_change then
    local age=now-m.respect_change.at
    s.respect_shine=age/1.6
    if age<.75 then s.respect_from,s.respect_progress=m.respect_change.from,age/.75 end
  end
  local context_known=type(s.armed)=="boolean"
  local visible=not context_known or s.armed or m.wait_for_walk or hurt or running or s.attacking
    or s.health_warning or s.sprint_warning or (s.sprint_enabled~=false and sp<.999) or now<m.visible_until
  if s.native_visible==false or hp<=0 then m.alpha=0
  elseif s.contextual==false or s.armed or not context_known then m.alpha=1
  elseif visible then m.alpha=math.min(1,m.alpha+dt*4)
  else m.alpha=math.max(0,m.alpha-dt*4) end
  s.visibility,s.context_known=m.alpha,context_known
  local clip,spare,infinite,_,has_reserve=ammo(s.ammo or s.ammo_text)
  local icon=s.weapon or s.weapon_icon
  if discontinuity or icon~=m.icon or not clip or hp<=0 then m.shot,m.reloaded=nil,nil
  elseif m.clip and icon==m.icon then
    if clip<m.clip then m.shot=now elseif clip>m.clip then m.reloaded=now end
  end
  s.shot=m.shot and clamp(1-(now-m.shot)/.16,0,1) or 0
  s.reloaded=m.reloaded and clamp(1-(now-m.reloaded)/.28,0,1) or 0
  s.reload_inferred=s.reloaded>0
  s.low_clip,s.low_reserve=M.ammo_warning(s)
  s.ammo_paint=nil
  if hp>0 and clip and not infinite and clip==0 then
    local empty=has_reserve and spare==0
    s.ammo_paint={kind=empty and "empty" or "reload",opacity=(70+65*(.5+.5*math.sin(now*PI*3)))/255,
      rgb=empty and {101/128,8/128,16/128} or {72/128,29/128,94/128}}
  elseif hp>0 and s.reloaded>0 then
    s.ammo_paint={kind="replenished",opacity=80*s.reloaded/255,rgb={104/128,76/128,127/128}}
  end
  local hx,hy=0,0
  if motion then
    hx,hy=clamp(s.camera_x or 0,-1,1),clamp(s.camera_y or 0,-1,1)
  end
  local sensitivity=clamp(s.camera_strength or 1,0,2)
  s.cluster={dx=-hx*3*sensitivity*.765,dy=-hy*2*sensitivity*.765,scale=1+hy*.006*sensitivity,
    origin_x=1015.56+148*.765,origin_y=590.55+70*.765}
  s.time=now
  m.health,m.sprint,m.armed,m.clock=hp,sp,s.armed,now
  m.clip,m.icon=clip,icon
  return s
end
return M

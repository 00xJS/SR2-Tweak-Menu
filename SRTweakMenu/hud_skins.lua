-- Reborn artwork with SR2 status values. Own interface objects; no player,
-- radar projection, mission-marker, or menu-renderer state is changed.
local G = require('game')
local ART = require('hud_art')
local H = { names = {"SR '22", 'Default+', 'GTA x Saints Row', 'E3 2005'} }
local presentation=require('sr22_motion').new()
local function clamp(v) return math.max(0, math.min(1, tonumber(v) or 0)) end

-- Pure layout builder, also used by offline image and boundary tests.
function H.build(style, s)
  local ops = {}
  local function image(name,x,y,w,h,c)
    if w > 0 and h > 0 then ops[#ops+1]={image=name,x=x,y=y,w=w,h=h,c=c or {1,1,1,1}} end
  end
  local function rect(x,y,w,h,c) image('ui_blank',x,y,w,h,c) end
  local function text(value,x,y,size,c)
    ops[#ops+1]={text=tostring(value),x=x,y=y,size=size,c=c or {1,1,1,1}}
  end
  local hp,sp,rp=clamp(s.health),clamp(s.sprint),clamp(s.respect)
  local red={.85,.12,.15,1};local purple={.52,.18,.76,1};local yellow={.94,.76,.15,1}
  local function bar(x,y,w,h,fill,c)
    rect(x-2,y-2,w+4,h+4,{0,0,0,.95})
    rect(x,y,w,h,{.06,.05,.07,.95})
    rect(x,y,w*fill,h,c)
    if fill>0 then rect(x,y,w*fill,1,{1,1,1,.26}) end
  end
  local function weapon(x,y,w,h)
    if s.weapon and s.weapon~='' then image(s.weapon,x,y,w,h) end
  end
  if style==1 then
    return require('sr22_skin')(s)
  elseif style==3 then
    return require('map_skin').build(s)
  elseif style==4 then
    return require('e3_skin').build(s)
  end
  return ops
end

local LIB=[==[
local VERSION=5
local H=rawget(_G,'TWK_HUD')
local function length(t) local n=0 while t[n+1]~=nil do n=n+1 end return n end
-- Stock system_lib.lua routes document globals through _DynamicGlobals.
-- rawget(_G,k) alone skips that native namespace and silently loses HUD data.
local function lookup(k,preferred)
 local ug=rawget(_G,'_UGGlobals')
 local dynamic=rawget(_G,'_DynamicGlobals') or (type(ug)=='table' and rawget(ug,'_DynamicGlobals'))
 if type(dynamic)=='table' and preferred then
  local scope=rawget(dynamic,preferred) or rawget(dynamic,preferred..'.lua')
  if type(scope)=='table' then local v=rawget(scope,k);if v~=nil then return v,preferred end end
 end
 local v=rawget(_G,k);if v~=nil then return v,'global' end
 local silent=rawget(_G,'_GetAnyGlobalSilent') or (type(ug)=='table' and rawget(ug,'_GetAnyGlobalSilent'))
 if type(silent)=='function' then
  local ok,value=pcall(silent,k)
  if ok and value~=nil then return value,'native-global-resolver' end
 end
 if type(ug)=='table' then local value=rawget(ug,k);if value~=nil then return value,'native-UGGlobals' end end
 if type(dynamic)=='table' then for name,scope in pairs(dynamic) do
  if type(scope)=='table' then local value=rawget(scope,k);if value~=nil then return value,'document:'..tostring(name) end end
 end end
 return nil,'missing:'..k
end
local function find_doc()
 local ok,d=pcall(vint_document_find,'hud')
 if ok and d and d~=0 then return d end
end
local function find_object(name,parent,doc)
 local ok,o=pcall(vint_object_find,name,parent,doc)
 if ok and o and o~=0 then return o end
end
local function get(o,k)
 if o and o~=0 then return vint_get_property(o,k) end
end
local function put(o,k,a,b,c)
 if not o or o==0 then return end
 if c~=nil then vint_set_property(o,k,a,b,c)
 elseif b~=nil then vint_set_property(o,k,a,b)
 else vint_set_property(o,k,a) end
end
-- Cache only properties on groups/objects created by this module. Native HUD
-- leases deliberately keep their actual-property reads and uncached writes.
local function cached_put(state,o,k,a,b,c)
 if not o or o==0 then return false end
 state.dirty=state.dirty or {}
 local object=state.dirty[o]
 if not object then object={} state.dirty[o]=object end
 local n=c~=nil and 3 or (b~=nil and 2 or 1)
 local previous=object[k]
 if previous and previous.n==n and previous[1]==a and previous[2]==b and previous[3]==c then return false end
 put(o,k,a,b,c)
 object[k]={a,b,c,n=n}
 if k=='image' then object.source_nw=nil object.source_se=nil end
 return true
end
local function retire(state,destroy)
 local remaining={}
 -- Never touch stale/recycled interface handles from another document.
 if state and state.doc and find_doc()==state.doc then
  local root=find_object(state.root_name or 'twk_hud_root',state.parent,state.doc)
  if root and root==state.root then
   -- Hide our own root first: a failed stock-property restore cannot strand it.
   pcall(cached_put,state,root,'visible',false)
   if destroy then pcall(vint_object_destroy,root) if state.dirty then state.dirty[root]=nil end end
  end
  for _,v in pairs(state.hidden or {}) do
   local stock=find_object(v[3] or 'health_grp',nil,state.doc)
   if stock and stock==v[1] then
    local ok,alpha=pcall(get,stock,'alpha')
    -- Only release the alpha value we still own. Native writes win otherwise.
    if not ok then remaining[length(remaining)+1]=v
    elseif alpha==0 then
     local restored=pcall(put,stock,'alpha',v[2])
     if not restored then remaining[length(remaining)+1]=v end
    end
   end
  end
 end
 if state then state.hidden=remaining end
 return length(remaining)==0
end
if not H or H.version~=VERSION then
 if not retire(H,true) then return end
 H={version=VERSION,b={},t={},hidden={},sources={},root_name='twk_hud_root_v5'}
 rawset(_G,'TWK_HUD',H)
end
H.get=get H.put=put H.lookup=lookup
local function own(o,k,a,b,c) return cached_put(H,o,k,a,b,c) end
function H.restore() retire(H,false) end
function H.ensure()
 local d=find_doc()
 if not d then H.restore() return false end
 local p=find_object('safe_frame',nil,d)
 if not p then H.restore() return false end
 if H.parent~=p or H.doc~=d then
  if not retire(H,true) then return false end
  H.parent=p H.doc=d H.root=nil H.b={} H.t={} H.hidden={} H.sources={} H.dirty={}
 end
 if H.root and find_object(H.root_name,p,d)~=H.root then
  -- The interface deleted our group while preserving the HUD document.
  H.restore() H.root=nil H.b={} H.t={} H.sources={} H.dirty={}
 end
 if not H.root then
  H.root=vint_object_create(H.root_name,'group',p)
  if not H.root or H.root==0 then H.root=nil return false end
  H.dirty=H.dirty or {} H.dirty[H.root]={}
  own(H.root,'visible',false)
  local x,y=get(p,'anchor')
  own(H.root,'anchor',-(x or 0),-(y or 0))
  local f=lookup('vint_hack_is_std_res')
  if f and f() then own(H.root,'scale',.5,480/720) end
 end
 return true
end
function H.allowed()
 local enable=lookup('Sui_hud_enable','vint_lib')
 if type(enable)=='number' and enable<2 then H.block_reason='native HUD disabled' return false end
 if lookup('Sui_paused','vint_lib') then H.block_reason='native UI paused' return false end
 if lookup('Hud_has_focus','vint_lib')==false then H.block_reason='native HUD lost focus' return false end
 local stock=find_object('health_grp',nil,H.doc)
 if not stock then H.block_reason='native health group unavailable' return false end
 -- Juiced autohides its own stock weapon-circle group while idle. That is
 -- separate from the global HUD policy and must not veto an authored skin.
 local autohide=lookup('Sui_hud_autohide','vint_lib')==true
 if get(stock,'visible')==false and not autohide then H.block_reason='native health group hidden' return false end
 H.stock_autohide=autohide H.block_reason=nil
 return true
end
local function finite(n) return type(n)=='number' and n==n and n>-1e100 and n<1e100 end
function H.native_alpha(name,o)
 local alpha=get(o,'alpha')
 if alpha==0 then for _,v in pairs(H.hidden) do
  if v[1]==o and (v[3] or 'health_grp')==name then return v[2] end
 end end
 return alpha
end
function H.cash_state(S)
 if not finite(S.cash) or not S.cash_h or find_object('cash',nil,H.doc)~=S.cash_h then return nil,0 end
 local alpha=H.native_alpha('cash',S.cash_h)
 if get(S.cash_h,'visible')==false then alpha=0 end
 return S.cash,finite(alpha) and math.max(0,math.min(1,alpha)) or 0
end
function H.map_bounds()
 -- Both radar and replacement are descendants of safe_frame. Walk the real
 -- VINT parent chain into safe-frame-local space, then invert our own root's
 -- transform. This cancels common safe-frame/ancestor scaling, including SD.
 local M=lookup('Hud_map','hud')
 local parent=lookup('vint_object_parent')
 if not M or type(parent)~='function' or not M.bg_map_h or not M.base_grp_h then return end
 if find_object('bg_map',M.base_grp_h,H.doc)~=M.bg_map_h then return end
 local bg=M.bg_map_h
 local nw,ny=get(bg,'source_nw') local se,sy=get(bg,'source_se')
 local width,height=get(bg,'unscaled_size')
 if not finite(nw) or not finite(ny) or not finite(se) or not finite(sy) or
  not finite(width) or not finite(height) or width<=0 or height<=0 or
  math.abs(width-(se-nw))>.05 or math.abs(height-(sy-ny))>.05 then return end
 local x,y,x1,y1=0,0,width,height
 local o=bg;local seen={};local reached_map=false
 for depth=1,32 do
  if o==H.parent then
   if not reached_map then return end
   local ax,ay=get(H.root,'anchor') local sx,sy=get(H.root,'scale')
   if not finite(ax) or not finite(ay) or not finite(sx) or not finite(sy) or sx<=0 or sy<=0 then return end
   x,y,x1,y1=(x-ax)/sx,(y-ay)/sy,(x1-ax)/sx,(y1-ay)/sy
   if x<0 or y<0 or x1>1280 or y1>720 or x1<=x or y1<=y then return end
   return x,y,x1-x,y1-y
  end
  if not o or o==0 or seen[o] then return end
  seen[o]=true;if o==M.base_grp_h then reached_map=true end
  if get(o,'visible')==false then return end
  local ax,ay=get(o,'anchor') local sx,sy=get(o,'scale')
  local ox,oy=get(o,'offset') local angle=get(o,'rotation')
  if not finite(ax) or not finite(ay) or not finite(sx) or not finite(sy) or
   not finite(ox) or not finite(oy) or not finite(angle) or math.abs(angle)>.00001 or sx<=0 or sy<=0 then return end
  x,y,x1,y1=ax+(x+ox)*sx,ay+(y+oy)*sy,ax+(x1+ox)*sx,ay+(y1+oy)*sy
  o=parent(o)
 end
end
function H.begin(cash)
 if not H.ensure() or not H.allowed() then H.restore() return false end
 H.want_cash=cash==true
 -- Do not show the replacement or hide stock until the whole frame succeeds.
 H.nb=0 H.nt=0
 return true
end
function H.bitmap(name,x,y,sx,sy,r,g,b,a,px,py,pw,ph)
 H.nb=H.nb+1 local o=H.b[H.nb]
 if not o then
  o=vint_object_create('twk_hud_b'..H.nb,'bitmap',H.root)
  assert(o and o~=0,'HUD bitmap allocation failed') H.b[H.nb]=o H.dirty=H.dirty or {} H.dirty[o]={}
 end
 own(o,'auto_offset','nw') own(o,'image',name)
 local source=H.sources[name]
 if not source then
  local x0,y0=get(o,'source_nw') local x1,y1=get(o,'source_se')
  source={x0 or 0,y0 or 0,x1,y1} H.sources[name]=source
 end
 if px~=nil then
  own(o,'source_nw',px,py) own(o,'source_se',px+pw,py+ph)
 elseif source[3] and source[4] then
  own(o,'source_nw',source[1],source[2]) own(o,'source_se',source[3],source[4])
 end
 own(o,'anchor',x,y) own(o,'scale',sx,sy)
 own(o,'tint',r,g,b) own(o,'alpha',a) own(o,'visible',true)
end
function H.text(s,x,y,k,r,g,b,a)
 H.nt=H.nt+1 local o=H.t[H.nt]
 if not o then
  o=vint_object_create('twk_hud_t'..H.nt,'text',H.root)
  assert(o and o~=0,'HUD text allocation failed') H.t[H.nt]=o H.dirty=H.dirty or {} H.dirty[o]={}
 end
 own(o,'auto_offset','nw') own(o,'font','header_n_overlay')
 own(o,'text_tag',s) own(o,'anchor',x,y) own(o,'scale',k,k)
 own(o,'tint',r,g,b) own(o,'alpha',a) own(o,'visible',true)
end
function H.lease(name,o)
 local alpha=get(o,'alpha');local v
 for _,entry in pairs(H.hidden) do if entry[1]==o and (entry[3] or 'health_grp')==name then v=entry;break end end
 if not v then v={o,alpha or 1,name};H.hidden[length(H.hidden)+1]=v end
 if alpha~=0 then v[2]=alpha or v[2] end
 if alpha~=0 then put(o,'alpha',0) end
 return v
end
function H.release_cash()
 local keep={}
 for _,v in pairs(H.hidden) do
  if v[3]=='cash' then
   local stock=find_object('cash',nil,H.doc)
   if stock==v[1] then
    local ok,alpha=pcall(get,stock,'alpha')
    if not ok then keep[length(keep)+1]=v
    elseif alpha==0 then local restored=pcall(put,stock,'alpha',v[2]);if not restored then keep[length(keep)+1]=v end end
   end
  else keep[length(keep)+1]=v end
 end
 H.hidden=keep
end
function H.finish()
 for i,o in pairs(H.b) do if i>H.nb then own(o,'visible',false) end end
 for i,o in pairs(H.t) do if i>H.nt then own(o,'visible',false) end end
 if not H.allowed() then H.restore() return false end
 local stock=find_object('health_grp',nil,H.doc)
 local v=H.lease('health_grp',stock)
 local cash=find_object('cash',nil,H.doc)
 if H.want_cash and cash and get(cash,'visible')~=false then H.lease('cash',cash) else H.release_cash() end
 own(H.root,'alpha',H.stock_autohide and 1 or v[2])
 own(H.root,'visible',true)
 return true
end
]==]
H.LIB=LIB
local F
local last_status
local function report(state,detail,key)
  key=key or (state..':'..tostring(detail))
  if key~=last_status then last_status=key;wml.log('HUD presentation '..state..': '..tostring(detail)) end
end
H.report=report
local function vint(code)
  -- Native host reports bridge execution separately from Lua success. Its
  -- tweak_out calls append, so an explicit trailing pcall sentinel is required.
  local wrapped="local ok,err=pcall(function() "..code.." end) tweak_out('__TWK_HUD_RESULT__',ok,tostring(err))"
  local result=table.pack(pcall(G.vint,wrapped))
  local n=result.n
  if not result[1] then return false,tostring(result[2]) end
  if not result[2] or result[n-2]~='__TWK_HUD_RESULT__' then return false,'native HUD request did not complete' end
  if result[n-1]~=true then return false,tostring(result[n]) end
  return table.unpack(result,2,n-3)
end
local function restore()
  -- A reload can inherit an older interface library. Hide the verified owned
  -- root before invoking even an older restore; never create objects here.
  vint([==[
local H=rawget(_G,'TWK_HUD')
if H then
 local ok,d=pcall(vint_document_find,'hud')
 if ok and d and d~=0 and d==H.doc then
  local found,o=pcall(vint_object_find,H.root_name or 'twk_hud_root',H.parent,d)
  if H.version~=5 and found and o and o~=0 and o==H.root then pcall(vint_set_property,o,'visible',false) end
  if H.restore then pcall(H.restore) end
 end
end
]==])
end
H.restore=restore
local function update(p)
  local it=F and F.items.hud_style
  local style=F and F.enabled and it and it.v or 2
  local hidden=false
  if wml.read_u32 then
    local ok,count=pcall(wml.read_u32,0x02528518)
    if not ok or type(count)~='number' then restore() return end
    hidden=count>0
  end
  if style==2 then restore() report('native','Default+') return end
  if not p or p==0 then restore() report('waiting','player not loaded') return end
  if hidden or (F.on and F.on('hide_hud')) then restore() report('suspended','native Hide HUD policy') return end
  if G.in_cutscene() then restore() report('suspended','cutscene') return end
  local ok,have=vint("local H=rawget(_G,'TWK_HUD') tweak_out(H and H.version==5)")
  if not ok then restore() report('blocked','native VINT bridge unavailable') return end
  if not have then
    local loaded,error=vint(LIB)
    if not loaded then restore() report('blocked','native HUD library: '..tostring(error)) return end
  end
  -- A failed texture load is retried next frame, not remembered as installed.
  if not vint("local H=rawget(_G,'TWK_HUD') if H and not H.peg_loaded then peg_load('srt_hud') H.peg_loaded=true end") then restore() report('blocked','HUD artwork package failed to load') return end
  local good,have_status,hp,sp,rp,level,ammo,weapon,sprinting,sprint_enabled,cash,cash_alpha,rx,ry,rw,rh,namespace,modern,native_autohide=vint("local sample_map="..tostring(style==3).." "..[==[
local H=rawget(_G,'TWK_HUD')
local S,namespace,W
if H then S,namespace=H.lookup('Hud_player_status','hud') W=H.lookup('Hud_weapon_status','hud') end
if S and W and H and H.version==5 and H.ensure() and H.allowed() then
 local cash,cash_alpha,rx,ry,rw,rh
 if sample_map then cash,cash_alpha=H.cash_state(S) rx,ry,rw,rh=H.map_bounds() end
 tweak_out(true,S.health_pct,S.sprint_pct,S.respect_bar_percent,S.respect_int,
 H.get(W.ammo_text_h,'text_tag') or '',H.get(W.single_wpn_icon_h,'image') or '',S.is_sprinting==true,S.sprint_enabled~=false,cash,cash_alpha,rx,ry,rw,rh,namespace,H.lookup('Sui_hud_modern_layout','vint_lib'),H.lookup('Sui_hud_autohide','vint_lib'))
else tweak_out(false,not H and 'HUD library unavailable' or (not S or not W) and 'native HUD document globals unavailable' or H.block_reason or 'HUD document or safe_frame unavailable') end
]==])
  if not good then restore() report('blocked','native HUD sampling: '..tostring(have_status)) return end
  if have_status~=true then restore() report('waiting',tostring(hp)) return end
  local state={health=hp,sprint=sp,respect=rp,level=level,ammo=ammo,weapon=weapon,
    player=p,generation=wml.read_u32 and wml.read_u32(p+0x44) or 0,
    is_sprinting=sprinting,sprint_enabled=sprint_enabled,native_visible=true}
  state.cash,state.cash_alpha=cash,cash_alpha
  if rx and ry and rw and rh then state.radar={x=rx,y=ry,w=rw,h=rh} end
  if style==3 and not state.radar then restore() report('waiting','native radar geometry unavailable; native HUD retained') return end
  if type(weapon)=='string' then
    local name=weapon:lower()
    state.armed=weapon~='' and not name:find('unarmed',1,true) and not name:find('fist',1,true) or false
  end
  if G.vehicle_handle then state.on_foot=G.vehicle_handle(p)==nil end
  local now=os.clock()
  state.motion=not F.items.hud_motion or F.items.hud_motion.v~=false
  state.camera_strength=(F.items.hud_camera_strength and F.items.hud_camera_strength.v or 100)/100
  if wml.read_f32 then
    state.x,state.z=wml.read_f32(p+0x14),wml.read_f32(p+0x1C)
    state.camera_x,state.camera_y=presentation:sample_camera(wml.read_f32,p,now)
  end
  if style==1 then state=presentation:update(state,now) else presentation:reset() end
  local ops=H.build(style,state)
  local owns_cash=false
  if style==3 then for _,op in ipairs(ops) do
    if op.tag=='cash' and op.c and op.c[4]>0 then owns_cash=true;break end
  end end
  local code={"local H=rawget(_G,'TWK_HUD') local submitted=false local ok,err=pcall(function() if H and H.begin("..tostring(owns_cash)..") then "}
  for _,op in ipairs(ops) do
    local c=op.c
    if op.image then
      local size=ART[op.image] or (op.image=='ui_blank' and {16,16}) or {84,64}
      local suffix=''
      if op.part then suffix=string.format(',%f,%f,%f,%f',op.part[1],op.part[2],op.part[3],op.part[4]) end
      code[#code+1]=string.format('H.bitmap(%q,%f,%f,%f,%f,%f,%f,%f,%f%s) ',op.image,op.x,op.y,op.w/(op.part and op.part[3] or size[3] or size[1]),op.h/(op.part and op.part[4] or size[4] or size[2]),c[1],c[2],c[3],c[4],suffix)
    else
      code[#code+1]=string.format('H.text(%q,%f,%f,%f,%f,%f,%f,%f) ',op.text,op.x,op.y,op.size,c[1],c[2],c[3],c[4])
    end
  end
  code[#code+1]='submitted=H.finish() end end) if not ok then if H and H.restore then pcall(H.restore) end error(err) end tweak_out(submitted==true,H and H.doc or 0,H and H.root or 0,H and H.nb or 0,H and H.nt or 0,H and H.block_reason or \"\")'
  local ran,submitted,doc,root,bitmaps,texts,why=vint(table.concat(code))
  if not ran or not submitted then restore() report('blocked',tostring(why or submitted or 'native HUD frame not submitted')) return end
  report('applied',string.format('%s; native namespace=%s; Juiced layout=%s, autohide=%s; doc=%s root=%s; %s bitmaps/%s texts',H.names[style],tostring(namespace),modern and 'modern' or 'classic',tostring(native_autohide),tostring(doc),tostring(root),tostring(bitmaps),tostring(texts)),tostring(style)..':'..tostring(doc)..':'..tostring(namespace))
end
local last_error
function H.after_update(p)
  local ok,err=pcall(update,p)
  if not ok then
    restore()
    if err~=last_error then wml.log('HUD style restored after error: '..tostring(err)); last_error=err end
  else last_error=nil end
end
function H.setup(features)
  F=features
  -- Release a prior Lua module instance before this reload registers callbacks.
  restore()
  local row={id='hud_style',label='HUD Style',kind='choice',options=H.names,v=2,needs='none',
    help='Reborn HUD artwork fitted to SR2. Default+ uses the game HUD. Radar and mission markers stay native.',
    change=function() restore() end}
  F.add_rows('Visual','hide_hud',{row})
  local controls={
    {id='hud_motion',label='HUD motion',kind='toggle',needs='none',v=true,
      help='Keep the SR22 cluster steady, or allow its camera motion and respect transitions.'},
    {id='hud_camera_strength',label='Camera sensitivity',kind='value',needs='none',default=100,min=0,max=200,step=5,
      fmt=function(v) return string.format('%d%%',v) end,
      help='Strength of the SR22 whole-cluster camera response. Zero keeps it steady.'},
  }
  F.register(controls)
  F.add_rows('Visual','hud_style',{{id='hud_settings',label='HUD Settings',kind='page',needs='none',
    help='Adjust the selected HUD presentation.',open=function() return {title='HUD Settings',rows=controls} end}})
end
return H

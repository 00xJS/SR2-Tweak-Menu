-- Style the native SR2 twelve-slot wheel. Input, sectors, selection, equip,
-- animations, slot anchors and native ammunition arcs remain engine-owned.
local ART=require('hud_art')
local W={}
local profiles={
 [1]={disc='srt22_wheel_circle',glow='srt22_wheel_glow',accent={1,.92,.84},arc={.94,.78,.35}},
 [3]={disc='srt22_wheel_circle',glow='srt_map_hover',accent={1,1,1},arc={1,1,1}},
 [4]={disc='srt_e3_chrome_ring',glow='srt_e3_selection_glow',accent={1,.85,.48},arc={1,.83,.42}},
}
function W.profile(style) return profiles[style] end
function W.icon(name)
 if type(name)~='string' then return end
 local key=name:match('^ui_hud_inv_w_(.+)$')
 if not key then return end
 key=({deserteagle='deseagle',desert_eagle='deseagle',baseball_bat='bat',pump_action_shotgun='shotgun',rpg_launcher='rpg'})[key] or key
 local image='srt_map_w_'..key
 if ART[image] then return image end
end

-- VINT Lua5.0: no length operator, table library, bit operations or input hooks.
W.LIB=[==[
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
local old=rawget(_G,'TWK_WHEEL')
if old and old.version~=2 and old.restore then old.restore() old=nil end
if not old then
 local Q={version=2,props={},pn=0,art={},an=0}
 rawset(_G,'TWK_WHEEL',Q)
 local function valid(o) return type(o)=='number' and o~=0 and o~=-1 end
 local function get(o,key)
  if not valid(o) then return end
  local ok,a,b,c=pcall(vint_get_property,o,key)
  if not ok or a==nil then return end
  local n=c~=nil and 3 or (b~=nil and 2 or 1)
  return {a,b,c,n=n}
 end
 local function same(a,b)
  if not a or not b or a.n~=b.n then return false end
  local i=1 while i<=a.n do
   if type(a[i])=='number' and type(b[i])=='number' then
    local d=a[i]-b[i] if d>.00001 or d<-.00001 then return false end
   elseif a[i]~=b[i] then return false end
   i=i+1
  end return true
 end
 local function put(o,key,v)
  if v.n==3 then return pcall(vint_set_property,o,key,v[1],v[2],v[3]) end
  if v.n==2 then return pcall(vint_set_property,o,key,v[1],v[2]) end
  return pcall(vint_set_property,o,key,v[1])
 end
 local function find(name,parent,doc)
  local ok,o=pcall(vint_object_find,name,parent,doc)
  if ok and valid(o) then return o end
 end
 local function doc()
  local ok,d=pcall(vint_document_find,'hud') if ok and valid(d) then return d end
 end
 function Q.context()
  local d=doc() local R=lookup('Hud_radial_menu','hud')
  if not d or not R or not valid(R.radial_grp_h) or find('radial_grp',nil,d)~=R.radial_grp_h then return end
  return d,R
 end
 local function binding(b)
  local d,R=Q.context()
  if d~=b.doc or not R or R.radial_grp_h~=b.radial then return false end
  if b.kind=='selector' then return R.selector_h==b.h end
  if b.kind=='caption' then return R.slot_desc_h==b.h end
  local s=R.slots[b.slot]
  if not s or s.grp_h~=b.group then return false end
  if b.kind=='arc' then return s.ammo_bar_fill_h==b.h end
  if b.kind=='icon' then
   if s.item_element_h~=b.element then return false end
   if b.child then return find(b.child,b.element,d)==b.h end
   return s.item_element_h==b.h
  end
  if b.kind=='art' then return find(b.name,b.group,d)==b.h end
  return false
 end
 local function property(b,key)
  local i=1 while i<=Q.pn do
   local p=Q.props[i] if p.h==b.h and p.key==key and p.binding.doc==b.doc then return p end
   i=i+1
  end
  local base=get(b.h,key) if not base then return end
  Q.pn=Q.pn+1 local p={h=b.h,key=key,base=base,binding=b}
  Q.props[Q.pn]=p return p
 end
 local function own(b,key,v)
  if not binding(b) then return false end
  local p=property(b,key) if not p then return false end
  local current=get(b.h,key) if not current then return false end
  if p.last and not same(current,p.last) then p.base=current end
  if not same(current,v) and not put(b.h,key,v) then error('wheel property '..key) end
  p.last=v return true
 end
 function Q.restore()
  -- Snapshot ownership decisions before restoring image, which can reset UVs.
  local decisions={} local i=1
  while i<=Q.pn do
   local p=Q.props[i]
   decisions[i]=binding(p.binding) and p.last and same(get(p.h,p.key),p.last)
   i=i+1
  end
  local pending={} local n=0 i=1
  while i<=Q.pn do
   local p=Q.props[i]
   if decisions[i] and not put(p.h,p.key,p.base) then n=n+1 pending[n]=p end
   i=i+1
  end
  Q.props,Q.pn=pending,n
  local remaining={} local rn=0
  i=1 while i<=Q.an do
   local a=Q.art[i]
   if binding(a) then
    pcall(vint_set_property,a.h,'visible',false)
    local ok=pcall(vint_object_destroy,a.h)
    if not ok then rn=rn+1 remaining[rn]=a end
   end
   i=i+1
  end
  Q.art=remaining Q.an=rn Q.style=nil Q.selected=nil
  return n==0 and rn==0
 end
 local function bnd(d,R,i,h,kind,element,child)
  return {doc=d,radial=R.radial_grp_h,slot=i,group=R.slots[i] and R.slots[i].grp_h,
   h=h,kind=kind,element=element,child=child}
 end
 local function art(d,R,i,name,image,width,height,size,alpha,tint,depth)
  local group=R.slots[i].grp_h
  local id='twk_wheel_'..i..'_'..name
  local h=find(id,group,d)
  local a
  local j=1 while j<=Q.an do if Q.art[j].name==id and Q.art[j].group==group then a=Q.art[j] end j=j+1 end
  if h and (not a or a.h~=h) then return end -- Don't claim someone else's child.
  if not h then
   h=vint_object_create(id,'bitmap',group)
   if not valid(h) then error('wheel art create') end
   a=bnd(d,R,i,h,'art') a.name=id Q.an=Q.an+1 Q.art[Q.an]=a
  end
  vint_set_property(h,'image',image)
  vint_set_property(h,'source_nw',0,0) vint_set_property(h,'source_se',width,height)
  vint_set_property(h,'auto_offset','c') vint_set_property(h,'anchor',0,0)
  vint_set_property(h,'scale',size/width,size/height)
  vint_set_property(h,'tint',tint[1],tint[2],tint[3])
  vint_set_property(h,'alpha',alpha) vint_set_property(h,'depth',depth)
  vint_set_property(h,'visible',true)
 end
 function Q.apply(style,config,icons,assets)
  local d,R=Q.context()
  if not d or not R then Q.restore() return false end
  local visible=get(R.radial_grp_h,'visible')
  if not visible or visible[1]~=true then Q.restore() return false end
  -- A visible pause document takes precedence, independent of wheel state.
  local ok,pause=pcall(vint_document_find,'pause_menu')
  if ok and valid(pause) then
   local root=find('safe_frame',nil,pause)
   local pv=root and get(root,'visible')
   if pv and pv[1]==true then Q.restore() return false end
  end
  if Q.style and Q.style~=style then if not Q.restore() then error('wheel restore pending') end end
  Q.style=style
  if not Q.peg_loaded then peg_load('srt_hud') Q.peg_loaded=true end
  local selected=R.slot_selected
  local i=0 while i<=11 do
   local s=R.slots[i]
   if s and valid(s.grp_h) then
    local parent=rawget(_G,'vint_object_parent')
    local safe=not parent or parent(s.grp_h)==R.radial_grp_h
    local anchor=get(s.grp_h,'anchor')
    if safe and anchor and anchor.n==2 then
     local diameter=64 -- Authored SR1 circle size; native group scale still applies.
     local arcsize=get(s.ammo_bar_bg_h,'unscaled_size')
     if arcsize and arcsize.n==2 and arcsize[1]>0 and arcsize[2]>0 then
      diameter=arcsize[1]>arcsize[2] and arcsize[1] or arcsize[2]
     end
     local disc=assets[config.disc] local glow=assets[config.glow]
     if disc then art(d,R,i,'disc',config.disc,disc[3],disc[4],diameter,.92,{1,1,1},30) end
     if glow then art(d,R,i,'glow',config.glow,glow[3],glow[4],diameter*1.5,
      i==selected and .85 or 0,config.accent,20) end
     if valid(s.ammo_bar_fill_h) then own(bnd(d,R,i,s.ammo_bar_fill_h,'arc'),'tint',{config.arc[1],config.arc[2],config.arc[3],n=3}) end
     local function icon(h,child)
      if not valid(h) then return end
      local b=bnd(d,R,i,h,'icon',s.item_element_h,child)
      if not binding(b) then return end
      local shade=s.availability==false and .25 or 1
      own(b,'tint',{shade,shade,shade,n=3})
      if style==3 and i<8 then
       local replacement=icons[s.bmp_name]
       local size=replacement and assets[replacement]
       if size then
        -- Capture all affected properties before changing an image resets UVs.
        local image=property(b,'image') local nw=property(b,'source_nw') local se=property(b,'source_se') local scale=property(b,'scale')
        if image and nw and se and scale then
         local sh=scale.base
         local width,height=se.base[1]-nw.base[1],se.base[2]-nw.base[2]
         if width and height and width>0 and height>0 and sh.n==2 then
          local k=width*sh[1]/size[3] local ky=height*sh[2]/size[4] if ky<k then k=ky end
          own(b,'image',{replacement,n=1}) own(b,'source_nw',{0,0,n=2}) own(b,'source_se',{size[3],size[4],n=2}) own(b,'scale',{k,k,n=2})
         end
        end
       end
      end
     end
     if s.dual_wield==true and i<8 then
      icon(find('inv_icon_0',s.item_element_h,d),'inv_icon_0') icon(find('inv_icon_1',s.item_element_h,d),'inv_icon_1')
     else icon(s.item_element_h) end
    end
   end
   i=i+1
  end
  if valid(R.selector_h) then own({doc=d,radial=R.radial_grp_h,h=R.selector_h,kind='selector'},'tint',{config.accent[1],config.accent[2],config.accent[3],n=3}) end
  -- The native caption/localization remains intact, including availability.
  Q.selected=selected return true
 end
end
]==]

local function literal(v)
 if type(v)=='string' then return string.format('%q',v) end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 local parts={'{'}
 for key,value in pairs(v) do parts[#parts+1]='['..literal(key)..']='..literal(value)..',' end
 parts[#parts+1]='}' return table.concat(parts)
end
function W.setup(F,G)
 G=G or require('game')
 local initialized=false
 local last_error
 local icons={}
 for name in pairs(ART) do
  local suffix=name:match('^srt_map_w_(.+)$')
  if suffix then icons['ui_hud_inv_w_'..suffix]=name end
 end
 for _,name in ipairs({'deserteagle','desert_eagle','baseball_bat','pump_action_shotgun','rpg_launcher'}) do
  local image=W.icon('ui_hud_inv_w_'..name) if image then icons['ui_hud_inv_w_'..name]=image end
 end
 local assetcode=literal(ART) local iconcode=literal(icons)
 local function bridge(code)
  local host,ok,why=G.vint('local ok,why=pcall(function() '..code..' end) tweak_out(ok,why)')
  return host and ok==true,why
 end
 local function restore()
  bridge("local Q=rawget(_G,'TWK_WHEEL') if Q and Q.restore then Q.restore() end")
 end
 local function update(p)
  local row=F.items and F.items.hud_style
  local style=F.enabled and row and row.v or 2
  if not profiles[style] or not p or p==0 or G.in_cutscene() or (F.on and F.on('hide_hud')) then restore() return end
  if not initialized then
   local ok,why=bridge(W.LIB)
   if not ok then restore() if why~=last_error then wml.log('Wheel style initialization failed: '..tostring(why)) last_error=why end return end
   initialized=true
  end
  local ok,why=bridge("local Q=rawget(_G,'TWK_WHEEL') if not Q or Q.version~=2 then error('wheel interface unavailable') end Q.apply("
   ..style..','..literal(profiles[style])..','..iconcode..','..assetcode..')')
  if not ok then restore() initialized=false if why~=last_error then wml.log('Wheel style restored after error: '..tostring(why)) last_error=why end end
 end
 F.after_updates[#F.after_updates+1]=update
 return {update=update,restore=restore}
end
return W


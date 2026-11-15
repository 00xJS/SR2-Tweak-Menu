-- Original Reborn H.build artwork and layout, with live continuous SR2 fills.
local font,reserve_font=require('sr22_font'),require('sr22_font_reserve')
local function clamp(v) return math.max(0,math.min(1,tonumber(v) or 0)) end
local function ammo(value)
 if type(value)~='string' or value=='' then return end
 local clip,reserve=value:match('^%s*(.-)%s*/%s*(.-)%s*$')
 clip=clip or value:match('^%s*(.-)%s*$')
 local function line(s)
  if not s or s=='' then return end
  if s:find('ui_hud_infinity',1,true) then return {infinite=true} end
  if s:match('^%d+$') then return {text=#s<2 and '0'..s or s} end
 end
 return line(clip),line(reserve)
end
return function(s)
 local ops={}
 local x,y,k=1015.56,590.55,.765
 local function image(name,px,py,w,h,c,part)
  if w>0 and h>0 then
   c=c or {1,1,1,1}
   ops[#ops+1]={image=name,x=x+px*k,y=y+py*k,w=w*k,h=h*k,c={c[1],c[2],c[3],c[4]},part=part}
  end
 end
 local function digits(value,px,py,height,small,center,max_width,tint)
  value=tostring(value or '')
  if not value:match('^%d+$') then return end
  local metrics=small and reserve_font or font
  local width,top,bottom=0,32,0
  for i=1,#value do
   local b=metrics[tonumber(value:sub(i,i))]
   width=width+b[3]-b[1];top=math.min(top,b[2]);bottom=math.max(bottom,b[4])
  end
  local scale=height/math.max(1,bottom-top)
  local gap=2
  local span=width*scale+math.max(0,#value-1)*gap
  if max_width and span>max_width then scale=scale*max_width/span;gap=gap*max_width/span;span=max_width end
  local left=center and px-span/2 or px
  local start=left
  for i=1,#value do
   local n=tonumber(value:sub(i,i));local b=metrics[n]
   image((small and 'srt22_reserve_' or 'srt22_digit_')..n,left-b[1]*scale,py-(top+bottom)/2*scale,24*scale,32*scale,tint)
   left=left+(b[3]-b[1])*scale+gap
  end
  return start,span
 end
 local clip,reserve=ammo(s.ammo)
 for _,meter in ipairs({'sprint','health'}) do
  local light=s[meter..'_light']
  if light and (light.opacity or 0)>0 then
   image('srt22_'..meter..'_halo',-8,-8,320,152,{1,1,1,light.opacity})
  end
 end
 image(clip and 'srt22_frame_gun' or 'srt22_frame_melee',-8,-8,320,152)
 -- Clip the continuous fill texture, preserving all four slanted cells and gloss.
 for _,meter in ipairs({'sprint','health'}) do
  local fraction=clamp(s[meter])
  if fraction>0 then
   local width=8+25+268*fraction
   image('srt22_'..meter,-8,-8,width,152,nil,{0,0,width,152})
  end
 end
 if s.weapon and s.weapon~='' then image(s.weapon,clip and 75 or 112,55,72,55) end
 local paint=s.ammo_paint
 if clip and paint then
  local c={paint.rgb[1],paint.rgb[2],paint.rgb[3],paint.opacity}
  image('srt_brush_left',145,51,149/2+.6,63,c)
  image('srt_brush_right',145+149/2-.6,51,149/2+.6,63,c)
 end
 if s.respect_progress and s.respect_from then
  local t=s.respect_progress
  local u=clamp(t/.55);local mix=u*u*(3-2*u)
  if mix<1 then digits(s.respect_from,40,83-t*5,13,true,false,32,{1,1,1,1-mix}) end
  digits(s.level,40,83+(1-t)^3*6,13*(1+.14*math.sin(t*math.pi)),true,false,32,{1,1,1,mix})
 else digits(s.level,40,83,13,true,false,32) end
 local function line(data,px,py,height,small,center,tint)
  if not data then return end
  if data.infinite then
   image('ui_hud_infinity',px-height*.615,py-height/2,height*1.23,height,tint)
   return px-height*.615
  end
  return digits(data.text,px,py,height,small,center,86,tint)
 end
 if reserve then
  local left=line(clip,222,72,22,false,true)
  line(reserve,left or 205,97,11,true,false,{.55,.25,.7,.85})
 else line(clip,222,82,23,false,true) end
 local cluster=s.cluster or {}
 local ox,oy=cluster.origin_x or x+148*k,cluster.origin_y or y+70*k
 local scale=cluster.scale or 1
 local alpha=s.visibility==nil and 1 or clamp(s.visibility)
 for _,op in ipairs(ops) do
  op.x=ox+(op.x-ox)*scale+(cluster.dx or 0)
  op.y=oy+(op.y-oy)*scale+(cluster.dy or 0)
  op.w,op.h=op.w*scale,op.h*scale
  op.c[4]=op.c[4]*alpha
 end
 return ops
end

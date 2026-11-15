-- Source-based Map Hybrid/Map Upper adaptation. Compacta glyphs, cash and
-- connected tribal ornament; SR2's circular radar/heat/mission markers stay native.
local ART=require('hud_art')
local M={}
local function clamp(n) n=tonumber(n) or 0;if n~=n then return 0 end;return math.max(0,math.min(1,n)) end
local function image(o,name,x,y,w,h,c,tag,part)
 if w>0 and h>0 then o[#o+1]={image=name,x=x,y=y,w=w,h=h,c=c or {1,1,1,1},tag=tag,part=part} end
end
local function rect(o,x,y,w,h,c,tag) image(o,'ui_blank',x,y,w,h,c,tag) end
-- Reborn map_font_metrics.lua ink bounds/advances at its native cells.
local metrics={bold={['0']={5,5,19.5,34.75,16.5},['1']={4.25,5.25,13.5,34.5,11.5},['2']={5.25,5,19.5,34.5,16.5},['3']={5,5,19.5,34.75,16.5},['4']={4.5,5.25,20,34.5,16.5},['5']={5,5.25,19.5,34.75,16.5},['6']={5,5,19.5,34.75,16.5},['7']={4.5,5.25,16.5,34.5,13.5},['8']={5,5,19.5,34.75,16.5},['9']={5,5,19.5,34.75,16.5},['$']={5,2.5,19.5,37,16.5},[',']={5.25,29,11,40.25,8.25},['-']={4.75,20,12,25,8.75}},light={['0']={5,5,14.5,34.5,11.5},['1']={4,5.25,10.5,34.5,8.5},['2']={5,5,14.5,34.5,11.5},['3']={4.75,5,14.5,34.5,11.5},['4']={4.25,5.25,14.75,34.5,11.5},['5']={5,5.25,14.5,34.5,11.5},['6']={5,5,14.5,34.5,11.5},['7']={4.75,5.25,13.25,34.5,10.5},['8']={5,5,14.5,34.5,11.5},['9']={5,5,14.5,34.5,11.5},['$']={5,3.25,14.5,36.5,11.5},[',']={5.25,29.5,8.5,39,5.75},['-']={5,20.75,12.25,23.75,9.25}}}
local function text(ops,value,family,anchor,y,height,a,tag,tone)
 local str=tostring(value);local m=metrics[family];local first,last,top,bottom,advance
 advance=0
 for ch in str:gmatch('.') do local g=m[ch];if not g then return end
  first=first or g[1];last=advance+g[3];top=math.min(top or g[2],g[2]);bottom=math.max(bottom or g[4],g[4]);advance=advance+g[5]+.8
 end
 if not first then return end
 local k=height/(bottom-top);local width=(last-first)*k;local x=anchor-width-first*k
 for ch in str:gmatch('.') do local g=m[ch];local name='srt_map_'..family..'_'..ch:byte();local art=ART[name]
  if not art then return end
  local w,h=art[3] or art[1],art[4] or art[2]
  image(ops,name,x,y-top*k,w*k,h*k,{tone or 1,tone or 1,tone or 1,a},tag,{0,0,w,h})
  x=x+(g[5]+.8)*k
 end
 return width
end
local function bar(ops,x,y,w,h,fill,rgb,a,tag)
 rect(ops,x-1,y-1,w+2,h+2,{0,0,0,.94*a},tag..'_stroke')
 rect(ops,x,y,w,h,{.016,.016,.016,.92*a},tag..'_empty')
 local n=clamp(fill)
 if n>0 then for row=0,7 do local t=row/7;local light=1-.48*t
  rect(ops,x,y+row*h/8,w*n,h/8,{rgb[1]*light,rgb[2]*light,rgb[3]*light,a},tag..'_fill')
 end
 rect(ops,x,y,w*n,.65,{1,1,1,.55*a},tag..'_highlight') end
end
local function currency(n)
 if type(n)~='number' or n~=n or math.abs(n)==math.huge then return end
 local str=tostring(math.floor(math.abs(n))):reverse():gsub('(%d%d%d)','%1,'):reverse():gsub('^,','')
 return (n<0 and '-$' or '$')..str
end
function M.build(s)
 local ops={};local a=clamp(s.alpha==nil and 1 or s.alpha);local right,cy=1236,26
 local cash=currency(s.cash)
 if cash then text(ops,cash,'bold',right,cy,24,a*clamp(s.cash_alpha==nil and 1 or s.cash_alpha),'cash') end
 -- Keep native wanted meters: unlike SR1, no duplicated or fabricated heat row.
 local ammo_y=62;local ammo=tostring(s.ammo or ''):gsub('%b[]','')
 local clip=s.clip~=nil and tostring(s.clip) or ammo:match('^%s*(%d+)')
 local reserve=s.reserve~=nil and tostring(s.reserve) or ammo:match('/%s*(%d+)')
 local width=0
 if s.armed~=false then
  if clip then width=text(ops,clip,'light',right,ammo_y,23,a,'ammo_clip') or 0
  elseif s.infinite or tostring(s.ammo or ''):find('ui_hud_infinity',1,true) then
   image(ops,'ui_hud_infinity',right-24,ammo_y,24,22,{1,1,1,a},'ammo_infinite');width=24
  end
  if reserve then text(ops,reserve,'light',right-width-10,ammo_y+5,18,a,'ammo_reserve',.82)
  elseif clip and tostring(s.ammo or ''):find('ui_hud_infinity',1,true) then
   image(ops,'ui_hud_infinity',right-width-32,ammo_y+4,22,18,{.82,.82,.82,a},'ammo_reserve_infinite')
  end
 end
 local weapon=s.weapon;local authored=s.weapon_key and ('srt_map_w_'..s.weapon_key)
 if authored and ART[authored] then weapon=authored end
 if weapon and weapon~='' then
  local ar=ART[weapon];local w,h=ar and (ar[3] or ar[1]) or 84,ar and (ar[4] or ar[2]) or 64
  image(ops,weapon,right-w*1.25,ammo_y+23,w*1.25,h*1.25,{1,1,1,a},'weapon',ar and {0,0,w,h} or nil)
 end
 local r=s.radar
 if r and type(r.x)=='number' and type(r.y)=='number' and type(r.w)=='number' and type(r.h)=='number' and r.w>0 and r.h>0 then
  -- The ornamental source frame has an open center; preserve the native circle
  -- and all native markers. Its connected lower health/sprint rail follows it.
  image(ops,'srt_map_border',r.x-18,r.y-18,r.w+33,r.h+46,{1,1,1,a},'tribal',{0,0,293,204})
  local y=r.y+r.h+2;local half=(r.w+2)/2
  bar(ops,r.x-2,y,half,8,s.health,{.93,.125,.157},a,'health')
  bar(ops,r.x+half,y,half,8,s.sprint,{.99,.71,.14},a,'sprint')
  rect(ops,r.x+r.w/2-1,y-1,2,10,{0,0,0,a},'meter_divider')
  local rx=r.x+r.w+24
  rect(ops,rx-1,r.y,9,r.h+2,{0,0,0,.94*a},'respect_track')
  local n=clamp(s.respect)
  for row=0,15 do local lo,hi=row/16,math.min(n,(row+1)/16)
   if hi>lo then local t=(lo+hi)/2
    rect(ops,rx,r.y+r.h*(1-hi),7,r.h*(hi-lo),{.17+.38*t,.035+.20*t,.35+.51*t,a},'respect_fill')
   end
  end
 end
 return ops
end
M.currency=currency
return M

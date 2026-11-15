-- SR2 adaptation of Reborn e3_hud.lua E.build/E.bar geometry (upper right).
-- Original chrome/glyph artwork; native radar, heat and weapon wheel remain native.
local ART=require('hud_art')
local E={}
local function clamp(n) n=tonumber(n) or 0;if n~=n then return 0 end;return math.max(0,math.min(1,n)) end
local widths={['0']=20,['1']=14,['2']=20,['3']=20,['4']=20,['5']=20,['6']=20,['7']=16,['8']=20,['9']=20,R=20,['$']=17,[',']=10,['.']=10,['+']=36,['-']=10}
local function image(ops,name,x,y,w,h,c,tag,part)
 if w>0 and h>0 then ops[#ops+1]={image=name,x=x,y=y,w=w,h=h,c=c or {1,1,1,1},tag=tag,part=part} end
end
local function rect(ops,x,y,w,h,c,tag) image(ops,'ui_blank',x,y,w,h,c,tag) end
local function text(ops,value,x,y,k,c,tag)
 value=tostring(value);local width=0
 for ch in value:gmatch('.') do if not widths[ch] then return end;width=width+widths[ch]+3 end
 local left=x-math.max(0,width-3)*k/2
 for shadow=1,0,-1 do
  local at=left+2*shadow;local colour=shadow==1 and {0,0,0,.82*c[4]} or c
  for ch in value:gmatch('.') do
   image(ops,'srt_e3_glyph_'..ch,at,y+2*shadow,64*k,64*k,colour,tag..(shadow==1 and '_shadow' or ''),{0,0,64,64})
   at=at+(widths[ch]+3)*k
  end
 end
end
local function respect(ops,x,y,k,fill,a)
 local h=108*k
 rect(ops,x-5*k,y+2*k,13*k,h+4*k,{0,0,0,.35*a},'respect_shadow')
 local rails={30,85,220,125,35,12,12,35,245,150,45}
 for j=-4,6 do local v=rails[j+5]/255
  rect(ops,x+j*k,y+math.abs(j-1)*.35*k,k,h-math.abs(j-1)*.7*k,{v,v,v,a},'respect_chrome')
 end
 -- Reproduce source E.bar's purple vertical gradient and five-column gloss.
 local gloss={.7,1.55,1.12,.85,.55};local n=clamp(fill)
 for row=0,15 do local lo,hi=row/16,math.min(n,(row+1)/16)
  if hi>lo then local t=(lo+hi)/2
   for col=0,4 do local v=gloss[col+1]
    rect(ops,x+col*k,y+h*(1-hi),k,h*(hi-lo),{math.min(1,(42+97*t)*v/255),math.min(1,(9+58*t)*v/255),math.min(1,(88+132*t)*v/255),a},'respect_fill')
   end
  end
 end
 for i=0,2 do rect(ops,x-4*k,y+i*h/2,11*k,k,{.69,.71,.75,a},'respect_notch') end
 text(ops,'R',x+2*k,y+h+11.5*k,.38*k,{1,1,1,a},'respect_label')
end
function E.build(s)
 local ops={};local x,y,k=1060,24,.85;local a=clamp(s.alpha==nil and 1 or s.alpha)
 local hp=clamp(s.health);local cx,cy=x+63*k,y+77*k
 local gold={.95,.79,.21,a}
 rect(ops,x+8*k,y+3*k,8*k,25*k,gold,'health_cross')
 rect(ops,x,y+11*k,24*k,8*k,gold,'health_cross')
 text(ops,math.floor(hp*100+.5),cx,y,.82*k,gold,'health')
 -- Authored chrome ring is the source 79-unit medallion; no fake wheel.
 image(ops,'srt_e3_chrome_ring',cx-39.5*k,cy-39.5*k,79*k,79*k,{1,1,1,a},'weapon_chrome',{0,0,96,96})
 if hp>0 and s.weapon and s.weapon~='' then
  local iw,ih=84,64;local entry=ART[s.weapon]
  if entry then iw,ih=entry[3] or entry[1],entry[4] or entry[2] end
  local w=86*k;image(ops,s.weapon,cx-11*k-w/2,cy-w*ih/iw/2,w,w*ih/iw,{1,1,1,a},'weapon')
 end
 local ammo=tostring(s.ammo or ''):gsub('%b[]','')
 local clip=tonumber(s.clip) or tonumber(ammo:match('^%s*(%d+)'))
 local infinity=(s.infinite or tostring(s.ammo or ''):find('ui_hud_infinity',1,true)) and not clip
 if s.armed~=false and hp>0 then
  if infinity then image(ops,'ui_hud_infinity',cx-14*k,cy+49*k,28*k,20*k,{1,1,1,a},'ammo_infinite')
  elseif clip then
   local capacity=tonumber(s.capacity)
   if capacity and capacity>0 then
    local fraction=clamp(clip/capacity);local w=54*k
    for row=0,5 do local inset=(math.abs(row-2.5)>2 and 2 or 0)*k
     rect(ops,cx-w/2+inset,cy+(42+row)*k,w-2*inset,k,{.14,.14,.16,a},'ammo_empty')
     if fraction>0 then local v=({75,190,245,170,120,65})[row+1]/255
      rect(ops,cx-w/2+inset,cy+(42+row)*k,math.max(k,w*fraction-2*inset),k,{v,v,v,a},'ammo_fill')
     end
    end
   end
   text(ops,math.floor(clip),cx,cy+51*k,.55*k,{1,1,1,a},'ammo')
  end
 end
 respect(ops,x+125*k,y+4*k,k,s.respect,a)
 return ops
end
return E

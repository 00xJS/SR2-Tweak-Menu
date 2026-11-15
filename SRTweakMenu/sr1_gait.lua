-- Real SR1 walk/run/sprint assets, routed through SR2's native gait resolver.
local M = {}
local names = {"sr1_gml1_bs_walk", "sr1_gml1_bs_run", "sr1_gml1_bs_sprint"}
local states = {"walk", "run", "sprint"}
local INVALID = 0xFFFFFFFF
local function loaded(id)
  return type(id)=="number" and id>=0 and id<5600 and id<wml.read_u32(0x024E1864)
    and wml.read_u32(0x024F2F00+id*32+0x1C)~=0
end
-- The game's load-by-name (0x006D3EB0) is its cutscene loader: it reads one
-- byte of the cutscene object (*0x02527D10, made by 0x006C3E40 when a
-- cutscene starts, cleared at 0x006C6412 when it ends) at +0xAFF to choose
-- where the file's memory comes from - 0: the cutscene's own pool, else the
-- game's general heap (0x02771178). Outside a cutscene the pointer is null,
-- which is why this never switched on in free roam. So, for the one call, a
-- stand-in object whose only set byte is that one: the file goes on the
-- general heap, as the game's own second path does, and the pointer is put
-- back at once. Nothing else in the loader, the file code (0x00BFxxxx) or
-- the animation registry (0x00CExxxx) reads the cutscene object.
local SCENE=0x02527D10
local load_file
function M.load_file(name) return load_file(name) end
local function load_file_impl(name)
  local out=wml.buffer(15)
  wml.write_u8(out,0)
  local stand_in
  if wml.read_u32(SCENE)==0 then
    stand_in=wml.buffer(11)            -- (+0xAFF is inside scratch slot 13; 14 and 15 hold the name and the out byte)
    wml.write_u8(stand_in+0xAFF,1)
    wml.write_u32(SCENE,stand_in)
  end
  local ok,id=pcall(wml.callx,0x006D3EB0,{ecx=wml.buffer(14,name)},out)
  if stand_in and wml.read_u32(SCENE)==stand_in then wml.write_u32(SCENE,0) end
  if not ok then wml.log("SR1 movement: loading "..name.." failed: "..tostring(id));return INVALID end
  return id
end
load_file=load_file_impl
function M.apply(G,p,enabled)
  if type(wml.sr1_gait)~="function" then return not enabled,"SR1 movement needs the matching menu host" end
  if not enabled then return wml.sr1_gait(false) end
  wml.sr1_gait(false) -- preparation is atomic: failures leave native movement active
  if p==0 or not G.playing(p) or wml.read_u32(p+0x18D4)~=0 then return false,"SR1 movement needs a player on foot" end
  local owner=wml.read_u32(p+0x5E0)
  if owner==0 or owner==INVALID then return false,"The player's animation owner is not ready" end
  local identity,actor=wml.read_u32(owner),wml.read_u32(p+0x44)
  if identity>=0x80000000 then return false,"The player's animation owner is not ready" end
  -- Callx supplies a genuine scratch byte for the native bool-out argument.
  -- A native loaded result may leave that byte false (already resident).
  if wml.read_u32(0x006D3EB0)~=0x00E8EC81 or wml.read_u16(0x006D3EB4)~=0 then
    return false,string.format("The native animation loader is not the one this was written for (%08X %04X)",
      wml.read_u32(0x006D3EB0),wml.read_u16(0x006D3EB4))
  end
  local files,keys={},{}
  for i,name in ipairs(names) do
    -- Walking: whatever walk state you have now (+0x1138, any walk style), so
    -- no walk style has to be picked first; run and sprint by name.
    if i==1 and wml.read_u32(p+0x1138)~=INVALID and wml.read_u32(p+0x1138)<0x2A4 then
      keys[1]=wml.read_u32(p+0x1138)
    else
      keys[i]=wml.callx(0x006EF510,{},wml.buffer(14,states[i]))
    end
    if keys[i]==INVALID then return false,"A native movement state is missing" end
    local id=wml.callx(0x00CEC2A0,{ecx=wml.buffer(14,name..".anim")})
    if not loaded(id) then
      if wml.read_u32(0x024E1864)>=5600 then return false,"The animation file pool is full" end
      id=load_file(name)
    end
    if not loaded(id) then wml.sr1_gait(false);return false,"Couldn't load the converted SR1 "..states[i].." animation" end
    files[i]=id
  end
  if G.player()~=p or wml.read_u32(p+0x44)~=actor or wml.read_u32(p+0x5E0)~=owner or wml.read_u32(owner)~=identity then
    wml.sr1_gait(false);return false,"The player changed while preparing movement"
  end
  return wml.sr1_gait(true,p,owner,actor,identity,keys[1],keys[2],keys[3],files[1],files[2],files[3])
end
function M.setup(F,G)
  local row={id="sr1_movement",label="Saints Row 1 movement",kind="toggle",needs="none",v=false,
    help="Use the original SR1 walk, run and sprint through normal movement. Turn off to restore SR2."}
  local signature
  local function off()
    if type(wml.sr1_gait)=="function" then wml.sr1_gait(false) end
    signature=nil
  end
  local function sync(p)
    local desired=F.enabled and row.v and p~=0 and G.playing(p) and wml.read_u32(p+0x18D4)==0
    if not desired then off();return end
    local owner=wml.read_u32(p+0x5E0)
    if owner==0 or owner==INVALID then off();return end
    local token=table.concat({p,wml.read_u32(p+0x44),owner,wml.read_u32(owner)},":")
    if token==signature then
      if wml.sr1_gait("status") then return end
      off();row.v=false
      local message="SR1 movement stopped because the walk style, native assets or definition capacity changed"
      wml.log(message);return message
    end
    local ok,message=M.apply(G,p,true)
    if ok then signature=token;return end
    off();row.v=false;wml.log(message or "SR1 movement could not be applied");return message
  end
  row.change=function(_,p)signature=nil;return sync(p)end
  F.register({row})
  -- No row of its own above Movement (the user's call): Saints Row 1 is one
  -- of the walk styles, first in Customize > Movement > Walk Style. Choosing
  -- it sets the game's default walk underneath and turns the SR1 walk, run
  -- and sprint on; choosing any other style turns it off. The setting is
  -- still saved with your tweaks under sr1_movement.
  local walk=F.items.walk_variant
  local open=walk and walk.open
  if open then
    walk.open=function(ctx,p,...)
      local pg=open(ctx,p,...)
      -- (the stock catalog can be unavailable; Saints Row 1 doesn't need it)
      if type(pg)~="table" or not pg.rows then pg={title="Walk Style",rows={}} end
      for _,r in ipairs(pg.rows) do
        local run=r.run
        if run and r.kind=="action" then
          r.run=function(...)
            local result=run(...)
            if row.v then row.v=false;signature=nil;off() end
            return result
          end
        end
      end
      table.insert(pg.rows,1,{label="Saints Row 1",kind="action",
        value=function() return row.v and "ON" or nil end,
        help="The original Saints Row 1 walk, run and sprint, through the game's normal movement. Works over any walk; another style turns it off.",
        run=function(_,who)
          who=who or G.player()
          if who==0 or not G.playing(who) then return "Can't change walk style right now" end
          row.v=true;signature=nil
          local message=sync(who)
          if not row.v then return message or "Couldn't apply Saints Row 1 movement" end
          return "Walk: Saints Row 1"
        end})
      if row.v then pg.cursor=1 elseif pg.cursor then pg.cursor=pg.cursor+1 end
      return pg
    end
  else
    local page=assert(F.items.style_movement,"SR1 movement requires the Customize > Movement page")
    table.insert(page.open().rows,1,row)
  end
  F.after_updates[#F.after_updates+1]=sync
  return row
end
return M

-- Own only the native controls lock acquired by this menu, for one actor.
local M = {}
function M.new(G,wml)
  local held
  local TOKEN, RELEASE = 0x02529750, 0x004F5210
  local function same(h,p)
    return h and p~=0 and p==h.player and wml.read_u32(p+0x44)==h.actor
  end
  local function disabled(p) return (wml.read_u8(p+0x1163)&0x20)~=0 end
  local function release(p)
    local h=held
    if not h then return end
    -- A changed native token belongs to someone else. Never enable it.
    if wml.read_u32(TOKEN)~=h.token then held=nil return end
    if same(h,p) then
      local ok,done=G.lua('player_controls_enable(LOCAL_PLAYER) tweak_out(true)')
      if ok and done then held=nil end
    elseif h.token~=0 and wml.read_u32(RELEASE)==0x83EC8B55 then
      -- The player was destroyed/replaced. Release our input-block token
      -- through the same native routine as controls_enable, without touching
      -- the stale human pointer or enabling the replacement actor.
      local ok=pcall(wml.callx,RELEASE,{edx=h.token})
      if ok and wml.read_u32(TOKEN)==h.token then wml.write_u32(TOKEN,0);held=nil end
    else held=nil end
  end
  local guard={}
  function guard.update(on)
    local p=G.player()
    if held and (not on or not same(held,p)) then release(p) end
    if not on or p==0 or held or not G.playing(p) then return end
    -- Native disable uses one shared token, so do not borrow an existing one.
    if disabled(p) or wml.read_u32(TOKEN)~=0 then return end
    local actor=wml.read_u32(p+0x44)
    local ok,done=G.lua('player_controls_disable(LOCAL_PLAYER) tweak_out(true)')
    if ok and done and G.player()==p and wml.read_u32(p+0x44)==actor and disabled(p) then
      held={player=p,actor=actor,token=wml.read_u32(TOKEN)}
    end
  end
  return guard
end
return M


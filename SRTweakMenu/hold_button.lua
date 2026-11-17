-- A long hold toggles once; a short tap is delivered on release. The game
-- never sees the beginning of the hold (Back would otherwise open its map).
local H = {}
function H.new(seconds)
  return { seconds = seconds }
end
function H.update(h, down, now, eligible, menu_open)
  if not eligible then
    -- (a hold that began while eligible stays hidden until it's let go: getting
    -- in a car mid-hold mustn't hand the rest of Back to the game, its map)
    local holding = h.started ~= nil or h.hiding
    h.started, h.fired, h.tap = nil, nil, nil
    h.blocked = down -- release before rearming after a pause/disconnect
    h.hiding = down and (menu_open or holding) or nil
    return false, false, h.hiding == true
  end
  h.hiding = nil
  if h.blocked then
    if not down then h.blocked = nil end
    return false, false, down
  end
  if down then
    if not h.started then h.started, h.tap = now, not menu_open end
    if not h.fired and now - h.started >= h.seconds then
      h.fired = true
      return true, false, true
    end
    return false, false, true
  end
  local tap = h.started ~= nil and not h.fired and h.tap and not menu_open
  h.started, h.fired, h.tap = nil, nil, nil
  return false, tap, false
end
return H

-- Call setup(F,G) after layout.apply/layout_sr2.apply and before defaults.snapshot.
local M = {}
function M.setup(F, G)
  local row = { id = "gang_dots", label = "Persistent gang dots", kind = "toggle", needs = "none", v = false,
    help = "Keep nearby gang members on the radar: Brotherhood red, Ronin yellow, Samedi green, Ultor orange, police red to blue. Follows radar visibility." }
  local applied, failure
  local function sync(p)
    local desired = not not (F.enabled and row.v and p ~= 0)
    if desired == applied then return end
    if type(wml.gang_dots) ~= "function" then
      if not desired then applied = false; return end
      failure = "Gang dots need the matching SR2 menu host"
    else
      local ok, message = wml.gang_dots(desired)
      if ok then applied = desired; return end
      failure = message or "The radar hooks could not be installed"
    end
    row.v = false
    if type(wml.gang_dots) == "function" then wml.gang_dots(false) end
    applied = false
    wml.log(failure)
    return failure
  end
  row.change = function(_, p) return sync(p) end
  F.register({row})
  local page = F.items.player_notoriety
  assert(page and page.open, "Gang dots require the Notoriety page")
  local rows = page.open().rows
  local at = #rows + 1
  for i, item in ipairs(rows) do if item.id == "join_gang" then at = i + 1; break end end
  table.insert(rows, at, row)
  F.after_updates[#F.after_updates + 1] = sync
  return row
end
return M

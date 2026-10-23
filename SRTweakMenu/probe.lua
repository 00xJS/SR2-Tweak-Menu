-- SR Tweak Menu (Saints Row 2) - live probe, for development (mod.ini:
-- dev_probe = true). Every second, if TweakMenu/probe_in.lua has changed, it
-- is run with this menu's modules at hand (G, F, MENU) and print() going to
-- TweakMenu/probe_out.txt, so the game can be tried out without restarting.

local P = {}
local root = wml.mod_folder:match("^(.*)[/\\][^/\\]+$")
local IN, OUT = root .. "\\probe_in.lua", root .. "\\probe_out.txt"
local last, tick = nil, 0

local function show(v)
  if type(v) == "number" and math.type(v) == "integer" and v > 0xFFFF then return string.format("%d (0x%08X)", v, v) end
  return tostring(v)
end

function P.frame(env)
  tick = tick + 1
  if tick % 60 ~= 0 then return end
  local f = io.open(IN, "rb")
  if not f then return end
  local code = f:read("a"); f:close()
  if code == last then return end
  -- (waits for a loaded game unless the probe says --anytime)
  if not code:find("--anytime", 1, true) and env.G.player() == 0 then return end
  last = code
  local out = io.open(OUT, "w")
  local function say(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = show((select(i, ...))) end
    out:write(table.concat(t, "\t"), "\n"); out:flush()
  end
  local chunk, err = load(code, "=probe", "t", setmetatable({ print = say }, { __index = function(_, k) return env[k] or _G[k] end }))
  if not chunk then say("compile error: " .. err) else
    local ok, e = pcall(chunk)
    if not ok then say("error: " .. tostring(e)) end
  end
  say("-- done " .. os.date("%H:%M:%S"))
  out:close()
end

return P

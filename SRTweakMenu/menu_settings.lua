-- A separate preference keeps mod.ini and other UI settings intact.
local C={file=(wml.mod_folder or '.')..'/menu_ui.txt'}
function C.load(path)
  C.style=tostring(wml.setting('menu_style','game')):lower()=='text' and 'text' or 'game'
  local f=io.open(path or C.file,'rb')
  if f then
    local s=f:read(32);f:close()
    s=s and s:match('^%s*(%a+)%s*$')
    if s=='game' or s=='text' then C.style=s end
  end
end
function C.set(style)
  C.style=style=='text' and 'text' or 'game'
  require('menu').set_style(C.style)
  local f=io.open(C.file,'wb')
  if not f then return 'Menu UI changed for this session; preference could not be saved.' end
  local ok=f:write(C.style,'\n');local closed=f:close()
  if not ok or not closed then return 'Menu UI changed for this session; preference could not be saved.' end
end
function C.row()
  return {id='specialized_menu_ui',label='Menu UI',kind='choice',needs='none',options={'Terminal','Game'},v=C.style=='game' and 2 or 1,
    help="Game: the menu drawn with Saints Row 2's own menu art, fonts and sounds. Terminal uses plain text. Switch to Game again to retry it after a loading problem.",
    change=function(_,_,_,it) return C.set(it.v==2 and 'game' or 'text') end}
end
C.load()
return C

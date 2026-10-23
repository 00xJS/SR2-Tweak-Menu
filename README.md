# SR Tweak Menu for Saints Row 2 (prototype)

[SR Tweak Menu](https://github.com/00xJS/SR-Tweak-Menu), the in-game cheat
menu for Saints Reborn (Saints Row 1), running in **Saints Row 2 on PC**.

This is a proof of concept. Its host runs the menu's own `menu.lua`,
unchanged, inside SR2. Only three rows are ported so far:

| Tab | Rows |
|---|---|
| Player | God mode, Money +$50,000 |
| Teleport | Teleport to waypoint |
| Settings | All tweaks, Show active tweaks |

## Requirements

- Saints Row 2 on PC, the Steam or GOG version, with
  [Juiced Patch](https://www.kobraworks.com/juiced) installed (tested with
  v9.3.1). It also runs without Juiced, but that's untested.
- To build it: Visual Studio 2022 with **Desktop development with C++**.

## Build and install

```bat
host\build.bat
install.bat
```

`install.bat` takes the game folder as an argument if Saints Row 2 isn't in
Steam's default folder. It puts:

- `dinput8.dll` next to `SR2_pc.exe`. This is the host, described below.
- the menu's files in `TweakMenu\SRTweakMenu\`. An existing `mod.ini` is kept.

To uninstall, delete `dinput8.dll` and the `TweakMenu` folder from the game folder.

## Controls

The same as SR1's menu: **F5** opens it, **Up/Down** move, **Left/Right**
adjust, **Enter** selects, **PgUp/PgDn** change tab, **Backspace** goes back
or closes. On a controller, hold **RB** and press **D-pad Down**. While the
menu is open the game doesn't see the arrows, Enter or Backspace. It still
sees the controller (see Limits).

Settings are in `TweakMenu\SRTweakMenu\mod.ini`. The `overlay_*` keys move
the menu text and change its size. The log is `TweakMenu\wml.log`.

## How it works

**The host (`host/host.c`, built as `dinput8.dll`)**

- **Loading.** SR2 imports one function from `dinput8.dll`, so Windows loads
  the host from the game folder. The host passes `DirectInput8Create` on to
  the real DLL in System32 and wraps the keyboard device, so the menu can
  keep keys from the game.
- **Lua.** It embeds Lua 5.4 and gives it a `wml` table shaped like
  Whompay's Mod Loader's. The SR1 menu's files only use that table.
- **Frame hook.** Lua runs every frame on the game's main thread, from the
  call at `0x0052050C`.
- **Drawing.** The menu text is drawn with the game's own text printer from
  the 2D call at `0x00521A69`. SR1's `menu.lua` writes its text to a
  "mailbox" for SR1's `menu_overlay.dll`. The host emulates that mailbox and
  draws its text.
- **Living with Juiced.** Juiced Patch hooks the same two calls. The host
  waits until Juiced has hooked them, then installs its own hooks and passes
  on to Juiced's. Its thunks keep every register and flag, so neither side
  notices.

**Extra `wml` calls for SR2**

| Call | What it does |
|---|---|
| `wml.script(code)` | Runs a line of the game's own Lua 5.0, the mission scripts' state, with their functions such as `cash_add` and `turn_invulnerable` |
| `wml.call(addr, ...)` | Calls a cdecl game function with up to 8 integer arguments |
| `wml.pad()` | Reads controller 1 |
| `wml.f2u` / `wml.u2f` | Convert a float to its bits and back |

`wml.hook` isn't available yet.

**The menu files (`SRTweakMenu/`)**

| File | What it is |
|---|---|
| `menu.lua` | SR1's, byte for byte |
| `features.lua` | SR1's row engine (toggle, value, choice, list, action) with SR2 rows |
| `game.lua` | SR2's addresses and calls |
| `gameui.lua` | A stub: the game look isn't on SR2 yet, so only the plain text look works |
| `main.lua` | Drives it all every frame |

Game facts (addresses, what the game's functions take) were found in the
game and cross-checked against Juiced Patch's sources. No Juiced code is
used.

## Testing

- **Offline.** `tools\build_lua_exe.bat`, then `build\lua.exe
  tools\offline_test.lua` runs the menu against fake memory and prints what
  would be drawn.
- **In game.** Set `selftest = true` in the installed `mod.ini`. Once a game
  is loaded, every row runs without keys and the results go to `wml.log`.
  The self-test changes your game: it adds $50,000 and moves you 3 m.

## Limits

- **The controller still reaches the game** while the menu is open. Only the
  keyboard's menu keys are kept from it.
- **SR1 rows need porting one by one.** Most of SR1's `features.lua` reads
  SR1 addresses or calls SR1 functions. In SR2, many of those features can use
  the game's own script functions instead.
- **Saves aren't marked as cheated**, unlike Juiced's Lua console.
- **Private play only**, like the SR1 menu.

## Credits

SR Tweak Menu by 00xJS and itsMJQ. The menu (`menu.lua`) and the row engine
come from it unchanged.

Saints Row 2 Juiced Patch by Kobraworks Modding was used as a reference for
addresses.

Lua 5.4.9 by PUC-Rio, MIT licensed (`third_party/lua-5.4.9`).

MIT licensed, see `LICENSE`.

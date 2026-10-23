# SR Tweak Menu for Saints Row 2

[SR Tweak Menu](https://github.com/00xJS/SR-Tweak-Menu), the in-game cheat
menu for Saints Reborn (Saints Row 1), running in **Saints Row 2 on PC**.

It's the same menu: SR Tweak Menu 2.5.0's `menu.lua` and `layout.lua` run
here unchanged, so the tabs, pages, row order, keys and look match SR1. The
rows underneath are SR2's own, built on the game's mission-script functions,
its phone cheats and its engine.

Work in progress: some SR1 rows have no SR2 version yet (see the end).

## Requirements

- Saints Row 2 on PC, the Steam or GOG version. Juiced Patch is optional:
  the menu runs with it or without it.
- To build it: Visual Studio 2022 with **Desktop development with C++**.

## Build and install

```bat
host\build.bat
install.bat
```

`install.bat` takes the game folder as an argument if Saints Row 2 isn't in
Steam's default folder. It puts:

- `dinput8.dll` (the host) next to `SR2_pc.exe`.
- the menu in `TweakMenu\SRTweakMenu\`. An existing `mod.ini` is kept.

To uninstall, delete `dinput8.dll` and the `TweakMenu` folder.

## Controls

As in SR1: **F5** opens the menu, **Up/Down** move, **Left/Right** adjust or
browse a list, **Enter** selects or opens a page, **PgUp/PgDn** change tab,
**Backspace** goes back or closes. On a controller, hold **RB** and press
**D-pad Down**. The game doesn't see the arrows, Enter or Backspace while the
menu is open. It still sees the controller.

Settings are in `TweakMenu\SRTweakMenu\mod.ini`; the `overlay_*` keys move
and size the menu text. The log is `TweakMenu\wml.log`.

## What's in it

| Tab | |
|---|---|
| Player | **Health & damage** (god mode, no ragdoll, health multiplier, heal on D-pad down, refill health, kill yourself), **Movement** (No Clip, infinite sprint), **Notoriety** (never wanted, no cops, no gangs, never busted, max notoriety, each team's level: Police, Brotherhood, Ronin, Sons of Samedi, Ultor), **Bodyguards** (spawn a bodyguard, dismiss homies, more homies), **Unlocks**; +$50,000, +5,000 respect |
| Weapons | Infinite ammo, no reload, perfect aim; **Special ammo** (super explosions, pimp strength); give any weapon, give every weapon, refill all ammo |
| Vehicles | Vehicle god mode, repair; **Toughness** (tank mode, bulletproof glass and tires, no explosion fling, vehicle smash), **Handling** (top speed), **Look** (sirens); spawn any of 118 vehicles, the phone's vehicle cheats, remove spawned vehicles, destroy |
| World | Weather, no fog, time of day, freeze time, low gravity, clear / restore streets; **People** (spawn any character, crowds of 10 and 40, remove spawned people, ragdoll all, crowd and traffic density, the phone's mayhem cheats) |
| Visual | Hide HUD; **Camera** (field of view), **Free camera** (the game's slew camera); giant, tiny, pratfall, elevator to heaven |
| Teleport | Districts, cribs, crib garages, every store chain, mission starts, strongholds; teleport to waypoint, auto-teleport to waypoint |
| Models | Play as any character, live; restore your character |
| Customize | SR2's character creator; **Movement** (walk, run and stand style) |
| Emotes | **Poses** (the game's stand poses, held), **Actions** (taunts, gang signs, dances...), stop, repeat, D-pad taunts |
| Settings | All tweaks, show active tweaks, save tweaks for next time, forget saved tweaks |

Phone cheats are switched through the game's own cheat code. Using one
unlocks it on your phone and marks the save as cheated, as the phone does.

## How it works

**The host (`host/host.c`, built as `dinput8.dll`)**

- **Loading.** SR2 imports one function from `dinput8.dll`, so Windows loads
  the host from the game folder. It passes `DirectInput8Create` on to the
  real DLL and wraps the keyboard, so the menu can keep keys from the game.
- **Lua.** Lua 5.4 with a `wml` table shaped like Whompay's Mod Loader's,
  which is all the SR1 menu's files use.
- **Hooks.** Lua runs every frame on the game's main thread from the call at
  `0x0052050C`; the menu is drawn with the game's text printer from the 2D
  call at `0x00521A69`. With Juiced installed the host waits for Juiced's
  hooks on those calls and chains to them; without it, it hooks the game
  directly.
- **The menu's text.** SR1's `menu.lua` writes its text to a "mailbox" for
  SR1's `menu_overlay.dll`; the host emulates that mailbox and draws it.

**Extra `wml` calls for SR2**

| Call | What it does |
|---|---|
| `wml.script(code)` / `wml.vint(code)` | Runs Lua in the game's mission-script state / interface state. Returns whether it ran, then whatever the code passed to `tweak_out(...)` |
| `wml.call(addr, ...)` | A cdecl game function with up to 8 integer arguments |
| `wml.callx(addr, regs, ...)` | A game function taking arguments in registers (`{ eax =, ecx =, ... }`) and up to 8 on the stack |
| `wml.patch(addr, bytes)` | Writes into the game's code |
| `wml.buffer(slot, text)` | The address of a scratch buffer, for passing strings and structs |
| `wml.read_string(addr)` | A zero-terminated string from the game |
| `wml.pad()` | Controller 1's buttons and triggers |
| `wml.f2u` / `wml.u2f` | A float to its bits and back |

The game guards its Lua globals: new names can't be made with a plain
assignment. The host adds `tweak_out` with a raw table set, and the menu
keeps its own values in a `TWEAK` table made with `rawset`.

**The menu files (`SRTweakMenu/`)**

| File | What it is |
|---|---|
| `menu.lua`, `layout.lua` | SR Tweak Menu 2.5.0's, byte for byte |
| `layout_sr2.lua` | Puts the SR2-only rows into the pages that fit them; leaves out SR1 pages SR2 has nothing for |
| `features.lua` | SR1's row engine (toggle, value, choice, list, action, page), phone cheats, saved tweaks |
| `tab_*.lua` | Each tab's rows, under SR1's row ids |
| `engine.lua` | Rows that call the game engine: No Clip, spawning, free camera, field of view, fog, respect, play as |
| `game.lua` | SR2's addresses and calls |
| `data/*.lua` | Lists built from the game's own tables: weapons, vehicles, characters, cheats, places, emotes, poses and movement styles |
| `gameui.lua` | A stub: the game look isn't on SR2 yet, so only the plain text look works |
| `main.lua` | Drives it all every frame |

Game facts (addresses, calling conventions) were read in the game's code;
Juiced Patch's sources were used as a map. No Juiced code is used.

## Testing

- **Offline.** `tools\build_lua_exe.bat`, then `build\lua.exe
  tools\offline_test.lua` opens every tab and page against fake game memory,
  presses every row and reports each row's game calls and any errors.
- **Live probe.** Set `dev_probe = true` in the installed `mod.ini`. While the
  game runs, anything written to `TweakMenu\probe_in.lua` is run in the
  menu's Lua (with `G`, `F` and `MENU` at hand), and what it prints goes to
  `TweakMenu\probe_out.txt`.
- **Self-test.** `selftest = true` runs god mode, money and a teleport once a
  game is loaded and logs the results. It changes your game: +$50,000 and a
  3 m step.
- **Data.** `tools\vpp2.py` lists and extracts SR2's packfiles (the `data`
  lists were built from them).

## Not on Saints Row 2 yet

The rest of SR1's rows are left out until each has an SR2 way to work:
weapon skins, districts, special ammo (rocket and fire ammo, money gun,
explosive punches), rapid fire, one-hit kills, run boost and high jump,
SR1's aiming add-ons (Precise Aim, Fine Aim, Weapon Switch, which are mods
of their own), the driving camera, filters and render modes, staged scenes
and voice lines, and SR1's start-up rows.

## Credits

SR Tweak Menu by 00xJS and itsMJQ; its menu, layout and row engine are used
as they are. Saints Row 2 Juiced Patch by Kobraworks Modding was the map to
SR2's engine. Lua 5.4.9 by PUC-Rio, MIT licensed (`third_party/lua-5.4.9`).

MIT licensed, see `LICENSE`.

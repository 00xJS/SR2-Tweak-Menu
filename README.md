# SR Tweak Menu for Saints Row 2

[SR Tweak Menu](https://github.com/00xJS/SR-Tweak-Menu), the in-game cheat
menu for Saints Reborn (Saints Row 1), running in **Saints Row 2 on PC**.

It's the same menu: SR Tweak Menu's `menu.lua` and `layout.lua` keep SR1's
tabs, pages, row order and keys. The rows underneath are SR2's own, built on
the game's mission-script functions, its phone cheats and its engine. The
menu can be drawn as plain text or in the game's own look (its menu art,
fonts and sounds).

**Status: preview (0.6.0).** Every row passes the offline test, but most
haven't been played in the game yet, so expect rough edges. Everything new in
0.4 to 0.6 is untested in game (see `SRTweakMenu/CHANGELOG.md`). Settings >
Run self-test checks what it can in your game and writes a report. `TESTING.md` is the checklist for playing it through. Some SR1
rows have no SR2 version (see the end). Bug reports are welcome in Issues.

**Offline only.** Use it in single player. Don't use it in co-op or online
with people who didn't agree to it.

## Requirements

- Saints Row 2 on PC, the Steam or GOG version. Juiced Patch is optional:
  the menu runs with it or without it. With Juiced, set
  `SR1MovingAttacks=0` in `juiced.ini`.
- To build it: Visual Studio 2022 with **Desktop development with C++**.

## Build and install

There's no prebuilt download yet. Build it from a Developer Command Prompt or
a normal one (`build.bat` finds Visual Studio):

```bat
host\build.bat
install.bat
```

`install.bat` takes the game folder as an argument if Saints Row 2 isn't in
Steam's default folder. Close the game first. It puts:

- the host next to `SR2_pc.exe` as `dinput8.dll`. If another `dinput8.dll`
  is there (an ASI loader), that one stays and the host goes in as
  `scripts\SRTweakMenu.asi`.
- the menu in `TweakMenu\SRTweakMenu\`. An existing `mod.ini` is kept.
- the HUD textures in `Mods\SRTweakMenu\HUD\`.

To uninstall, delete the host (`dinput8.dll` or `scripts\SRTweakMenu.asi`),
the `TweakMenu` folder and `Mods\SRTweakMenu`.

## Controls

As in SR1: **F5** opens the menu, **Up/Down** move, **Left/Right** adjust or
browse a list, **Enter** selects or opens a page, **PgUp/PgDn** change tab,
**Backspace** goes back or closes. On a controller, hold **RB** and press
**D-pad Down**; **A** selects, **B** goes back, **LB/RB** change tab. While
the menu is open the game sees neither its keys nor the controller.

- **Favorites.** **F** (or **Y** on a controller) on a row pins it to the
  Favorites tab, the last tab (one PgUp from Player). The same button
  unpins it.
- **Hotkeys.** **H** on a switch, choice, list or action, then a key (F1-F12,
  Num 0-9, Insert, Home, End or Delete), gives the row that key. With the
  menu closed the key switches the row, steps it or presses it. Settings >
  Hotkeys lists and clears them. Keyboard only.

Settings are in `TweakMenu\SRTweakMenu\mod.ini`. The log is
`TweakMenu\wml.log`.

## What's in it

| Tab | |
|---|---|
| Player | **Health & damage** (god mode, no ragdoll, health multiplier, fall damage, no health regen, refill health, kill yourself), **Movement** (No Clip, sprint, run boost, high jump, jump height, soft landing, crouch while moving, swim speed), **Notoriety** (never wanted, no cops, no gangs, never busted, max notoriety, each team's level, join a gang, persistent gang dots), **Bodyguards** (spawn, recruit the nearest gang member, dismiss, their weapon), **Unlocks** (music, collectibles, clothing, rewards), **Items** (food and drugs, experimental), **Cash safe** (deposit, withdraw, Limited Cash); +$50,000, +5,000 respect |
| Customize | Face & Body (the plastic surgeon's sliders), Hair, Clothing, Jewelry, Tattoos, Mission Outfits, voice; **Saved Looks** (8 slots, clothing included); restore outfit, customization pose; **Movement** (walk, run and stand style, keep walk style) |
| Models | Play as any character, live; restore your character |
| Weapons | Infinite ammo, no reload, rapid fire, one-hit kill, heavy knockback, perfect aim, no melee lock-on, reload in cars; **Aiming** (Fine Aim zoom, spread and turn speed); **Limited Weapons** (one big gun at a time, a stash, swap); **Special ammo** (rocket ammo, fire ammo, money gun, explosive melee); give any weapon, give every weapon, give item, remove weapon, refill all ammo |
| Vehicles | Vehicle god mode, repair; **Toughness** (tank mode, bulletproof glass and tires, no explosion fling, Locked Cars), **Handling** (extra grip, nitrous everywhere, top speed, bouncy and less stiff cars), **Look** (customize the car in the menu, **Vehicle Presets** (4 slots per model), paint from all 548 of the game's colours), **Driving camera**; spawn any of 118 vehicles, remove spawned vehicles, garage, destroy |
| World | Weather, no fog, time of day, freeze time, clear / restore streets; **People** (spawn anyone, crowds, everybody dance / pose, ragdoll all, kill everyone, gangs without guns), **Drops** (cash, money rain, weapons, cash drop chance), **Districts** (hand any district to a gang, reveal the map) |
| Visual | Hide HUD, map arrow, letterbox, filter, render mode, saturation, bloom; **HUD Style** (SR22, Default+, GTA x Saints Row, E3 2005, with matching weapon wheels); **Camera** (field of view, first-person view, turn speed, side offset, height), **Free camera** (fly it or hold the shot, freeze world) |
| Teleport | Districts, cribs, crib garages, every store chain, mission starts, strongholds; teleport to waypoint |
| Emotes | **Poses**, **Actions** (taunts, gang signs, dances), **Voice Lines**, stage a scene, stop, repeat |
| Settings | All tweaks, show active tweaks, save / forget tweaks, Menu UI (text or game look), **Run self-test**, **Export / Import settings**, **Hotkeys**; **Game & saving** (skip intro, load last save, quick save, pause cutscenes, no tutorial popups) |
| Favorites | The rows you pinned |

Rows marked experimental in their help rest on the game's code read, not
yet on play.

Phone cheats are switched through the game's own cheat code. Using one
unlocks it on your phone and marks the save as cheated, as the phone does.

**Kept in your game folder, not in the repo:** saved tweaks
(`saved_tweaks.txt`), saved looks, vehicle presets, favorites, hotkeys, the
kept walk, the weapon stash and the cash safe (`saved_presets.lua`), the export
(`TweakMenu\SRTweakMenu-backup.lua`) and the self-test report
(`TweakMenu\selftest_report.txt`).

## How it works

**The host (`host/host.c`, built as `dinput8.dll` or `SRTweakMenu.asi`)**

- **Loading.** SR2 imports one function from `dinput8.dll`, so Windows loads
  the host from the game folder. It passes `DirectInput8Create` on to the
  real DLL and wraps the keyboard, so the menu can keep keys from the game.
- **Lua.** Lua 5.4 with a `wml` table shaped like Whompay's Mod Loader's,
  which is all the SR1 menu's files use.
- **Hooks.** Lua runs every frame on the game's main thread from the call at
  `0x0052050C`; the text look is drawn with the game's text printer from the
  2D call at `0x00521A69`. With Juiced installed the host waits for Juiced's
  hooks on those calls and chains to them; without it, it hooks the game
  directly.
- **The controller.** The host wraps the game's controller read, so the
  menu can keep buttons from the game while it is open.

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
| `menu.lua`, `layout.lua` | SR Tweak Menu's menu and layout, with SR2's controller handling, the game look, and Favorites' keys |
| `layout_sr2.lua` | Puts the SR2-only rows into the pages that fit them |
| `features.lua` | SR1's row engine (toggle, value, choice, list, action, page), phone cheats, saved tweaks |
| `tab_*.lua` | Each tab's rows, under SR1's row ids |
| `engine.lua`, `gameplay.lua`, `physics.lua`, `qol.lua`, `visual.lua`, `items.lua` | Rows that call the game engine or change its memory |
| `face_body.lua`, `hair.lua`, `vehicle_customize.lua`, `native_walk.lua` | Customize and the in-menu car customizing |
| `presets.lua`, `looks.lua` | Saved looks and vehicle presets (`saved_presets.lua`) |
| `favorites.lua` | The Favorites tab and hotkeys |
| `healthcheck.lua`, `backup.lua` | Run self-test; export and import |
| `gameui.lua`, `hud_skins.lua`, `hud_wheel.lua` | The game look; HUD styles and weapon wheels |
| `game.lua` | SR2's addresses and calls |
| `data/*.lua` | Lists built from the game's own tables: weapons, vehicles, characters, cheats, places, emotes, poses and movement styles |
| `main.lua` | Drives it all every frame |

Game facts (addresses, calling conventions) were read in the game's code;
Juiced Patch's sources were used as a map. No Juiced code is used.

## Testing

- **Offline.** `tools\build_lua_exe.bat`, then `build\lua.exe
  tools\offline_test.lua` opens every tab and page against fake game memory,
  presses every row and reports each row's game calls and any errors. Three
  pages refuse offline because the fake game has no walk catalog or
  customizable car. `--controls`, `--customize`, `--native`, `--selftest` and
  `--favorites` and `--fixes` test one area each, and `tools\test_*.lua` test single
  features.
- **In game.** Settings > Run self-test (on foot, in free roam) checks that
  every game function the menu calls exists, opens every page, reads back
  what Customize, weapons and paint use, lists rows that failed, and writes
  `TweakMenu\selftest_report.txt` with a list of things to try by hand. It
  changes nothing.
- **Live probe.** Set `dev_probe = true` in the installed `mod.ini`. While the
  game runs, anything written to `TweakMenu\probe_in.lua` is run in the
  menu's Lua (with `G`, `F` and `MENU` at hand), and what it prints goes to
  `TweakMenu\probe_out.txt`.
- **Data.** `tools\vpp2.py` lists and extracts SR2's packfiles (the `data`
  lists were built from them).

## Not on Saints Row 2

- **SR1's own:** the SR1 gangs' notoriety and "Saints are enemies" (SR2 has
  its own gangs' rows), SR1's Precise Aim and Weapon Switch, weapon skins
  (SR1's texture work), and Heal on D-pad down and
  D-pad taunts (SR2 has its own healing and taunt buttons).
- **No SR2 way:** quick crouch (the crouch is an animation with no speed
  value), brake lights when stopped (the brake is also reverse), multiplayer
  clothing, and stores open 24/7 (SR2's stores don't close).
- **Partly:** Unlock all collectibles gives what the 60 CDs unlock, not the
  CDs themselves; the money gun throws bills the way you aim; Limited
  Weapons, Limited Cash and Locked Cars are simpler than SR1's (no trunks,
  safe screen or break-ins; a locked car is only the one you're in).
- **Parked:** the SR1 walk and prone kick import (it overflowed the game's
  animation table), and player-only voice pitch.

## Credits

SR Tweak Menu by 00xJS and itsMJQ; its menu, layout and row engine are used
here. itsMJQ built 0.3.1 to 0.4.16 (the game look, Customize, HUD styles and
much more). Saints Row 2 Juiced Patch by Kobraworks Modding was the map to
SR2's engine. Lua 5.4.9 by PUC-Rio, MIT licensed (`third_party/lua-5.4.9`).

MIT licensed, see `LICENSE`.

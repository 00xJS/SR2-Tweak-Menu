# Testing SR Tweak Menu 0.6.0 in Saints Row 2

Almost nothing in 0.4 to 0.6 has been played yet. Every row passes the
offline test, which runs the menu against a fake game. This list is what only
the real game can tell us. Tick what works, and for anything that doesn't,
send the three things under "What to send back".

You don't have to do it all in one go. Sections 1 and 2 matter most.

## Before you start

- Install with `install.bat` (close the game first). Check that
  `TweakMenu\SRTweakMenu\favorites.lua` exists in the game folder.
- Play with Juiced Patch **off** first, then once more with it **on**
  (section 6). With Juiced on, `juiced.ini` should have `SR1MovingAttacks=0`.
- Use a save past the opening mission, in free roam, on foot.
- To reproduce a bug, set `debug = true` in the installed
  `TweakMenu\SRTweakMenu\mod.ini`. It logs every call the menu makes, so the
  log gets big; set it back to `false` afterwards.

## What to send back

1. `TweakMenu\wml.log` (it's overwritten when the game starts, so copy it
   before you start the game again).
2. `TweakMenu\selftest_report.txt`, if you ran the self-test.
3. A line per problem: what you did, what happened, and what you expected. A
   short clip helps for anything visual (HUD, animations, the camera).

## 1. Self-test first (5 minutes)

- [ ] Settings > **Run self-test**, on foot in free roam. Wait until its row
  says NO PROBLEMS or N PROBLEMS (a few seconds). It changes nothing.
- [ ] Send `selftest_report.txt`. Its "Try by hand" list overlaps this one.

## 2. The menu itself

- [ ] F5 opens and closes it. RB + D-pad Down does too on a controller.
- [ ] While it's open, nothing reaches the game: no taunts, compliments, map,
  jumping or shooting when you press menu buttons, on foot and in a car.
- [ ] Settings > Menu UI switches between the game look and plain text. Both
  draw. In plain text, Menu background puts a dark box behind the text.
- [ ] Hide HUD (Visual) leaves the menu visible.
- [ ] Die and respawn at the hospital, then open and close the menu. You can
  still move afterwards. (A known open bug: the player could be left frozen.)
- [ ] Change model (Models), then open and close the menu: you can still move.

## 3. New in 0.5.0

**Favorites and hotkeys**
- [ ] On Player, press **F** (or **Y**) on God mode. PgUp goes to the Favorites tab,
  and God mode is there. Switching it there switches it in Player too.
- [ ] Press F on it again in Favorites: it's gone.
- [ ] Press **H** on God mode, then **F3**. Close the menu and press F3: god
  mode switches. Does a message show at the top left? (We don't know yet.)
- [ ] F3 does nothing else in the game (the key is kept from it).
- [ ] H then F5 or F9 is refused (the menu's own keys). Backspace cancels H.
- [ ] Settings > Hotkeys lists F3; Enter on it clears it.
- [ ] Quit and restart the game: favorites and hotkeys are still there.

**Saved tweaks** (fixed in 0.5.0: they came back ON but did nothing)
- [ ] Turn on No cops and Freeze time (World), then Settings > Save tweaks
  for next time. Restart and load a save. A few seconds after loading, no
  police spawn even with notoriety, and the clock is stopped.

**Customize**
- [ ] Customize > Saved Looks: save a slot, change your hair and skin, load
  the slot. You get the saved look back. (Clothing isn't saved yet.)
- [ ] Customize > Movement > Walk Style, pick a walk, switch on Keep walk
  style. Do a mission or die: your walk comes back by itself.

**Player**
- [ ] Bodyguards > Bodyguard weapon: pick the rifle, spawn a bodyguard. They
  carry it.
- [ ] Items: Give food, then check the game's inventory. Same for drugs.
  (Experimental: it may do nothing. Tell us either way.)

**Weapons**
- [ ] Limited Weapons on: pick up a second big gun (rifle, shotgun, SMG).
  The first goes away; Swap big gun brings it back. After a restart it's still
  in the stash.
- [ ] Give item gives the item picked, as many as How many says.
- [ ] Remove Weapon: taking one weapon away removes just that one.

**Vehicles**
- [ ] Look > Vehicle Presets: save a slot, change a part and the paint,
  load the slot. The car goes back to the saved look.
- [ ] Toughness > Locked Cars on, in a car: gang members and police can't
  pull you out.
- [ ] Open Look > Customize Vehicle while parked, close the menu, drive off,
  open the menu again. The car doesn't stop dead.

**Settings**
- [ ] Export settings, change a few tweaks, Import settings (press twice). Your
  tweaks come back. The file is `TweakMenu\SRTweakMenu-backup.lua`.

**Other fixes to check**
- [ ] Visual: Draw Distance to the furthest, Render mode Low detail, Draw
  Distance back to the game's own, Render mode Normal. The view distance is
  normal again.
- [ ] World: Freeze time on, then Sky to Dawn and back to Default. The clock
  stays stopped. Freeze time off: it runs.
- [ ] Free camera (both stick clicks, or F7; Visual > Free camera > Quick
  Camera shortcut is on by default): fly, open the menu, type in it. The car or character doesn't
  move while you do.

## 4. New in 0.6.0

**Saved Looks with clothing**
- [ ] Save a look wearing a coat, shoes and a chain. Change all three (and
  take one off), load the slot: the same items come back, colours too.
- [ ] A look saved as a man, loaded as a woman: items that don't fit are
  skipped; nothing breaks.

**Customize clothing and the stores** (fixed)
- [ ] Wear something from Customize > Clothing, then walk into a clothing
  store, the barber and your crib's wardrobe: they all open.

**Aiming**
- [ ] Weapons > Aiming & switching > Fine Aim zoom at x0.5: aim a gun; the
  camera comes in closer than before. Back to x1: normal.
- [ ] Fine Aim spread at x0: shots while aiming go dead on.
- [ ] Fine Aim turn speed at x0.3: the mouse and stick turn slower while
  aiming only.

**Bloom and camera**
- [ ] Visual > Bloom at 0 (off) and x2 at night by street lights: the glow
  goes and comes back stronger.
- [ ] Visual > Camera > Camera side offset +0.5, then start running: the
  camera sits over your right shoulder. Camera height moves it up and down.

**Cash safe**
- [ ] Player > Cash safe: Deposit $10,000, then Withdraw: your cash goes
  down and comes back (the safe's amount shows on Deposit).
- [ ] Limited Cash on: away from a crib it says to use a crib. At your crib's
  cash pickup it works.
- [ ] Limited Cash on, carrying cash: die. After you respawn you have no
  cash; the safe still has its money.

**Locked Cars** (changed)
- [ ] On, in a car: gang members and police can't pull you out. Get out, then
  get back in: you can.

## 5. MJQ's 0.4 work, never confirmed in game

**Customize**
- [ ] Face & Body: the sliders move your face live, with the plastic surgeon's
  names. Back asks to save or discard; Discard puts it back.
- [ ] Body Type: gender, fat, muscle, age and skin colour.
- [ ] Hair: each list previews as you move, colours work, Discard restores.
- [ ] Clothing, Jewelry, Tattoos, Mission Outfits: pick an item, its variant
  and wear option; save and discard both work.
- [ ] Customization T-pose: the character holds the rest pose and doesn't
  collapse.
- [ ] Voice: the six stock voices change your voice. Pedestrians still talk.
- [ ] Movement: previews loop, stop when you move off the row, and don't show
  weapons or props they shouldn't.

**Models and emotes**
- [ ] Models: switch to a few characters in different groups; each uses its
  own voice. Restore your character works.
- [ ] Emotes > Poses and Actions play on you without a T-pose. Repeat loops
  them; Stop and leaving the tab end them.
- [ ] World > People > Everybody...: crowds play it; Back to normal stops it.

**Combat**
- [ ] Fire ammo sets people alight like a molotov, and they die of it.
- [ ] Money gun: bills on every shot, including full-auto bursts.

**Notoriety and people**
- [ ] Persistent gang dots: gang members, including ones in cars, show on the
  map in their gang's colour; police blend red and blue.
- [ ] Join Gang: pick a gang; its members don't attack you, and Recruit
  nearest gang member gets one to follow, fight and get in your car.
- [ ] Spawn bodyguard, Dismiss homies, Remove spawned people: only the
  menu's own people are removed.

**Vehicles**
- [ ] Customize Vehicle while parked: parts and colours preview live, the
  sticks (or I/J/K/L and Z/X) orbit and zoom, the car doesn't creep.

**HUD**
- [ ] Visual > HUD Style: SR22, Default+, GTA x Saints Row and E3 2005 each
  draw correctly, with matching weapon wheels. They survive a reload, a store
  and the pause menu.

**Other**
- [ ] Teleport categories open their own pages; teleports land you there.
- [ ] Quick Camera: both stick clicks open the camera page and start it.

## 6. Things we already know are missing

No need to report these. Precise Aim, weapon skins, player-only voice pitch,
the SR1 walk and kick import, getting busted under Limited Cash, and SR1's
full Limited Weapons and Locked Cars (trunks, the safe screen, break-ins)
aren't built yet.

## 7. Juiced on

- [ ] Switch Juiced on and repeat sections 1 and 2. Note anything that
  differs from Juiced off.
- [ ] Look in `wml.log` for lines saying "isn't what the menu expects
  (another mod?)": they name rows that stand aside for Juiced.

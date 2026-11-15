# 0.4.16 — 0.4.12 stability base

- Returned the active menu and native host to the 10:17 p.m. 0.4.12 build. The 0.4.13–0.4.15 SR1 animation table import, lookup expansion, native SR1 kick routing and player-only pitch experiment are inactive. Their source and assets are kept in the handoff prerequisites.
- Removed the Saints Row 1 movement choice and Kick (LB) toggle from the active menu; neither the imported movement nor prone kick can start through the menu. The game no longer loads the 48 imported movement/kick clips or four imported mapping tables.
- Kept the 0.4.12 Fire Ammo damage behavior and NPC dialogue restoration. This build does not reintroduce the shared voice-bank edits that silenced pedestrians; voice pitch remains unavailable pending a verified player-only implementation.
- Carried forward independent actor ownership checks for emote previews, spawned people and vehicles, hair restore and model switching. Join Gang can choose a team directly. Vehicle preview calls the game's immediate stop function while the menu is open.
- Borrowed emotes use registered resident clips only; the experimental fallback that invoked the SR1 movement file loader is disabled. Gameplay and visual stability still need in-game confirmation.

# 0.4.12

- Every open tweak-menu page captures gameplay movement and buttons, including pages outside Customize and Emotes. Camera preview still reads the raw controls.
- Native menu capture forces full controller blocking even if a later filter request asks for partial input.
- Menu control locks track the exact player handle and native input token. Closing releases only the lock acquired by the menu. Existing mission locks and replacement tokens are preserved.
- Death/model replacement releases the owned input token without reading the old character, then acquires a lock for the current player when ready.
- Charged punches and the SR1 animation-data import remain unfinished; this update does not claim those are fixed.

# 0.4.11

- Custom HUDs and weapon-wheel skins read the actual HUD document namespace. Juiced modern/classic and autohide policies use the actual native settings; selected skins no longer inherit the idle health-circle fade.
- Customization T-pose preserves the native rig bind offsets and world transform instead of zeroing bone translations, which collapsed the character.
- Fire Ammo uses the game's configured fire damage per second. Removed the guessed percentage-of-health drain and repeated manual screams; native burning owns damage and reactions.
- Includes the charged-punch trigger diagnostics Claude built after 0.4.10. Charged punches are still under investigation, not claimed fixed.
- Offline checks do not establish in-game appearance or combat behavior.

# 0.4.10

- Kick (LB) happens on the spot where you press it. It no longer turns to or latches onto the person next to you, which was the grab that started with every kick.
- No kick while sprinting.
- On someone who is down, LB only does the prone kick. Kick the same person twice and the third is the long prone kick, as a small combo.
- Hide HUD no longer turns the menu into the text look. It hides only the game's HUD now; the engine's own HUD hide also hid the layer the menu is drawn on.
- Emotes load an animation that isn't in memory before playing it, including Taunt 1-3 from multiplayer.
- Saints Row 1 movement says exactly why when it can't switch on, so the next log pins it down.
- Not yet seen in game: all of the above.

# 0.4.9

- Pedestrian dialogue is back. The voice banks behind Voice pitch are shared by every pedestrian of that voice type, not only the six player voices, so they are removed. Voice pitch shows as not working until it is redone for the player only.
- D-pad left and right (taunt, compliment) no longer reach the game while the menu is open. Your controller sends the D-pad to the game outside the button bytes the lock checked, so the lock never caught it. Now a held-back D-pad press drops every game action for that moment.
- The kick no longer floats. The game's kick aimed its lunge 1 m above the target; it is now flat, as punches are.
- The kick no longer fires twice: a held LB could look released for a frame. A grab that starts with the kick is ended, and the log says so.
- Saints Row 1 movement needs no other walk picked first. It replaces whatever walk you have.
- People set alight by Fire ammo scream while they burn.
- HUD Style draws even when the game's HUD script hides its health table: health then comes from the game itself, sprint shows full and respect empty.
- Not yet seen in game: all of the above.

# 0.4.8

- Fire ammo burns people to death as a molotov does. The game's fire on its own did no damage without a weapon behind it, so they now lose about a quarter of their health a second while burning. The kill and notoriety are yours.
- Customize, Emotes and car customizing hold you and the car with the game's own control lock, as well as keeping the controller back. Your character and the car no longer creep forward. The lock lets go as soon as you leave those pages or close the menu.
- Face & Body uses the plastic surgeon's own names (for example "Jowls Height", not "jowls elevation"). Any the game can't name show in Title Case.
- Saints Row 1 movement has no row of its own above Movement now. It is the first entry in Customize > Movement > Walk Style, like any other walk. Picking another walk style turns it off.
- HUD Style: works with Juiced Patch's HUD options. Juiced's autohide hid the stock health group at full health, and that switched the new HUD off. Only Juiced's "HUD off" hides it now. When the game's HUD shows instead, the log says why.
- Not yet seen in game: all of the above, and all of 0.4.7.

# 0.4.7

- Kick (LB) is the game's own melee attack now, as LB is in Saints Row 1. Someone on the ground in reach gets the prone kick, picked by distance; otherwise you do the standing kick with its step forward. It can lead into punches like any other strike.
- The kick no longer starts a move by hand and writes nothing into your character. That hand-started move is what looked like an emote and could leave you stuck.
- Hard lock on menu buttons. A button the menu holds back that still reaches the game has every game action dropped for that moment, so scrolling the menu can't set off taunts or compliments, and LB can't grab while it kicks. The triggers are covered too. The log says how often the lock was needed.
- Saints Row 1 movement can switch on outside cutscenes. It refused every time in free roam because the game's file loader expected a cutscene to be running.
- Not yet seen in game: all of the above.

# 0.4.6

- Visual > HUD Style adds the original SR22 artwork and meters, Default+ using SR2's HUD, GTA x Saints Row, and E3 2005 adaptations. Matching wheel artwork uses SR2's native twelve slots and selection controls.
- SR22 retains the original gold sprint/red health segments, slanted edges, gradients, gloss, tribal frame, supplied paint and authored ammo digits. Meter fills remain continuous. HUD Settings controls cluster motion.
- HUD ownership restores native rendering on reloads, pause/store screens, missing geometry, hidden HUD and rendering errors. Menu rendering stays independent.
- Fixed native Lua 5.0 syntax in face/body and walk catalogs. Native bridge errors now return failure and discard partial captures instead of reporting success.
- New native chunks pass the actual Lua 5.0 parser. HUD appearance, wheel depth and native animation transitions still require in-game verification.

# 0.4.5

- Customize > Movement adds Saints Row 1 movement, using converted SR1 walk, run and sprint files through SR2's native movement resolver.
- Select the Default Walk Style before enabling it. Distinct directional, custom-walk and object-context states retain SR2 behavior.
- The player-only override preserves native movement control and restores native state resolution when disabled. It does not play movement as an emote.
- Missing assets, changed characters, occupied vehicles, unsupported hooks and full native animation pools disable the override safely.
- Imported keyframes and rig mappings pass offline validation. Actual movement transitions and footstep cadence still need live verification.

# 0.4.4

- Player > Notoriety adds Persistent gang dots, including gang members in vehicles. Colors follow each faction; police dots blend red and blue.
- Bodyguards use the native follower limit and party behavior, receive a weapon and ammo, and retry joining briefly while spawning finishes.
- Recruitment rejects dead, already assigned and other-player characters, and reports whether joining succeeded.
- Dismissing cancels pending bodyguards. Removing menu-spawned people checks character, level and player identity before deleting anyone.

# 0.4.3

- LB uses the regular native combat kick, with Y grabbing while enabled.
- Teleport categories open destination submenus.
- Fire Ammo uses normal damaging fire instead of cinematic continuous fire.
- Face controls accept numeric native IDs. Body Type groups gender, fat, muscle, age and skin color with numeric controls.
- Vehicle parts preview inside the tweak menu with orbit controls and save/discard.
- Native Walk Style uses the verified game catalog. Context-dependent motion clips remain previews.
- Preview cleanup runs independently on close and tab changes. Native input capture protects a failed menu update.
- Preserves 0.4.2 crowd animations, emote filtering and gang recruitment.
# 0.4.2

- Emotes lists only what a person can play. Unused names and vehicle or prop actions are gone from Poses, Actions and Every Action.
- World > People > Everybody... plays the animation on each person as a looping clip, as Emotes does on you. Back to normal stops it.
- Player > Bodyguards > Recruit nearest gang member: the nearest member of your side within 20 metres follows you. Works for the gang picked in Join Gang.

# 0.4.1

- Fixed invalid scratch-buffer slots aborting pose cleanup and voice-pitch cleanup.
- Rebuild the styled menu after the HUD interface is recreated. Drawing failures fall back to terminal mode during recovery.

# 0.4.0

- Ordinary menu tabs allow movement and looking. Customize and Emotes capture gameplay controls.
- Movement and poses use continuous native loops. Preview-only styles say so before applying.
- Face and body sliders and six stock voices are built into Customize. Voice pitch ranges from deeper to higher.
- Customization T-pose uses the rig rest pose. Menu previews suppress ambient idle fidgets and temporarily unequip weapons.
- Money Gun counts native discharges during automatic bursts. Fire Ammo ignites weapon-hit people.
- Prone Kick requests native target search outside melee lock and includes settled bodies.
- Hide HUD keeps the menu visible and owns one balanced hide request. Both stick clicks open Free Camera.
- Vehicle customization uses the full native editor where the vehicle is parked.
# 0.3.5

- Player, Customize, and Models are the first three tabs.
- Customize shows one Restore outfit and one Customization pose. Movement opens with a wider view so you can see the whole animation.
- The submenu footer says Return next to the back button.

# 0.3.4

- Menu input is captured from the opening frame through the closing frame. Browsing Emotes stops the current preview and pauses Repeat.
- Movement previews follow the highlighted style or clip and stay in the fitting room until you move to another row.
- LB uses the game's native melee strike against an eligible downed person.

# 0.3.3

- Face & Body opens the in-world plastic surgeon after the story intro.
- Head hair, beard, mustache, sideburns and eyebrows have vertical style lists. Highlight to preview and Accept to keep. Discard restores the previous style and colors.

# 0.3.2

- Customize separates Face & Body, Hair, Clothing, Jewelry, Tattoos and Mission Outfits. Select an item, then choose its variant and wear option.
- Back, closing the menu and switching tabs prompt to save or discard the staged item. Face & Body opens the game's character creator and hands it the controls.
- Movement previews locomotion, combat stances and melee clips in the fitting room. Walk, run and stand styles can be previewed before applying.
- Removed duplicate Join Gang and Saints are enemies rows from Notoriety.

# 0.3.1

- Emotes try your character's clip first, then try loaded clips from other characters that share the main human rig.
- Stop, leaving Emotes, and death end the preview and cancel Repeat. Unavailable clips show a message.
- Poses are temporary previews. Some actions need props or a scene to look as they do in the game.



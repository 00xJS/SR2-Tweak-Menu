-- Every weapon in the game's weapons.xtbl, vehicle-mounted guns left out (they live on
-- heli_fighter_01, sp_apc01 etc.). { xtbl name, display name, inventory slot } plus:
--   melee / thrown = true  (slot "melee" / "thrown"; pimpcane is in the shotgun slot)
--   class          = weapons.xtbl <Weapon_Class>
--   cheat          = index of the cheats.xtbl entry that gives it (that entry's name is
--                    where most display names come from; the rest are the in-game names)
--   unlockable     = weapons.xtbl flags it "unlockable"
-- Note the cheat gives "deserteagle" while the table name is "desert eagle".
-- T.SPECIAL: drug/food items, cutscene and mission-only entries. Same shape, plus a note.
local T = {
  { "grenade",              "Grenade",                    "thrown", thrown = true, class = "thrown", cheat = 40 },
  { "molotov",              "Molotov",                    "thrown", thrown = true, class = "thrown", cheat = 48 },
  { "pipe_bomb",            "Pipe Bomb",                  "thrown", thrown = true, class = "thrown", cheat = 50 },
  { "flashbang",            "Flashbang",                  "thrown", thrown = true, class = "thrown", cheat = 37 },
  { "satchel",              "Satchel Charge",             "thrown", thrown = true, class = "thrown", cheat = 98 },
  { "glock",                "NR4",                        "pistol", class = "pistol", cheat = 41 },
  { "beretta",              "Vice 9",                     "pistol", class = "pistol", cheat = 105 },
  { "magnum",               "44 Shepherd",                "pistol", class = "pistol", cheat = 3 },
  { "desert eagle",         "GDHC",                       "pistol", class = "pistol", cheat = 39 },
  { "Holt_55",              "Holt 55",                    "pistol", class = "pistol", cheat = 44, unlockable = true },
  { "tec9",                 "T3K Urban",                  "smg", class = "smg", cheat = 102 },
  { "SKR-9",                "SKR-9",                      "smg", class = "smg", cheat = 96 },
  { "Gal43",                "GAL 43",                     "smg", class = "smg", cheat = 38, unlockable = true },
  { "twelve_gauge",         "12 Gauge",                   "shotgun", class = "shotgun", cheat = 2 },
  { "pump_action_shotgun",  "Tombstone",                  "shotgun", class = "shotgun", cheat = 104 },
  { "AS14",                 "AS14 Hammer",                "shotgun", class = "shotgun", cheat = 32 },
  { "ak47",                 "K6 Krukov",                  "rifle", class = "rifle", cheat = 42 },
  { "m16",                  "M16",                        "rifle", class = "rifle", note = "in the table but no store/cheat entry" },
  { "AR50",                 "AR-50",                      "rifle", class = "rifle", cheat = 29 },
  { "AR200",                "AR-200",                     "rifle", class = "rifle", cheat = 31 },
  { "minigun",              "Minigun",                    "rifle", class = "minigun", cheat = 47, unlockable = true },
  { "samurai_sword",        "Samurai Sword",              "melee", melee = true, class = "sword", cheat = 97 },
  { "shock_paddles",        "Shock Paddles",              "melee", melee = true, class = "knuckles", cheat = 99, unlockable = true },
  { "pepper_spray",         "Pepper Spray",               "melee", melee = true, class = "pepper spray", cheat = 93 },
  { "machete",              "Machete",                    "melee", melee = true, class = "knife", cheat = 45 },
  { "butterfly_knife",      "Butterfly Knife",            "melee", melee = true, class = "knife" },
  { "pimp_slap",            "Pimp Slap",                  "melee", melee = true, class = "pimp slap", cheat = 52 },
  { "sledgehammer",         "Sledgehammer",               "melee", melee = true, class = "bat", cheat = 100 },
  { "stun_gun",             "Stun Gun",                   "melee", melee = true, class = "stungun", cheat = 101 },
  { "tire_iron",            "Tire Iron",                  "melee", melee = true, class = "nightstick", cheat = 103 },
  { "rpg_launcher",         "RPG Launcher",               "launcher", class = "launcher", cheat = 94 },
  { "nightstick",           "Nightstick",                 "melee", melee = true, class = "nightstick", cheat = 49 },
  { "flamethrower",         "Flamethrower",               "launcher", class = "flamethrower", cheat = 36, unlockable = true },
  { "knife",                "Knife",                      "melee", melee = true, class = "knife", cheat = 43 },
  { "baseball_bat",         "Baseball Bat",               "melee", melee = true, class = "bat", cheat = 33 },
  { "mcmanus2010",          "McManus 2010",               "launcher", class = "rifle", cheat = 46 },
  { "rpg_annihilator",      "RPG Annihilator",            "launcher", class = "launcher", cheat = 95, unlockable = true },
  { "XS-2",                 "XS-2 Ultimax",               "shotgun", class = "shotgun", cheat = 106, unlockable = true },
  { "chainsaw",             "Chainsaw",                   "melee", melee = true, class = "chainsaw", cheat = 34, unlockable = true },
  { "AR50_launcher",        "AR-50 with Grenade Launcher", "rifle", class = "rifle", cheat = 30, unlockable = true },
  { "dual_swords",          "Dual Swords",                "melee", melee = true, class = "sword", note = "NPC melee set; not sold or given by any cheat" },
  { "fireext",              "Fire Extinguisher",          "launcher", class = "waterspray", cheat = 35 },
  { "pimpcane",             "Pimp Cane",                  "shotgun", class = "shotgun", cheat = 51, unlockable = true },
}

T.SPECIAL = {
  { "bean_bag_gun",         "Bean Bag Gun",               "shotgun", class = "shotgun", unlockable = true, note = "flagged cutscene only" },
  { "video_camera",         "Video Camera",               "launcher", class = "video camera", note = "activity item (no damage)" },
  { "pcp",                  "PCP",                        "unarmed", class = "thrown", note = "drug item" },
  { "large_softdrink",      "Large Soft Drink",           "unarmed", class = "thrown", note = "drug/food item" },
  { "cellphone",            "Cellphone",                  "unarmed", class = "cutscene only", note = "cutscene only" },
  { "40oz",                 "40oz",                       "unarmed", class = "thrown", note = "drug/liquor item" },
  { "Detonator",            "Detonator",                  "melee", melee = true, class = "script", note = "mission script item" },
  { "giegerCounter",        "Geiger Counter",             "melee", melee = true, class = "script", note = "mission script item" },
  { "pyroBox",              "Pyro Box",                   "thrown", thrown = true, class = "thrown", note = "activity/mission thrown item" },
  { "satchel_barrel",       "Satchel Barrel",             "thrown", thrown = true, class = "thrown", note = "mission thrown item" },
  { "AR200_ss03",           "AR-200 (ss03 mission copy)", "rifle", class = "rifle", note = "copy of AR200 for mission ss03" },
}

return T

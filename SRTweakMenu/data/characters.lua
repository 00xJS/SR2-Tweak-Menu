-- Play-as characters: the "Character" entries of cheats.xtbl (via cheats.txt).
-- { cheat index, preset name, display name }. T.RESTORE is the index of "Restore Player".
-- Caution: all of these sit in cheats.xtbl's <TableTemplates> block, not its <Table>, so
-- the game may not load them as cheats; the preset names (character presets, e.g.
-- npc_Gat) are still real and can be used with whatever play-as call the menu ends up with.
local T = {
  { 133,  "npc_Aisha",              "Aisha" },
  { 134,  "npc_barbershop",         "Barbershop" },
  { 135,  "npc_service_bartender",  "Bartender" },
  { 136,  "npc_biker_female",       "Biker Female" },
  { 137,  "npc_biker_male",         "Biker Male" },
  { 138,  "npc_bum",                "Bum" },
  { 139,  "npc_Carlos_blood",       "Carlos Bloody" },
  { 140,  "npc_cheerleader",        "Cheerleader" },
  { 141,  "npc_construction",       "Construction" },
  { 142,  "npc_cop",                "Cop" },
  { 143,  "npc_cowboy",             "Cowboy" },
  { 144,  "npc_Dane",               "Dane" },
  { 145,  "npc_Donnie",             "Donnie" },
  { 146,  "npc_fbi",                "FBI" },
  { 147,  "npc_freckle_bitch",      "Freckle Bitch" },
  { 148,  "npc_Gat",                "Gat" },
  { 149,  "npc_General",            "General" },
  { 150,  "npc_hazmat",             "Hazmat" },
  { 151,  "npc_ho",                 "Ho" },
  { 152,  "npc_JaneV",              "JaneV" },
  { 153,  "npc_Jessica",            "Jessica" },
  { 154,  "npc_Julius",             "Julius" },
  { 155,  "npc_Jyunichi",           "Jyunichi" },
  { 156,  "npc_Kazuo",              "Kazuo" },
  { 157,  "npc_Maero",              "Maero" },
  { 158,  "npc_Matt",               "Matt" },
  { 159,  "npc_mime",               "Mime" },
  { 160,  "npc_patient",            "Patient" },
  { 161,  "npc_Pierce",             "Pierce" },
  { 162,  "npc_pirate",             "Pirate" },
  { 163,  "npc_roid_freak",         "Roid Freak" },
  { 164,  "npc_Shaundi",            "Shaundi" },
  { 165,  "npc_Shogo",              "Shogo" },
  { 166,  "npc_sportsfan",          "Sportsfan" },
  { 167,  "npc_stripper_female",    "Stripper" },
  { 168,  "npc_sunbather_female",   "Sunbather" },
  { 169,  "npc_Sunshine",           "Sunshine" },
  { 170,  "npc_Tobias",             "Tobias" },
  { 171,  "npc_Troy",               "Troy" },
  { 172,  "npc_Wong",               "Wong" },
  { 173,  "npc_ZombMale_A",         "Zombie" },
}

T.RESTORE = 132

return T

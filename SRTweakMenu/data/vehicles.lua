-- Every vehicle in the game's vehicles.xtbl that a player can drive, with its name and
-- group from the vehicle's own <name>_veh.xtbl. { xtbl name, display name, type, group,
-- special type }; type is car/bike/boat/heli/plane (trucks, vans, buses and SUVs count as
-- car). cheat = the cheats.xtbl index that drops one. Left out (T.NOT_DRIVABLE): trailers,
-- the El train and the cutscene-only copies (_cs, _interior, ...).
-- The display names are the table's, so sp_ufo01 is "Destroy" (the cheat calls it UFO),
-- heli_standard_03 "Gyro Daddy" (cheat: Gyrocopter), bike_pocket01 "Peewee" (Pocket Bike).
local T = {
  { "sp_atv01",               "Toad",                 "car",  "Car - compact",            "ATV",        cheat = 122 },
  { "car_2dr_exoticsports01", "Attrazione",           "car",  "Car - sports",             "None",       cheat = 56 },
  { "bike_rocket01",          "Tetsuo",               "bike", "Motorcycle",               "None" },
  { "car_2dr_exoticsports03", "Zenith",               "car",  "Car - sports",             "None",       cheat = 126 },
  { "car_2dr_exoticsports04", "Vortex",               "car",  "Car - sports",             "None",       cheat = 125 },
  { "car_2dr_exoticsports05", "Bezier",               "car",  "Car - sports",             "None" },
  { "car_2dr_standard03",     "Cosmos",               "car",  "Car - standard",           "None" },
  { "car_2dr_standard06",     "Go!",                  "car",  "Car - standard",           "None" },
  { "truck_2dr_semi01",       "Peterliner",           "car",  "Truck - big (semi cab)",   "None" },
  { "wagon_4dr_01",           "Komodo",               "car",  "Station Wagon",            "None" },
  { "wagon_4dr_sprt01",       "Keystone",             "car",  "Station Wagon",            "None" },
  { "van_2dr_riot01",         "Peacekeeper",          "car",  "Truck - trailer",          "SWAT Van" },
  { "truck_2dr_armored01",    "Titan",                "car",  "Truck - trailer",          "None",       cheat = 88 },
  { "sp_charterbus02",        "Cheetah",              "car",  "Truck - trailer",          "Bus" },
  { "car_2dr_compact03",      "Mockingbird",          "car",  "Car - compact",            "None" },
  { "car_2dr_compact04",      "Halberd",              "car",  "Car - compact",            "None" },
  { "suv_2dr_01",             "Swindle",              "car",  "SUV",                      "None" },
  { "suv_4dr_04",             "Nordberg",             "car",  "SUV",                      "None" },
  { "car_4dr_std01",          "Capshaw",              "car",  "Car - standard",           "None" },
  { "car_2dr_standard07",     "Danville",             "car",  "Car - big domestic",       "None" },
  { "car_2dr_muscle01",       "Hammerhead",           "car",  "Car - big domestic",       "None" },
  { "car_2dr_muscle02",       "Bootlegger",           "car",  "Car - big domestic",       "None",       cheat = 62 },
  { "car_2dr_muscle03",       "La Fuerza",            "car",  "Car - big domestic",       "None" },
  { "car_2dr_luxury04",       "Nelson",               "car",  "Car - luxury",             "None" },
  { "car_2dr_exolux01",       "Baron",                "car",  "Car - luxury",             "None",       cheat = 60 },
  { "car_4dr_luxury01",       "Zomkah",               "car",  "Car - luxury",             "None" },
  { "car_4dr_luxury04",       "Eiswolf",              "car",  "Car - luxury",             "None",       cheat = 66 },
  { "car_4dr_luxury05",       "Socialite",            "car",  "Car - luxury",             "None" },
  { "car_4dr_standard03",     "Zimos",                "car",  "Car - standard",           "None" },
  { "truck_2dr_mover01",      "Mule",                 "car",  "Truck - big (semi cab)",   "None" },
  { "truck_2dr_pickup02",     "Varsity",              "car",  "Truck - small (pickups)",  "None",       cheat = 123 },
  { "suv_4dr_06",             "Alaskan",              "car",  "SUV",                      "None" },
  { "suv_4dr_luxury01",       "Mag",                  "car",  "SUV",                      "None",       cheat = 72 },
  { "suv_4dr_luxury05",       "Bulldog",              "car",  "SUV",                      "None",       cheat = 63 },
  { "truck_2dr_pickup03",     "Thorogood",            "car",  "Truck - small (pickups)",  "None" },
  { "truck_2dr_pickup06",     "Legion",               "car",  "Truck - small (pickups)",  "None" },
  { "truck_2dr_classic01",    "Betsy",                "car",  "Truck - small (pickups)",  "None" },
  { "truck_2dr_mail01",       "Newman",               "car",  "Truck - small (pickups)",  "None" },
  { "car_2dr_muscle04",       "Phoenix",              "car",  "Car - sports",             "None",       cheat = 76 },
  { "car_2dr_luxury02",       "Stiletto",             "car",  "Car - big domestic",       "None" },
  { "car_4dr_standard02",     "Zircon",               "car",  "Car - luxury",             "None" },
  { "car_2dr_exoticsports06", "Superiore",            "car",  "Car - sports",             "None",       cheat = 85 },
  { "car_2dr_sports03",       "Raycaster",            "car",  "Car - sports",             "None",       cheat = 81 },
  { "car_2dr_sports05",       "Venom Classic",        "car",  "Car - sports",             "None",       cheat = 124 },
  { "car_2dr_sports06",       "Magma",                "car",  "Car - sports",             "None" },
  { "suv_4dr_luxury06",       "Quasar",               "car",  "SUV",                      "None",       cheat = 77 },
  { "suv_4dr_fbi01",          "FBI",                  "car",  "SUV",                      "FBI",        cheat = 67 },
  { "sp_limosuv01",           "The Job",              "car",  "SUV",                      "None",       cheat = 87 },
  { "car_4dr_exoticluxury01", "Justice",              "car",  "Car - standard",           "None",       cheat = 70 },
  { "car_4dr_police01",       "Five-O",               "car",  "Car - standard",           "Police",     cheat = 68 },
  { "car_4dr_taxi01",         "Taxi",                 "car",  "Car - standard",           "Taxi",       cheat = 86 },
  { "van_4dr_01",             "NRG V8",               "car",  "Van/Minivan",              "None" },
  { "car_2dr_sports07",       "Hayate Z70",           "car",  "Car - sports",             "None" },
  { "car_4dr_sports01",       "Voxel",                "car",  "Car - standard",           "None" },
  { "car_4dr_sports02",       "Wakazashi",            "car",  "Car - standard",           "None" },
  { "sp_bagcart01",           "Bag Boy",              "car",  "Car - compact",            "Industrial", cheat = 59 },
  { "truck_2dr_tow01",        "Shaft",                "car",  "Truck - big (semi cab)",   "Tow Truck",  cheat = 83 },
  { "truck_2dr_fire01",       "Blaze",                "car",  "Truck - big (semi cab)",   "Firetruck",  cheat = 57 },
  { "bike_rocket02",          "Kenshin",              "bike", "Motorcycle",               "None",       cheat = 108 },
  { "boat_wavecraft01",       "Shark",                "boat", "Boat",                     "None",       cheat = 116 },
  { "boat_speed01",           "Miami",                "boat", "Boat",                     "None",       cheat = 114 },
  { "boat_speed02",           "Python",               "boat", "Boat",                     "None",       cheat = 115 },
  { "plane_fighter01",        "Wolverine",            "plane", "Airplane",                 "None",       cheat = 121 },
  { "heli_4dr_police01",      "Oppressor",            "heli", "Helicopter",               "None" },
  { "heli_fighter_01",        "Tornado",              "heli", "Helicopter",               "None",       cheat = 120 },
  { "plane_biplane01",        "Parrot",               "plane", "Airplane",                 "None" },
  { "truck_2dr_septic01",     "Septic Avenger",       "car",  "Truck - big (semi cab)",   "Industrial", cheat = 82 },
  { "truck_4dr_pickup04",     "Compensator",          "car",  "Truck - big (semi cab)",   "None" },
  { "car_4dr_classic01",      "Hollywood",            "car",  "Car - big domestic",       "None",       cheat = 69 },
  { "sp_dlvry_truck01",       "Delivery Truck",       "car",  "Truck - big (semi cab)",   "None" },
  { "sp_apc01",               "Bear",                 "car",  "Truck - big (semi cab)",   "Industrial", cheat = 61 },
  { "sp_bulldozer01",         "Bulldozer",            "car",  "Truck - big (semi cab)",   "Industrial", cheat = 64 },
  { "sp_backhoe01",           "Backhoe",              "car",  "Truck - big (semi cab)",   "Industrial", cheat = 58 },
  { "sp_combine",             "Kent",                 "car",  "Truck - big (semi cab)",   "Industrial", cheat = 71 },
  { "truck_2dr_garbage01",    "Stilwater Municipal",  "car",  "Truck - big (semi cab)",   "Industrial", cheat = 84 },
  { "truck_2dr_construct01",  "Longhauler",           "car",  "Truck - big (semi cab)",   "Industrial", cheat = 73 },
  { "sp_hearse01",            "Reaper",               "car",  "Car - standard",           "Limo",       cheat = 79 },
  { "sp_metermaid01",         "Quota",                "car",  "Car - standard",           "Meter Maid", cheat = 78 },
  { "sp_limo01",              "Status Quo",           "car",  "Car - standard",           "Limo" },
  { "van_4dr_03",             "Topher",               "car",  "Van/Minivan",              "None" },
  { "van_4dr_04",             "Voyage",               "car",  "Van/Minivan",              "None" },
  { "van_4dr_news01",         "Anchor",               "car",  "Van/Minivan",              "News Van",   cheat = 54 },
  { "minivan_4dr_01",         "Westbury",             "car",  "Van/Minivan",              "None" },
  { "sp_ambulance01",         "Ambulance",            "car",  "Truck - big (semi cab)",   "Ambulance",  cheat = 53 },
  { "bike_exotic01",          "Kaneda",               "bike", "Motorcycle",               "None",       cheat = 107 },
  { "bike_standard01",        "Shard",                "bike", "Motorcycle",               "None" },
  { "bike_standard02",        "Melbourne",            "bike", "Motorcycle",               "None",       cheat = 109 },
  { "truck_2dr_monster01",    "Atlasbreaker",         "car",  "Truck - big (semi cab)",   "None",       cheat = 55 },
  { "plane_standard01",       "Woodpecker",           "plane", "Airplane",                 "None" },
  { "car_4dr_classic02",      "Ethel",                "car",  "Car - big domestic",       "None" },
  { "car_4dr_standard07",     "Churchill",            "car",  "Car - big domestic",       "None" },
  { "car_4dr_standard09",     "Wellington",           "car",  "Car - big domestic",       "None" },
  { "car_4dr_lowrider01",     "Compton",              "car",  "Car - big domestic",       "None",       cheat = 65 },
  { "sp_derbycar01",          "Ruckus",               "car",  "Car - big domestic",       "None" },
  { "sp_derbycar02",          "Rampage",              "car",  "Car - big domestic",       "None",       cheat = 80 },
  { "sp_cart01",              "Knoxville",            "car",  "Car - compact",            "None" },
  { "sp_hearse02",            "Hounfor",              "car",  "Car - standard",           "Limo" },
  { "boat_speed03",           "Hurricane",            "boat", "Boat",                     "None",       cheat = 113 },
  { "sp_derbycar03",          "Rumble",               "car",  "Car - big domestic",       "None" },
  { "sp_derbycar04",          "Frenzy",               "car",  "Van/Minivan",              "None" },
  { "sp_shortbus01",          "DonoVan",              "car",  "Truck - big (semi cab)",   "Bus" },
  { "sp_RV01",                "Buffalo",              "car",  "Truck - big (semi cab)",   "Bus" },
  { "car_2dr_buggy01",        "Mongoose",             "car",  "Car - compact",            "None",       cheat = 74 },
  { "sp_novelty01",           "Oring",                "car",  "Car - big domestic",       "None",       cheat = 75 },
  { "bike_chopper01",         "Sabretooth",           "bike", "Motorcycle",               "None",       cheat = 110 },
  { "heli_standard_01",       "Horizon",              "heli", "Helicopter",               "None",       cheat = 118 },
  { "bike_moped01",           "Widowmaker",           "bike", "Motorcycle",               "None",       cheat = 112 },
  { "heli_standard_02",       "Thompson",             "heli", "Helicopter",               "Industrial" },
  { "plane_jet01",            "Snipes 57",            "plane", "Airplane",                 "None",       cheat = 119 },
  { "boat_standard01",        "Maelstrom",            "boat", "Boat",                     "None" },
  { "bike_dirt01",            "Sandstorm",            "bike", "Motorcycle",               "None",       cheat = 111 },
  { "boat_yacht01",           "Skipper",              "boat", "Boat",                     "None",       cheat = 117 },
  { "boat_yacht02",           "Convict",              "boat", "Boat",                     "None" },
  { "sp_RV02",                "Buffalo B",            "car",  "Truck - big (semi cab)",   "Bus" },
  { "heli_4dr_police02",      "Side Shooter",         "heli", "Helicopter",               "None" },
  { "heli_standard_03",       "Gyro Daddy",           "heli", "Helicopter",               "None",       cheat = 129 },
  { "sp_ufo01",               "Destroy",              "heli", "Helicopter",               "None",       cheat = 130 },
  { "bike_pocket01",          "Peewee",               "bike", "Motorcycle",               "None",       cheat = 131 },
}

-- In vehicles.xtbl but not for the spawn list: trailers (sp_trailer_*, sp_bagtrailer01),
-- trains, and copies made for cutscenes (truck_2dr_pickup06C is a second Legion that only
-- differs by name; it is kept here as an unverified cutscene copy).
T.NOT_DRIVABLE = {
  { "sp_eltrain_01",          "El Train",             "car",  "El Train",                 "None" },
  { "sp_trailer_tank1",       "Tank",                 "car",  "Trailers",                 "None" },
  { "sp_bagtrailer01",        "Baggage Trailer",      "car",  "Trailers",                 "None" },
  { "sp_trailer_box01",       "Box",                  "car",  "Trailers",                 "None" },
  { "sp_trailer_flatbed01",   "Flatbed",              "car",  "Trailers",                 "None" },
  { "sp_hearse02_interior",   "HounforCut",           "car",  "Car - standard",           "Limo" },
  { "car_4dr_standard02_cs",  "Zircon",               "car",  "Car - luxury",             "None" },
  { "sp_el_train_cutscene",   "El Train Cut",         "car",  "El Train",                 "None" },
  { "sp_hearse02_cs",         "Hounfor",              "car",  "Car - standard",           "Limo" },
  { "truck_2dr_pickup06C",    "Legion",               "car",  "Truck - small (pickups)",  "None" },
  { "car_2dr_muscle04_cs",    "Phoenix",              "car",  "Car - sports",             "None" },
  { "truck_2dr_monster01_CS", "Atlasbreaker",         "car",  "Truck - big (semi cab)",   "None" },
}

-- cheats.xtbl index -> vehicle it drops (cheats.txt order). Some drops ask for a variant;
-- those are in T.CHEAT_VEHICLE_VARIANTS (mostly "bling").
T.CHEAT_VEHICLES = {
  [53] = "sp_ambulance01", -- Ambulance
  [54] = "van_4dr_news01", -- Anchor
  [55] = "truck_2dr_monster01", -- Atlasbreaker
  [56] = "car_2dr_exoticsports01", -- Attrazione
  [57] = "truck_2dr_fire01", -- Backdraft
  [58] = "sp_backhoe01", -- Backhoe
  [59] = "sp_bagcart01", -- Bag Boy
  [60] = "car_2dr_exolux01", -- Baron
  [61] = "sp_apc01", -- Bear
  [62] = "car_2dr_muscle02", -- Bootlegger
  [63] = "suv_4dr_luxury05", -- Bulldog
  [64] = "sp_bulldozer01", -- Bulldozer
  [65] = "car_4dr_lowrider01", -- Compton
  [66] = "car_4dr_luxury04", -- Eiswolf
  [67] = "suv_4dr_fbi01", -- FBI
  [68] = "car_4dr_police01", -- Five0
  [69] = "car_4dr_classic01", -- Hollywood
  [70] = "car_4dr_exoticluxury01", -- Justice
  [71] = "sp_combine", -- Kent
  [72] = "suv_4dr_luxury01", -- Mag
  [73] = "truck_2dr_construct01", -- Mixmaster
  [74] = "car_2dr_buggy01", -- Mongoose
  [75] = "sp_novelty01", -- Oring
  [76] = "car_2dr_muscle04", -- Phoenix
  [77] = "suv_4dr_luxury06", -- Quasar
  [78] = "sp_metermaid01", -- Quota
  [79] = "sp_hearse01", -- Reaper
  [80] = "SP_derbycar02", -- Rampage
  [81] = "car_2dr_sports03", -- Raycaster
  [82] = "truck_2dr_septic01", -- Septic Avenger
  [83] = "truck_2dr_tow01", -- Shaft
  [84] = "truck_2dr_garbage01", -- Stilwater Municipal
  [85] = "car_2dr_exoticsports06", -- Superiore
  [86] = "car_4dr_taxi01", -- Taxi
  [87] = "sp_limosuv01", -- The Job
  [88] = "truck_2dr_armored01", -- Titan
  [107] = "bike_exotic01", -- Kaneda
  [108] = "bike_rocket02", -- Kenshin
  [109] = "bike_standard02", -- Melbourne
  [110] = "bike_chopper01", -- Sabretooth
  [111] = "bike_dirt01", -- Sandstorm
  [112] = "bike_moped01", -- Widowmaker
  [113] = "boat_speed03", -- Hurricane
  [114] = "boat_speed01", -- Miami
  [115] = "boat_speed02", -- Python
  [116] = "boat_wavecraft01", -- Shark
  [117] = "boat_yacht01", -- Skipper
  [118] = "heli_standard_01", -- Horizon
  [119] = "plane_jet01", -- Snipes57
  [120] = "heli_fighter_01", -- Tornado
  [121] = "plane_fighter01", -- Wolverine
  [122] = "sp_atv01", -- Toad
  [123] = "truck_2dr_pickup02", -- Varsity
  [124] = "car_2dr_sports05", -- Venom Classic
  [125] = "car_2dr_exoticsports04", -- Vortex
  [126] = "car_2dr_exoticsports03", -- Zenith
  [129] = "heli_standard_03", -- Gyrocopter
  [130] = "sp_ufo01", -- UFO
  [131] = "bike_pocket01", -- Pocket Bike
}

T.CHEAT_VEHICLE_VARIANTS = {
  [56] = "bling", -- Attrazione
  [60] = "bling", -- Baron
  [63] = "military_turret", -- Bulldog
  [65] = "bling", -- Compton
  [66] = "bling", -- Eiswolf
  [69] = "bling", -- Hollywood
  [70] = "bling", -- Justice
  [72] = "bling", -- Mag
  [73] = "longhauler", -- Mixmaster
  [76] = "bling", -- Phoenix
  [77] = "bling", -- Quasar
  [80] = "derby_02_lvl3", -- Rampage
  [81] = "bling", -- Raycaster
  [85] = "bling", -- Superiore
  [123] = "bling", -- Varsity
  [124] = "bling", -- Venom Classic
  [125] = "bling", -- Vortex
  [126] = "bling", -- Zenith
}

return T

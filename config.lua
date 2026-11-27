Config = {}

Config.Locale = 'da'   -- sprogfil i locales/ (da, en). Labels på maskiner og items står her i config.lua

-- Hvordan man interagerer med maskiner, laptop, scanner og hæler:
--   'ox_target' = sigt på tingene med ox_target (kræver ox_target)
--   'st_libs'   = 3D-tekst med tastetryk (E / G / H) fra st_libs
Config.Interaction = 'st_libs'

-- ============================================================
-- ITEMS (registreret i ox_inventory/data/items.lua)
-- ============================================================
Config.Items = {
    paper    = 'cf_paper',       -- bomuldspapir
    ink      = 'cf_ink',         -- sikkerhedsblæk
    sheetWet = 'cf_sheet_wet',   -- våde trykark
    sheet    = 'cf_sheet',       -- tørre trykark (8 sedler pr. ark)
    bills    = 'cf_bills',       -- løse falske sedler
    band     = 'cf_band',        -- banderoler
    bundle   = 'cf_bundle',      -- bundt falske sedler (metadata: serie)
    scanner  = 'cf_scanner',     -- UV-seddelscanner
    plate    = 'cf_plate',       -- graveret trykplade (metadata: prefix, uses)
    plateBlank = 'cf_plate_blank', -- blank kobberplade
    uvlight  = 'cf_uvlight',     -- politiets UV-lommelygte
}

-- UV-lommelygte (politi): lys på en spiller for at se falske bundter, eller på en maskine for at se typeskiltet.
Config.UVLight = {
    range = 3.0,
    color = { 150, 60, 255 },
    prop  = 'prop_cs_police_torch',
    anim  = { dict = 'amb@world_human_security_shine_torch@male@base', clip = 'base' },
}

-- Trykpressen sælges ikke af hæleren. Den skal stjæles i Union-heistet (mani-unheist), mens boksen er åben.
Config.Heist = {
    enabled  = true,
    resource = 'mani-unheist',
    crewOnly = true,                                    -- kun spillere, der er med i heistet
    coords   = vector4(5.2, -661.8, 16.13, 90.0),       -- i boksen ved vognene (ret hvis den står forkert)
    seconds  = 30,                                       -- tid det tager at afmontere pressen
}

-- Trykplader: laves på graverbordet med et prefiks på 2 bogstaver, som står foran serienummeret
-- (fx "AB 04821K"). Pladen slides: 'uses' = antal portioner i trykpressen. Politiet kan koble alle sedler
-- med et prefiks til pladens ejer, når de har beslaglagt pladen og scannet den med UV-scanneren.
Config.Plate = {
    uses     = 20,
    reserved = { LS = true },   -- prefikser der ikke må bruges (LS = sedler lavet uden plade)
}

-- Et bundt = så mange løse sedler. 'value' = pålydende (bruges af hæleren og vises i inventaret).
Config.Bundle = { bills = 25, value = 25000, label = 'Bundt falske sedler' }

-- ============================================================
-- MASKINER
-- ============================================================
-- mode = 'timed': fyld den, gå fra den, hent output når tiden er gået (som en ovn).
-- mode = 'active': man står ved den imens; output kommer direkte i inventaret.
-- input/output er pr. portion. models: første model der findes i spillet bruges.
-- anim = prop-animation fra stream/m1_cf_anims.ycd (lavet i Blender).
-- work = hvor spilleren står (offset i maskinens rum, heading i forhold til maskinen) og ped-animationen imens.
--        Ped-animationerne (stream/m1_cf_ped.ycd) er lavet i Blender til netop disse positioner, så ret dem ikke uden
--        at gen-bage animationerne. 'take' = position/animation når man tømmer en tidsstyret maskine.
Config.Stations = {
    cf_press = {
        label       = 'Trykpresse',
        mode        = 'timed',
        plate       = true,                           -- kræver en trykplade (cf_plate) i inventaret
        input       = { cf_paper = 2, cf_ink = 1 },
        output      = { cf_sheet_wet = 2 },
        maxBatches  = 5,
        minutes     = 6,
        spoil       = { after = 30, keep = 0.5 },     -- våde ark i bakken klistrer sammen
        fillText    = 'Lægger papir i og fylder blæk på...',
        collectText = 'Tager de trykte ark ud...',
        uiHeight    = 1.35,
        noise       = true,                           -- se Config.Noise
        work = { offset = vec3(0.0, 1.12, 0.0), heading = 180.0, clip = 'press_feed' },    -- ved indføringen bagpå
        take = { offset = vec3(0.0, -1.02, 0.0), clip = 'press_take' },                   -- ved bakken foran
        anim = { working = 'press_run' },
        models = {
            empty   = { 'm1_cf_press_off',  'bkr_prop_prtmachine_dryer' },
            working = { 'm1_cf_press_on',   'bkr_prop_prtmachine_dryer_spin' },
            done    = { 'm1_cf_press_done', 'bkr_prop_prtmachine_dryer' },
        },
    },
    cf_dryline = {
        label       = 'Tørresnor',
        mode        = 'timed',
        carry       = 'cf_sheet_wet',                 -- prefikset følger arkene videre
        input       = { cf_sheet_wet = 2 },
        output      = { cf_sheet = 2 },
        maxBatches  = 5,
        minutes     = 8,
        fillText    = 'Hænger arkene op...',
        collectText = 'Tager de tørre ark ned...',
        uiHeight    = 1.9,
        work = { offset = vec3(0.0, -0.42, 0.0), clip = 'hang' },
        anim = { working = 'dryline_sway', done = 'dryline_sway' },
        models = {
            empty   = { 'm1_cf_dryline_empty', 'prop_clothes_rail_01' },
            working = { 'm1_cf_dryline_wet',   'prop_clothes_rail_02' },
            done    = { 'm1_cf_dryline_dry',   'prop_clothes_rail_02' },
        },
    },
    cf_cutter = {
        label       = 'Skæremaskine',
        mode        = 'active',
        carry       = 'cf_sheet',
        input       = { cf_sheet = 1 },
        output      = { cf_bills = 8 },
        maxBatches  = 6,
        seconds     = 5.0,                            -- pr. ark (= to knivslag)
        workText    = 'Skærer trykark til sedler...',
        uiHeight    = 1.45,
        doneSeconds = 120,                            -- hvor længe de skårne bunker ligger fremme bagefter
        work = { offset = vec3(0.19, -0.8, 0.0), clip = 'cut' },                          -- to hænder på håndtaget
        anim = { active = 'cutter_cut' },
        models = {
            empty  = { 'm1_cf_cutter_empty',  'bkr_prop_fakeid_papercutter' },
            active = { 'm1_cf_cutter_loaded', 'bkr_prop_fakeid_papercutter' },
            done   = { 'm1_cf_cutter_done',   'bkr_prop_fakeid_papercutter' },
        },
    },
    cf_counter = {
        label       = 'Sedeltæller',
        mode        = 'active',
        carry       = 'cf_bills',
        input       = { cf_band = 1 },                 -- + Config.Bundle.bills sedler (sættes efter tabellen)
        output      = { cf_bundle = 1 },
        maxBatches  = 8,
        seconds     = 4.0,                            -- pr. bundt
        workText    = 'Tæller og bundter sedler...',
        uiHeight    = 0.4,
        doneSeconds = 90,                             -- så længe displayet viser serienummeret bagefter
        work = { offset = vec3(0.0, -0.55, 0.0), clip = 'count' },                        -- tælleren står på et bord (0,9 m)
        anim = { active = 'counter_count' },
        models = {
            empty  = { 'm1_cf_counter',     'bkr_prop_money_counter' },
            active = { 'm1_cf_counter_run', 'bkr_prop_money_counter' },
        },
    },
    cf_engraver = {
        label       = 'Graverbord',
        mode        = 'active',
        engraver    = true,                           -- spilleren vælger prefikset, output er en trykplade
        input       = { cf_plate_blank = 1 },
        output      = { cf_plate = 1 },
        maxBatches  = 1,
        seconds     = 20.0,
        workText    = 'Graverer trykpladen...',
        uiHeight    = 0.35,
        work = { offset = vec3(0.0, -0.55, 0.0), clip = 'engrave' },                      -- graverbordet står på et bord (0,9 m)
        anim = { active = 'engrave_run' },
        models = {
            empty  = { 'm1_cf_engraver',     'prop_tool_bench02' },
            active = { 'm1_cf_engraver_run', 'prop_tool_bench02' },
        },
    },
}

-- Antal sedler pr. bundt står kun ét sted (Config.Bundle.bills)
Config.Stations.cf_counter.input.cf_bills = Config.Bundle.bills

Config.AnimDict = 'm1_cf_anims'   -- prop-animationer (stream/m1_cf_anims.ycd)
Config.PedDict  = 'm1_cf_ped'     -- ped-animationer der matcher maskinerne (stream/m1_cf_ped.ycd)

Config.StationLimits = {
    maxPerPlayer = 2,       -- pr. maskintype
    minDistance  = 0.4,
}

-- ============================================================
-- INVENTAR
-- ============================================================
Config.Props = {
    cf_table = {
        label = 'Arbejdsbord', maxPerPlayer = 6, uiHeight = 1.0,
        models = { default = { 'm1_cf_table', 'bkr_prop_fakeid_table' } },
    },
    -- Laptop: skærmen viser status for alle maskiner i nærheden (DUI). E åbner listen.
    cf_laptop = {
        label = 'Laptop', maxPerPlayer = 2, uiHeight = 0.35, screen = 'laptop',
        models = { default = { 'm1_cf_laptop', 'prop_laptop_01a' } },
    },
    -- UV-scanner til politiet: kun politiet kan stille den op og bruge den. Skærmen viser resultatet.
    cf_uvscanner = {
        label = 'UV-scanner', maxPerPlayer = 2, uiHeight = 0.4, screen = 'uv', police = true,
        models = { default = { 'm1_cf_uvscanner', 'prop_cs_server_drive' } },
    },
    -- Kursskærm: viser hælerens kurs live, så du kan følge med fra dit eget værksted. E viser kursen.
    cf_priceboard = {
        label = 'Kursskærm', maxPerPlayer = 2, uiHeight = 1.75, screen = 'board',
        models = { default = { 'm1_cf_priceboard', 'prop_tv_flat_01' } },
    },
}

-- ============================================================
-- SKÆRME (DUI): live-billeder på modellernes skærme
-- ============================================================
-- Skærmen på den nærmeste maskine af hver slags bliver levende (GTA kan kun skifte en tekstur for alle
-- eksemplarer på én gang, så de andre viser standardbilledet). txd/texture skal matche stream/m1_cf_tex.ytd.
Config.Screens = {
    enabled  = true,
    txd      = 'm1_cf_tex',
    distance = 12.0,           -- hvor tæt på man skal være, før skærmen tændes
    rate     = 250,            -- ms mellem opdateringer
    types = {
        counter = { texture = 'm1f_lcd_d',        size = { 256, 128 } },   -- sedeltællerens display
        hygro   = { texture = 'm1f_scr_hygro_d',  size = { 256, 128 } },   -- fugtmåleren på tørresnoren
        laptop  = { texture = 'm1f_scr_laptop_d', size = { 512, 288 }, range = 25.0 },  -- range = hvor langt laptoppen "ser" maskiner
        uv      = { texture = 'm1f_scr_uv_d',     size = { 256, 128 } },   -- politiets UV-scanner
        board   = { texture = 'm1f_scr_board_d',  size = { 512, 288 }, distance = 25.0 },  -- kursskærmen (cf_priceboard)
    },
}

-- ============================================================
-- STØJ: trykpressen larmer. Naboer ringer til politiet.
-- ============================================================
Config.Noise = {
    callChancePerMinute = 4,        -- % pr. minut pr. presse der kører
    cooldownMinutes     = 10,       -- mindst så længe mellem to opkald fra samme presse
    message             = 'Naboer klager over højlydt maskinstøj fra en adresse i området',
    -- Presser inde i et hus/instance (routing bucket ≠ 0) står på shell-koordinater, som ikke giver mening
    -- på kortet. Som standard ringer naboerne derfor kun om presser ude i verden.
    callFromInstances   = false,
}

-- ============================================================
-- PLACERING / INTERAKTION
-- ============================================================
Config.Place = {
    maxDistance    = 5.0,
    maxSnap        = 0.5,       -- så langt fra arbejdspladsen må spilleren stå og stadig blive flyttet på plads
    heightStep     = 0.02,
    maxLift        = 1.5,
    renderDistance = 80.0,
    displayDist    = 3.0,
    interactDist   = 1.8,
}

Config.Anims = {
    place   = { dict = 'anim@heists@money_grab@briefcase', clip = 'put_down_case', duration = 2500 },
    collect = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', duration = 4000 },
    fill    = 5000,
    seize   = { scenario = 'PROP_HUMAN_BUM_BIN', duration = 5000 },
    scan    = { dict = 'amb@world_human_clipboard@male@idle_a', clip = 'idle_c', duration = 3000 },
}

-- ============================================================
-- POLITI
-- ============================================================
Config.Police = {
    jobs        = { police = 0, sheriff = 0 },   -- job = minimum grade
    blipSeconds = 180,
    blip        = { color = 1, radius = 70.0 },
}

-- ============================================================
-- HÆLER (NPC): sælger udstyr og køber bundter
-- ============================================================
Config.Dealer = {
    enabled  = true,
    coords   = vector4(-28.7189, -2663.7817, 6.0043, 235.1031),    -- Elysian Island (skift frit)
    model    = 'mp_m_counterfeit_01',
    scenario = 'WORLD_HUMAN_SMOKING',
    account  = 'money',            -- betaling for varer
    sell = {
        account = 'black_money',   -- udbetaling for bundter
        rate    = 0.45,            -- normal andel af pålydende
        max     = 20,              -- max bundter pr. handel
        -- Kursen svinger: den falder, når der bliver solgt meget, og stiger langsomt igen.
        minRate        = 0.30,
        maxRate        = 0.55,
        dropPerBundle  = 0.004,    -- så meget falder kursen pr. solgt bundt
        recoverPerHour = 0.03,     -- så meget stiger den igen pr. time (mod 'rate', og lidt over i rolige perioder)
    },
    items = {
        { name = 'cf_paper',   label = 'Bomuldspapir',      price = 150 },
        { name = 'cf_ink',     label = 'Sikkerhedsblæk',    price = 400 },
        { name = 'cf_band',    label = 'Banderoler',        price = 50 },
        -- cf_press sælges ikke: den skal stjæles i Union-heistet (Config.Heist)
        { name = 'cf_dryline', label = 'Tørresnor',         price = 1500 },
        { name = 'cf_cutter',  label = 'Skæremaskine',      price = 6000 },
        { name = 'cf_counter', label = 'Sedeltæller',       price = 4500 },
        { name = 'cf_table',   label = 'Arbejdsbord',       price = 1500 },
        { name = 'cf_laptop',  label = 'Laptop',            price = 2500 },
        { name = 'cf_priceboard', label = 'Kursskærm',      price = 3500 },
        { name = 'cf_engraver', label = 'Graverbord',       price = 8000 },
        { name = 'cf_plate_blank', label = 'Kobberplade',   price = 800 },
    },
}

-- ============================================================
-- KURER: hæleren giver leveringsopgaver
-- ============================================================
-- Tag en opgave hos hæleren, kør bundterne ud til en køber inden tiden løber ud og få bedre betaling
-- end ved disken. Der er en chance for, at politiet får et tip om afleveringsstedet.
Config.Courier = {
    enabled         = true,
    bundles         = { min = 5, max = 12 },
    minutes         = 15,
    bonus           = 1.25,          -- gange hælerens aktuelle kurs
    tipChance       = 25,            -- % chance for at politiet får et tip
    tipDelay        = 60,            -- sekunder efter opgaven er taget
    cooldownMinutes = 20,
    pedModel        = 'g_m_y_mexgoon_02',
    -- Afleveringssteder (fra elevate-oxyRun). Ret frit.
    points = {
        vector4(196.76, -2231.34, 5.95, 92.24),
        vector4(1072.23, -787.65, 58.26, 175.74),
        vector4(1222.27, -487.97, 66.94, 257.27),
        vector4(-1031.66, -1524.87, 5.19, 121.87),
        vector4(-990.05, -1438.62, 5.05, 115.18),
        vector4(-557.05, 426.43, 99.04, 312.93),
        vector4(902.44, -87.31, 78.76, 61.88),
        vector4(590.15, -2226.13, 5.99, 166.49),
    },
}

-- ============================================================
-- LOG
-- ============================================================
Config.Log = {
    discordWebhook = '',     -- tom = kun konsol
}

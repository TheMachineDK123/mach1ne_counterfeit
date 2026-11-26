Config = {}

Config.Locale = 'da'   -- sprogfil i locales/ (da, en). Labels på maskiner og items står her i config.lua

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
        input       = { cf_bills = 25, cf_band = 1 },  -- holdes i sync med Config.Bundle.bills
        output      = { cf_bundle = 1 },
        maxBatches  = 8,
        seconds     = 4.0,                            -- pr. bundt
        workText    = 'Tæller og bundter sedler...',
        uiHeight    = 0.4,
        work = { offset = vec3(0.0, -0.55, 0.0), clip = 'count' },                        -- tælleren står på et bord (0,9 m)
        anim = { active = 'counter_count' },
        models = {
            empty  = { 'm1_cf_counter',     'bkr_prop_money_counter' },
            active = { 'm1_cf_counter_run', 'bkr_prop_money_counter' },
        },
    },
}

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
}

-- ============================================================
-- STØJ: trykpressen larmer. Naboer ringer til politiet.
-- ============================================================
Config.Noise = {
    callChancePerMinute = 4,        -- % pr. minut pr. presse der kører
    cooldownMinutes     = 10,       -- mindst så længe mellem to opkald fra samme presse
    message             = 'Naboer klager over højlydt maskinstøj fra en adresse i området',
}

-- ============================================================
-- PLACERING / INTERAKTION
-- ============================================================
Config.Place = {
    maxDistance    = 5.0,
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
    coords   = vector4(1240.6, -3179.2, 7.1, 270.0),    -- Elysian Island (skift frit)
    model    = 'mp_m_counterfeit_01',
    scenario = 'WORLD_HUMAN_SMOKING',
    account  = 'money',            -- betaling for varer
    sell = {
        account = 'black_money',   -- udbetaling for bundter
        rate    = 0.45,            -- andel af pålydende
        max     = 20,              -- max bundter pr. handel
    },
    items = {
        { name = 'cf_paper',   label = 'Bomuldspapir',      price = 150 },
        { name = 'cf_ink',     label = 'Sikkerhedsblæk',    price = 400 },
        { name = 'cf_band',    label = 'Banderoler',        price = 50 },
        { name = 'cf_press',   label = 'Trykpresse',        price = 15000 },
        { name = 'cf_dryline', label = 'Tørresnor',         price = 1500 },
        { name = 'cf_cutter',  label = 'Skæremaskine',      price = 6000 },
        { name = 'cf_counter', label = 'Sedeltæller',       price = 4500 },
        { name = 'cf_table',   label = 'Arbejdsbord',       price = 1500 },
    },
}

-- ============================================================
-- LOG
-- ============================================================
Config.Log = {
    discordWebhook = '',     -- tom = kun konsol
}

-- Live-skærme (DUI) på modellerne: sedeltæller, fugtmåler, laptop, UV-scanner og kurstavlen hos hæleren.
-- GTA kan kun erstatte en tekstur for alle eksemplarer på én gang, så hver skærmtype følger den nærmeste
-- model af sin slags. De andre viser standardbilledet fra m1_cf_tex.ytd.
local SC = Config.Screens
local screens = {}   -- [type] = { dui, txd, txn, last, sentAt }
local serial = 0     -- runtime-txd'er kan ikke slettes, så hver ny DUI får sit eget navn
local boardObj

-- ===================== Status til laptop og fugtmåler =====================

local function progressOf(o, t)
    local d = o.data
    if d.done and d.started and d.done > d.started then
        return math.min(1.0, math.max(0.0, (t - d.started) / (d.done - d.started)))
    end
    if d.activeUntil and d.duration then
        if o.t0 then return math.min(1.0, (GetGameTimer() - o.t0) / (d.duration * 1000.0)) end
        return math.min(1.0, math.max(0.0, 1.0 - (d.activeUntil - t) / d.duration))
    end
    return 0.0
end

-- Maskinerne omkring en position (samme bucket), til laptoppens skærm og liste.
function CF.workshopStatus(center, range)
    local t, list = CF.now(), {}
    for _, o in pairs(CF.objects) do
        if o.kind == 'station' and o.bucket == CF.bucket
            and #(vec3(o.pos.x, o.pos.y, o.pos.z) - center) <= range then
            local def = Config.Stations[o.type]
            local state = Util.stationState(o.data, t)
            local e = {
                id = o.id, label = def.label, state = state,
                progress = math.floor(progressOf(o, t) * 100),
                dist = #(vec3(o.pos.x, o.pos.y, o.pos.z) - center),
            }
            if state == 'working' then e.minutes = math.max(1, math.ceil((o.data.done - t) / 60)) end
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b) return a.label == b.label and a.id < b.id or a.label < b.label end)
    return list
end

-- ===================== Data pr. skærmtype =====================

local builders = {}

function builders.counter(o, t)
    local state = Util.stationState(o.data, t)
    if state == 'active' then
        local total = (o.data.batches or 1) * Config.Bundle.bills
        return { state = 'active', count = math.floor(progressOf(o, t) * total), total = total }
    elseif state == 'done' and o.data.lastSerial then
        return { state = 'done', serial = o.data.lastSerial, bundles = o.data.lastCount or 1 }
    end
    return { state = 'idle' }
end

function builders.hygro(o, t)
    local state = Util.stationState(o.data, t)
    if state == 'working' then
        local p = progressOf(o, t)
        local wobble = math.sin(GetGameTimer() / 900.0) * 0.6
        return { state = 'working', humidity = math.floor(92 - 84 * p + wobble + 0.5),
                 minutes = math.max(1, math.ceil((o.data.done - t) / 60)) }
    end
    return { state = state }
end

function builders.laptop(o)
    local center = vec3(o.pos.x, o.pos.y, o.pos.z)
    local list = CF.workshopStatus(center, SC.types.laptop.range or 25.0)
    local rows = {}
    for i = 1, math.min(#list, 6) do
        local e = list[i]
        rows[i] = { label = e.label, state = e.state, progress = e.progress, minutes = e.minutes }
    end
    return { rows = rows, more = math.max(0, #list - 6), clock = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()) }
end

function builders.uv(o)
    local s = o.data.scan
    if not s or CF.now() - (s.at or 0) > 120 then return { state = 'ready' } end
    local area
    if s.pos then
        area = GetLabelText(GetNameOfZone(s.pos.x, s.pos.y, s.pos.z))
    end
    return { state = s.total > 0 and 'fake' or 'none', total = s.total, serials = s.serials,
             serial = s.serial, created = s.created, area = area }
end

function builders.board()
    local r = GlobalState.m1cfRate
    if not r then return { state = 'closed' } end
    return { state = 'open', price = r.price, rate = math.floor(r.rate * 100 + 0.5), trend = r.trend, demand = r.demand }
end

-- ===================== Hvilken model viser hvilken skærm =====================

local function screenTypeOf(o)
    if o.kind == 'station' then
        if o.type == 'cf_counter' then return 'counter' end
        if o.type == 'cf_dryline' then return 'hygro' end
    elseif o.kind == 'prop' then
        local def = Config.Props[o.type]
        return def and def.screen
    end
end

-- Nærmeste synlige model af hver type (kun vores egne modeller har skærm-teksturen).
local function nearest(me)
    local best = {}
    for id, o in pairs(CF.objects) do
        local typ = screenTypeOf(o)
        local obj = typ and CF.entity(id)
        if obj and o.bucket == CF.bucket and GetEntityModel(obj) ~= 0 then
            local d = #(me - vec3(o.pos.x, o.pos.y, o.pos.z))
            local max = SC.types[typ].distance or SC.distance
            if d <= max and (not best[typ] or d < best[typ].d) then best[typ] = { o = o, d = d } end
        end
    end
    if boardObj and DoesEntityExist(boardObj) then      -- den faste skærm ved hæleren (hvis slået til)
        local d = #(me - GetEntityCoords(boardObj))
        if d <= (SC.types.board.distance or SC.distance) and (not best.board or d < best.board.d) then
            best.board = { d = d }
        end
    end
    return best
end

-- ===================== DUI =====================

local function open(typ)
    local cfg = SC.types[typ]
    local w, h = cfg.size[1], cfg.size[2]
    serial = serial + 1
    local s = { txd = ('m1cf_dui_%s_%d'):format(typ, serial), txn = 'screen' }
    s.dui = CreateDui(('nui://%s/html/dui.html?screen=%s'):format(GetCurrentResourceName(), typ), w, h)
    local txd = CreateRuntimeTxd(s.txd)
    CreateRuntimeTextureFromDuiHandle(txd, s.txn, GetDuiHandle(s.dui))
    AddReplaceTexture(SC.txd, cfg.texture, s.txd, s.txn)
    screens[typ] = s
    return s
end

local function close(typ)
    local s = screens[typ]
    if not s then return end
    RemoveReplaceTexture(SC.txd, SC.types[typ].texture)
    DestroyDui(s.dui)
    screens[typ] = nil
end

-- Oversatte tekster til skærmene (locales/*.json, dui_*)
local TEXTS
local function texts()
    if TEXTS then return TEXTS end
    local states = {}
    for _, st_ in ipairs({ 'empty', 'idle', 'working', 'done', 'spoiled', 'active' }) do states[st_] = locale('dui_state_' .. st_) end
    TEXTS = {
        counter = { ready = locale('dui_ready'), pcs = locale('dui_pcs'), of = locale('dui_of'), bundles = locale('dui_bundles') },
        hygro   = { humidity = locale('dui_humidity'), dry = locale('dui_dry'), empty = locale('dui_hygro_empty'), min = locale('dui_min') },
        laptop  = { title = locale('dui_laptop_title'), none = locale('laptop_none'), more = locale('dui_more'), min = locale('dui_min'), states = states },
        uv      = { ready = locale('dui_uv_ready'), fake = locale('dui_uv_fake'), none = locale('dui_uv_none'), bundles = locale('dui_bundles') },
        board   = { title = locale('dealer_title'), closed = locale('dui_closed'), perBundle = locale('dui_per_bundle'),
                    currency = locale('dui_currency'),
                    demand = { high = locale('dui_demand_high'), normal = locale('dui_demand_normal'), low = locale('dui_demand_low') } },
    }
    return TEXTS
end

-- Sender data til skærmen. Siden er ikke klar i det øjeblik DUI'en oprettes, så vi venter på
-- IsDuiAvailable og sender den seneste besked igen hvert 2. sekund. Ellers ville en skærm med uændrede
-- data (en tom tørresnor, en tæller der står stille) blive ved med at vise sidens tomme starttilstand.
local RESEND_MS = 2000

local function push(typ, data)
    local s = screens[typ] or open(typ)
    if not IsDuiAvailable(s.dui) then return end
    data.screen = typ
    data.txt = texts()[typ]
    local msg = json.encode(data)
    local t = GetGameTimer()
    if msg ~= s.last or t - (s.sentAt or 0) >= RESEND_MS then
        s.last, s.sentAt = msg, t
        SendDuiMessage(s.dui, msg)
    end
end

if SC.enabled then
    CreateThread(function()
        while true do
            local me, t = GetEntityCoords(PlayerPedId()), CF.now()
            local best = nearest(me)
            for typ in pairs(SC.types) do
                local b = best[typ]
                if b then
                    push(typ, builders[typ](b.o, t))
                elseif screens[typ] then
                    close(typ)
                end
            end
            Wait(next(screens) and SC.rate or 1000)
        end
    end)
end

-- ===================== Kurstavlen ved hæleren =====================

function CF.spawnBoard(dealerCoords)
    local B = Config.Dealer.board
    if not (B and B.enabled) or boardObj then return end
    local hash = joaat('m1_cf_priceboard')
    if not IsModelInCdimage(hash) or not pcall(st.requestModel, hash, 5000) then return end
    local c = dealerCoords
    local p = vec3(c.x, c.y, c.z) + Util.rotate(B.offset, c.w)
    boardObj = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(boardObj, (c.w + (B.headingOffset or 180.0)) % 360)
    FreezeEntityPosition(boardObj, true)
    PlaceObjectOnGroundProperly(boardObj)
    SetModelAsNoLongerNeeded(hash)
end

function CF.removeBoard()
    if boardObj and DoesEntityExist(boardObj) then DeleteEntity(boardObj) end
    boardObj = nil
end

-- ===================== Laptop, UV-scanner og kursskærm (handlinger) =====================

function CF.showRate()
    local r = GlobalState.m1cfRate
    if not r then return CF.notify(locale('rate_unknown'), 'inform') end
    local trend = r.trend > 0 and locale('rate_up') or (r.trend < 0 and locale('rate_down') or locale('rate_flat'))
    CF.notify(locale('rate_now', r.price, math.floor(r.rate * 100 + 0.5), trend), 'inform')
end

local STATE_KEYS = { empty = 'st_empty', working = 'st_working', done = 'st_done', spoiled = 'st_spoiled', active = 'st_active', idle = 'st_empty' }

function CF.openLaptop(id)
    local o = CF.objects[id]
    if not o then return end
    local list = CF.workshopStatus(vec3(o.pos.x, o.pos.y, o.pos.z), SC.types.laptop.range or 25.0)
    local options = {}
    for _, e in ipairs(list) do
        local desc = locale(STATE_KEYS[e.state] or 'st_empty')
        if e.state == 'working' then desc = locale('st_working_min', e.minutes) end
        options[#options + 1] = {
            title = ('%s #%d'):format(e.label, e.id), description = desc, icon = 'gears',
            progress = (e.state == 'working' or e.state == 'active') and e.progress or nil,
            colorScheme = e.state == 'done' and 'green' or (e.state == 'spoiled' and 'red' or 'blue'),
        }
    end
    if #options == 0 then options[1] = { title = locale('laptop_none'), disabled = true } end
    lib.registerContext({ id = 'mach1ne_counterfeit_laptop', title = locale('laptop_title'), options = options })
    lib.showContext('mach1ne_counterfeit_laptop')
end

function CF.scanDesk(id)
    if CF.busy then return end
    CF.busy = true
    local A = Config.Anims.scan
    local done = st.progressBar({
        duration = A.duration, label = locale('scan_progress'), useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    })
    CF.busy = false
    if not done then return end
    local ok, list = st.callback.await('mach1ne_counterfeit:scanDesk', 500, id)
    if not ok then return CF.notify(list or locale('err_failed'), 'error') end
    CF.showScanResults(list, true)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for typ in pairs(screens) do close(typ) end
    CF.removeBoard()
end)

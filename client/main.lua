CF = { objects = {}, busy = false, timeOffset = 0, bucket = 0 }

local Objects = CF.objects
local ents    = {}   -- [id] = { obj, model, loading, uiKey, clip }
local P       = Config.Place

function CF.now() return GetCloudTimeAsInt() + CF.timeOffset end

function CF.notify(description, nType)
    st.notify({ title = locale('title'), description = description, type = nType or 'inform' })
end

function CF.isPolice()
    local data = ESX.GetPlayerData()
    return data and Util.isPoliceJob(data.job)
end

local itemLabels
function CF.itemLabel(name)
    if not itemLabels then
        local ok, items = pcall(function() return exports.ox_inventory:Items() end)
        itemLabels = {}
        if ok and items then
            for k, v in pairs(items) do itemLabels[k] = v.label end
        end
    end
    return itemLabels[name] or name
end

function CF.defOf(o)
    if o.kind == 'station' then return Config.Stations[o.type] end
    if o.kind == 'prop' then return Config.Props[o.type] end
end

-- ===================== Modeller =====================

local resolved = {}

-- Første model i listen der findes i spillet (egen Blender-model først, ellers vanilla-fallback).
function CF.resolveModel(list)
    if not list then return end
    if resolved[list] ~= nil then return resolved[list] or nil end
    for _, name in ipairs(list) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then
            resolved[list] = hash
            return hash
        end
    end
    resolved[list] = false
end

-- Er modellen vores egen (med skelet og prop-animation)?
local function isCustom(hash, list)
    return list and hash == joaat(list[1]) and list[1]:sub(1, 6) == 'm1_cf_'
end

function CF.placeModels(itemName)
    if Config.Stations[itemName] then return Config.Stations[itemName].models.empty end
    if Config.Props[itemName] then return Config.Props[itemName].models.default end
end

local function stateOf(o, t)
    if o.kind ~= 'station' then return 'default' end
    local s = Util.stationState(o.data, t)
    return s == 'spoiled' and 'done' or s
end

local function modelList(o, t)
    local def = CF.defOf(o)
    if not def then return end
    local s = stateOf(o, t)
    return def.models[s] or def.models.empty or def.models.default
end

-- ===================== Prop-animationer (Blender -> m1_cf_anims.ycd) =====================

local dictLoaded = false

local function loadDict()
    if dictLoaded then return true end
    RequestAnimDict(Config.AnimDict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(Config.AnimDict) and GetGameTimer() < timeout do Wait(0) end
    dictLoaded = HasAnimDictLoaded(Config.AnimDict)
    return dictLoaded
end

-- Fase (0-1) for aktive maskiner ud fra hvornår spilleren startede (o.t0, GetGameTimer-ms).
local function animPhase(o, clip)
    if not o.t0 then return end
    local len = GetAnimDuration(Config.AnimDict, clip)
    if not len or len <= 0 then return end
    return ((GetGameTimer() - o.t0) / 1000.0 / len) % 1.0
end

local function updateAnim(o, e, t)
    if not e.obj or not DoesEntityExist(e.obj) then return end
    local def   = CF.defOf(o)
    local state = stateOf(o, t)
    local clip  = o.kind == 'station' and def and def.anim and def.anim[state]
    if clip and not e.custom then clip = nil end
    if clip then
        if e.clip ~= clip or not IsEntityPlayingAnim(e.obj, Config.AnimDict, clip, 3) then
            if loadDict() then
                local obj = e.obj
                PlayEntityAnim(obj, clip, Config.AnimDict, 1000.0, true, true, false, 0.0, 0)
                e.clip = clip
                local phase = state == 'active' and animPhase(o, clip)
                if phase then
                    CreateThread(function()
                        Wait(0)
                        if DoesEntityExist(obj) then SetEntityAnimCurrentTime(obj, Config.AnimDict, clip, phase) end
                    end)
                end
            end
        end
    elseif e.clip then
        StopEntityAnim(e.obj, e.clip, Config.AnimDict, 4.0)
        e.clip = nil
    end
end

-- ===================== Interaktion (ox_target eller st_libs, se client/interact.lua) =====================

local function uiId(id) return 'mach1ne_counterfeit_' .. id end
local function canAct() return not CF.busy end
local function canPolice() return not CF.busy and CF.isPolice() end

local function minutesLeft(o, t)
    return math.max(1, math.ceil((o.data.done - t) / 60))
end

local function inputText(def)
    local parts = {}
    for item, amount in pairs(def.input) do
        parts[#parts + 1] = ('%dx %s'):format(amount, CF.itemLabel(item))
    end
    return table.concat(parts, ' + ')
end

local function buildOptions(o, t)
    local id, base = o.id, uiId(o.id)
    local def = CF.defOf(o)
    local top = vec3(o.pos.x, o.pos.y, o.pos.z + (def and def.uiHeight or 0.6))
    local opts = {}

    local function add(text, k, keyNum, dz, onSelect, canInteract)
        opts[#opts + 1] = {
            id = ('%s_%d'):format(base, #opts + 1), text = text,
            displayDist = P.displayDist, interactDist = P.interactDist,
            key = k, keyNum = keyNum, coords = top - vec3(0.0, 0.0, dz),
            canInteract = canInteract or canAct, onSelect = onSelect,
        }
    end

    if not def then return opts end

    if o.kind == 'station' and def.mode == 'timed' then
        local state = Util.stationState(o.data, t)
        if state == 'empty' then
            add(locale('ui_fill', def.label:lower(), inputText(def)), 'E', 38, 0.0, function() CF.fill(id) end)
            if def.plate then
                local p = o.data.plate
                if p then
                    add(locale('ui_plate_remove', p.prefix, p.uses), 'Y', 246, 0.125, function() CF.plate(id, 'removePlate') end)
                else
                    add(locale('ui_plate_insert'), 'Y', 246, 0.125, function() CF.plate(id, 'insertPlate') end)
                end
            end
            add(locale('ui_pickup', def.label:lower()), 'G', 47, 0.25, function() CF.pickup(id) end)
        elseif state == 'working' then
            local m = minutesLeft(o, t)
            add(locale('ui_running', def.label, m), 'E', 38, 0.0, function()
                CF.notify(locale('done_in', def.label, minutesLeft(o, CF.now())))
            end)
        elseif state == 'done' then
            add(locale('ui_collect', def.label:lower()), 'E', 38, 0.0, function() CF.collect(id) end)
        else
            add(locale('ui_collect_spoiled'), 'E', 38, 0.0, function() CF.collect(id) end)
        end
    elseif o.kind == 'station' then
        local state = Util.stationState(o.data, t)
        if state == 'active' then
            add(locale('ui_in_use', def.label), 'E', 38, 0.0, function() CF.notify(locale('err_in_use'), 'error') end)
        else
            add(locale('ui_work', (def.workText:gsub('%.%.%.$', '')), inputText(def)), 'E', 38, 0.0, function() CF.work(id) end)
            add(locale('ui_pickup', def.label:lower()), 'G', 47, 0.25, function() CF.pickup(id) end)
        end
    else
        if def.screen == 'laptop' then
            add(locale('ui_laptop'), 'E', 38, 0.0, function() CF.openLaptop(id) end)
        elseif def.screen == 'uv' then
            add(locale('ui_uv_scan'), 'E', 38, 0.0, function() CF.scanDesk(id) end, canPolice)
        elseif def.screen == 'board' then
            add(locale('ui_rate'), 'E', 38, 0.0, function() CF.showRate() end)
        end
        add(locale('ui_pickup', def.label:lower()), 'G', 47, 0.25, function() CF.pickup(id) end)
    end
    if not def.police then
        add(locale('ui_seize'), 'H', 74, 0.5, function() CF.seize(id) end, canPolice)
    end
    if o.data.serial then
        add(locale('ui_serial'), 'L', 182, 0.625, function() CF.showSerial(id) end, canPolice)
    end
    return opts
end

-- Billig nøgle for hvad 3D-teksten skal vise. Options bygges kun, når den ændrer sig.
local function uiKeyOf(o, t)
    local def = CF.defOf(o)
    if not def then return 'unknown' end
    if o.kind ~= 'station' then return 'prop' end
    local state = Util.stationState(o.data, t)
    if def.mode == 'timed' then
        local plate = o.data.plate and (o.data.plate.prefix .. o.data.plate.uses) or '-'
        return (state == 'working' and ('working:' .. minutesLeft(o, t)) or state) .. ':' .. plate
    end
    return state == 'active' and 'active' or 'idle'
end

local function refreshUI(o, e, t)
    local key = uiKeyOf(o, t)
    if e.uiKey == key then return end
    if Interact.object(uiId(o.id), e.obj, buildOptions(o, t)) then e.uiKey = key end
end

-- ===================== Spawn / despawn =====================

-- Isat trykplade vises som en kobberplade på pressens pladevalse (sidder på 'plate'-knoglen og drejer med).
local function updatePlate(o, e)
    local want = o.data.plate and e.custom and e.obj and DoesEntityExist(e.obj)
    if want and not e.plateObj then
        local hash = joaat('m1_cf_platemount')
        if not IsModelInCdimage(hash) or not pcall(st.requestModel, hash, 3000) then return end
        local p = CreateObjectNoOffset(hash, o.pos.x, o.pos.y, o.pos.z, false, false, false)
        SetEntityCollision(p, false, false)
        local bone = GetEntityBoneIndexByName(e.obj, 'plate')
        if bone ~= -1 then
            AttachEntityToEntity(p, e.obj, bone, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        else
            AttachEntityToEntity(p, e.obj, 0, 0.0, 0.12, 0.98, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
        end
        SetModelAsNoLongerNeeded(hash)
        e.plateObj = p
    elseif not want and e.plateObj then
        if DoesEntityExist(e.plateObj) then DeleteEntity(e.plateObj) end
        e.plateObj = nil
    end
end

local function despawn(id)
    local e = ents[id]
    if not e then return end
    if e.plateObj and DoesEntityExist(e.plateObj) then DeleteEntity(e.plateObj) end
    Interact.clear(uiId(id))
    if e.obj and DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    ents[id] = nil
end

function CF.entity(id)
    local e = ents[id]
    return e and e.obj
end

CF.stateOf = function(o, t) return stateOf(o, t) end

local sync

local function spawnModel(o, e, hash, list)
    e.model, e.loading = hash, true
    CreateThread(function()
        local ok = pcall(st.requestModel, hash, 5000)
        e.loading = false
        if not ok or ents[o.id] ~= e or e.model ~= hash then return end
        if e.obj and DoesEntityExist(e.obj) then
            if Interact.target then Interact.clear(uiId(o.id)) end
            DeleteEntity(e.obj)
        end
        if e.plateObj and DoesEntityExist(e.plateObj) then DeleteEntity(e.plateObj) end
        e.plateObj = nil
        if Interact.target then e.uiKey = nil end      -- ox_target sidder på entity'en: bind igen
        local obj = CreateObjectNoOffset(hash, o.pos.x, o.pos.y, o.pos.z, false, false, false)
        SetEntityHeading(obj, o.h or 0.0)
        FreezeEntityPosition(obj, true)
        SetEntityInvincible(obj, true)
        SetModelAsNoLongerNeeded(hash)
        e.obj, e.clip, e.custom = obj, nil, isCustom(hash, list)
        sync(o, CF.now())
    end)
end

sync = function(o, t)
    local e = ents[o.id]
    if not e then
        e = {}
        ents[o.id] = e
    end
    local list = modelList(o, t)
    local hash = CF.resolveModel(list)
    if hash and hash ~= e.model and not e.loading then spawnModel(o, e, hash, list) end
    refreshUI(o, e, t)
    updateAnim(o, e, t)
    updatePlate(o, e)
end

CreateThread(function()
    while true do
        local me, t = GetEntityCoords(PlayerPedId()), CF.now()
        for id, o in pairs(Objects) do
            local show = o.bucket == CF.bucket and #(me - vec3(o.pos.x, o.pos.y, o.pos.z)) <= P.renderDistance
            if show then sync(o, t) elseif ents[id] then despawn(id) end
        end
        Wait(1000)
    end
end)

-- ===================== Netværk =====================

local function setT0(o, elapsed)
    o.t0 = elapsed and (GetGameTimer() - elapsed) or nil
end

RegisterNetEvent('mach1ne_counterfeit:add', function(o)
    setT0(o, o.elapsed)
    Objects[o.id] = o
end)

RegisterNetEvent('mach1ne_counterfeit:remove', function(id)
    Objects[id] = nil
    despawn(id)
end)

RegisterNetEvent('mach1ne_counterfeit:update', function(id, data, elapsed)
    local o = Objects[id]
    if not o then return end
    o.data = data
    if elapsed then setT0(o, elapsed) elseif Util.stationState(data, CF.now()) ~= 'active' then o.t0 = nil end
    if ents[id] then sync(o, CF.now()) end
end)

RegisterNetEvent('mach1ne_counterfeit:notify', function(message, nType)
    CF.notify(message, nType)
end)

-- Ny bucket (fx ind i et hus): serveren sender præcis de værksteder, der er i den.
RegisterNetEvent('mach1ne_counterfeit:bucket', function(bucket, list)
    CF.bucket = bucket or 0
    local keep = {}
    for _, o in ipairs(list or {}) do
        setT0(o, o.elapsed)
        Objects[o.id] = o
        keep[o.id] = true
    end
    for id in pairs(Objects) do
        if not keep[id] then
            Objects[id] = nil
            despawn(id)
        end
    end
end)

RegisterNetEvent('mach1ne_counterfeit:dispatch', function(pos, message)
    local B = Config.Police.blip
    local area = AddBlipForRadius(pos.x + math.random(-30, 30), pos.y + math.random(-30, 30), pos.z, B.radius)
    SetBlipColour(area, B.color)
    SetBlipAlpha(area, 120)
    CF.notify(message or locale('dispatch_default'), 'warning')
    SetTimeout(Config.Police.blipSeconds * 1000, function() RemoveBlip(area) end)
end)

CreateThread(function()
    local list, serverNow, bucket = st.callback.await('mach1ne_counterfeit:getAll', false)
    if serverNow then CF.timeOffset = serverNow - GetCloudTimeAsInt() end
    CF.bucket = bucket or 0
    for _, o in ipairs(list or {}) do
        setT0(o, o.elapsed)
        Objects[o.id] = o
    end
end)

-- ===================== Handlinger =====================

local function progress(label, duration, anim)
    local data = {
        duration = duration, label = label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    }
    if anim then
        data.anim = { dict = anim.dict, clip = anim.clip, scenario = anim.scenario, flag = anim.flag or 1 }
    end
    return st.progressBar(data)
end

-- Arbejdsposition: punkt og heading ud fra maskinens offset (Config.Stations[*].work / take).
local function spotOf(o, w)
    local p = vec3(o.pos.x, o.pos.y, o.pos.z) + Util.rotate(w.offset, o.h)
    return p, ((o.h or 0.0) + (w.heading or 0.0)) % 360
end

-- Gå hen til arbejdspositionen og stil dig præcist (ped-animationerne er lavet til netop det punkt).
local function goTo(o, w)
    local ped = PlayerPedId()
    if not w then
        TaskTurnPedToFaceCoord(ped, o.pos.x, o.pos.y, o.pos.z, 800)
        Wait(800)
        return true
    end
    local p, heading = spotOf(o, w)
    TaskGoStraightToCoord(ped, p.x, p.y, GetEntityCoords(ped).z, 1.0, 4000, heading, 0.05)
    local timeout = GetGameTimer() + 4000
    while #(GetEntityCoords(ped).xy - p.xy) > 0.2 and GetGameTimer() < timeout do Wait(50) end
    ClearPedTasks(ped)
    local here = GetEntityCoords(ped)
    -- Kom spilleren ikke helt hen (væg, møbler i vejen), bliver spilleren IKKE flyttet det sidste stykke.
    -- Ellers kunne man stille en maskine op ad en væg og blive sat ind på den anden side.
    if #(here.xy - p.xy) > P.maxSnap or math.abs(here.z - p.z - 1.0) > 1.2 then
        CF.notify(locale('err_no_space'), 'error')
        return false
    end
    SetEntityCoordsNoOffset(ped, p.x, p.y, here.z, false, false, false)
    SetEntityHeading(ped, heading)
    Wait(50)
    return true
end

-- Ped-animation fra m1_cf_ped.ycd, placeret med maskinen som reference (hænderne rammer håndtag, papir osv.).
local function playSpot(o, w)
    if not (w and w.clip) or not pcall(st.requestAnimDict, Config.PedDict, 3000) then return false end
    local ped = PlayerPedId()
    local p, heading = spotOf(o, w)
    TaskPlayAnimAdvanced(ped, Config.PedDict, w.clip, p.x, p.y, GetEntityCoords(ped).z, 0.0, 0.0, heading,
        4.0, 4.0, -1, 1, 0.0, 0, 0)
    return true
end

local function stopSpot(w)
    local ped = PlayerPedId()
    if w and w.clip then StopAnimTask(ped, Config.PedDict, w.clip, 2.0) end
    ClearPedTasks(ped)
end

-- spot = arbejdsposition med egen ped-animation; anim = vanilla-animation (pak sammen, beslaglæg osv.)
local function action(label, duration, anim, event, id, spot)
    if CF.busy then return end
    CF.busy = true
    local o = Objects[id]
    if o and not goTo(o, spot) then
        CF.busy = false
        return
    end
    if o and playSpot(o, spot) then anim = nil end
    local done = progress(label, duration, anim)
    local ok, a, b
    if done then ok, a, b = st.callback.await(event, 500, id) end
    stopSpot(spot)
    CF.busy = false
    if not done then return end
    if not ok then CF.notify(a or locale('err_failed'), 'error') end
    return ok, a, b
end

function CF.fill(id)
    local o = Objects[id]
    local def = o and Config.Stations[o.type]
    if not def then return end
    local ok, batches = action(def.fillText, Config.Anims.fill, nil, 'mach1ne_counterfeit:fill', id, def.work)
    if ok then
        CF.notify(locale(batches == 1 and 'started_one' or 'started_other', def.label, batches, def.minutes), 'success')
    end
end

function CF.collect(id)
    local o = Objects[id]
    local def = o and Config.Stations[o.type]
    if not def then return end
    local ok, got, spoiled = action(def.collectText, Config.Anims.collect.duration, Config.Anims.collect,
        'mach1ne_counterfeit:collect', id, def.take or def.work)
    if not ok then return end
    if got == 0 then
        CF.notify(locale('collect_ruined'), 'error')
    elseif spoiled then
        CF.notify(locale('collect_spoiled', got), 'warning')
    else
        CF.notify(locale('collect_ok', got), 'success')
    end
end

-- Vent til maskinen har skiftet til sin "aktive" model, og genstart dens animation fra start,
-- så den går i takt med spillerens animation (begge loops har samme længde).
local function restartPropAnim(o)
    local timeout = GetGameTimer() + 2000
    while GetGameTimer() < timeout do
        local e = ents[o.id]
        local t = CF.now()
        if e and e.obj and DoesEntityExist(e.obj) and stateOf(o, t) == 'active'
            and e.model == CF.resolveModel(modelList(o, t)) and not e.loading then
            o.t0 = GetGameTimer()
            e.clip = nil
            updateAnim(o, e, CF.now())
            return
        end
        Wait(0)
    end
end

local working

RegisterNetEvent('mach1ne_counterfeit:interrupted', function(id)
    if working == id then
        working = nil
        CF.notify(locale('seized_while_working'), 'error')
    end
end)

-- En anden spiller er gået i gang: sæt maskinens animation i takt med spillerens ped-animation.
RegisterNetEvent('mach1ne_counterfeit:animSync', function(id, elapsed)
    local o = Objects[id]
    if not o or working == id then return end
    setT0(o, elapsed)
    local e = ents[id]
    if e then
        e.clip = nil
        updateAnim(o, e, CF.now())
    end
end)

-- Skæremaskine / sedeltæller: maskinen animerer, mens spilleren arbejder ved den.
function CF.work(id)
    if CF.busy then return end
    local o = Objects[id]
    local def = o and Config.Stations[o.type]
    if not def then return end
    CF.busy = true
    if not goTo(o, def.work) then
        CF.busy = false
        return
    end

    local prefix
    if def.engraver then
        local input = lib.inputDialog(locale('engrave_title'), {
            { type = 'input', label = locale('engrave_prefix'), description = locale('engrave_prefix_desc'),
              required = true, min = 2, max = 2 },
        })
        prefix = input and input[1] and input[1]:upper()
        if not prefix then
            CF.busy = false
            return
        end
    end

    local ok, batches, duration = st.callback.await('mach1ne_counterfeit:startWork', 500, id, prefix)
    if not ok then
        CF.busy = false
        return CF.notify(batches or locale('err_failed'), 'error')
    end

    working = id
    restartPropAnim(o)
    local anim = not playSpot(o, def.work) and Config.Anims.collect or nil
    TriggerServerEvent('mach1ne_counterfeit:animStart', id)
    local done = progress(def.workText, duration, anim)
    stopSpot(def.work)
    local stillMine = working == id
    working = nil
    CF.busy = false

    if not stillMine then return end   -- maskinen blev beslaglagt undervejs
    if not done then
        st.callback.await('mach1ne_counterfeit:cancelWork', 500, id)
        return CF.notify(locale('work_cancelled'), 'inform')
    end

    local fin, n, serial = st.callback.await('mach1ne_counterfeit:finishWork', 500, id)
    if not fin then return CF.notify(n or locale('err_failed'), 'error') end
    if def.engraver then
        CF.notify(locale('plate_ready', prefix, Config.Plate.uses), 'success')
    elseif serial then
        CF.notify(locale(n == 1 and 'bundles_ready_one' or 'bundles_ready_other', n, serial), 'success')
    else
        local out = {}
        for item, amount in pairs(def.output) do out[#out + 1] = ('%dx %s'):format(amount * n, CF.itemLabel(item)) end
        CF.notify(table.concat(out, ', '), 'success')
    end
end

function CF.plate(id, event)
    local ok, a, b = action(locale(event == 'insertPlate' and 'plate_inserting' or 'plate_removing'), 3000,
        Config.Anims.collect, 'mach1ne_counterfeit:' .. event, id, Config.Stations.cf_press.work)
    if ok then CF.notify(locale(event == 'insertPlate' and 'plate_inserted' or 'plate_removed', a, b), 'success') end
end

-- Politiet aflæser pressens typeskilt.
function CF.showSerial(id)
    local o = Objects[id]
    if not o or not o.data.serial then return end
    local p = o.data.plate
    CF.notify(p and locale('serial_plate', o.data.serial, p.prefix, p.uses) or locale('serial_noplate', o.data.serial), 'inform')
end

function CF.pickup(id)
    local ok = action(locale('picking_up'), Config.Anims.place.duration, Config.Anims.place, 'mach1ne_counterfeit:pickup', id)
    if ok then CF.notify(locale('picked_up'), 'success') end
end

function CF.seize(id)
    local A = Config.Anims.seize
    local ok = action(locale('seizing'), A.duration, A, 'mach1ne_counterfeit:seize', id)
    if ok then CF.notify(locale('seized'), 'success') end
end

-- ===================== UV-scanner =====================

local function zoneLabel(pos)
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(pos.x, pos.y, pos.z))
    local zone = GetLabelText(GetNameOfZone(pos.x, pos.y, pos.z))
    return street ~= '' and ('%s, %s'):format(street, zone) or zone
end

function CF.notifyPlates(plates)
    for _, p in ipairs(plates or {}) do CF.notify(locale('plate_seized', p), 'success') end
end

-- Viser scanningsresultatet (bruges af håndscanneren og politiets scanner-bord).
function CF.showScanResults(list, police)
    if not list or #list == 0 then return CF.notify(locale('scan_none'), 'inform') end
    local options = {}
    for _, e in ipairs(list) do
        local desc = locale(e.count == 1 and 'scan_fake_one' or 'scan_fake_other', e.count)
        local meta
        if police and e.created then
            desc = locale('scan_origin', desc, e.createdText or '?', e.counterId,
                e.active and locale('scan_still_placed') or locale('scan_removed'))
            if e.press then desc = desc .. '\n' .. locale('scan_press', e.press) end
            if e.plateOwner then desc = desc .. '\n' .. locale('scan_plate_owner', e.plateOwner) end
            meta = { { label = locale('scan_area'), value = zoneLabel(e.pos) },
                     { label = locale('scan_batch'), value = locale('scan_batch_value', e.batch or 0) } }
        end
        options[#options + 1] = {
            title = locale('scan_serial', e.serial), description = desc, icon = 'money-bill-wave', metadata = meta,
            onSelect = police and e.pos and function()
                SetNewWaypoint(e.pos.x + math.random(-40, 40), e.pos.y + math.random(-40, 40))
                CF.notify(locale('scan_waypoint'), 'inform')
            end or nil,
        }
    end
    lib.registerContext({ id = 'mach1ne_counterfeit_scan', title = locale('scan_title'), options = options })
    lib.showContext('mach1ne_counterfeit_scan')
end

exports('useScanner', function()
    if CF.busy then return end
    CF.busy = true
    local A = Config.Anims.scan
    local done = progress(locale('scan_progress'), A.duration, A)
    ClearPedTasks(PlayerPedId())
    CF.busy = false
    if not done then return end
    local list, police, plates = st.callback.await('mach1ne_counterfeit:scan', 500)
    CF.showScanResults(list, police)
    CF.notifyPlates(plates)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(ents) do despawn(id) end
    if dictLoaded then RemoveAnimDict(Config.AnimDict) end
end)

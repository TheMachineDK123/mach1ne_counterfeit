local ox      = exports.ox_inventory
local Objects = {}   -- [id] = { id, kind = 'station'|'prop', type, owner, bucket, pos, h, data }
local loaded  = false
local Work    = {}   -- [id] = { src, identifier, batches, input, output, finishAt }

local function now() return os.time() end

-- ===================== Log =====================

local function log(src, msg)
    local name = src and GetPlayerName(src) or 'server'
    print(('[mach1ne_counterfeit] %s: %s'):format(name, msg))
    local hook = Config.Log.discordWebhook
    if hook and hook ~= '' then
        PerformHttpRequest(hook, function() end, 'POST', json.encode({
            username = 'Falskmøntner-log',
            embeds = { { description = ('**%s** (%s)\n%s'):format(name, src or '-', msg), color = 3066993 } },
        }), { ['Content-Type'] = 'application/json' })
    end
end

-- ===================== Database =====================

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `m1_counterfeit_objects` (
            `id`         INT NOT NULL AUTO_INCREMENT,
            `kind`       VARCHAR(10) NOT NULL,
            `type`       VARCHAR(32) NOT NULL,
            `owner`      VARCHAR(60) NOT NULL,
            `bucket`     INT NOT NULL DEFAULT 0,
            `x`          DOUBLE NOT NULL,
            `y`          DOUBLE NOT NULL,
            `z`          DOUBLE NOT NULL,
            `h`          FLOAT  NOT NULL DEFAULT 0,
            `data`       LONGTEXT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `m1_counterfeit_serials` (
            `serial`     VARCHAR(16) NOT NULL,
            `counter_id` INT NOT NULL,
            `owner`      VARCHAR(60) NOT NULL,
            `amount`     INT NOT NULL DEFAULT 0,
            `x`          DOUBLE NOT NULL,
            `y`          DOUBLE NOT NULL,
            `z`          DOUBLE NOT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`serial`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Trykplader: hvem der ejer hvilket serieprefiks, og om politiet har beslaglagt pladen
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `m1_counterfeit_plates` (
            `prefix`     VARCHAR(4)  NOT NULL,
            `owner`      VARCHAR(60) NOT NULL,
            `seized`     TINYINT     NOT NULL DEFAULT 0,
            `created_at` BIGINT      NOT NULL DEFAULT 0,
            PRIMARY KEY (`prefix`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    -- Materialer til spillere, der loggede ud midt i arbejdet (udbetales næste gang de logger ind)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `m1_counterfeit_refunds` (
            `id`         INT NOT NULL AUTO_INCREMENT,
            `identifier` VARCHAR(60) NOT NULL,
            `items`      LONGTEXT NOT NULL,
            `created_at` BIGINT NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`),
            KEY `idx_identifier` (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])

    for _, row in ipairs(MySQL.query.await('SELECT * FROM m1_counterfeit_objects') or {}) do
        local data = row.data and json.decode(row.data) or {}
        data.activeUntil, data.user = nil, nil   -- igangværende arbejde overlever ikke en genstart
        Objects[row.id] = {
            id = row.id, kind = row.kind, type = row.type, owner = row.owner, bucket = row.bucket or 0,
            pos = { x = row.x, y = row.y, z = row.z }, h = row.h, data = data,
        }
    end
    loaded = true
end)

-- ===================== Hjælpere =====================

-- ms siden spilleren startede animationen ved en aktiv maskine (så klienter kan sætte samme fase)
local function animElapsed(o)
    local w = Work[o.id]
    return w and w.startMs and (GetGameTimer() - w.startMs) or nil
end

local function public(o)
    return { id = o.id, kind = o.kind, type = o.type, bucket = o.bucket, pos = o.pos, h = o.h, data = o.data,
             elapsed = animElapsed(o) }
end

local function changed(o)
    MySQL.update('UPDATE m1_counterfeit_objects SET data = ? WHERE id = ?', { json.encode(o.data), o.id })
    TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data)
end

local function getIdentifier(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier
end

local function isPolice(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and Util.isPoliceJob({ name = xPlayer.job.name, grade = xPlayer.job.grade })
end

local function playerPos(src)
    return GetEntityCoords(GetPlayerPed(src))
end

local function getObj(src, id, kind)
    local o = Objects[tonumber(id)]
    if not o or (kind and o.kind ~= kind) then return nil, locale('err_gone') end
    if o.bucket ~= GetPlayerRoutingBucket(src) then return nil, locale('err_gone') end
    if #(playerPos(src) - vec3(o.pos.x, o.pos.y, o.pos.z)) > 4.0 then return nil, locale('err_too_far') end
    return o
end

local function countOwned(identifier, kind, typ)
    local n = 0
    for _, o in pairs(Objects) do
        if o.owner == identifier and o.kind == kind and (not typ or o.type == typ) then n = n + 1 end
    end
    return n
end

local function tooClose(pos, bucket, dist)
    local p = vec3(pos.x, pos.y, pos.z)
    for _, o in pairs(Objects) do
        if o.kind == 'station' and o.bucket == bucket and #(p - vec3(o.pos.x, o.pos.y, o.pos.z)) < dist then return true end
    end
    return false
end

local function deleteObj(id)
    Objects[id] = nil
    Work[id] = nil
    MySQL.query('DELETE FROM m1_counterfeit_objects WHERE id = ?', { id })
    TriggerClientEvent('mach1ne_counterfeit:remove', -1, id)
end

local function near(src, o, dist)
    return GetPlayerRoutingBucket(src) == o.bucket
        and #(playerPos(src) - vec3(o.pos.x, o.pos.y, o.pos.z)) <= (dist or 4.0)
end

-- Giv items til spilleren. Kan de ikke være i inventaret, lægges resten på jorden ved spilleren,
-- så intet forsvinder. items = { { name, count, metadata? }, ... }
local function giveOrDrop(src, items)
    local drop = {}
    for _, it in ipairs(items) do
        local name, count, meta = it[1], it[2], it[3]
        if count and count > 0 then
            local ok = ox:CanCarryItem(src, name, count, meta) and ox:AddItem(src, name, count, meta)
            if not ok then drop[#drop + 1] = { name, count, meta } end
        end
    end
    if #drop > 0 then
        local c = playerPos(src)
        ox:CustomDrop(locale('drop_label'), drop, vec3(c.x, c.y, c.z - 0.95), nil, nil, GetPlayerRoutingBucket(src))
        TriggerClientEvent('mach1ne_counterfeit:notify', src, locale('items_dropped'), 'warning')
    end
    return #drop == 0
end

local function canCarryAll(src, list)
    for item, count in pairs(list) do
        if count > 0 and not ox:CanCarryItem(src, item, count) then return false end
    end
    return true
end

-- Serieprefikset (fra trykpladen) følger arkene og sedlerne som metadata gennem hele kæden.
local function prefixMeta(prefix)
    return prefix and { prefix = prefix, description = locale('prefix_desc', prefix) } or nil
end

-- Den prefiks-gruppe af et item, spilleren har flest af. false = items uden prefiks (lavet før pladerne).
local function pickPrefix(src, item)
    local groups, best, bestN = {}, false, 0
    for _, slot in pairs(ox:Search(src, 'slots', item) or {}) do
        local p = slot.metadata and slot.metadata.prefix or false
        groups[p] = (groups[p] or 0) + slot.count
        if groups[p] > bestN then best, bestN = p, groups[p] end
    end
    return best, groups
end

local function possibleBatches(src, def, prefix, groups)
    local n = def.maxBatches
    for item, amount in pairs(def.input) do
        local have = (def.carry == item and groups) and (groups[prefix or false] or 0) or ox:GetItemCount(src, item)
        n = math.min(n, math.floor(have / amount))
    end
    return n
end

local function takeInput(src, def, batches, prefix)
    local taken = {}
    for item, amount in pairs(def.input) do
        -- shortcut: items uden prefiks (prefix = false) fjernes uden metadata-filter og kan tage prefiks-items med,
        -- hvis spilleren har begge slags. Kun relevant for gamle items fra før trykpladerne.
        local meta = def.carry == item and prefix and { prefix = prefix } or nil
        if not ox:RemoveItem(src, item, amount * batches, meta, nil, nil, false) then
            for _, t in ipairs(taken) do ox:AddItem(src, t[1], t[2], t[3]) end   -- rul tilbage
            return false
        end
        taken[#taken + 1] = { item, amount * batches, meta and prefixMeta(prefix) or nil }
    end
    return true
end

-- Find en trykplade med slag tilbage. Returnerer slot og metadata.
local function findPlate(src)
    for _, slot in pairs(ox:Search(src, 'slots', Config.Items.plate) or {}) do
        if slot.metadata and slot.metadata.prefix and (slot.metadata.uses or 0) > 0 then return slot end
    end
end

local function wearPlate(src, slot, used)
    local meta = slot.metadata
    meta.uses = (meta.uses or 0) - used
    if meta.uses <= 0 then
        ox:RemoveItem(src, Config.Items.plate, 1, nil, slot.slot)
        TriggerClientEvent('mach1ne_counterfeit:notify', src, locale('plate_worn', meta.prefix), 'warning')
    else
        meta.description = locale('plate_desc', meta.prefix, meta.uses)
        ox:SetMetadata(src, slot.slot, meta)
    end
end

local function policeAlert(pos, message)
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        if Util.isPoliceJob({ name = xPlayer.job.name, grade = xPlayer.job.grade }) then
            TriggerClientEvent('mach1ne_counterfeit:dispatch', xPlayer.source, pos, message)
        end
    end
end

-- ===================== Routing buckets =====================

local playerBucket = {}

CreateThread(function()
    while true do
        for _, s in ipairs(GetPlayers()) do
            local src = tonumber(s)
            local b = GetPlayerRoutingBucket(src)
            if playerBucket[src] ~= b then
                playerBucket[src] = b
                TriggerClientEvent('mach1ne_counterfeit:bucket', src, b)
            end
        end
        Wait(1500)
    end
end)

AddEventHandler('playerDropped', function() playerBucket[source] = nil end)

-- ===================== Hent / placér =====================

st.callback.register('mach1ne_counterfeit:getAll', function(src)
    while not loaded do Wait(100) end
    local list = {}
    for _, o in pairs(Objects) do list[#list + 1] = public(o) end
    playerBucket[src] = GetPlayerRoutingBucket(src)
    return list, now(), playerBucket[src]
end)

st.callback.register('mach1ne_counterfeit:place', function(src, itemName, pos, heading)
    if type(pos) ~= 'table' or type(pos.x) ~= 'number' or type(pos.y) ~= 'number' or type(pos.z) ~= 'number' then
        return false, locale('err_position')
    end
    heading = (tonumber(heading) or 0.0) % 360

    local identifier = getIdentifier(src)
    if not identifier then return false, locale('err_no_player') end
    if #(playerPos(src) - vec3(pos.x, pos.y, pos.z)) > Config.Place.maxDistance + Config.Place.maxLift + 1.0 then
        return false, locale('place_too_far')
    end

    local kind   = Util.kindOf(itemName)
    local bucket = GetPlayerRoutingBucket(src)
    local data

    if kind == 'station' then
        if countOwned(identifier, 'station', itemName) >= Config.StationLimits.maxPerPlayer then
            return false, locale('err_max_type', Config.StationLimits.maxPerPlayer)
        end
        if tooClose(pos, bucket, Config.StationLimits.minDistance) then return false, locale('place_too_close') end
        data = { station = itemName, batches = 0 }
    elseif kind == 'prop' then
        local def = Config.Props[itemName]
        if def.police and not isPolice(src) then return false, locale('err_police_item') end
        if countOwned(identifier, 'prop', itemName) >= def.maxPerPlayer then
            return false, locale('err_max_type', def.maxPerPlayer)
        end
        data = {}
    else
        return false, locale('err_unknown_item')
    end

    if not ox:RemoveItem(src, itemName, 1) then return false, locale('err_missing_item') end

    local id = MySQL.insert.await(
        'INSERT INTO m1_counterfeit_objects (kind, type, owner, bucket, x, y, z, h, data, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { kind, itemName, identifier, bucket, pos.x, pos.y, pos.z, heading, json.encode(data), now() })
    if not id then
        ox:AddItem(src, itemName, 1)
        return false, locale('err_database')
    end

    local o = { id = id, kind = kind, type = itemName, owner = identifier, bucket = bucket,
                pos = { x = pos.x, y = pos.y, z = pos.z }, h = heading, data = data }
    Objects[id] = o
    TriggerClientEvent('mach1ne_counterfeit:add', -1, public(o))
    log(src, ('placerede %s #%d ved %.1f, %.1f, %.1f (bucket %d)'):format(itemName, id, pos.x, pos.y, pos.z, bucket))
    return true, id
end)

-- ===================== Tidsstyrede maskiner (presse / tørresnor) =====================

st.callback.register('mach1ne_counterfeit:fill', function(src, id)
    local o, err = getObj(src, id, 'station')
    if not o then return false, err end
    local def = Config.Stations[o.type]
    if not def or def.mode ~= 'timed' then return false, locale('err_unknown_machine') end
    if Util.stationState(o.data, now()) ~= 'empty' then return false, locale('err_busy') end

    local prefix, groups, plate
    if def.plate then
        plate = findPlate(src)
        if not plate then return false, locale('err_no_plate') end
        prefix = plate.metadata.prefix
    elseif def.carry then
        prefix, groups = pickPrefix(src, def.carry)
    end
    local batches = possibleBatches(src, def, prefix, groups)
    if plate then batches = math.min(batches, plate.metadata.uses) end
    if batches < 1 then return false, locale('err_materials') end
    if not takeInput(src, def, batches, prefix) then return false, locale('err_materials') end
    if plate then wearPlate(src, plate, batches) end

    local t = now()
    o.data = { station = o.type, batches = batches, started = t, done = t + def.minutes * 60, prefix = prefix or nil }
    changed(o)
    log(src, ('startede %s #%d med %d portion(er)'):format(o.type, o.id, batches))
    return true, batches
end)

st.callback.register('mach1ne_counterfeit:collect', function(src, id)
    local o, err = getObj(src, id, 'station')
    if not o then return false, err end
    local def   = Config.Stations[o.type]
    if not def or def.mode ~= 'timed' then return false, locale('err_unknown_machine') end
    local state = Util.stationState(o.data, now())
    if state == 'empty' then return false, locale('err_empty') end
    if state == 'working' then return false, locale('err_not_done') end

    local keep = state == 'spoiled' and def.spoil.keep or 1.0
    local out  = {}
    for item, amount in pairs(def.output) do
        out[item] = math.floor(amount * o.data.batches * keep)
    end
    if not canCarryAll(src, out) then return false, locale('err_carry_all') end

    local prefix = o.data.prefix
    o.data = { station = o.type, batches = 0 }
    changed(o)

    local got, give = 0, {}
    for item, count in pairs(out) do
        give[#give + 1] = { item, count, prefixMeta(prefix) }
        got = got + count
    end
    giveOrDrop(src, give)
    log(src, ('tømte %s #%d (%s) - %d stk.'):format(o.type, o.id, state, got))
    return true, got, state == 'spoiled'
end)

-- Støj fra presser der kører
local lastCall = {}

CreateThread(function()
    while not loaded do Wait(500) end
    local N = Config.Noise
    while true do
        Wait(60000)
        local t = now()
        for id, o in pairs(Objects) do
            local def = o.kind == 'station' and Config.Stations[o.type]
            if def and def.noise and Util.stationState(o.data, t) == 'working'
                and (o.bucket == 0 or N.callFromInstances)
                and t - (lastCall[id] or 0) >= N.cooldownMinutes * 60
                and math.random(100) <= N.callChancePerMinute then
                lastCall[id] = t
                policeAlert(o.pos, N.message)
                log(nil, ('naboer meldte støj fra %s #%d'):format(o.type, id))
            end
        end
    end
end)

-- ===================== Aktive maskiner (skæremaskine / sedeltæller) =====================

local SERIAL_CHARS = 'ABCDEFGHJKLMNPRSTUVWXYZ'

local function newSerial(prefix)
    prefix = prefix or 'LS'
    for _ = 1, 20 do
        local i = math.random(#SERIAL_CHARS)
        local s = ('%s %05d%s'):format(prefix, math.random(0, 99999), SERIAL_CHARS:sub(i, i))
        if not MySQL.scalar.await('SELECT 1 FROM m1_counterfeit_serials WHERE serial = ?', { s }) then return s end
    end
    return ('%s %d'):format(prefix, now() % 100000000)
end

-- Gyldigt prefiks til en ny trykplade: 2 store bogstaver, ikke reserveret, ikke ejet af en anden.
local function checkPrefix(prefix, identifier)
    prefix = type(prefix) == 'string' and prefix:upper() or ''
    if not prefix:match('^%u%u$') or Config.Plate.reserved[prefix] then return nil, locale('err_prefix_invalid') end
    local owner = MySQL.scalar.await('SELECT owner FROM m1_counterfeit_plates WHERE prefix = ?', { prefix })
    if owner and owner ~= identifier then return nil, locale('err_prefix_taken') end
    return prefix
end

st.callback.register('mach1ne_counterfeit:startWork', function(src, id, wantPrefix)
    local o, err = getObj(src, id, 'station')
    if not o then return false, err end
    local def = Config.Stations[o.type]
    if not def or def.mode ~= 'active' then return false, locale('err_unknown_machine') end
    if Work[o.id] or Util.stationState(o.data, now()) == 'active' then return false, locale('err_in_use') end

    local identifier = getIdentifier(src)
    local prefix, groups
    if def.engraver then
        local reason
        prefix, reason = checkPrefix(wantPrefix, identifier)
        if not prefix then return false, reason end
    elseif def.carry then
        prefix, groups = pickPrefix(src, def.carry)
    end

    local batches = possibleBatches(src, def, prefix, groups)
    if batches < 1 then return false, locale('err_materials') end

    local out = {}
    for item, amount in pairs(def.output) do out[item] = amount * batches end
    if not canCarryAll(src, out) then return false, locale('err_carry_all') end
    if not takeInput(src, def, batches, not def.engraver and prefix or nil) then return false, locale('err_materials') end

    local duration = math.ceil(def.seconds * batches)
    Work[o.id] = { src = src, identifier = identifier, batches = batches, finishAt = now() + duration - 1,
                   startMs = GetGameTimer(), prefix = prefix or nil }
    o.data = { station = o.type, activeUntil = now() + duration, batches = batches, duration = duration }
    TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data, 0)
    return true, batches, duration * 1000
end)

-- Spilleren melder, at ped-animationen er startet: alle sætter maskinens animation i samme fase.
RegisterNetEvent('mach1ne_counterfeit:animStart', function(id)
    local src = source
    local w = Work[tonumber(id)]
    if not w or w.src ~= src then return end
    w.startMs = GetGameTimer()
    TriggerClientEvent('mach1ne_counterfeit:animSync', -1, tonumber(id), 0)
end)

local function inputItems(def, batches, prefix)
    local list = {}
    for item, amount in pairs(def.input) do
        list[#list + 1] = { item, amount * batches, def.carry == item and prefixMeta(prefix) or nil }
    end
    return list
end

local function refund(src, def, batches, prefix)
    giveOrDrop(src, inputItems(def, batches, prefix))
end

-- Spilleren er ikke online: gem materialerne og giv dem ved næste login.
local function queueRefund(identifier, def, batches, prefix)
    if not identifier then return end
    MySQL.insert('INSERT INTO m1_counterfeit_refunds (identifier, items, created_at) VALUES (?, ?, ?)',
        { identifier, json.encode(inputItems(def, batches, prefix)), now() })
end

-- Afbryd en igangværende opgave og lås maskinen op igen.
local function endWork(o, w, how)
    Work[o.id] = nil
    local def = Config.Stations[o.type]
    local carried = not def.engraver and w.prefix or nil
    if how == 'refund' then
        refund(w.src, def, w.batches, carried)
    elseif how == 'queue' then
        queueRefund(w.identifier, def, w.batches, carried)
    end
    o.data = { station = o.type }
    TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data)
end

st.callback.register('mach1ne_counterfeit:cancelWork', function(src, id)
    local o = Objects[tonumber(id)]
    local w = o and Work[o.id]
    if not w or w.src ~= src then return false end
    endWork(o, w, 'refund')
    return true
end)

st.callback.register('mach1ne_counterfeit:finishWork', function(src, id)
    local o = Objects[tonumber(id)]
    local w = o and Work[o.id]
    if not w or w.src ~= src then return false, locale('err_interrupted') end
    if now() < w.finishAt then return false, locale('err_too_fast') end
    if not near(src, o) then
        endWork(o, w, 'refund')
        return false, locale('err_too_far')
    end
    local def = Config.Stations[o.type]
    Work[o.id] = nil

    local serial
    if def.engraver then
        -- ny trykplade: prefikset registreres på spilleren (en anden kan have taget det imens)
        local prefix = checkPrefix(w.prefix, w.identifier)
        if not prefix then
            refund(src, def, w.batches)
            o.data = { station = o.type }
            changed(o)
            return false, locale('err_prefix_taken')
        end
        MySQL.insert.await('INSERT INTO m1_counterfeit_plates (prefix, owner, created_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE seized = 0',
            { prefix, w.identifier, now() })
        giveOrDrop(src, { { Config.Items.plate, w.batches, {
            prefix = prefix, uses = Config.Plate.uses, description = locale('plate_desc', prefix, Config.Plate.uses),
        } } })
    elseif o.type == 'cf_counter' then
        serial = newSerial(w.prefix)
        local B = Config.Bundle
        giveOrDrop(src, { { Config.Items.bundle, w.batches, {
            serial = serial, value = B.value,
            description = locale('bundle_description', serial, B.bills),
        } } })
        MySQL.insert('INSERT INTO m1_counterfeit_serials (serial, counter_id, owner, amount, x, y, z, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { serial, o.id, w.identifier, w.batches, o.pos.x, o.pos.y, o.pos.z, now() })
    else
        local give = {}
        for item, amount in pairs(def.output) do give[#give + 1] = { item, amount * w.batches, prefixMeta(w.prefix) } end
        giveOrDrop(src, give)
    end

    o.data = { station = o.type, doneUntil = def.doneSeconds and (now() + def.doneSeconds) or nil,
               lastSerial = serial, lastCount = serial and w.batches or nil }
    changed(o)
    log(src, ('%s #%d: %d portion(er)%s'):format(o.type, o.id, w.batches, serial and (' - serie ' .. serial) or ''))
    return true, w.batches, serial
end)

-- Spilleren forsvandt midt i arbejdet: lås maskinen op igen og giv materialerne tilbage, hvis muligt.
CreateThread(function()
    while true do
        Wait(5000)
        local t = now()
        for id, w in pairs(Work) do
            local o = Objects[id]
            if not o then
                Work[id] = nil
            elseif t > w.finishAt + 30 then
                local online = GetPlayerName(w.src) and getIdentifier(w.src) == w.identifier
                endWork(o, w, online and 'refund' or 'queue')
            end
        end
    end
end)

-- Logger spilleren ud midt i arbejdet, gemmes materialerne til næste login.
AddEventHandler('playerDropped', function()
    local src = source
    for id, w in pairs(Work) do
        local o = Objects[id]
        if w.src == src and o then endWork(o, w, 'queue') end
    end
end)

local function payRefunds(src, identifier)
    local rows = MySQL.query.await('SELECT id, items FROM m1_counterfeit_refunds WHERE identifier = ?', { identifier }) or {}
    if #rows == 0 then return end
    MySQL.query.await('DELETE FROM m1_counterfeit_refunds WHERE identifier = ?', { identifier })
    for _, row in ipairs(rows) do giveOrDrop(src, json.decode(row.items) or {}) end
    TriggerClientEvent('mach1ne_counterfeit:notify', src, locale('refund_paid'), 'inform')
    log(src, ('fik %d gemt(e) refundering(er)'):format(#rows))
end

AddEventHandler('esx:playerLoaded', function(src, xPlayer)
    local identifier = xPlayer and xPlayer.identifier or getIdentifier(src)
    if not identifier then return end
    SetTimeout(8000, function()     -- giv ox_inventory tid til at indlæse inventaret
        if GetPlayerName(src) then payRefunds(src, identifier) end
    end)
end)

-- ===================== Pak sammen / beslaglæg =====================

st.callback.register('mach1ne_counterfeit:pickup', function(src, id)
    local o, err = getObj(src, id)
    if not o then return false, err end
    if o.owner ~= getIdentifier(src) then return false, locale('err_not_owner') end
    if o.kind == 'station' then
        local state = Util.stationState(o.data, now())
        if state ~= 'empty' and not (state == 'done' and Config.Stations[o.type].mode == 'active') then
            return false, locale('err_empty_first')
        end
    end
    if not ox:CanCarryItem(src, o.type, 1) then return false, locale('err_carry_it') end
    deleteObj(o.id)
    ox:AddItem(src, o.type, 1)
    log(src, ('pakkede %s #%d sammen'):format(o.type, o.id))
    return true
end)

st.callback.register('mach1ne_counterfeit:seize', function(src, id)
    if not isPolice(src) then return false, locale('err_police_only') end
    local o, err = getObj(src, id)
    if not o then return false, err end
    local w = Work[o.id]
    if w then TriggerClientEvent('mach1ne_counterfeit:interrupted', w.src, o.id) end
    deleteObj(o.id)
    log(src, ('beslaglagde %s #%d'):format(o.type, o.id))
    return true
end)

-- ===================== UV-scanner =====================
-- Alle kan se at bundterne er falske. Politiet får også registret: hvornår og hvor de blev talt op.

local function scanInventory(src)
    local items = ox:Search(src, 'slots', Config.Items.bundle) or {}
    local police = isPolice(src)
    local bySerial, list = {}, {}
    for _, slot in pairs(items) do
        local serial = slot.metadata and slot.metadata.serial or '?'
        if not bySerial[serial] then
            bySerial[serial] = { serial = serial, count = 0 }
            list[#list + 1] = bySerial[serial]
        end
        bySerial[serial].count = bySerial[serial].count + slot.count
    end
    local plates = {}
    if police then
        -- Trykplader politiet har på sig, bliver registreret som beslaglagt. Så kan alle sedler med det
        -- prefiks kobles til pladens ejer.
        for _, slot in pairs(ox:Search(src, 'slots', Config.Items.plate) or {}) do
            local p = slot.metadata and slot.metadata.prefix
            if p then
                MySQL.update.await('UPDATE m1_counterfeit_plates SET seized = 1 WHERE prefix = ?', { p })
                plates[#plates + 1] = p
            end
        end
        for _, e in ipairs(list) do
            local row = MySQL.single.await('SELECT counter_id, amount, x, y, z, created_at FROM m1_counterfeit_serials WHERE serial = ?', { e.serial })
            if row then
                e.counterId, e.batch, e.created = row.counter_id, row.amount, row.created_at
                e.createdText = os.date('%d/%m %H:%M', row.created_at)
                e.pos = { x = row.x, y = row.y, z = row.z }
                e.active = Objects[row.counter_id] ~= nil
            end
            local prefix = e.serial:match('^(%u+) ')
            local plate = prefix and MySQL.single.await(
                'SELECT u.firstname, u.lastname FROM m1_counterfeit_plates p LEFT JOIN users u ON u.identifier = p.owner WHERE p.prefix = ? AND p.seized = 1',
                { prefix })
            if plate then e.plateOwner = ('%s %s'):format(plate.firstname or '?', plate.lastname or '') end
        end
    end
    return list, police, plates
end

-- Håndscanner (item)
st.callback.register('mach1ne_counterfeit:scan', function(src)
    return scanInventory(src)
end)

-- Scanner-bordet (prop): kun politiet. Resultatet vises også på bordets skærm for alle i nærheden.
st.callback.register('mach1ne_counterfeit:scanDesk', function(src, id)
    if not isPolice(src) then return false, locale('err_police_only') end
    local o, err = getObj(src, id, 'prop')
    if not o or not (Config.Props[o.type] and Config.Props[o.type].screen == 'uv') then return false, err end
    local list, _, plates = scanInventory(src)
    local total, first = 0, list[1]
    for _, e in ipairs(list) do total = total + e.count end
    local screen = {
        at = now(), serials = #list, total = total,
        serial = first and first.serial or nil, created = first and first.createdText or nil,
        pos = first and first.pos or nil,
    }
    o.data.scan = screen
    TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data)
    log(src, ('scannede %d bundt(er) ved UV-scanner #%d'):format(total, o.id))
    return true, list, plates
end)

-- ===================== Hæler =====================

-- Hælerens kurs: falder når der sælges meget, stiger langsomt igen. Gemmes i KVP og deles via GlobalState.
local Rate = { value = GetResourceKvpFloat('m1cf_rate') }
if not Rate.value or Rate.value <= 0 then Rate.value = Config.Dealer.sell.rate end
Rate.hourAgo = Rate.value

local function publishRate()
    local S = Config.Dealer.sell
    local trend = Rate.value > Rate.hourAgo + 0.002 and 1 or (Rate.value < Rate.hourAgo - 0.002 and -1 or 0)
    local demand = Rate.value >= S.rate + 0.03 and 'high' or (Rate.value <= S.rate - 0.05 and 'low' or 'normal')
    GlobalState.m1cfRate = {
        rate = Rate.value, price = math.floor(Config.Bundle.value * Rate.value), trend = trend, demand = demand,
        max = S.max,
    }
    SetResourceKvpFloat('m1cf_rate', Rate.value)
end

CreateThread(function()
    local S = Config.Dealer.sell
    publishRate()
    local ticks = 0
    while true do
        Wait(60000)
        ticks = ticks + 1
        -- op mod 'rate' (og lidt over, hvis der er roligt), med lidt tilfældig støj
        local target = S.rate + 0.04
        local step = S.recoverPerHour / 60
        Rate.value = math.min(S.maxRate, math.max(S.minRate, Rate.value + (Rate.value < target and step or -step * 0.2)
            + (math.random() - 0.5) * 0.002))
        if ticks % 60 == 0 then Rate.hourAgo = Rate.value end
        publishRate()
    end
end)

st.callback.register('mach1ne_counterfeit:getRate', function()
    return GlobalState.m1cfRate
end)

local function dealerNear(src)
    local c = Config.Dealer.coords
    return #(playerPos(src) - vec3(c.x, c.y, c.z)) <= 5.0
end

st.callback.register('mach1ne_counterfeit:buy', function(src, itemName, amount)
    if not Config.Dealer.enabled then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > 100 then return false, locale('err_amount') end

    local entry
    for _, it in ipairs(Config.Dealer.items) do
        if it.name == itemName then entry = it break end
    end
    if not entry then return false, locale('err_unknown_ware') end
    if not dealerNear(src) then return false, locale('err_too_far') end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local price = entry.price * amount
    if xPlayer.getAccount(Config.Dealer.account).money < price then return false, locale('err_no_money') end
    if not ox:CanCarryItem(src, itemName, amount) then return false, locale('err_carry') end

    xPlayer.removeAccountMoney(Config.Dealer.account, price)
    ox:AddItem(src, itemName, amount)
    return true, price
end)

st.callback.register('mach1ne_counterfeit:sell', function(src, amount)
    if not Config.Dealer.enabled then return false end
    local S = Config.Dealer.sell
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > S.max then return false, locale('err_sell_range', S.max) end
    if not dealerNear(src) then return false, locale('err_too_far') end
    if ox:GetItemCount(src, Config.Items.bundle) < amount then return false, locale('err_not_enough_bundles') end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    if not ox:RemoveItem(src, Config.Items.bundle, amount) then return false, locale('err_not_enough_bundles') end
    local pay = math.floor(Config.Bundle.value * Rate.value * amount)
    xPlayer.addAccountMoney(S.account, pay)
    Rate.value = math.max(S.minRate, Rate.value - S.dropPerBundle * amount)
    publishRate()
    log(src, ('solgte %d bundt(er) til hæleren for %d'):format(amount, pay))
    return true, pay
end)

-- ===================== Kurer =====================
-- Hæleren giver en leveringsopgave: N bundter til et tilfældigt sted inden for X minutter.

local Courier, lastCourier = {}, {}   -- [src] = { point, bundles, expires }; [identifier] = tid

st.callback.register('mach1ne_counterfeit:courierStart', function(src)
    local C = Config.Courier
    if not C.enabled then return false end
    if not dealerNear(src) then return false, locale('err_too_far') end
    if Courier[src] then return false, locale('courier_busy') end
    local identifier = getIdentifier(src)
    local wait = (lastCourier[identifier] or 0) + C.cooldownMinutes * 60 - now()
    if wait > 0 then return false, locale('courier_cooldown', math.ceil(wait / 60)) end

    local idx = math.random(#C.points)
    local job = { point = idx, bundles = math.random(C.bundles.min, C.bundles.max), expires = now() + C.minutes * 60 }
    Courier[src], lastCourier[identifier] = job, now()
    if math.random(100) <= C.tipChance then
        local p = C.points[idx]
        SetTimeout(C.tipDelay * 1000, function()
            if Courier[src] == job then policeAlert({ x = p.x, y = p.y, z = p.z }, locale('courier_tip')) end
        end)
    end
    log(src, ('tog en kurer-opgave: %d bundter til punkt %d'):format(job.bundles, idx))
    return true, idx, job.bundles, C.minutes
end)

st.callback.register('mach1ne_counterfeit:courierDeliver', function(src)
    local C, job = Config.Courier, Courier[src]
    if not job then return false, locale('courier_none') end
    if now() > job.expires then
        Courier[src] = nil
        return false, locale('courier_expired')
    end
    local p = C.points[job.point]
    if #(playerPos(src) - vec3(p.x, p.y, p.z)) > 5.0 then return false, locale('err_too_far') end
    if ox:GetItemCount(src, Config.Items.bundle) < job.bundles then
        return false, locale('courier_missing', job.bundles)
    end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not ox:RemoveItem(src, Config.Items.bundle, job.bundles) then return false, locale('err_failed') end
    local S = Config.Dealer.sell
    local pay = math.floor(Config.Bundle.value * Rate.value * C.bonus * job.bundles)
    xPlayer.addAccountMoney(S.account, pay)
    Rate.value = math.max(S.minRate, Rate.value - S.dropPerBundle * job.bundles)
    publishRate()
    Courier[src] = nil
    log(src, ('leverede %d bundter som kurer for %d'):format(job.bundles, pay))
    return true, pay, job.bundles
end)

st.callback.register('mach1ne_counterfeit:courierCancel', function(src)
    Courier[src] = nil
    return true
end)

AddEventHandler('playerDropped', function() Courier[source] = nil end)

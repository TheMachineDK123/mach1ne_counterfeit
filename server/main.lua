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

local function canCarryAll(src, list)
    for item, count in pairs(list) do
        if count > 0 and not ox:CanCarryItem(src, item, count) then return false end
    end
    return true
end

local function possibleBatches(src, def)
    local n = def.maxBatches
    for item, amount in pairs(def.input) do
        n = math.min(n, math.floor(ox:GetItemCount(src, item) / amount))
    end
    return n
end

local function takeInput(src, def, batches)
    local taken = {}
    for item, amount in pairs(def.input) do
        if not ox:RemoveItem(src, item, amount * batches) then
            for it, n in pairs(taken) do ox:AddItem(src, it, n) end   -- rul tilbage
            return false
        end
        taken[item] = amount * batches
    end
    return true
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

    local batches = possibleBatches(src, def)
    if batches < 1 then return false, locale('err_materials') end
    if not takeInput(src, def, batches) then return false, locale('err_materials') end

    local t = now()
    o.data = { station = o.type, batches = batches, started = t, done = t + def.minutes * 60 }
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

    o.data = { station = o.type, batches = 0 }
    changed(o)

    local got = 0
    for item, count in pairs(out) do
        if count > 0 then
            ox:AddItem(src, item, count)
            got = got + count
        end
    end
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

local function newSerial()
    for _ = 1, 20 do
        local i = math.random(#SERIAL_CHARS)
        local s = ('LS %05d%s'):format(math.random(0, 99999), SERIAL_CHARS:sub(i, i))
        if not MySQL.scalar.await('SELECT 1 FROM m1_counterfeit_serials WHERE serial = ?', { s }) then return s end
    end
    return ('LS %d'):format(now())
end

st.callback.register('mach1ne_counterfeit:startWork', function(src, id)
    local o, err = getObj(src, id, 'station')
    if not o then return false, err end
    local def = Config.Stations[o.type]
    if not def or def.mode ~= 'active' then return false, locale('err_unknown_machine') end
    if Util.stationState(o.data, now()) == 'active' then return false, locale('err_in_use') end

    local batches = possibleBatches(src, def)
    if batches < 1 then return false, locale('err_materials') end

    local out = {}
    for item, amount in pairs(def.output) do out[item] = amount * batches end
    if not canCarryAll(src, out) then return false, locale('err_carry_all') end
    if not takeInput(src, def, batches) then return false, locale('err_materials') end

    local duration = math.ceil(def.seconds * batches)
    Work[o.id] = { src = src, identifier = getIdentifier(src), batches = batches, finishAt = now() + duration - 1,
                   startMs = GetGameTimer() }
    o.data = { station = o.type, activeUntil = now() + duration }
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

local function refund(src, def, batches)
    for item, amount in pairs(def.input) do ox:AddItem(src, item, amount * batches) end
end

st.callback.register('mach1ne_counterfeit:cancelWork', function(src, id)
    local o = Objects[tonumber(id)]
    local w = o and Work[o.id]
    if not w or w.src ~= src then return false end
    Work[o.id] = nil
    refund(src, Config.Stations[o.type], w.batches)
    o.data = { station = o.type }
    TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data)
    return true
end)

st.callback.register('mach1ne_counterfeit:finishWork', function(src, id)
    local o = Objects[tonumber(id)]
    local w = o and Work[o.id]
    if not w or w.src ~= src then return false, locale('err_interrupted') end
    if now() < w.finishAt then return false, locale('err_too_fast') end
    local def = Config.Stations[o.type]
    Work[o.id] = nil

    local serial
    if o.type == 'cf_counter' then
        serial = newSerial()
        local B = Config.Bundle
        ox:AddItem(src, Config.Items.bundle, w.batches, {
            serial = serial, value = B.value,
            description = locale('bundle_description', serial, B.bills),
        })
        MySQL.insert('INSERT INTO m1_counterfeit_serials (serial, counter_id, owner, amount, x, y, z, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { serial, o.id, w.identifier, w.batches, o.pos.x, o.pos.y, o.pos.z, now() })
    else
        for item, amount in pairs(def.output) do ox:AddItem(src, item, amount * w.batches) end
    end

    o.data = { station = o.type, doneUntil = def.doneSeconds and (now() + def.doneSeconds) or nil }
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
                Work[id] = nil
                if GetPlayerName(w.src) and getIdentifier(w.src) == w.identifier then
                    refund(w.src, Config.Stations[o.type], w.batches)
                end
                o.data = { station = o.type }
                TriggerClientEvent('mach1ne_counterfeit:update', -1, o.id, o.data)
            end
        end
    end
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

st.callback.register('mach1ne_counterfeit:scan', function(src)
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
    if police then
        for _, e in ipairs(list) do
            local row = MySQL.single.await('SELECT counter_id, amount, x, y, z, created_at FROM m1_counterfeit_serials WHERE serial = ?', { e.serial })
            if row then
                e.counterId, e.batch, e.created = row.counter_id, row.amount, row.created_at
                e.createdText = os.date('%d/%m %H:%M', row.created_at)
                e.pos = { x = row.x, y = row.y, z = row.z }
                e.active = Objects[row.counter_id] ~= nil
            end
        end
    end
    return list, police
end)

-- ===================== Hæler =====================

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
    local pay = math.floor(Config.Bundle.value * S.rate * amount)
    xPlayer.addAccountMoney(S.account, pay)
    log(src, ('solgte %d bundt(er) til hæleren for %d'):format(amount, pay))
    return true, pay
end)

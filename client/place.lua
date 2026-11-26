-- Fri placering af maskiner og inventar: inde, ude, på borde og oven på andre ting.
local placing = false
local PL = Config.Place

local function rotationToDirection(rot)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    return vec3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
end

-- Sigter fra kameraet. Rammer verden og objekter (fx et placeret arbejdsbord), ikke spøgelset.
local function aim(ped)
    local cam  = GetGameplayCamCoord()
    local dest = cam + rotationToDirection(GetGameplayCamRot(2)) * (#(cam - GetEntityCoords(ped)) + PL.maxDistance + 2.0)
    local ray  = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 1 | 16, ped, 4)
    local _, hit, coords, normal = GetShapeTestResult(ray)
    if not hit or hit == 0 then return end
    return coords, normal
end

local function validate(kind, normal, coords)
    if normal.z < 0.6 then return locale('place_too_steep') end
    if kind == 'station' then
        for _, o in pairs(CF.objects) do
            if o.kind == 'station' and o.bucket == CF.bucket and #(coords - vec3(o.pos.x, o.pos.y, o.pos.z)) < Config.StationLimits.minDistance then
                return locale('place_too_close')
            end
        end
    end
end

local function hint(label, reason)
    local text = locale('place_help')
    if reason then text = ('⚠ %s  ·  %s'):format(reason, text) end
    st.showHintUI(locale('place_title', label), text, 'E')
end

local function startPlacing(itemName)
    if placing or CF.busy then return end
    local ped  = PlayerPedId()
    local kind = Util.kindOf(itemName)
    if not kind then return end
    if IsPedInAnyVehicle(ped, false) then return CF.notify(locale('place_vehicle'), 'error') end

    local hash = CF.resolveModel(CF.placeModels(itemName))
    if not hash or not pcall(st.requestModel, hash, 5000) then
        return CF.notify(locale('place_model'), 'error')
    end

    local def   = Config.Stations[itemName] or Config.Props[itemName]
    local label = def.label:lower()
    local ghost = CreateObjectNoOffset(hash, 0.0, 0.0, -100.0, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)

    local heading, lift = GetEntityHeading(ped), 0.0
    local chosen, lastReason
    placing = true
    hint(label)

    while true do
        Wait(0)
        for _, c in ipairs({ 14, 15, 16, 17, 24, 25, 37, 140, 141, 142, 261, 262 }) do DisableControlAction(0, c, true) end

        if IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 194) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then break end

        local speed = IsControlPressed(0, 21) and 15.0 or 90.0
        if IsControlPressed(0, 174) then heading = (heading + speed * GetFrameTime()) % 360 end
        if IsControlPressed(0, 175) then heading = (heading - speed * GetFrameTime()) % 360 end
        if IsDisabledControlJustPressed(0, 15) or IsDisabledControlJustPressed(0, 261) then lift = math.min(PL.maxLift, lift + PL.heightStep) end
        if IsDisabledControlJustPressed(0, 14) or IsDisabledControlJustPressed(0, 262) then lift = math.max(-PL.maxLift, lift - PL.heightStep) end

        local coords, normal = aim(ped)
        local reason
        if not coords or #(GetEntityCoords(ped) - coords) > PL.maxDistance then
            reason = locale('place_too_far')
        else
            coords = coords + vec3(0.0, 0.0, lift)
            reason = validate(kind, normal, coords)
        end

        if reason ~= lastReason then
            lastReason = reason
            hint(label, reason)
        end

        if coords then
            SetEntityCoordsNoOffset(ghost, coords.x, coords.y, coords.z, false, false, false)
            SetEntityHeading(ghost, heading)
            SetEntityAlpha(ghost, reason and 80 or 180, false)
            SetEntityVisible(ghost, true, false)
            if reason then
                DrawMarker(28, coords.x, coords.y, coords.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.08, 0.08, 0.08, 220, 40, 40, 180, false, false, 2, false, nil, nil, false)
            end
        else
            SetEntityVisible(ghost, false, false)
        end

        if IsControlJustPressed(0, 38) then
            if reason then
                CF.notify(reason, 'error')
            else
                chosen = coords
                break
            end
        end
    end

    st.hideHintUI()
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    placing = false
    if not chosen then return end

    TaskTurnPedToFaceCoord(ped, chosen.x, chosen.y, chosen.z, 800)
    Wait(800)

    local A = Config.Anims.place
    CF.busy = true
    local done = st.progressBar({
        duration = A.duration, label = locale('place_progress', label),
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = A.dict, clip = A.clip, flag = 49 },
    })
    ClearPedTasks(ped)
    CF.busy = false
    if not done then return end

    local ok, res = st.callback.await('mach1ne_counterfeit:place', 500, itemName,
        { x = chosen.x, y = chosen.y, z = chosen.z }, heading)
    if not ok then return CF.notify(res or locale('place_failed'), 'error') end
    CF.notify(locale('placed', def.label), 'success')
end

local function itemName(data, slot)
    return (slot and slot.name) or (type(data) == 'table' and data.name) or (type(data) == 'string' and data)
end

local function use(data, slot) startPlacing(itemName(data, slot)) end

exports('useStation', use)
exports('useProp', use)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and placing then st.hideHintUI() end
end)

-- UV-lommelygte (politi): tænd/sluk ved at bruge itemet. Lys på en spiller for at se falske bundter,
-- eller på en maskine for at aflæse typeskiltet.
local U = Config.UVLight
local on, torch = false, nil

local function aimDir()
    local r = GetGameplayCamRot(2)
    local x, z = math.rad(r.x), math.rad(r.z)
    return vec3(-math.sin(z) * math.abs(math.cos(x)), math.cos(z) * math.abs(math.cos(x)), math.sin(x))
end

local function stop()
    on = false
    local ped = PlayerPedId()
    StopAnimTask(ped, U.anim.dict, U.anim.clip, 2.0)
    if torch and DoesEntityExist(torch) then DeleteEntity(torch) end
    torch = nil
end

-- Den maskine (vores objekt-id) en entity hører til.
local function machineOf(ent)
    for id in pairs(CF.objects) do
        if CF.entity(id) == ent then return id end
    end
end

local function scanPlayer(ped)
    local target = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
    local ok, list = st.callback.await('mach1ne_counterfeit:uvScanPlayer', 500, target)
    if not ok then return CF.notify(list or locale('err_failed'), 'error') end
    CF.showScanResults(list, true)
end

local function start()
    on = true
    local ped = PlayerPedId()
    local ok, hash = pcall(st.requestModel, U.prop, 3000)
    if ok then
        torch = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
        AttachEntityToEntity(torch, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.03, -0.02, -80.0, 0.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(hash)
    end
    if pcall(st.requestAnimDict, U.anim.dict, 3000) then
        TaskPlayAnim(ped, U.anim.dict, U.anim.clip, 4.0, 4.0, -1, 49, 0.0, false, false, false)
    end
    CreateThread(function()
        local c = U.color
        while on do
            local p = PlayerPedId()
            if IsEntityDead(p) or IsPedInAnyVehicle(p, false) or CF.busy then break end
            local from = torch and DoesEntityExist(torch) and GetEntityCoords(torch) or GetPedBoneCoords(p, 57005, 0.0, 0.0, 0.0)
            local dir = aimDir()
            DrawSpotLight(from.x, from.y, from.z, dir.x, dir.y, dir.z, c[1], c[2], c[3], U.range + 4.0, 12.0, 0.0, 18.0, 25.0)

            local cam = GetGameplayCamCoord()
            local to = cam + dir * (#(cam - GetEntityCoords(p)) + U.range)
            local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 12 | 16, p, 4)
            local _, hit, _, _, ent = GetShapeTestResult(ray)
            if hit == 1 and ent ~= 0 and #(GetEntityCoords(ent) - GetEntityCoords(p)) <= U.range + 1.0 then
                if IsEntityAPed(ent) and IsPedAPlayer(ent) then
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName(locale('uv_hint_player'))
                    EndTextCommandDisplayHelp(0, false, false, -1)
                    if IsControlJustPressed(0, 38) then scanPlayer(ent) end
                else
                    local id = machineOf(ent)
                    if id then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(locale('uv_hint_machine'))
                        EndTextCommandDisplayHelp(0, false, false, -1)
                        if IsControlJustPressed(0, 38) then
                            local o = CF.objects[id]
                            if o.data.serial then CF.showSerial(id) else CF.notify(locale('uv_no_serial'), 'inform') end
                        end
                    end
                end
            end
            Wait(0)
        end
        if on then stop() end
    end)
end

exports('useUVLight', function()
    if on then return stop() end
    if not CF.isPolice() then return CF.notify(locale('err_police_item'), 'error') end
    start()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and on then stop() end
end)

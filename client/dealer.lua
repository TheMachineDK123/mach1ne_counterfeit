local D = Config.Dealer
if not D.enabled then return end

local ped

local function spawn()
    local ok, hash = pcall(st.requestModel, D.model, 5000)
    if not ok then return end
    local c = D.coords
    ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if D.scenario then TaskStartScenarioInPlace(ped, D.scenario, 0, true) end
    SetModelAsNoLongerNeeded(hash)

    Interact.entity('mach1ne_counterfeit_dealer', ped, {
        {
            id = 'mach1ne_counterfeit_dealer_shop', text = locale('dealer_talk'), icon = 'fa-solid fa-comments-dollar',
            displayDist = 8.0, interactDist = 2.5, key = 'E', keyNum = 38, onSelect = CF.openShop,
        },
    })
end

local function despawn()
    if not ped then return end
    Interact.clear('mach1ne_counterfeit_dealer')
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    ped = nil
end

CreateThread(function()
    local c = vec3(D.coords.x, D.coords.y, D.coords.z)
    while true do
        local near = #(GetEntityCoords(PlayerPedId()) - c) < 60.0
        if near and not ped then spawn() elseif not near and ped then despawn() end
        Wait(1500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then despawn() end
end)

-- Trykpressen i Union Depository (mani-unheist). Den står i boksen og kan afmonteres, mens boksen er åben.
local H = Config.Heist
if not H.enabled then return end

local obj
local UI_ID = 'mach1ne_counterfeit_heistpress'

local function despawn()
    if not obj then return end
    Interact.clear(UI_ID)
    if DoesEntityExist(obj) then DeleteEntity(obj) end
    obj = nil
end

local function take()
    if CF.busy then return end
    CF.busy = true
    local done = st.progressBar({
        duration = H.seconds * 1000, label = locale('heist_taking'), useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
    })
    ClearPedTasks(PlayerPedId())
    CF.busy = false
    if not done then return end
    local ok, err = st.callback.await('mach1ne_counterfeit:heistTake', 500)
    if not ok then return CF.notify(err or locale('err_failed'), 'error') end
    CF.notify(locale('heist_got'), 'success')
    despawn()
end

local function spawn()
    local hash = CF.resolveModel(Config.Stations.cf_press.models.empty)
    if not hash or not pcall(st.requestModel, hash, 5000) then return end
    local c = H.coords
    obj = CreateObjectNoOffset(hash, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(obj, c.w)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    local p = GetEntityCoords(obj)
    Interact.object(UI_ID, obj, {
        {
            id = UI_ID .. '_take', text = locale('heist_take'), icon = 'fa-solid fa-screwdriver-wrench',
            displayDist = 4.0, interactDist = 2.0, key = 'E', keyNum = 38,
            coords = p + vec3(0.0, 0.0, 1.35), onSelect = take,
        },
    })
end

CreateThread(function()
    local c = vec3(H.coords.x, H.coords.y, H.coords.z)
    while true do
        local show = GlobalState.m1cfHeistPress ~= 'taken' and #(GetEntityCoords(PlayerPedId()) - c) < 50.0
        if show and not obj then spawn() elseif not show and obj then despawn() end
        Wait(1500)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then despawn() end
end)

-- Kurer-opgaver fra hæleren: kør N bundter ud til en køber (NPC) inden tiden løber ud.
local C = Config.Courier
if not C.enabled then
    CF.courierInfo = function() end
    return
end

local job   -- { point, bundles, expires (GetGameTimer ms), blip }
local ped
local UI_ID = 'mach1ne_counterfeit_courier'

local function despawnPed()
    if not ped then return end
    Interact.clear(UI_ID)
    if DoesEntityExist(ped) then DeleteEntity(ped) end
    ped = nil
end

local function clear()
    if job and job.blip then RemoveBlip(job.blip) end
    despawnPed()
    job = nil
end

local function deliver()
    if CF.busy or not job then return end
    CF.busy = true
    local done = st.progressBar({
        duration = 2500, label = locale('courier_deliver', job.bundles), useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mp_common', clip = 'givetake1_a', flag = 49 },
    })
    CF.busy = false
    if not done then return end
    local ok, pay, bundles = st.callback.await('mach1ne_counterfeit:courierDeliver', 500)
    if not ok then
        CF.notify(pay or locale('err_failed'), 'error')
        if pay == locale('courier_expired') or pay == locale('courier_none') then clear() end
        return
    end
    if ped then TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true) end
    CF.notify(locale('courier_done', bundles, pay), 'success')
    SetTimeout(3000, clear)
end

local function spawnPed(p)
    local ok, hash = pcall(st.requestModel, C.pedModel, 5000)
    if not ok then return end
    ped = CreatePed(4, hash, p.x, p.y, p.z - 1.0, p.w, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_SMOKING', 0, true)
    SetModelAsNoLongerNeeded(hash)
    Interact.entity(UI_ID, ped, {
        {
            id = UI_ID .. '_deliver', text = locale('courier_deliver', job.bundles), icon = 'fa-solid fa-sack-dollar',
            displayDist = 6.0, interactDist = 2.5, key = 'E', keyNum = 38, onSelect = deliver,
        },
    })
end

-- Bruges af butikken (client/shop.lua): info om den aktive opgave, start og aflys.
function CF.courierInfo()
    if not job then return nil end
    return { bundles = job.bundles, minutes = math.max(0, math.ceil((job.expires - GetGameTimer()) / 60000)) }
end

function CF.courierCancel()
    st.callback.await('mach1ne_counterfeit:courierCancel', false)
    clear()
    return true, locale('courier_cancelled')
end

function CF.courierStart()
    local ok, idx, bundles, minutes = st.callback.await('mach1ne_counterfeit:courierStart', 500)
    if not ok then return false, idx or locale('err_failed') end
    local p = C.points[idx]
    job = { point = p, bundles = bundles, expires = GetGameTimer() + minutes * 60000 }
    job.blip = AddBlipForCoord(p.x, p.y, p.z)
    SetBlipSprite(job.blip, 500)
    SetBlipColour(job.blip, 2)
    SetBlipRoute(job.blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('courier_blip'))
    EndTextCommandSetBlipName(job.blip)
    return true, locale('courier_started', bundles, minutes)
end

CreateThread(function()
    while true do
        if job then
            if GetGameTimer() > job.expires then
                clear()
                CF.notify(locale('courier_expired'), 'error')
            else
                local p = job.point
                local near = #(GetEntityCoords(PlayerPedId()) - vec3(p.x, p.y, p.z)) < 60.0
                if near and not ped then spawnPed(p) elseif not near and ped then despawnPed() end
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clear() end
end)

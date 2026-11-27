local D = Config.Dealer
if not D.enabled then return end

local ped

local function buy(entry)
    local input = lib.inputDialog(entry.label, {
        { type = 'number', label = locale('dealer_amount', entry.price), default = 1, min = 1, max = 100, required = true },
    })
    local amount = input and tonumber(input[1])
    if not amount then return end
    local ok, res = st.callback.await('mach1ne_counterfeit:buy', 500, entry.name, amount)
    if ok then
        CF.notify(locale('dealer_bought', amount, entry.label, res), 'success')
    else
        CF.notify(res or locale('dealer_buy_failed'), 'error')
    end
end

local function sell()
    local have = exports.ox_inventory:Search('count', Config.Items.bundle) or 0
    if have < 1 then return CF.notify(locale('dealer_no_bundles'), 'error') end
    local S = D.sell
    local r = GlobalState.m1cfRate
    local each = r and r.price or math.floor(Config.Bundle.value * S.rate)
    local input = lib.inputDialog(locale('dealer_sell'), {
        { type = 'number', label = locale('dealer_sell_amount', each), default = math.min(have, S.max), min = 1, max = math.min(have, S.max), required = true },
    })
    local amount = input and tonumber(input[1])
    if not amount then return end
    local ok, res = st.callback.await('mach1ne_counterfeit:sell', 500, amount)
    if ok then
        CF.notify(locale(amount == 1 and 'dealer_sold_one' or 'dealer_sold_other', amount, res), 'success')
    else
        CF.notify(res or locale('dealer_sell_failed'), 'error')
    end
end

local function openShop()
    local options = {
        {
            title = locale('dealer_sell'),
            description = locale('dealer_sell_desc', math.floor(((GlobalState.m1cfRate or {}).rate or D.sell.rate) * 100 + 0.5)),
            icon = 'sack-dollar',
            onSelect = sell,
        },
    }
    if Config.Courier.enabled then
        options[#options + 1] = CF.courierOption()
    end
    for _, entry in ipairs(D.items) do
        options[#options + 1] = {
            title = entry.label,
            description = locale('dealer_price', entry.price),
            icon = 'cart-shopping',
            onSelect = function() buy(entry) end,
        }
    end
    lib.registerContext({ id = 'mach1ne_counterfeit_shop', title = locale('dealer_title'), options = options })
    lib.showContext('mach1ne_counterfeit_shop')
end

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
            displayDist = 8.0, interactDist = 2.5, key = 'E', keyNum = 38, onSelect = openShop,
        },
    })
    CF.spawnBoard(D.coords)
end

local function despawn()
    if not ped then return end
    Interact.clear('mach1ne_counterfeit_dealer')
    CF.removeBoard()
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

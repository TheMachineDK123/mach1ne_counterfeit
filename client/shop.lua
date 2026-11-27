-- Hælerens butik som egen NUI (html/shop.html): køb udstyr, sælg bundter, tag kurer-opgaver.
local D = Config.Dealer
local open = false

local function itemImage(name)
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)
    local file = ok and item and item.client and item.client.image or (name .. '.png')
    return 'nui://ox_inventory/web/images/' .. file
end

local function state()
    return {
        rate = GlobalState.m1cfRate,
        bundles = exports.ox_inventory:Search('count', Config.Items.bundle) or 0,
        courier = CF.courierInfo(),
    }
end

local function push()
    local d = state()
    d.action = 'update'
    SendNUIMessage(d)
end

function CF.openShop()
    if open then return end
    open = true
    local items = {}
    for _, e in ipairs(D.items) do
        items[#items + 1] = { name = e.name, label = e.label, price = e.price, image = itemImage(e.name) }
    end
    local d = state()
    d.action, d.items, d.sellMax, d.courierEnabled = 'open', items, D.sell.max, Config.Courier.enabled
    d.t = {
        title = locale('dealer_title'), sub = locale('shop_sub'), rate = locale('shop_rate'), currency = locale('dui_currency'),
        tabBuy = locale('shop_tab_buy'), tabSell = locale('shop_tab_sell'), tabJobs = locale('shop_tab_jobs'),
        buy = locale('shop_buy'), have = locale('shop_have'), payout = locale('shop_payout'), sellBtn = locale('shop_sell_btn'),
        jobTake = locale('courier_take'), jobDesc = locale('courier_desc'), jobStart = locale('shop_job_start'),
        jobActive = locale('courier_active'), jobActiveDesc = locale('courier_active_desc'), jobCancel = locale('shop_job_cancel'),
    }
    SendNUIMessage(d)
    SetNuiFocus(true, true)
    CreateThread(function()     -- kursen kan ændre sig, mens butikken er åben
        while open do
            Wait(2000)
            if open then push() end
        end
    end)
end

local function close()
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('buy', function(data, cb)
    local amount = math.floor(tonumber(data.amount) or 0)
    local ok, res = st.callback.await('mach1ne_counterfeit:buy', 500, data.name, amount)
    local label = data.name
    for _, e in ipairs(D.items) do if e.name == data.name then label = e.label end end
    cb({ ok = ok, msg = ok and locale('dealer_bought', amount, label, res) or (res or locale('dealer_buy_failed')) })
    push()
end)

RegisterNUICallback('sell', function(data, cb)
    local amount = math.floor(tonumber(data.amount) or 0)
    local ok, res = st.callback.await('mach1ne_counterfeit:sell', 500, amount)
    cb({ ok = ok, msg = ok and locale(amount == 1 and 'dealer_sold_one' or 'dealer_sold_other', amount, res)
                          or (res or locale('dealer_sell_failed')) })
    push()
end)

RegisterNUICallback('courier', function(_, cb)
    local ok, msg
    if CF.courierInfo() then
        ok, msg = CF.courierCancel()
    else
        ok, msg = CF.courierStart()
    end
    cb({ ok = ok, msg = msg })
    push()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then SetNuiFocus(false, false) end
end)

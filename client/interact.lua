-- Fælles interaktionslag: Config.Interaction = 'ox_target' eller 'st_libs'.
-- Options skrives i st_libs-format { id, text, key, keyNum, coords, displayDist, interactDist, canInteract, onSelect }
-- og oversættes til ox_target, når det er valgt.
Interact = {}

local useTarget = Config.Interaction == 'ox_target' and GetResourceState('ox_target') ~= 'missing'
if Config.Interaction == 'ox_target' and not useTarget then
    print('^3[mach1ne_counterfeit] ox_target findes ikke - bruger st_libs i stedet^0')
end
Interact.target = useTarget

local ICONS = {
    E = 'fa-solid fa-hand',
    G = 'fa-solid fa-box-archive',
    H = 'fa-solid fa-handcuffs',
}

local bound = {}   -- [id] = { kind = 'coords'|'entity', entity, names }

local function toTarget(opts)
    local out, names = {}, {}
    for i, o in ipairs(opts) do
        local name = o.id or ('opt_' .. i)
        names[#names + 1] = name
        out[#out + 1] = {
            name = name,
            label = o.text,
            icon = o.icon or ICONS[o.key] or 'fa-solid fa-circle',
            distance = (o.interactDist or 2.0) + 0.5,
            canInteract = function() return not o.canInteract or o.canInteract() end,
            onSelect = function() o.onSelect() end,
        }
    end
    return out, names
end

function Interact.clear(id)
    local b = bound[id]
    if not b then return end
    if useTarget then
        if b.entity and DoesEntityExist(b.entity) then
            exports.ox_target:removeLocalEntity(b.entity, b.names)
        end
    elseif b.kind == 'entity' then
        pcall(st.remove3DTextUIFromEntity, id)
    else
        st.remove3DTextUIFromCoords(id)
    end
    bound[id] = nil
end

-- Et objekt vi selv har spawnet (maskiner, laptop, scanner). Med ox_target bindes options til entity'en,
-- med st_libs til koordinaterne (opts[*].coords). Returnerer false, hvis entity'en ikke findes endnu.
function Interact.object(id, entity, opts)
    if useTarget and not (entity and DoesEntityExist(entity)) then return false end
    Interact.clear(id)
    if useTarget then
        local out, names = toTarget(opts)
        exports.ox_target:addLocalEntity(entity, out)
        bound[id] = { kind = 'entity', entity = entity, names = names }
    else
        st.create3DTextUIOnCoords(id, opts)
        bound[id] = { kind = 'coords' }
    end
    return true
end

-- En ped/entity uden faste koordinater (hæleren).
function Interact.entity(id, entity, opts)
    Interact.clear(id)
    if useTarget then
        local out, names = toTarget(opts)
        exports.ox_target:addLocalEntity(entity, out)
        bound[id] = { kind = 'entity', entity = entity, names = names }
    else
        for _, o in ipairs(opts) do o.entity = entity end
        st.create3DTextUIOnEntity(id, opts)
        bound[id] = { kind = 'entity', entity = entity }
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for id in pairs(bound) do Interact.clear(id) end
end)

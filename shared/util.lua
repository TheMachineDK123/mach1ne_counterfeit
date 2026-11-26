Util = {}

st.locale(Config.Locale)   -- indlæser locales/<sprog>.json (st_libs), giver global locale(key, ...)

-- timed: empty | working | done | spoiled
-- active: empty | active | done (done = kosmetisk, de skårne bunker ligger fremme lidt)
function Util.stationState(data, now)
    local def = data and Config.Stations[data.station]
    if not def then return 'empty' end
    if def.mode == 'active' then
        if data.activeUntil and now < data.activeUntil + 10 then return 'active' end
        if data.doneUntil and now < data.doneUntil then return 'done' end
        return 'empty'
    end
    if not data.batches or data.batches <= 0 then return 'empty' end
    if now < data.done then return 'working' end
    if def.spoil and now >= data.done + def.spoil.after * 60 then return 'spoiled' end
    return 'done'
end

function Util.isPoliceJob(job)
    if not job then return false end
    local min = Config.Police.jobs[job.name]
    return min ~= nil and (job.grade or 0) >= min
end

-- 'station' | 'prop' | nil
function Util.kindOf(itemName)
    if Config.Stations[itemName] then return 'station' end
    if Config.Props[itemName] then return 'prop' end
end

-- Rotér en offset (objektets lokale akser) med en heading i grader.
function Util.rotate(v, heading)
    local r = math.rad(heading or 0.0)
    local c, s = math.cos(r), math.sin(r)
    return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
end

if not MultiBot then return end

local function perfCount(counterName, delta)
    local debugApi = MultiBot and MultiBot.Debug
    if type(debugApi) ~= "table" or type(debugApi.IncrementCounter) ~= "function" or type(debugApi.IsPerfEnabled) ~= "function" or not debugApi.IsPerfEnabled() then
        return
    end

    debugApi.IncrementCounter(counterName, delta)
end

local function perfDuration(counterName, elapsed)
    local debugApi = MultiBot and MultiBot.Debug
    if type(debugApi) ~= "table" or type(debugApi.AddDuration) ~= "function" or type(debugApi.IsPerfEnabled) ~= "function" or not debugApi.IsPerfEnabled() then
        return
    end

    debugApi.AddDuration(counterName, elapsed)
end

local function runProtectedCallback(callback)
    local ok, err = pcall(callback)
    if not ok and MultiBot and type(MultiBot.dprint) == "function" then
        MultiBot.dprint("TimerAfter", err)
    end
end

-- M11 ownership: ONE OnUpdate driver for the whole addon's delayed work.
-- Reason: this client has no C_Timer, and WoW frames are never garbage collected, so the
-- old "one CreateFrame per TimerAfter" fallback leaked a permanent frame on every call —
-- including the request watchdog, which re-arms itself every 2.5s for the whole session.
-- A single shared frame with a pending list has the same semantics and a fixed cost.
-- The driver only runs while something is scheduled (it hides itself when the list empties).
local driver = CreateFrame("Frame")
local pending = {}
local pendingCount = 0
-- Timers scheduled from inside a running callback land here and are spliced in after the
-- pass. Without it, a callback calling NextTick would have its new timer fire in the SAME
-- frame (its due time is <= the time sampled at the top of the pass), which the old
-- one-frame-per-timer fallback never did — a self-rescheduling callback could spin.
local incoming = {}
local incomingCount = 0
local dispatching = false

local function now()
    return (type(GetTime) == "function" and GetTime()) or 0
end

local function onDriverUpdate(self, dt)
    perfCount("scheduler.driver.onupdate.calls")
    perfDuration("scheduler.driver.onupdate.elapsed", tonumber(dt) or 0)

    local currentTime = now()
    dispatching = true

    local index = 1
    while index <= pendingCount do
        local entry = pending[index]
        if entry.cancelled or currentTime >= entry.at then
            -- Swap-remove keeps this O(1) per entry; order is not guaranteed between timers
            -- that come due on the same frame, which no caller depends on.
            pending[index] = pending[pendingCount]
            pending[pendingCount] = nil
            pendingCount = pendingCount - 1

            if not entry.cancelled then
                perfCount("scheduler.driver.fired")
                runProtectedCallback(entry.callback)
            end
        else
            index = index + 1
        end
    end

    dispatching = false

    for i = 1, incomingCount do
        pendingCount = pendingCount + 1
        pending[pendingCount] = incoming[i]
        incoming[i] = nil
    end
    incomingCount = 0

    if pendingCount == 0 then
        self:SetScript("OnUpdate", nil)
        self:Hide()
    end
end

local function schedule(delay, callback)
    perfCount("scheduler.timerafter.calls")
    if type(callback) ~= "function" then
        return nil
    end

    local waitTime = math.max(tonumber(delay) or 0, 0)
    perfDuration("scheduler.timerafter.delay_total", waitTime)

    local entry = { at = now() + waitTime, callback = callback }

    if dispatching then
        incomingCount = incomingCount + 1
        incoming[incomingCount] = entry
        return entry
    end

    pendingCount = pendingCount + 1
    pending[pendingCount] = entry

    if pendingCount == 1 then
        driver:Show()
        driver:SetScript("OnUpdate", onDriverUpdate)
    end

    return entry
end

driver:Hide()

-- M11 scheduler contract:
-- TimerAfter/NextTick/CancelTimer are the only delay APIs that should be used outside this file.
-- Note we deliberately do NOT adopt a pre-existing _G.TimerAfter: the name is generic enough
-- that another addon could own it with different argument semantics. We define ours, then
-- publish it for backwards compatibility with older MultiBot code that called the bare global.
MultiBot.TimerAfter = schedule
_G.TimerAfter = schedule

function MultiBot.NextTick(callback)
    perfCount("scheduler.nexttick.calls")
    if type(callback) ~= "function" then
        return nil
    end

    return schedule(0, callback)
end

-- Cancel a timer using the handle returned by TimerAfter/NextTick. Safe to call on an
-- already-fired or already-cancelled handle.
function MultiBot.CancelTimer(handle)
    if type(handle) ~= "table" then
        return false
    end

    if handle.cancelled then
        return false
    end

    handle.cancelled = true
    return true
end

if not MultiBot then return end

-- RTSC ("RTS control") drives playerbots' click-to-command feature. Nothing here computes a world
-- position: the only channel for one is the master casting the ground-targeted spell 30758 (named
-- "aedm" server-side), which playerbots intercepts in SeeSpellAction. Every command below merely
-- *arms* what that next cast will do, or replays an already stored point.
-- Commands go through the bridge (RUN~RTSC / GET~RTSC) and fall back to party/raid chat only when
-- the bridge is down. See docs/rtsc.md.

local RTSC_FRAME_NAME = "RTSC"
local RTSC_SELECTOR_NAME = "Selector"
local RTSC_FRAME_X = -2
local RTSC_FRAME_Y = -34
local RTSC_SELECTOR_Y = 2
local RTSC_SELECTOR_HEIGHT = 28
local RTSC_STORAGE_ICON = "achievement_bg_winwsg_3-0"
local RTSC_SPELL_ID = 30758
local RTSC_SLOT_COUNT = 9
-- The bots only store the spot once their AI has processed the master's cast packet; re-reading
-- the server state any sooner just returns the pre-cast snapshot.
local RTSC_CAST_SETTLE = 1.5

local RTSC_GROUP_BUTTONS = {
    { tag = "@group1", x = 30, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group1.blp", tip = "tips.rtsc.group1", hidden = true, disabled = true },
    { tag = "@group2", x = 60, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group2.blp", tip = "tips.rtsc.group2", hidden = true, disabled = true },
    { tag = "@group3", x = 90, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group3.blp", tip = "tips.rtsc.group3", hidden = true, disabled = true },
    { tag = "@group4", x = 120, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group4.blp", tip = "tips.rtsc.group4", hidden = true, disabled = true },
    { tag = "@group5", x = 150, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group5.blp", tip = "tips.rtsc.group5", hidden = true, disabled = true },
}

local RTSC_ROLE_BUTTONS = {
    { tag = "@tank", x = 30, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_tank.blp", tip = "tips.rtsc.tank", disabled = true },
    { tag = "@dps", x = 60, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_dps.blp", tip = "tips.rtsc.dps", disabled = true },
    { tag = "@healer", x = 90, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_healer.blp", tip = "tips.rtsc.healer", disabled = true },
    { tag = "@melee", x = 120, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_melee.blp", tip = "tips.rtsc.melee", disabled = true },
    { tag = "@ranged", x = 150, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_ranged.blp", tip = "tips.rtsc.ranged", disabled = true },
    { tag = "@meleedps", x = 180, icon = "Interface\\AddOns\\MultiBot\\Icons\\attack_melee.blp", tip = "tips.rtsc.meleedps", disabled = true },
    { tag = "@rangeddps", x = 210, icon = "Interface\\AddOns\\MultiBot\\Icons\\attack_range.blp", tip = "tips.rtsc.rangeddps", disabled = true },
}

-- Browse swaps the whole role row for the group row, so it has to list every role button or the
-- ones it forgets stay on screen underneath the groups.
local RTSC_BROWSE_ROLES = { "@dps", "@tank", "@melee", "@healer", "@ranged", "@meleedps", "@rangeddps" }
local RTSC_BROWSE_GROUPS = { "@group1", "@group2", "@group3", "@group4", "@group5" }

-- Every tag that can take part in a selection, so the lit state can be repainted as a whole set
-- instead of button by button.
local RTSC_SELECTOR_TAGS = {}
for _, definition in ipairs(RTSC_GROUP_BUTTONS) do
    table.insert(RTSC_SELECTOR_TAGS, definition.tag)
end
for _, definition in ipairs(RTSC_ROLE_BUTTONS) do
    table.insert(RTSC_SELECTOR_TAGS, definition.tag)
end

-- Optimistic slot bookkeeping, used only while the bridge cannot tell us the real server state.
local localSlots = {}
local rtscUI = nil
-- Every button whose click only means something once the master knows the marker spell. They are
-- greyed as a block until then: leaving them bright while they are inert is the single biggest
-- source of "RTSC is buggy / does not do what it says".
local castButtons = {}
local lastReportedAt = {}
local rtscStateRetries = 0
-- A slot the master has just confirmably saved into, shown as filled until the authoritative
-- GET~RTSC lands ~1.5s later. UNIT_SPELLCAST_SUCCEEDED is proof the cast happened, so this cannot
-- light a slot for a reticle the user escaped.
local pendingSlotFill = {}
-- What this bar last armed ("save <n>" or "move"). Tracked here rather than read back from the
-- server snapshot, which is up to a refresh behind at the moment the cast lands.
local armedAction = nil
local reassertSelection
local scheduleSelectionRepair
-- The server-side selection survives a plain marker cast only if the worldserver knows the `lock`
-- sub-command (bridge + playerbots' "RTSC selection locked"). nil = not probed yet, false = an
-- older server, in which case the delayed re-assert below is the fallback.
local selectionLockSupported = nil
local selectionLockActive = false
local lockProbePending = false
-- The bot names the bridge reported as selected right after the last *deliberate* selection
-- change. That is the only exact yardstick the bar has: it knows its tags, not who they match.
local expectedSelection = nil
local captureSelection = false
local verifySelection = false
local selectionRepairs = 0

local RTSC_STATE_RETRY_LIMIT = 5
local RTSC_STATE_RETRY_DELAY = 0.75
local RTSC_REPORT_INTERVAL = 8
-- Must outlast the bots' AI tick: the cast is queued into each bot's masterIncomingPacketHandlers,
-- and PlayerbotAI::UpdateAIInternal drains HandleCommands() *before* that queue - so a re-assert
-- sent at cast time is applied first and then overwritten by the rubber-band branch, for every bot
-- that has not ticked in the client round-trip. Sitting behind RTSC_CAST_SETTLE also keeps it out
-- of the settle read's way.
local RTSC_MARQUEE_SETTLE = RTSC_CAST_SETTLE + 0.25
local RTSC_SELECTION_REPAIR_LIMIT = 2

local function L(key, fallback)
    if MultiBot and type(MultiBot.L) == "function" then
        return MultiBot.L(key, fallback)
    end

    return fallback or key
end

-- The client resolves /cast by *its own* Spell.dbc name. The server renames 30758 to "aedm", but a
-- differently patched client would leave every RTSC button silently inert, so ask the client.
local function aedmName()
    if type(GetSpellInfo) ~= "function" then
        return "aedm"
    end

    return GetSpellInfo(RTSC_SPELL_ID) or "aedm"
end

local function aedmKnown()
    if type(IsSpellKnown) ~= "function" then
        return true
    end

    return IsSpellKnown(RTSC_SPELL_ID) and true or false
end

local function addAedmMacro(button)
    button.addMacro("type1", "/cast " .. aedmName())
    -- Modified clicks carry their own (non-casting) meaning; an empty modified type stops the
    -- secure handler from falling back to the plain one and opening a reticle we do not want.
    button:SetAttribute("shift-type1", "")
    button:SetAttribute("ctrl-type1", "")
    table.insert(castButtons, button)
    return button
end

local function bridgeRtsc()
    local bridge = MultiBot.bridge
    if not bridge or not bridge.connected then
        return nil
    end

    local state = bridge.rtsc
    if type(state) ~= "table" or not state.stamp then
        return nil
    end

    return state
end

local function slotIsFilled(index)
    local key = tostring(index)

    if pendingSlotFill[key] then
        return true
    end

    local state = bridgeRtsc()

    if state then
        return state.slots[key] == true
    end

    return localSlots[key] == true
end

local function anyBotArmed(action)
    local state = bridgeRtsc()
    if not state then
        return false
    end

    for _, entry in pairs(state.bots) do
        if entry.armed == action then
            return true
        end
    end

    return false
end

local function selectedCount()
    local state = bridgeRtsc()
    return state and state.selected or 0
end

-- Who the server says is selected, by name. nil while the bridge has never answered.
local function selectedBotSet()
    local state = bridgeRtsc()
    if not state then
        return nil
    end

    local set = {}
    for name, entry in pairs(state.bots) do
        if entry.selected then
            set[name] = true
        end
    end

    return set
end

local function sameSelection(a, b)
    -- Nothing to compare against yet: never report a disagreement we cannot substantiate.
    if not a or not b then
        return true
    end

    for name in pairs(a) do
        if not b[name] then
            return false
        end
    end

    for name in pairs(b) do
        if not a[name] then
            return false
        end
    end

    return true
end

-- Tell the server the bar owns the selection, so SeeSpellAction's rubber-band branch stops
-- rewriting every bot's flag on a plain cast. Sent straight through Comm rather than sendRtsc:
-- there is no chat equivalent, and the fallback path would only print "requires the bridge".
local function applySelectionLock(active, force)
    active = active and true or false

    if not force and active == selectionLockActive then
        return false
    end

    selectionLockActive = active

    if selectionLockSupported == false then
        return false
    end

    local comm = MultiBot.Comm
    if not comm or type(comm.RunRtscCommand) ~= "function" then
        return false
    end

    if not (MultiBot.bridge and MultiBot.bridge.connected) then
        return false
    end

    lockProbePending = true

    return comm.RunRtscCommand("ALL", "", active and "lock" or "unlock") and true or false
end

local function rtscNow()
    return (type(GetTime) == "function") and GetTime() or 0
end

local function rtscMessage(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MultiBot|r " .. tostring(text or ""))
    end
end

-- One line per kind per RTSC_REPORT_INTERVAL: these fire from click handlers, and a user poking a
-- dead button repeatedly should not fill the chat frame.
local function rtscMessageThrottled(kind, text)
    local last = lastReportedAt[kind]
    local now = rtscNow()

    if last and (now - last) < RTSC_REPORT_INTERVAL then
        return false
    end

    lastReportedAt[kind] = now
    rtscMessage(text)
    return true
end

-- Sub-commands that only *arm* what the next ground cast will do (see docs/rtsc.md). They are
-- inert without the marker spell, so they are the ones worth warning about.
local function needsMarkerCast(sub)
    if sub == "select" or sub == "move" then
        return true
    end

    return string.match(sub or "", "^save%s+%d+$") ~= nil
        or string.match(sub or "", "^save selected%s+%d+$") ~= nil
end

-- Chat wording for the sub-commands that have one. `here` and `persist` are bridge-only.
local function chatSubCommand(sub)
    if sub == "enable" then
        return "rtsc"
    end

    if sub == "here" or sub == "persist" then
        return nil
    end

    return "rtsc " .. sub
end

-- Single transport for the whole feature: bridge first, party/raid chat only as a fallback.
-- `tag` is an optional playerbots chat filter ("@tank", "@group1-3"); the bridge forwards it and
-- PlayerbotAI::HandleCommand applies exactly the same filtering party chat would.
local function sendRtsc(sub, tag)
    local comm = MultiBot.Comm

    if needsMarkerCast(sub) and not aedmKnown() then
        rtscMessageThrottled("spell", L(
            "rtsc.spell.missing",
            "You have not learned the RTSC marker spell yet - right-click the RTSC button to learn it."
        ))
    end

    if comm and type(comm.RunRtscCommand) == "function" then
        local command = tag and (tag .. " " .. sub) or sub
        if comm.RunRtscCommand("ALL", "", command) then
            return true
        end
    end

    local chatCommand = chatSubCommand(sub)
    if not chatCommand then
        DEFAULT_CHAT_FRAME:AddMessage(L("rtsc.bridge.required", "This RTSC action requires the MultiBot bridge."))
        return false
    end

    return MultiBot.ActionToGroup(tag and (tag .. " " .. chatCommand) or chatCommand)
end

local function requestRtscState()
    local comm = MultiBot.Comm
    if comm and type(comm.RequestRtscState) == "function" then
        return comm.RequestRtscState("")
    end

    return false
end

-- The handshake can still be in flight when the panel opens; a single request that fails then left
-- the bar rendering empty slots from local bookkeeping, which reads as "my saved spots are gone".
-- Retry until the bridge answers, like RequestBridgeSnapshot does for the roster.
local function requestRtscStateUntilConnected()
    if requestRtscState() then
        rtscStateRetries = 0
        return true
    end

    if rtscStateRetries >= RTSC_STATE_RETRY_LIMIT or type(MultiBot.TimerAfter) ~= "function" then
        rtscStateRetries = 0
        return false
    end

    rtscStateRetries = rtscStateRetries + 1
    MultiBot.TimerAfter(RTSC_STATE_RETRY_DELAY, requestRtscStateUntilConnected)
    return false
end

local function refreshSlotButtons()
    if not rtscUI then
        return
    end

    local buttons = rtscUI.selectorFrame.buttons

    for index = 1, RTSC_SLOT_COUNT do
        local macroButton = buttons["MACRO" .. index]
        local slotButton = buttons["RTSC" .. index]

        if macroButton and slotButton then
            if slotIsFilled(index) then
                macroButton.doHide()
                slotButton.doShow()
            else
                slotButton.doHide()
                macroButton.doShow()
            end
        end
    end
end

-- Fade every button that only does something once a ground cast follows it. Alpha is used rather
-- than setEnable/setDisable on purpose: the slot buttons already use desaturation to mean
-- "empty vs filled", and that meaning must survive.
local function refreshCastAvailability()
    local available = aedmKnown()
    local rootButton = rtscUI and rtscUI.rootButton

    for _, button in ipairs(castButtons) do
        if button ~= rootButton and button.SetAlpha then
            button:SetAlpha(available and 1 or 0.35)
        end
    end
end

local function refreshModeButtons()
    if not rtscUI then
        return
    end

    local moveButton = rtscUI.selectorFrame.buttons["Move"]
    if moveButton then
        if anyBotArmed("move") then
            moveButton.setEnable()
        else
            moveButton.setDisable()
        end
    end

    local hereButton = rtscUI.selectorFrame.buttons["Here"]
    if hereButton then
        -- "here" seeds the click position server-side; there is no chat command that can do it.
        if MultiBot.bridge and MultiBot.bridge.connected then
            hereButton.doShow()
        else
            hereButton.doHide()
        end
    end

    refreshCastAvailability()

    -- Grey the root button until the master actually knows the marker spell; every cast button is
    -- inert until then, and right-clicking the root is what trains it.
    local rootButton = rtscUI.rootButton
    if rootButton then
        if aedmKnown() then
            rootButton.setEnable(false)
        else
            rootButton.setDisable(false)
        end

        -- The bots' selection lives server-side, so report it here rather than tinting unit
        -- buttons (their state is the online flag and must not be repurposed).
        local tip = rtscUI.rootTip

        if not aedmKnown() then
            tip = tip .. "\n\n|cffff2020" .. L(
                "rtsc.spell.missing",
                "You have not learned the RTSC marker spell yet - right-click the RTSC button to learn it."
            ) .. "|r"
        end

        -- The selection is a server-side per-bot flag, so the only honest indicator is the
        -- count the bridge reports. It rides on the root button as a badge, because the point
        -- of this pass is that the selection must stop being invisible.
        local badge = ""
        if bridgeRtsc() then
            local count = selectedCount()
            tip = tip .. "\n\n" ..
                string.format(L("rtsc.selected.count", "Bots currently selected: %d"), count)
            if count > 0 then
                badge = tostring(count)
            end
        end

        if rootButton.amount then
            rootButton.amount:SetText(badge)
        else
            rootButton.setAmount(badge)
        end
        if rootButton.amount and rootButton.amount.SetTextColor then
            rootButton.amount:SetTextColor(0.4, 1, 0.4)
        end

        -- A half-built multi-role selection was previously invisible unless you remembered which
        -- buttons you had right-clicked.
        local pending = rtscUI.selectorFrame and rtscUI.selectorFrame.selector or ""
        if pending ~= "" then
            tip = tip .. "\n" .. string.format(L("rtsc.selector.pending", "Pending selection: %s"), pending)
        end

        tip = tip .. "\n|cff999999" .. L("rtsc.help.hint", "Type /mb help rtsc for the full control list.") .. "|r"

        rootButton.tip = tip
    end
end

local function refreshRtscUI()
    refreshSlotButtons()
    refreshModeButtons()
end

-- Called by MultiBotComm once a GET~RTSC stream completes.
MultiBot.OnBridgeRtscState = function()
    -- The server has spoken; drop the optimistic fills so a save that never landed goes back to
    -- showing empty instead of lying.
    pendingSlotFill = {}

    if captureSelection then
        -- A deliberate selection change has settled: record who it actually reached, so a later
        -- cast can be checked against it rather than against a tag list the client cannot resolve.
        captureSelection = false
        verifySelection = false
        selectionRepairs = 0
        expectedSelection = selectedBotSet()
    elseif verifySelection then
        verifySelection = false

        if sameSelection(expectedSelection, selectedBotSet()) then
            selectionRepairs = 0
        elseif selectionRepairs < RTSC_SELECTION_REPAIR_LIMIT then
            -- The re-assert lost the race with the bots' packet queue after all. Repeat it; the
            -- bots that already ticked make this converge instead of oscillating.
            selectionRepairs = selectionRepairs + 1
            if reassertSelection then
                reassertSelection()
            end
        end
    end

    refreshRtscUI()
end

-- Called by MultiBotComm for every RTSC_ACK. The bridge has always reported how many bots ran the
-- command; saying nothing when that is zero is what made RTSC look broken rather than unaddressed.
MultiBot.OnRtscCommandApplied = function(command, executed)
    local ran = (tonumber(executed) or 0) > 0
    local sub = tostring(command or "")

    if sub == "lock" or sub == "unlock" then
        -- The lock is the deterministic fix, but it only exists on a worldserver carrying both
        -- halves of it (the bridge sub-command and playerbots' "RTSC selection locked"). With
        -- playerbots too old the flag does not exist and `executed` is 0, so stop asking and fall
        -- back to re-asserting. Never reported: it is a probe, not a click.
        lockProbePending = false
        selectionLockSupported = ran
        return
    end

    if sub == "" then
        -- The bridge echoes the *normalized* command, and normalizing rejects anything it does not
        -- know - so an empty one means "this bridge never heard of what you sent". If a lock probe
        -- is outstanding that is exactly what it rejected. Reporting "no bot ran ''" either way
        -- would be noise: nothing was asked of any bot.
        if lockProbePending then
            lockProbePending = false
            selectionLockSupported = false
        end

        return
    end

    if ran then
        return
    end

    local kind = "none:" .. (string.match(tostring(command or ""), "([%a]+)") or "rtsc")
    rtscMessageThrottled(kind, string.format(
        L("rtsc.applied.none", "RTSC: no bot ran '%s'. Bots must be grouped with you and in range."),
        tostring(command or "")
    ))
end

local function refreshRtscStateSoon(persist)
    if type(MultiBot.TimerAfter) ~= "function" then
        requestRtscState()
        return
    end

    MultiBot.TimerAfter(RTSC_CAST_SETTLE, function()
        if persist then
            local comm = MultiBot.Comm
            if comm and type(comm.RunRtscCommand) == "function" then
                comm.RunRtscCommand("ALL", "", "persist")
            end
        end

        requestRtscState()
    end)
end

-- The armed `save <n>` only lands when the bots process the master's cast, and context writes stay
-- in memory until the bridge flushes them - so wait for the cast, ask the bridge to persist, then
-- re-read the real state instead of guessing.
-- The marker spell has no spell visual, no sound and no combat-log line, so a cast that did
-- something and a cast that did nothing looked identical. Say what it just did.
local function reportAedmCast(armed)
    local state = bridgeRtsc()
    if not state then
        rtscMessage(L("rtsc.cast.placed", "RTSC: marker placed."))
        return
    end

    if not armed then
        for _, entry in pairs(state.bots) do
            if entry.armed and entry.armed ~= "" then
                armed = entry.armed
                break
            end
        end
    end

    if armed then
        local slot = string.match(armed, "^save%s+(%S+)$") or string.match(armed, "^save selected%s+(%S+)$")
        if slot then
            rtscMessage(string.format(L("rtsc.cast.saved", "RTSC: marker placed - stored as spot %s."), slot))
            return
        end

        if armed == "move" then
            rtscMessage(L("rtsc.cast.move", "RTSC: marker placed - move mode is armed, so the selection follows every cast."))
            return
        end
    end

    local count = selectedCount()
    if count > 0 then
        rtscMessage(string.format(L("rtsc.cast.sent", "RTSC: marker placed - %d selected bot(s) sent there."), count))
        return
    end

    rtscMessage(L("rtsc.cast.marquee", "RTSC: marker placed - nothing was selected, so bots within 10 yards of it are now selected."))
end

local function onAedmCast()
    local armed = armedAction

    reportAedmCast(armed)

    local savedSlot = armed and string.match(armed, "^save%s+(%S+)$") or nil
    if savedSlot then
        -- Show it immediately. Playerbots consumes the armed save on this cast (it resets
        -- "RTSC next spell action"), so the bar must stop advertising it as armed too.
        pendingSlotFill[savedSlot] = true
        armedAction = nil
        refreshSlotButtons()
    elseif armed ~= "move" then
        -- A plain send. With the lock in force the server left every flag alone and there is
        -- nothing to repair. Without it, SeeSpellAction's marquee branch has just overwritten
        -- every bot's selected flag with "was within 10 yards of the click" - dropping the bots
        -- that were sent and tagging the bystanders standing at the destination, who then get
        -- dragged along by the next cast. Repair it, but only once the marquee has certainly
        -- landed: see RTSC_MARQUEE_SETTLE.
        if selectionLockSupported ~= true and scheduleSelectionRepair then
            scheduleSelectionRepair()
        end
    end

    refreshRtscStateSoon(true)
end

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castWatcher:RegisterEvent("SPELLS_CHANGED")
castWatcher:SetScript("OnEvent", function(_, eventName, unit, spellName, _, _, spellId)
    if eventName == "SPELLS_CHANGED" then
        refreshModeButtons()
        return
    end

    if unit ~= "player" then
        return
    end

    if spellName ~= aedmName() and tonumber(spellId) ~= RTSC_SPELL_ID then
        return
    end

    onAedmCast()
end)

-- SELECTION -------------------------------------------------------------------------------------
--
-- There is one selection, and it lives on the server as a per-bot "RTSC selected" flag. Two things
-- about it are invisible from the bar and caused most of the "sometimes it moves the tanks,
-- sometimes the whole raid, sometimes half of it" confusion:
--
--   1. `rtsc select` is purely ADDITIVE - RtscAction only ever sets the flag true, never false for
--      anyone else. Clicking Tanks then DPS left both selected.
--   2. A plain ground cast REPLACES every bot's flag with "was within 10 yards of the click"
--      (SeeSpellAction's marquee branch). So one cast silently discards a role selection and
--      leaves a proximity blob behind, which the next role click then added to.
--
-- The bar therefore drives it explicitly: left-click is "only these" and always clears the server
-- selection first, right-click is "add these". The lit buttons are what was asked for; the count
-- badge on the root button is what the server actually reports.
local function selectionTags(frame)
    return MultiBot.doSplit(frame and frame.selector or "", " ")
end

local function paintSelection(frame)
    local active = {}
    for _, tag in ipairs(selectionTags(frame)) do
        active[tag] = true
    end

    for _, tag in ipairs(RTSC_SELECTOR_TAGS) do
        local button = frame.buttons[tag]
        if button then
            if active[tag] then
                button.setEnable()
            else
                button.setDisable()
            end
        end
    end

    -- Every selection mutation funnels through here, so this is the one place the lock has to
    -- track. An empty selector means the bar is not driving a selection, and the rubber-band
    -- select is then exactly what a cast should do - so the lock comes off.
    applySelectionLock(frame.selector ~= "")

    refreshModeButtons()
end

-- The server applies the flag a moment after the command lands; re-read so the count badge and
-- tooltip show the truth rather than what we assumed. `capture` marks the answer as the new
-- yardstick - pass it for a deliberate selection change, not for a repair.
local function refreshSelectionSoon(capture)
    if capture then
        captureSelection = true
    end

    if type(MultiBot.TimerAfter) ~= "function" then
        requestRtscState()
        return
    end

    MultiBot.TimerAfter(0.4, function()
        requestRtscState()
    end)
end

local function clearSelection(frame, sendCancel)
    if sendCancel then
        sendRtsc("cancel")
        -- `cancel` also resets "RTSC next spell action" server-side.
        armedAction = nil
        refreshSelectionSoon(true)
    end

    frame.selector = ""
    paintSelection(frame)
end

local function replaceSelection(frame, tag)
    -- `cancel` first: without it the new tag piles on top of whatever was already selected. It
    -- disarms any pending save/move too, which is why the bar drops its armed state here.
    sendRtsc("cancel")
    sendRtsc("select", tag)
    armedAction = nil

    frame.selector = tag
    paintSelection(frame)
    refreshSelectionSoon(true)
end

local function removeFromSelection(frame, tag)
    local kept = {}
    for _, existing in ipairs(selectionTags(frame)) do
        if existing ~= tag then
            table.insert(kept, existing)
        end
    end

    -- `cancel` takes a chat filter, so a single tag can be dropped without disturbing the rest.
    sendRtsc("cancel", tag)
    armedAction = nil

    frame.selector = table.concat(kept, " ")
    paintSelection(frame)
    refreshSelectionSoon(true)
end

-- Re-apply the bar's selection to the server, used after a plain send-cast has clobbered it on a
-- worldserver that does not know `lock`. Always followed by a verification read.
reassertSelection = function()
    local frame = rtscUI and rtscUI.selectorFrame
    if not frame then
        return
    end

    local tags = selectionTags(frame)
    if #tags == 0 then
        -- Nothing explicit selected: the marquee is the intended behaviour, leave it alone.
        return
    end

    sendRtsc("cancel")
    for _, tag in ipairs(tags) do
        sendRtsc("select", tag)
    end

    verifySelection = true
    refreshSelectionSoon(false)
end

-- Deliberately not immediate: a command sent now is applied *before* the queued cast packet on
-- every bot that has not ticked yet, and is then overwritten by it (see RTSC_MARQUEE_SETTLE).
scheduleSelectionRepair = function()
    local frame = rtscUI and rtscUI.selectorFrame
    if not frame or frame.selector == "" then
        -- Nothing explicit selected: the marquee is the intended behaviour here.
        return
    end

    if type(MultiBot.TimerAfter) ~= "function" then
        reassertSelection()
        return
    end

    MultiBot.TimerAfter(RTSC_MARQUEE_SETTLE, function()
        reassertSelection()
    end)
end

-- Right-click toggles: add the tag, or drop it if it is already part of the selection.
local function toggleSelection(frame, tag)
    for _, existing in ipairs(selectionTags(frame)) do
        if existing == tag then
            return removeFromSelection(frame, tag)
        end
    end

    sendRtsc("select", tag)

    frame.selector = (frame.selector == "") and tag or (frame.selector .. " " .. tag)
    paintSelection(frame)
    refreshSelectionSoon(true)
end

local function createSelectorButton(selectorFrame, definition)
    local button = addAedmMacro(selectorFrame
        .addButton(definition.tag, definition.x, 0, definition.icon, MultiBot.L(definition.tip), "SecureActionButtonTemplate"))

    if definition.hidden then
        button.doHide()
    end

    if definition.disabled then
        button.setDisable()
    end

    -- Right = add this role/group to the selection, or drop it if it is already in.
    button.doRight = function(owner)
        toggleSelection(owner.parent, definition.tag)
    end

    -- Left = select ONLY this role/group (and open the reticle, since the button casts).
    button.doLeft = function(owner)
        replaceSelection(owner.parent, definition.tag)
    end

    return button
end

-- The nine spot buttons share one icon and one position each, so without a number on the face
-- there is no way to tell slot 3 from slot 7 - the empty/filled desaturation is the only other
-- cue. Grey digits for an empty slot, gold for a stored one.
local function labelStorageButton(button, index, filled)
    button.setAmount(tostring(index))

    if button.amount and button.amount.SetTextColor then
        if filled then
            button.amount:SetTextColor(1, 0.82, 0)
        else
            button.amount:SetTextColor(0.6, 0.6, 0.6)
        end
    end
end

local function createStoragePair(selectorFrame, index)
    local macroName = "MACRO" .. index
    local rtscName = "RTSC" .. index
    local x = -304 + 30 * index

    local macroButton = addAedmMacro(selectorFrame
        .addButton(macroName, x, 0, RTSC_STORAGE_ICON, L("tips.rtsc.macro"), "SecureActionButtonTemplate"))
        .setDisable()

    labelStorageButton(macroButton, index, false)

    macroButton.doLeft = function(button)
        -- Shift stores where the bots are standing *right now* - each bot records its own spot, so
        -- a later "go" restores the formation instead of stacking everyone on one point.
        if IsShiftKeyDown() then
            -- Stores immediately, no cast involved, so the slot can be shown as filled right away.
            button.parent.doExecute(button, "save here " .. index)
            pendingSlotFill[tostring(index)] = true
            refreshSlotButtons()
            refreshRtscStateSoon(false)
            return
        end

        -- Scoped by tag through doExecute, exactly like go/last/move.
        --
        -- This used to send an untagged `save selected <n>` whenever anything was selected, which
        -- left the scoping to the server's per-bot "RTSC selected" flag - the same flag a plain
        -- marker cast overwrites with "was within 10 yards of the click". So after any send, the
        -- flag was usually empty, the save landed on nobody, and the slot never lit up until a bot
        -- happened to be selected again. A chat filter (`@tank save 4`) reaches exactly the bots
        -- the bar says are selected, whatever the flag currently holds.
        button.parent.doExecute(button, "save " .. index)
        armedAction = "save " .. index

        -- Without the bridge there is no way to learn whether the cast ever happened, so keep the
        -- old optimistic flip; with it, the cast watcher fills the slot once the cast is confirmed.
        if not bridgeRtsc() then
            localSlots[tostring(index)] = true
            refreshSlotButtons()
        end
    end

    local slotButton = selectorFrame
        .addButton(rtscName, x, 0, RTSC_STORAGE_ICON, L("tips.rtsc.spot"), "SecureActionButtonTemplate")
        .doHide()

    labelStorageButton(slotButton, index, true)

    slotButton.doRight = function()
        sendRtsc("unsave " .. index)
        localSlots[tostring(index)] = nil
        pendingSlotFill[tostring(index)] = nil

        if bridgeRtsc() then
            requestRtscState()
        else
            refreshSlotButtons()
        end
    end

    slotButton.doLeft = function(button)
        -- Ctrl previews the saved point: playerbots summons a 2s marker creature there.
        if IsControlKeyDown() then
            button.parent.doExecute(button, "show " .. index)
            return
        end

        button.parent.doExecute(button, "go " .. index)
    end

    return slotButton
end

local function bindSelectorLogic(selectorFrame)
    selectorFrame.selector = ""

    selectorFrame.doExecute = function(button, action)
        if button.parent.selector == "" then
            return sendRtsc(action)
        end

        local selected = MultiBot.doSplit(button.parent.selector, " ")
        local others = {}
        local groupIndexes = {}

        for _, tag in ipairs(selected) do
            local groupIndex = string.match(tag, "^@group(%d+)$")
            if groupIndex then
                table.insert(groupIndexes, tonumber(groupIndex))
            else
                table.insert(others, tag)
            end
        end

        for _, tag in ipairs(others) do
            sendRtsc(action, tag)
        end

        if #groupIndexes > 0 then
            table.sort(groupIndexes)

            local parts = {}
            local index = 1
            while index <= #groupIndexes do
                local rangeStart = groupIndexes[index]
                local endIndex = index

                while endIndex + 1 <= #groupIndexes and groupIndexes[endIndex + 1] == groupIndexes[endIndex] + 1 do
                    endIndex = endIndex + 1
                end

                local rangeEnd = groupIndexes[endIndex]
                table.insert(parts, rangeStart == rangeEnd and tostring(rangeStart) or (tostring(rangeStart) .. "-" .. tostring(rangeEnd)))
                index = endIndex + 1
            end

            sendRtsc(action, "@group" .. table.concat(parts, ","))
        end

        -- The selection deliberately survives the action: sending the same group to spot 1 and
        -- then spot 2 should not silently need re-selecting, and a selection that clears itself
        -- behind your back was half of what made this bar feel random.
        refreshModeButtons()
    end

end

local function createBrowseButton(selectorFrame)
    local browseButton = selectorFrame.addButton("Browse", 270, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc_browse.blp", MultiBot.L("tips.rtsc.browse"))

    -- `state` belongs to the engine (it drives setEnable/setDisable and the desaturation), so the
    -- "which row am I showing" flag gets its own field. Writing state raw meant the button's look
    -- and its logical state permanently disagreed, and you could not see which row you were on.
    browseButton.showingGroups = false
    browseButton.setDisable()

    browseButton.doRight = function(button)
        clearSelection(button.parent, true)
    end

    browseButton.doLeft = function(button)
        local frame = button.parent
        local showGroups = not button.showingGroups

        for _, tag in ipairs(RTSC_BROWSE_ROLES) do
            if frame.buttons[tag] then
                if showGroups then
                    frame.buttons[tag].doHide()
                else
                    frame.buttons[tag].doShow()
                end
            end
        end

        for _, tag in ipairs(RTSC_BROWSE_GROUPS) do
            if frame.buttons[tag] then
                if showGroups then
                    frame.buttons[tag].doShow()
                else
                    frame.buttons[tag].doHide()
                end
            end
        end

        button.showingGroups = showGroups
        if showGroups then
            button.setEnable()
        else
            button.setDisable()
        end
    end

    return browseButton
end

-- The row runs saved spots -> selection -> actions with nothing to say where one block ends. Two
-- hairlines make the 22 buttons readable as three groups.
local function createSeparator(selectorFrame, x)
    local separator = selectorFrame:CreateTexture(nil, "OVERLAY")
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(1, 1, 1, 0.25)
    separator:SetWidth(1)
    separator:SetHeight(24)
    separator:SetPoint("BOTTOMRIGHT", selectorFrame, "BOTTOMRIGHT", x, 2)
    return separator
end

-- Move / Last / Here sit right of Browse so the existing -274..270 layout is untouched.
local function createModeButtons(selectorFrame)
    local moveButton = addAedmMacro(selectorFrame
        .addButton("Move", 300, 0, "ability_rogue_sprint",
            L("tips.rtsc.move", "RTSC Move Mode\n\nLeft-click to arm move mode and place a marker: from then on every AEDM cast moves your selection, with no further commands.\nRight-click to disarm."),
            "SecureActionButtonTemplate"))
        .setDisable()

    -- Scoped by the current selection, like Last and the spot slots. It used to always send
    -- untagged, so arming Move with only the tanks selected quietly armed the whole raid.
    moveButton.doLeft = function(button)
        button.parent.doExecute(button, "move")
        -- Persistent until cancel/reset, and it makes casts skip the marquee branch entirely.
        armedAction = "move"
    end

    moveButton.doRight = function(button)
        clearSelection(button.parent, true)
    end

    local lastButton = selectorFrame
        .addButton("Last", 330, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc_target.blp",
            L("tips.rtsc.last", "Last Marker\n\nSend the selection back to the most recently marked spot, in formation.\nRight-click to re-read the saved spots from the server."))

    lastButton.doLeft = function(button)
        button.parent.doExecute(button, "last")
    end

    lastButton.doRight = function()
        -- Chatless equivalent of playerbots' `rtsc show`, which answers with a whisper per bot.
        requestRtscState()
    end

    local hereButton = selectorFrame
        .addButton("Here", 360, 0, "spell_arcane_blink",
            L("tips.rtsc.here", "Regroup On Me\n\nSend everyone to your exact position, in formation - no marker cast needed.\nRequires the MultiBot bridge."))

    -- "here" seeds the click position natively, before playerbots' chat filters run, so it cannot
    -- be scoped with an @tag - it always applies to the whole visible pool.
    hereButton.doLeft = function(button)
        sendRtsc("here")
        clearSelection(button.parent, false)
    end

    return moveButton, lastButton, hereButton
end

-- Opening the bar trains the master's aedm spell (playerbots' bare `rtsc`) and pulls the real
-- server state so the slots render from it instead of from stale UI bookkeeping.
function MultiBot.RTSCOnPanelOpen()
    sendRtsc("enable")
    rtscStateRetries = 0
    requestRtscStateUntilConnected()

    -- "RTSC selection locked" is not persisted, so a bot that relogged since the last selection
    -- change defaults to unlocked. Re-send rather than trusting the cached value; this doubles as
    -- the probe that tells the bar whether the server knows the sub-command at all.
    local frame = rtscUI and rtscUI.selectorFrame
    applySelectionLock(frame and frame.selector ~= "", true)

    refreshRtscUI()
end

-- Closing must NOT send `rtsc reset`: that wipes every saved location on every bot and untrains the
-- master's spell. `cancel` only drops the selection and any armed action.
function MultiBot.RTSCOnPanelClose()
    -- ...and since it does drop the selection, the bar has to drop its lit tags with it. Leaving
    -- them lit meant re-opening showed a selection no bot was part of any more, and the lock stayed
    -- on for a selection that no longer existed.
    local frame = rtscUI and rtscUI.selectorFrame
    if frame then
        clearSelection(frame, true)
        return
    end

    sendRtsc("cancel")
end

function MultiBot.InitializeRTSCUI(tMultiBar)
    if not tMultiBar or not tMultiBar.addFrame then
        return nil
    end

    local rtscFrame = tMultiBar.addFrame(RTSC_FRAME_NAME, RTSC_FRAME_X, RTSC_FRAME_Y, 32).doHide()

    local rootButton = addAedmMacro(rtscFrame
        .addButton("RTSC", 0, 0, "ability_hunter_markedfordeath", MultiBot.L("tips.rtsc.master"), "SecureActionButtonTemplate"))

    rootButton.doRight = function(button)
        -- Shift is the only way to reach playerbots' destructive `rtsc reset` (drops every saved
        -- location on every bot and removes the master's aedm spell).
        if IsShiftKeyDown() then
            sendRtsc("reset")
            armedAction = nil
            pendingSlotFill = {}
            for index = 1, RTSC_SLOT_COUNT do
                localSlots[tostring(index)] = nil
            end

            clearSelection(button.parent.frames[RTSC_SELECTOR_NAME], false)
            requestRtscState()
            refreshRtscUI()
            return
        end

        sendRtsc("enable")
        MultiBot.ActionToGroup("co +rtsc,+guard,?")
        MultiBot.ActionToGroup("nc +rtsc,+guard,?")
    end

    -- Left = just open the reticle. This is the "send" button: the click on the ground moves
    -- every currently selected bot there (SeeSpellAction's marquee branch). It deliberately does
    -- NOT touch the selection - clearing it here left a selection built from right-clicks with no
    -- way to act on it, which is why adding groups "sometimes didn't send them".
    rootButton.doLeft = function()
        -- The lock is per bot and not persisted, so a bot summoned or relogged since the last
        -- selection change would still run the rubber-band branch on this cast and pull itself
        -- into the selection. Re-assert it now: the reticle still needs a ground click, which is
        -- far longer than the round-trip.
        local frame = rtscUI and rtscUI.selectorFrame
        applySelectionLock(frame and frame.selector ~= "", true)
    end

    local selectorFrame = rtscFrame.addFrame(RTSC_SELECTOR_NAME, 0, RTSC_SELECTOR_Y, RTSC_SELECTOR_HEIGHT)
    bindSelectorLogic(selectorFrame)

    for index = RTSC_SLOT_COUNT, 1, -1 do
        createStoragePair(selectorFrame, index)
    end

    for _, definition in ipairs(RTSC_GROUP_BUTTONS) do
        createSelectorButton(selectorFrame, definition)
    end

    for _, definition in ipairs(RTSC_ROLE_BUTTONS) do
        createSelectorButton(selectorFrame, definition)
    end

    local allButton = addAedmMacro(selectorFrame
        .addButton("@all", 240, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc.blp", MultiBot.L("tips.rtsc.all"), "SecureActionButtonTemplate"))

    -- Untagged `select` already reaches every bot, so there is nothing to clear first; dropping
    -- the role scoping is what makes the bar agree that "all" is now the scope. Left and right
    -- send the same command on purpose: only left carries the secure /cast, so left = "select
    -- everyone and mark a spot now", right = "select everyone". Deselect-all lives on Browse's
    -- right-click (`cancel`).
    local function selectEveryone(frame)
        sendRtsc("select")
        frame.selector = ""
        paintSelection(frame)
        refreshSelectionSoon(true)
    end

    allButton.doLeft = function(button)
        selectEveryone(button.parent)
    end

    allButton.doRight = function(button)
        selectEveryone(button.parent)
    end

    local browseButton = createBrowseButton(selectorFrame)
    local moveButton, lastButton, hereButton = createModeButtons(selectorFrame)

    -- Buttons are 28 wide on a 30 pitch, so the only real gap is between the last spot slot
    -- (right edge -34) and the first selector icon (left edge +2); the second hairline goes in the
    -- 2px gap between Browse (270) and Move (300).
    createSeparator(selectorFrame, -16)
    createSeparator(selectorFrame, 271)

    rtscUI = {
        frame = rtscFrame,
        selectorFrame = selectorFrame,
        rootButton = rootButton,
        rootTip = rootButton.tip or "",
        browseButton = browseButton,
        allButton = allButton,
        moveButton = moveButton,
        lastButton = lastButton,
        hereButton = hereButton,
    }

    refreshRtscUI()

    return rtscUI
end

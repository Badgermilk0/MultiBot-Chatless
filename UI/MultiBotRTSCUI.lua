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

-- A raid holds eight subgroups, and playerbots' `@group<n>` filter reads `GetSubGroup() + 1` with
-- no upper bound (SubGroupChatFilter), so all eight have always been addressable - the bar just
-- never drew the last three. `Icons/` only ships art for 1-5, so 6-8 reuse the generic RTSC icon
-- and carry their number on the face (`label`), the way the nine location slots do. Dropping
-- matching `rtsc_group<n>.blp` files in and clearing `label` is all it takes to give them art.
local RTSC_GROUP_BUTTONS = {
    { tag = "@group1", x = 30, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group1.blp", tip = "tips.rtsc.group1", hidden = true, disabled = true },
    { tag = "@group2", x = 60, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group2.blp", tip = "tips.rtsc.group2", hidden = true, disabled = true },
    { tag = "@group3", x = 90, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group3.blp", tip = "tips.rtsc.group3", hidden = true, disabled = true },
    { tag = "@group4", x = 120, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group4.blp", tip = "tips.rtsc.group4", hidden = true, disabled = true },
    { tag = "@group5", x = 150, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc_group5.blp", tip = "tips.rtsc.group5", hidden = true, disabled = true },
    { tag = "@group6", x = 180, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc.blp", tip = "tips.rtsc.group6", hidden = true, disabled = true, label = "6" },
    { tag = "@group7", x = 210, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc.blp", tip = "tips.rtsc.group7", hidden = true, disabled = true, label = "7" },
    { tag = "@group8", x = 240, icon = "Interface\\AddOns\\MultiBot\\Icons\\rtsc.blp", tip = "tips.rtsc.group8", hidden = true, disabled = true, label = "8" },
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
local RTSC_BROWSE_GROUPS = {
    "@group1", "@group2", "@group3", "@group4", "@group5", "@group6", "@group7", "@group8",
}

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
-- Slots the master has just confirmably saved into / emptied, shown that way until the
-- authoritative GET~RTSC has caught up. A cast event is proof the cast happened, so these cannot
-- light a slot for a reticle the user escaped. Each entry stores *when* it was made: `save`,
-- `save here` and `unsave` all reach the bots through their command queue, so a state read that
-- answers before they applied it still describes the old world, and repainting from it is what
-- made a stored or deleted spot look like it had not registered until some later click.
local pendingSlotFill = {}
local pendingSlotClear = {}
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
-- Force move. An RTSC move is one spline stamped MOVEMENT_NORMAL and nothing re-issues it, so the
-- first combat chase (MOVEMENT_COMBAT) steals the bot on the next AI tick - the "they abort as soon
-- as something aggroes" behaviour. While the flag is set the server remembers the destination and
-- moves at MOVEMENT_FORCED until the bot arrives. Detected, not configured: an older worldserver
-- has no such value (0 of N bots applied it) or rejects the sub-command outright (empty command
-- echo). "0 of 0" is *not* evidence - with no bots online nothing was asked of anyone, and reading
-- that as "unsupported" is what left the button dead for the session after the bar was opened
-- without bots, lighting on click while sending nothing.
local forceSupported = nil
local forceModeActive = false
local forceProbePending = false
-- Set when the last force/unforce ack came back with no bots to apply it to. The poll re-sends
-- while it is true, so summoning bots with the bar already open still ends up forced.
local forceNeedsBots = false
-- The bot names the bridge reported as selected right after the last *deliberate* selection
-- change. That is the only exact yardstick the bar has: it knows its tags, not who they match.
local expectedSelection = nil
local captureSelection = false
local verifySelection = false
local selectionRepairs = 0
local rtscPollArmed = false

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
-- Outlives the post-action read by a margin: that read is the one most likely to be a hair early.
local RTSC_PENDING_TTL = RTSC_CAST_SETTLE + 1
-- Backstop read while the bar is open. Everything else here repaints from a click or a cast, so
-- state the master never asked for - the rubber-band selection a plain cast performs, a command
-- that landed late, a bot that relogged - had no way onto the screen until the next click.
local RTSC_POLL_INTERVAL = 5

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

    if pendingSlotClear[key] then
        return false
    end

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
local function applySelectionLock(active, force, silent)
    active = active and true or false

    if not force and active == selectionLockActive then
        return false
    end

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

    if not comm.RunRtscCommand("ALL", "", active and "lock" or "unlock", silent) then
        return false
    end

    -- Only once the command is actually on the wire: recording the mode for a send that never
    -- happened is what left the bar's idea of the server and the server permanently out of step.
    selectionLockActive = active
    lockProbePending = true
    return true
end

-- Turn the per-bot force flag on or off for the whole visible pool. Like the lock it is applied
-- natively, before playerbots' chat filter runs, so it cannot be `@tag`-scoped - which is right:
-- Force is a mode, and *who* moves is still decided by the tag on the move command. `unforce` also
-- clears any destination in flight server-side, so it doubles as the abort.
local function applyForceMode(active, force, silent)
    active = active and true or false

    if not force and active == forceModeActive then
        return false
    end

    if forceSupported == false then
        return false
    end

    local comm = MultiBot.Comm
    if not comm or type(comm.RunRtscCommand) ~= "function" then
        return false
    end

    if not (MultiBot.bridge and MultiBot.bridge.connected) then
        return false
    end

    if not comm.RunRtscCommand("ALL", "", active and "force" or "unforce", silent) then
        return false
    end

    -- The flag is set only for a command that really left: lighting the button first meant a
    -- toggle the server never heard about still looked armed, and every move went out unforced.
    forceModeActive = active
    forceProbePending = true
    return true
end

local function rtscNow()
    return (type(GetTime) == "function") and GetTime() or 0
end

-- Optimistic paint for a slot the bar just changed, held for RTSC_PENDING_TTL so the state read
-- that follows the action (which can still answer from before the bots applied it) cannot flip it
-- back. The next read after that reconciles it with the truth.
local function markSlotPending(index, filled)
    local key = tostring(index)
    local now = rtscNow()

    if filled then
        pendingSlotFill[key] = now
        pendingSlotClear[key] = nil
    else
        pendingSlotClear[key] = now
        pendingSlotFill[key] = nil
    end
end

local function expirePendingSlots()
    local now = rtscNow()

    for key, stamp in pairs(pendingSlotFill) do
        if (now - (stamp or 0)) >= RTSC_PENDING_TTL then
            pendingSlotFill[key] = nil
        end
    end

    for key, stamp in pairs(pendingSlotClear) do
        if (now - (stamp or 0)) >= RTSC_PENDING_TTL then
            pendingSlotClear[key] = nil
        end
    end
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
-- `silent` is for the sends the bar makes on its own, whose acks must not report to the user.
local function sendRtsc(sub, tag, silent)
    local comm = MultiBot.Comm

    if needsMarkerCast(sub) and not aedmKnown() then
        rtscMessageThrottled("spell", L(
            "rtsc.spell.missing",
            "You have not learned the RTSC marker spell yet - right-click the RTSC button to learn it."
        ))
    end

    if comm and type(comm.RunRtscCommand) == "function" then
        local command = tag and (tag .. " " .. sub) or sub
        if comm.RunRtscCommand("ALL", "", command, silent) then
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

    local forceButton = rtscUI.selectorFrame.buttons["Force"]
    if forceButton then
        -- Lit = "moves are forced". The logical flag lives in `forcing`, never in `state`: state is
        -- the engine's enable/desaturation flag, and writing it raw is what left Browse's look and
        -- its meaning permanently out of step.
        forceButton.forcing = forceModeActive

        if forceModeActive then
            forceButton.setEnable()
        else
            forceButton.setDisable()
        end

        -- Same treatment as an unlearned marker spell: fade what cannot work rather than hide it,
        -- so the reason is visible in the tooltip instead of the control just vanishing.
        if forceButton.SetAlpha then
            forceButton:SetAlpha(forceSupported == false and 0.35 or 1)
        end

        if MultiBot.bridge and MultiBot.bridge.connected then
            forceButton.doShow()
        else
            forceButton.doHide()
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
    -- The server has spoken; drop the optimistic marks it has had time to account for, so a save
    -- that never landed goes back to showing empty instead of lying. Marks younger than that are
    -- kept: this state can predate the command that made them (see markSlotPending).
    expirePendingSlots()

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
-- `considered` is how many bots it was offered to (nil on a bridge too old to say). It is what
-- turns "nobody ran it" into a verdict: 0 of N is a worldserver that cannot do it, 0 of 0 is an
-- empty bot pool and means nothing at all.
MultiBot.OnRtscCommandApplied = function(command, executed, considered, silent)
    local ran = (tonumber(executed) or 0) > 0
    local sub = tostring(command or "")
    -- nil (old bridge) keeps the pre-`considered` reading, where 0 executed was the only signal.
    local noBots = (tonumber(considered) or -1) == 0

    if sub == "lock" or sub == "unlock" then
        -- The lock is the deterministic fix, but it only exists on a worldserver carrying both
        -- halves of it (the bridge sub-command and playerbots' "RTSC selection locked"). With
        -- playerbots too old the flag does not exist and no bot applies it, so stop asking and
        -- fall back to re-asserting. Never reported: it is a probe, not a click.
        lockProbePending = false

        if not noBots then
            selectionLockSupported = ran
        end

        return
    end

    if sub == "force" or sub == "unforce" then
        -- Same probe as the lock: force move needs both halves (this bridge sub-command and
        -- playerbots' "RTSC force enabled"). Without them the flag does not exist, no bot applies
        -- it, and the bar greys the button instead of pretending the mode is on. With no bots to
        -- ask, the probe is simply inconclusive - leave it unprobed and let the poll retry once
        -- bots exist, or the feature stays dead for the session over an empty pool.
        forceProbePending = false
        forceNeedsBots = noBots

        if noBots then
            -- The mode stays armed and the poll keeps pushing it, but a deliberate toggle that
            -- reached nobody still has to say why - silence here is what "it does nothing" is
            -- made of.
            if not silent then
                rtscMessageThrottled("none:nobots", L("rtsc.applied.nobots", "RTSC: no bots online."))
            end

            refreshModeButtons()
            return
        end

        forceSupported = ran

        if not ran then
            forceModeActive = false
            rtscMessageThrottled("force", L(
                "rtsc.force.unsupported",
                "RTSC: force move needs a newer worldserver (mod-playerbots + mod-multibot-bridge). Bots will still break off a move when something aggroes."
            ))
        end

        refreshModeButtons()
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

        if forceProbePending then
            forceProbePending = false
            forceNeedsBots = false
            forceSupported = false
            forceModeActive = false
            rtscMessageThrottled("force", L(
                "rtsc.force.unsupported",
                "RTSC: force move needs a newer worldserver (mod-playerbots + mod-multibot-bridge). Bots will still break off a move when something aggroes."
            ))
            refreshModeButtons()
        end

        return
    end

    if ran then
        return
    end

    -- Nothing was clicked, so nothing is owed an answer: the bar re-asserts its modes on open,
    -- close and before every cast, and those acks used to report "no bot ran 'enable'" at anyone
    -- who opened the row without bots out.
    if silent then
        return
    end

    if noBots then
        rtscMessageThrottled("none:nobots", L("rtsc.applied.nobots", "RTSC: no bots online."))
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
        markSlotPending(savedSlot, true)
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

-- The bots act on the master's *outgoing* cast packet: SeeSpellAction is driven by the marker
-- spell's CMSG_CAST_SPELL, not by the server confirming anything back. So a cast can do its whole
-- job on the bots while UNIT_SPELLCAST_SUCCEEDED - which needs the server to report the cast -
-- never arrives, and hanging every post-cast repaint off that one event is why a stored spot could
-- stay grey and the selection badge stay empty after a plain send, until an unrelated click
-- refreshed the bar. UNIT_SPELLCAST_SENT fires when the client transmits that packet (for a
-- ground-targeted spell, on the terrain click), so it is the signal that always accompanies a real
-- RTSC cast - but it says nothing about the server having accepted it, so it is used only as a
-- fallback: SUCCEEDED keeps the job whenever it does arrive, and the deferred SENT handler stands
-- down when it sees that it did.
local RTSC_CAST_DEDUPE = 0.5
local RTSC_CAST_FALLBACK = 1
local lastCastHandledAt = nil

local function handleAedmCast()
    local now = rtscNow()

    if lastCastHandledAt and (now - lastCastHandledAt) < RTSC_CAST_DEDUPE then
        return
    end

    lastCastHandledAt = now
    onAedmCast()
end

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterEvent("UNIT_SPELLCAST_SENT")
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

    -- UNIT_SPELLCAST_SENT carries no spell id (its 4th argument is the target name), so the name
    -- is all it can be matched on - which is safe here, since it comes from the same client
    -- Spell.dbc entry aedmName() reads.
    if spellName ~= aedmName() and tonumber(spellId) ~= RTSC_SPELL_ID then
        return
    end

    if eventName ~= "UNIT_SPELLCAST_SENT" then
        handleAedmCast()
        return
    end

    if type(MultiBot.TimerAfter) ~= "function" then
        handleAedmCast()
        return
    end

    local sentAt = rtscNow()
    MultiBot.TimerAfter(RTSC_CAST_FALLBACK, function()
        -- SUCCEEDED handled this cast already; nothing to fall back to.
        if lastCastHandledAt and lastCastHandledAt >= sentAt then
            return
        end

        handleAedmCast()
    end)
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

    -- Same reasoning as the numbered location slots: a shared icon with nothing on the face is
    -- unreadable. setDisable() desaturates the icon only, so the digit stays legible either way.
    if definition.label then
        button.setAmount(definition.label)

        if button.amount and button.amount.SetTextColor then
            button.amount:SetTextColor(1, 0.82, 0)
        end
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
            markSlotPending(index, true)
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
            -- No bridge means no state read to expire an earlier optimistic "emptied" mark, so
            -- drop it here or an unsaved-then-saved slot would stay grey for the session.
            pendingSlotClear[tostring(index)] = nil
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

        -- `unsave` reaches the bots through their command queue, so a state read fired right here
        -- answers from before they applied it and paints the spot as still stored - the delete
        -- then only appeared to take effect on whatever click refreshed the bar next. Show it
        -- empty at once and read back once the bots have had the settle window.
        markSlotPending(index, false)
        refreshSlotButtons()

        if bridgeRtsc() then
            refreshRtscStateSoon(false)
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
    local browseButton = selectorFrame.addButton("Browse", 300, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc_browse.blp", MultiBot.L("tips.rtsc.browse"))

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
        .addButton("Move", 330, 0, "ability_rogue_sprint",
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
        .addButton("Last", 360, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc_target.blp",
            L("tips.rtsc.last", "Last Marker\n\nSend the selection back to the most recently marked spot, in formation.\nRight-click to re-read the saved spots from the server."))

    lastButton.doLeft = function(button)
        button.parent.doExecute(button, "last")
    end

    lastButton.doRight = function()
        -- Chatless equivalent of playerbots' `rtsc show`, which answers with a whisper per bot.
        requestRtscState()
    end

    local hereButton = selectorFrame
        .addButton("Here", 390, 0, "spell_arcane_blink",
            L("tips.rtsc.here", "Regroup On Me\n\nSend everyone to your exact position, in formation - no marker cast needed.\nRequires the MultiBot bridge."))

    -- "here" seeds the click position natively, before playerbots' chat filters run, so it cannot
    -- be scoped with an @tag - it always applies to the whole visible pool.
    hereButton.doLeft = function(button)
        sendRtsc("here")
        clearSelection(button.parent, false)
    end

    -- Not a cast button: it changes how the *next* destination is carried out, it does not place
    -- one. Every RTSC move path inherits it, because `go`, `last`, `here` and a plain cast all
    -- funnel through SeeSpellAction::MoveToSpell.
    local forceButton = selectorFrame
        .addButton("Force", 420, 0, "ability_warrior_charge",
            L("tips.rtsc.force", "Force Move\n\nWhile lit, bots carry out an RTSC move to the end - they no longer break it off when something aggroes on the way. They still fight back; only their movement is locked to the destination.\nApplies to a marker cast, Move, Last, a saved spot and Regroup On Me alike.\n\nLeft-click to toggle.\nRight-click to stop forcing and abort any move in progress.\nRequires the MultiBot bridge and a worldserver with force-move support."))

    forceButton.setDisable()
    forceButton.forcing = false

    -- A click that changes nothing has to say so. The toggle silently doing nothing - because the
    -- worldserver cannot force, or the bridge is down - is exactly how it came to look like force
    -- move "was on" while every move went out unforced.
    local function reportForceRefused()
        if forceSupported == false then
            rtscMessageThrottled("force", L(
                "rtsc.force.unsupported",
                "RTSC: force move needs a newer worldserver (mod-playerbots + mod-multibot-bridge). Bots will still break off a move when something aggroes."
            ))
            return
        end

        rtscMessageThrottled("force.bridge", L("rtsc.bridge.required", "This RTSC action requires the MultiBot bridge."))
    end

    forceButton.doLeft = function()
        if not applyForceMode(not forceModeActive) then
            reportForceRefused()
        end

        refreshModeButtons()
    end

    forceButton.doRight = function()
        -- Always re-send, even when the bar already thinks force is off: `unforce` clears the
        -- destination server-side, so this is the only way to call a forced move back mid-run.
        if not applyForceMode(false, true) then
            reportForceRefused()
        end

        refreshModeButtons()
    end

    return moveButton, lastButton, hereButton, forceButton
end

-- Slow backstop read while the row is open. Every other refresh here is hung off a click or a
-- cast event, so anything that changes the server state without one - the rubber-band selection a
-- plain cast performs, a command that landed after its post-action read, a bot that relogged -
-- stayed invisible until the next click happened to refresh the bar. One read every few seconds
-- costs a single GET~RTSC and keeps the slot faces and the count badge honest on their own.
local schedulePoll

local function pollRtscState()
    rtscPollArmed = false

    local frame = rtscUI and rtscUI.frame
    if not frame or not frame:IsShown() then
        return
    end

    -- A deliberate read is outstanding and OnBridgeRtscState consumes the next state that lands as
    -- its answer; a poll landing first would hand it the pre-change snapshot.
    if not (captureSelection or verifySelection) then
        requestRtscState()
    end

    -- The last force reached nobody because there were no bots. Bots summoned since would be
    -- running unforced - the flag is per bot and set only by this command - so push it again
    -- rather than waiting for the user to notice and re-toggle. Only while the mode is on: there
    -- is nothing to un-force on a pool that does not exist.
    if forceModeActive and forceNeedsBots and not forceProbePending then
        applyForceMode(true, true, true)
    end

    schedulePoll()
end

schedulePoll = function()
    if rtscPollArmed or type(MultiBot.TimerAfter) ~= "function" then
        return
    end

    local frame = rtscUI and rtscUI.frame
    if not frame or not frame:IsShown() then
        return
    end

    rtscPollArmed = true
    MultiBot.TimerAfter(RTSC_POLL_INTERVAL, pollRtscState)
end

-- Opening the bar trains the master's aedm spell (playerbots' bare `rtsc`) and pulls the real
-- server state so the slots render from it instead of from stale UI bookkeeping.
function MultiBot.RTSCOnPanelOpen()
    -- Everything this function sends is bookkeeping the user did not ask for, so all of it goes
    -- out silent: opening the row with no bots out used to answer with two errors about a broken
    -- worldserver, when the only thing missing was bots.
    sendRtsc("enable", nil, true)
    rtscStateRetries = 0
    requestRtscStateUntilConnected()

    -- "RTSC selection locked" is not persisted, so a bot that relogged since the last selection
    -- change defaults to unlocked. Re-send rather than trusting the cached value; this doubles as
    -- the probe that tells the bar whether the server knows the sub-command at all.
    local frame = rtscUI and rtscUI.selectorFrame
    applySelectionLock(frame and frame.selector ~= "", true, true)

    -- "RTSC force enabled" is not persisted either, and the bar reopens unlit, so push the off
    -- state out rather than leaving bots forced from a previous session. Doubles as the probe.
    applyForceMode(forceModeActive, true, true)

    refreshRtscUI()
    -- Self-terminates on the first tick that finds the row hidden, so closing the bar needs no
    -- teardown of its own.
    schedulePoll()
end

-- Closing must NOT send `rtsc reset`: that wipes every saved location on every bot and untrains the
-- master's spell. `cancel` only drops the selection and any armed action.
function MultiBot.RTSCOnPanelClose()
    -- ...and since it does drop the selection, the bar has to drop its lit tags with it. Leaving
    -- them lit meant re-opening showed a selection no bot was part of any more, and the lock stayed
    -- on for a selection that no longer existed.
    -- Force is a mode, not a selection, so `cancel` alone would leave the pool forced with the bar
    -- gone. Drop it explicitly; this also clears any destination still in flight. Silent for the
    -- same reason as the open: closing a row is not a request for a report.
    applyForceMode(false, true, true)

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
            for index = 1, RTSC_SLOT_COUNT do
                localSlots[tostring(index)] = nil
                markSlotPending(index, false)
            end

            clearSelection(button.parent.frames[RTSC_SELECTOR_NAME], false)
            refreshRtscUI()
            refreshRtscStateSoon(false)
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
        applySelectionLock(frame and frame.selector ~= "", true, true)

        -- Same reasoning for the force flag: it is per bot and not persisted, so a bot summoned
        -- since the toggle was set would take this cast unforced. Silent: the click the user made
        -- was "open the reticle", and it reports for itself.
        if forceModeActive then
            applyForceMode(true, true, true)
        end
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

    -- 270, not 240: the group row runs to 240 now (eight subgroups) and @all stays visible while
    -- Browse shows it. With the role row up, the freed 240 slot reads as a gap between the tag
    -- buttons and @all, which is no bad thing.
    local allButton = addAedmMacro(selectorFrame
        .addButton("@all", 270, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc.blp", MultiBot.L("tips.rtsc.all"), "SecureActionButtonTemplate"))

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
    local moveButton, lastButton, hereButton, forceButton = createModeButtons(selectorFrame)

    -- Buttons are 28 wide on a 30 pitch, so the only real gap is between the last spot slot
    -- (right edge -34) and the first selector icon (left edge +2); the second hairline goes in the
    -- 2px gap between Browse (300) and Move (330).
    createSeparator(selectorFrame, -16)
    createSeparator(selectorFrame, 301)

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
        forceButton = forceButton,
    }

    refreshRtscUI()

    return rtscUI
end

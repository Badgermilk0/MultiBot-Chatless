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

-- Optimistic slot bookkeeping, used only while the bridge cannot tell us the real server state.
local localSlots = {}
local rtscUI = nil

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
        rootButton.tip = rtscUI.rootTip
        if bridgeRtsc() then
            rootButton.tip = rtscUI.rootTip .. "\n\n" ..
                string.format(L("rtsc.selected.count", "Bots currently selected: %d"), selectedCount())
        end
    end
end

local function refreshRtscUI()
    refreshSlotButtons()
    refreshModeButtons()
end

-- Called by MultiBotComm once a GET~RTSC stream completes.
MultiBot.OnBridgeRtscState = function()
    refreshRtscUI()
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
local function onAedmCast()
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

local function createSelectorButton(selectorFrame, definition)
    local button = addAedmMacro(selectorFrame
        .addButton(definition.tag, definition.x, 0, definition.icon, MultiBot.L(definition.tip), "SecureActionButtonTemplate"))

    if definition.hidden then
        button.doHide()
    end

    if definition.disabled then
        button.setDisable()
    end

    button.doRight = function(owner)
        sendRtsc("select", definition.tag)
        owner.parent.doSelect(owner, definition.tag)
        owner.setEnable()
    end

    button.doLeft = function(owner)
        sendRtsc("select", definition.tag)
        owner.parent.doReset(owner.parent)
    end

    return button
end

local function createStoragePair(selectorFrame, index)
    local macroName = "MACRO" .. index
    local rtscName = "RTSC" .. index
    local x = -304 + 30 * index

    local macroButton = addAedmMacro(selectorFrame
        .addButton(macroName, x, 0, RTSC_STORAGE_ICON, L("tips.rtsc.macro"), "SecureActionButtonTemplate"))
        .setDisable()

    macroButton.doLeft = function(button)
        -- Shift stores where the bots are standing *right now* - each bot records its own spot, so
        -- a later "go" restores the formation instead of stacking everyone on one point.
        if IsShiftKeyDown() then
            -- Stores immediately (and the bridge flushes it for us), so only the re-read is needed.
            sendRtsc("save here " .. index)
            if not bridgeRtsc() then
                localSlots[tostring(index)] = true
                refreshSlotButtons()
            end

            refreshRtscStateSoon(false)
            return
        end

        -- With a selector armed, only the selected bots record the spot.
        local selector = button.parent.selector
        sendRtsc((selector ~= "" and "save selected " or "save ") .. index)

        -- Without the bridge there is no way to learn whether the cast ever happened, so keep the
        -- old optimistic flip; with it, the cast watcher fills the slot from real server state.
        if not bridgeRtsc() then
            localSlots[tostring(index)] = true
            refreshSlotButtons()
        end
    end

    local slotButton = selectorFrame
        .addButton(rtscName, x, 0, RTSC_STORAGE_ICON, L("tips.rtsc.spot"), "SecureActionButtonTemplate")
        .doHide()

    slotButton.doRight = function()
        sendRtsc("unsave " .. index)
        localSlots[tostring(index)] = nil

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
            if button.parent.buttons[tag] then
                button.parent.buttons[tag].setDisable()
            end
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

            for _, groupIndex in ipairs(groupIndexes) do
                local key = "@group" .. tostring(groupIndex)
                if button.parent.buttons[key] then
                    button.parent.buttons[key].setDisable()
                end
            end
        end

        button.parent.selector = ""
    end

    selectorFrame.doSelect = function(button, selector)
        if button.parent.selector == "" then
            button.parent.selector = selector
            return
        end

        button.parent.selector = button.parent.selector .. " " .. selector
    end

    selectorFrame.doReset = function(frame)
        if frame.selector == "" then
            return
        end

        local groups = MultiBot.doSplit(frame.selector, " ")
        for _, tag in ipairs(groups) do
            if frame.buttons[tag] then
                frame.buttons[tag].setDisable()
            end
        end
        frame.selector = ""
    end
end

local function createBrowseButton(selectorFrame)
    local browseButton = selectorFrame.addButton("Browse", 270, 0, "Interface\\AddOns\\MultiBot\\Icons\\rtsc_browse.blp", MultiBot.L("tips.rtsc.browse"))

    browseButton.doRight = function(button)
        sendRtsc("cancel")
        button.parent.doReset(button.parent)
    end

    browseButton.doLeft = function(button)
        local frame = button.parent

        if button.state then
            for _, tag in ipairs(RTSC_BROWSE_ROLES) do
                frame.buttons[tag].doShow()
            end
            for _, tag in ipairs(RTSC_BROWSE_GROUPS) do
                frame.buttons[tag].doHide()
            end
            button.state = false
            return
        end

        for _, tag in ipairs(RTSC_BROWSE_ROLES) do
            frame.buttons[tag].doHide()
        end
        for _, tag in ipairs(RTSC_BROWSE_GROUPS) do
            frame.buttons[tag].doShow()
        end
        button.state = true
    end

    return browseButton
end

-- Move / Last / Here sit right of Browse so the existing -274..270 layout is untouched.
local function createModeButtons(selectorFrame)
    local moveButton = addAedmMacro(selectorFrame
        .addButton("Move", 300, 0, "ability_rogue_sprint",
            L("tips.rtsc.move", "RTSC Move Mode\n\nLeft-click to arm move mode and place a marker: from then on every AEDM cast moves your selection, with no further commands.\nRight-click to disarm."),
            "SecureActionButtonTemplate"))
        .setDisable()

    moveButton.doLeft = function()
        sendRtsc("move")
    end

    moveButton.doRight = function(button)
        sendRtsc("cancel")
        button.parent.doReset(button.parent)
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
        button.parent.doReset(button.parent)
    end

    return moveButton, lastButton, hereButton
end

-- Opening the bar trains the master's aedm spell (playerbots' bare `rtsc`) and pulls the real
-- server state so the slots render from it instead of from stale UI bookkeeping.
function MultiBot.RTSCOnPanelOpen()
    sendRtsc("enable")
    requestRtscState()
    refreshRtscUI()
end

-- Closing must NOT send `rtsc reset`: that wipes every saved location on every bot and untrains the
-- master's spell. `cancel` only drops the selection and any armed action.
function MultiBot.RTSCOnPanelClose()
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
            for index = 1, RTSC_SLOT_COUNT do
                localSlots[tostring(index)] = nil
            end

            button.parent.frames[RTSC_SELECTOR_NAME].doReset(button.parent.frames[RTSC_SELECTOR_NAME])
            requestRtscState()
            refreshRtscUI()
            return
        end

        sendRtsc("enable")
        MultiBot.ActionToGroup("co +rtsc,+guard,?")
        MultiBot.ActionToGroup("nc +rtsc,+guard,?")
    end

    rootButton.doLeft = function(button)
        local frame = button.parent.frames[RTSC_SELECTOR_NAME]
        frame.doReset(frame)
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

    -- Left and right send the same command on purpose: only left carries the secure /cast, so
    -- left = "select and mark a spot now", right = "select only". Deselect-all lives on Browse's
    -- right-click (`cancel`), which every locale already documents.
    allButton.doLeft = function(button)
        sendRtsc("select")
        button.parent.doReset(button.parent)
    end

    allButton.doRight = function(button)
        sendRtsc("select")
        button.parent.doReset(button.parent)
    end

    local browseButton = createBrowseButton(selectorFrame)
    local moveButton, lastButton, hereButton = createModeButtons(selectorFrame)

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

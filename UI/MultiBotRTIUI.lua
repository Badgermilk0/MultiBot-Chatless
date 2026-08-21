if not MultiBot then return end

local RTI_ATTACK_ICONS = {
    { key = "star",     id = 1, label = "Star",     labelKey = "rti.icon.star"     },
    { key = "circle",   id = 2, label = "Circle",   labelKey = "rti.icon.circle"   },
    { key = "diamond",  id = 3, label = "Diamond",  labelKey = "rti.icon.diamond"  },
    { key = "triangle", id = 4, label = "Triangle", labelKey = "rti.icon.triangle" },
    { key = "moon",     id = 5, label = "Moon",     labelKey = "rti.icon.moon"     },
    { key = "square",   id = 6, label = "Square",   labelKey = "rti.icon.square"   },
    { key = "cross",    id = 7, label = "Cross",    labelKey = "rti.icon.cross"    },
    { key = "skull",    id = 8, label = "Skull",    labelKey = "rti.icon.skull"    },
}

-- playerbots only knows these eight names (RtiTargetValue::GetRtiIndex) and their order is also the
-- client's SetRaidTarget index, so `id` doubles as the marker slot.
local RTI_ICON_BY_KEY = {}
for _, icon in ipairs(RTI_ATTACK_ICONS) do
    RTI_ICON_BY_KEY[icon.key] = icon
end

-- Both pickers are the same nine-slot horizontal strip: the eight markers, then a "clear" slot
-- sitting directly over the button that opened it.
local ICON_STRIP_WIDTH = 270
local ICON_STRIP_HEIGHT = 30
local ICON_STRIP_STEP = 30
local ICON_STRIP_SIZE = 24

-- The toolbar strip, bottom to top: All, raid groups 1-8, then the three strip-level rows. Named
-- rather than spelled out at the call sites so adding a row can not leave two buttons stacked on
-- the same 24px slot.
local RTI_ROW_STEP = 24
local RTI_ROW_ALL = 0
local RTI_ROW_CC = 9 * RTI_ROW_STEP
local RTI_ROW_ATTACK = 10 * RTI_ROW_STEP
local RTI_ROW_PULL = 11 * RTI_ROW_STEP
local RTI_STRIP_HEIGHT = RTI_ROW_PULL + RTI_ROW_STEP

-- Per-bot markers live in the AceDB UI store: a /reload mid-raid used to wipe the whole per-bot
-- assignment, and with it the toolbar button that fires them.
local BOT_MARKER_STORE_KEY = "rtiBotMarkers"

-- One report per kind per window. A scope action fans out to eight raid groups and the per-bot
-- action to the whole pool, so an unreachable bridge used to print one line per send.
local MESSAGE_THROTTLE_SECONDS = 2

-- Past this many stored bots the toolbar tooltip stops listing and just counts the rest.
local BOT_MARKER_TOOLTIP_LIMIT = 12

local fallbackBotMarkers = {}
-- name -> that bot's marker button. "Clear all" has to repaint the rows that are on screen: an
-- EveryBar is only rebuilt when the roster changes, so the stale icon would otherwise stay up.
local botMarkerButtons = {}
local lastMessageAt = {}

local function raidIconTexture(iconId)
    return "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_" .. tostring(iconId)
end

local function rtiSelectorTexture()
    return "Interface\\Icons\\Achievement_PVP_P_01"
end

local function safeNow()
    if type(GetTime) == "function" then
        return GetTime() or 0
    end

    return 0
end

local function showRTIMessage(message, r, g, b)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, r or 1, g or 0.82, b or 0, 1)
        return
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(message)
    end
end

local function showRTIMessageThrottled(key, message, r, g, b)
    local at = safeNow()
    local previous = lastMessageAt[key]

    if previous and at >= previous and (at - previous) < MESSAGE_THROTTLE_SECONDS then
        return
    end

    lastMessageAt[key] = at
    showRTIMessage(message, r, g, b)
end

local function localized(key, fallback, ...)
    local text = MultiBot.L(key, fallback)
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

local function makeTip(title, body)
    return title .. "\n" .. body
end

local function localizedTip(titleKey, titleFallback, bodyKey, bodyFallback, ...)
    return makeTip(localized(titleKey, titleFallback, ...), localized(bodyKey, bodyFallback, ...))
end

local function iconLabel(icon)
    if not icon then
        return ""
    end
    return localized(icon.labelKey or "", icon.label or icon.key or "")
end

-- SavedVariables content is never trusted: every stored marker is resolved back through the
-- canonical table, so a stale or hand-edited entry can not feed a bogus icon id to the bridge or to
-- SetRaidTarget.
local function resolveStoredIcon(value)
    if type(value) ~= "table" then
        return nil
    end

    return RTI_ICON_BY_KEY[tostring(value.key or "")]
end

-- The UI store only exists once AceDB is up (OnInitialize), while the toolbar and the EveryBars are
-- built while the files load. Anything stored before that lands in the in-memory fallback and is
-- migrated on the first read that finds a real store.
-- The profile is checked directly rather than through Store.EnsureProfileStore: before AceDB runs,
-- that helper hands back the raw MultiBotDB SavedVariable, and writing our table into AceDB's own
-- root would strand the markers outside the profile AceDB then builds there.
local function botMarkerStore()
    if not (MultiBot.db and type(MultiBot.db.profile) == "table") then
        return nil
    end

    if not (MultiBot.Store and MultiBot.Store.EnsureUIChildStore) then
        return nil
    end

    return MultiBot.Store.EnsureUIChildStore(BOT_MARKER_STORE_KEY)
end

local function botMarkers()
    local store = botMarkerStore()

    if type(store) ~= "table" then
        MultiBot.RTIBotSelections = fallbackBotMarkers
        return fallbackBotMarkers
    end

    for name, icon in pairs(fallbackBotMarkers) do
        if store[name] == nil then
            store[name] = icon
        end
        fallbackBotMarkers[name] = nil
    end

    MultiBot.RTIBotSelections = store
    return store
end

local function raidMemberCount()
    if type(GetNumRaidMembers) == "function" then
        return GetNumRaidMembers() or 0
    end

    return 0
end

local function partyMemberCount()
    if type(GetNumPartyMembers) == "function" then
        return GetNumPartyMembers() or 0
    end

    return 0
end

-- Same online authority the Units roster uses (IsBridgeRosterBotActive in Core/MultiBot.lua): a
-- group slot keeps a bot's name after it logs out, so the name alone is not enough.
local function isGroupedBot(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    for index = 1, raidMemberCount() do
        if UnitName("raid" .. index) == name and UnitIsConnected("raid" .. index) then
            return true
        end
    end

    for index = 1, partyMemberCount() do
        if UnitName("party" .. index) == name and UnitIsConnected("party" .. index) then
            return true
        end
    end

    return false
end

-- Every bot that has a usable stored marker, sorted. `pairs` order is undefined and this drives both
-- the dispatch order (the bridge send queue is a FIFO) and the tooltip listing.
local function storedBotMarkerList()
    local markers = botMarkers()
    local names = {}

    for botName, value in pairs(markers) do
        if type(botName) == "string" and botName ~= "" and resolveStoredIcon(value) then
            names[#names + 1] = botName
        end
    end

    table.sort(names)
    return names, markers
end

-- The toolbar button is the only place the per-bot assignment is visible once the roster window is
-- closed, so its tooltip lists what it would actually fire. Bots outside the group are greyed: the
-- action skips them, because `rti target` can not resolve for them.
local function botActionTooltip(names, markers)
    local tip = localizedTip(
        "tips.rti.bot.action.title",
        "Per-Bot Marker Actions",
        "tips.rti.bot.action.body",
        "Orders every Bot that has its own raid marker stored to attack or pull the target carrying it."
    )

    if #names <= 0 then
        return tip
    end

    local lines = {
        tip,
        "",
        "|cffffd100" .. localized("info.rti.bot.markers.header", "Stored markers") .. "|r",
    }

    for index = 1, math.min(#names, BOT_MARKER_TOOLTIP_LIMIT) do
        local botName = names[index]
        local colour = isGroupedBot(botName) and "|cffffffff" or "|cff999999"
        lines[#lines + 1] = colour .. botName .. ": " .. iconLabel(resolveStoredIcon(markers[botName])) .. "|r"
    end

    if #names > BOT_MARKER_TOOLTIP_LIMIT then
        lines[#lines + 1] = "|cff999999+" .. tostring(#names - BOT_MARKER_TOOLTIP_LIMIT) .. "|r"
    end

    return table.concat(lines, "\n")
end

local function updateBotRTIActionButton()
    local button = MultiBot.RTIBotActionButton
    if not button then
        return
    end

    local names, markers = storedBotMarkerList()

    -- The engine reads button.tip at hover time, so refreshing the string is enough.
    button.tip = botActionTooltip(names, markers)

    if #names > 0 then
        button.doShow()
    else
        button.doHide()

        if MultiBot.RTIBotActionFrame then
            MultiBot.RTIBotActionFrame:Hide()
        end
    end
end

local function bridgeReady()
    if MultiBot.bridge and MultiBot.bridge.connected then
        return true
    end

    showRTIMessageThrottled(
        "bridge",
        MultiBot.L("rti.bridge.required", "Raid Marker commands need the MultiBot bridge."),
        1, 0.2, 0.2
    )
    return false
end

-- `silent` marks the `rti <icon>` half of an action: nobody clicked that on its own, so its ack must
-- stay quiet. Only the attack/pull half is a user action worth reporting on.
local function sendRTI(scope, target, command, silent)
    local comm = MultiBot.Comm

    if not comm or not comm.RunRtiCommand then
        return false
    end

    return comm.RunRtiCommand(scope, target or "", command, silent) and true or false
end

local function runRTI(scope, target, command)
    if not bridgeReady() then
        return false
    end

    return sendRTI(scope, target, command)
end

-- Assigning a marker only tells the bots WHICH raid icon to focus (playerbots resolves it through
-- the group's icon table); something still has to put that icon on a mob. That was the missing half
-- of the feature: "Attack Marked Target" resolved to nothing unless the marker happened to have been
-- placed by hand through Blizzard's own target menu.
local function canPlaceRaidMarker()
    if type(SetRaidTarget) ~= "function" then
        return false
    end

    if not UnitExists("target") then
        showRTIMessage(MultiBot.L("info.rti.mark.no_target", "Select a target to mark first."), 1, 0.2, 0.2)
        return false
    end

    local inRaid = raidMemberCount() > 0

    if not inRaid and partyMemberCount() <= 0 then
        showRTIMessage(MultiBot.L("info.rti.mark.no_group", "Raid markers only exist in a party or raid."), 1, 0.2, 0.2)
        return false
    end

    -- In a raid the server silently drops SetRaidTarget from a plain member; say so rather than let
    -- the click look broken.
    if inRaid then
        local allowed = (type(IsRaidLeader) == "function" and IsRaidLeader())
            or (type(IsRaidOfficer) == "function" and IsRaidOfficer())

        if not allowed then
            showRTIMessage(
                MultiBot.L("info.rti.mark.not_leader", "Only the raid leader or an assistant can place raid markers."),
                1, 0.2, 0.2
            )
            return false
        end
    end

    return true
end

local function markTargetWithIcon(icon)
    if not icon or not icon.id or not canPlaceRaidMarker() then
        return false
    end

    SetRaidTarget("target", icon.id)
    return true
end

-- Index 0 is Blizzard's "no marker". There is no API to clear an icon without a unit to clear it
-- from, so this is deliberately "clear whatever my target wears", not "clear marker N everywhere".
local function clearTargetMarker()
    if not canPlaceRaidMarker() then
        return false
    end

    if type(GetRaidTargetIndex) == "function" then
        -- Unmarked reads back as nil on some 3.3.5a builds and as 0 on others; treat both as "no
        -- marker" rather than clearing something that was never there.
        local current = GetRaidTargetIndex("target")

        if not current or current == 0 then
            showRTIMessage(MultiBot.L("info.rti.mark.nothing_to_clear", "Your target carries no raid marker."), 1, 0.82, 0)
            return false
        end
    end

    SetRaidTarget("target", 0)
    return true
end

-- Every marker button shares one click contract: plain left-click places the button's marker on the
-- current target, shift+left-click clears whatever marker the target wears.
local function applyMarkerClick(icon, missingIconMessage)
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
        return clearTargetMarker()
    end

    if not icon then
        showRTIMessage(missingIconMessage, 1, 0.82, 0)
        return false
    end

    return markTargetWithIcon(icon)
end

local function makeState()
    return {
        selectedGroups = {},
        selectedIcons = {},
        scopeButtons = {},
        scopeDefaults = {},
        menus = {},
        -- playerbots keeps a second, independent marker per bot: `rti cc` (default "moon"). Bots
        -- crowd-control whatever wears it and, just as importantly, leave it out of their attack
        -- target selection (TargetValue.cpp). One CC marker for the whole strip - it follows the
        -- same scope selection Attack and Pull use.
        ccIcon = nil,
        ccButton = nil,
        ccDefault = nil,
    }
end

local function scopeKey(scope, target)
    return tostring(scope or "ALL") .. ":" .. tostring(target or "")
end

local function setButtonAmount(button, amount)
    if not button or not button.setAmount then
        return
    end

    local value = amount or ""

    -- setAmount builds a fresh FontString every call and only hides the old one, so repeatedly
    -- picking markers would pile hidden strings onto the button.
    if button._mbRtiAmount == value then
        return
    end

    button._mbRtiAmount = value
    button.setAmount(value)
end

local function setButtonTexture(button, texture)
    if not button or not texture then
        return
    end

    if button.setTexture then
        button.setTexture(texture)
        return
    end

    local safe = texture
    if MultiBot.SafeTexturePath then
        safe = MultiBot.SafeTexturePath(texture)
    end

    if button.icon and button.icon.SetTexture then
        button.icon:SetTexture(safe)

        if button.icon.SetAllPoints then
            button.icon:SetAllPoints(button)
        end

        if button.icon.Show then
            button.icon:Show()
        end
    end

    button.texture = safe
end

local function rememberBotRTISelection(botName, button, icon)
    if not botName or botName == "" or not button or not icon or not icon.key or not icon.id then
        return
    end

    botMarkers()[botName] = {
        key = icon.key,
        id = icon.id,
        label = icon.label,
    }

    button._mbRtiSelectedIcon = icon
    setButtonTexture(button, raidIconTexture(icon.id))
end

local function clearBotRTISelection(botName, button, defaultTexture)
    if botName and botName ~= "" then
        botMarkers()[botName] = nil
    end

    if button then
        button._mbRtiSelectedIcon = nil
        setButtonTexture(button, defaultTexture or rtiSelectorTexture())
    end
end

local function restoreBotRTISelection(botName, button, defaultTexture)
    local icon = botName and resolveStoredIcon(botMarkers()[botName]) or nil

    if icon and button then
        button._mbRtiSelectedIcon = icon
        setButtonTexture(button, raidIconTexture(icon.id))
        return
    end

    clearBotRTISelection(botName, button, defaultTexture)
end

local function hideDropdownMenu(menu, restoreCollapsedBars)
    if not menu or not menu.Hide then
        return
    end

    if restoreCollapsedBars and menu.IsShown and menu:IsShown() and MultiBot.ShowHideSwitch then
        MultiBot.ShowHideSwitch(menu)
        return
    end

    menu:Hide()
    if MultiBot.RequestClickBlockerUpdate then
        MultiBot.RequestClickBlockerUpdate(menu)
    end
end

local function hideAllMenus(state, restoreCollapsedBars)
    for _, menu in pairs(state.menus) do
        hideDropdownMenu(menu, restoreCollapsedBars)
    end
end

local function toggleMenu(state, menu)
    if not menu then
        return
    end

    local shown = menu:IsShown()
    hideAllMenus(state, true)

    if shown then
        return
    end

    if MultiBot.ShowHideSwitch then
        MultiBot.ShowHideSwitch(menu)
    else
        menu:Show()
        if MultiBot.RequestClickBlockerUpdate then
            MultiBot.RequestClickBlockerUpdate(menu)
        end
    end
end

local function updateScopeButtonVisual(state, scope, target, icon)
    local button = state.scopeButtons[scopeKey(scope, target)]

    if not button or not icon then
        return
    end

    setButtonTexture(button, raidIconTexture(icon.id))

    if scope == "ALL" then
        setButtonAmount(button, "A")
    elseif scope == "GROUP" then
        setButtonAmount(button, tostring(target or ""))
    end
end

local function resetScopeButtonVisual(state, key)
    local button = state.scopeButtons[key]
    local defaults = state.scopeDefaults[key]

    if not button or not defaults then
        return
    end

    setButtonTexture(button, defaults.texture)
    setButtonAmount(button, defaults.amount)
end

local function clearScopeSelection(state, scope, target)
    state.selectedIcons[scopeKey(scope, target)] = nil

    if scope == "GROUP" then
        state.selectedGroups[tostring(target or "")] = nil
    end
end

-- "All bots" and the per-group scopes are mutually exclusive (runSelectedScopes prefers the groups
-- whenever any of them carries a marker), so the losing side has to drop its stored icon as well as
-- its highlight. Without this the strip kept showing a marker on a scope that no longer took part.
local function applyScopeExclusivity(state, scope)
    if scope == "ALL" then
        for groupIndex = 1, 8 do
            clearScopeSelection(state, "GROUP", tostring(groupIndex))
            resetScopeButtonVisual(state, scopeKey("GROUP", tostring(groupIndex)))
        end
        return
    end

    clearScopeSelection(state, "ALL", "")
    resetScopeButtonVisual(state, scopeKey("ALL", ""))
end

-- Raid groups the player is not actually running are greyed out; picking a marker for raid group 6
-- while in a five-man party only ever produced a command the bridge matched zero bots against.
-- `oBorder = false` keeps the border out of it: the border is the addon's "toggled on" look
-- everywhere else, and availability must not start painting it.
local function refreshScopeAvailability(state)
    local populated = {}
    local raidCount = raidMemberCount()

    if raidCount > 0 then
        for index = 1, raidCount do
            local _, _, subgroup = GetRaidRosterInfo(index)
            if subgroup then
                populated[tostring(subgroup)] = true
            end
        end
    elseif partyMemberCount() > 0 then
        -- A party is subgroup 0 server-side, which the bridge's GROUP scope reads as raid group 1.
        populated["1"] = true
    end

    for groupIndex = 1, 8 do
        local button = state.scopeButtons[scopeKey("GROUP", tostring(groupIndex))]

        if button then
            if populated[tostring(groupIndex)] then
                button.setEnable(false)
            else
                button.setDisable(false)
            end
        end
    end
end

-- One shared horizontal strip for both pickers. The per-bot picker used to be a 274px column that
-- opened DOWNWARDS from a roster row already sitting ~218px off the bottom of the screen, so its
-- first icons rendered off-screen (and over the MultiBar) and could not be clicked at all.
local function addIconStrip(parentFrame, namePrefix, x, y, defaultTexture, defaultAmount, iconTip, resetTip, onIcon, onReset)
    local menuFrame = parentFrame.addFrame(
        namePrefix .. "Menu",
        x,
        y,
        ICON_STRIP_SIZE,
        ICON_STRIP_WIDTH,
        ICON_STRIP_HEIGHT
    )

    menuFrame:Hide()
    menuFrame._mbDropdownManaged = true

    for index, icon in ipairs(RTI_ATTACK_ICONS) do
        local button = menuFrame.addButton(
            namePrefix .. "Icon" .. tostring(index),
            -ICON_STRIP_WIDTH + index * ICON_STRIP_STEP,
            0,
            raidIconTexture(icon.id),
            iconTip(icon)
        )

        button.doLeft = function()
            onIcon(icon)
            hideDropdownMenu(menuFrame, true)
        end
    end

    local resetButton = menuFrame.addButton(namePrefix .. "Reset", 0, 0, defaultTexture, resetTip)
    setButtonAmount(resetButton, defaultAmount)

    resetButton.doLeft = function()
        onReset()
        hideDropdownMenu(menuFrame, true)
    end

    return menuFrame
end

local function scopeIconTip(icon)
    return localizedTip(
        "tips.rti.icon.title",
        "Raid Marker: %s",
        "tips.rti.icon.body",
        "Stores the %s marker for this scope.",
        iconLabel(icon)
    )
end

local function addScopeButton(parentFrame, state, scope, target, x, y, texture, tip, amount)
    local key = scopeKey(scope, target)

    local button = parentFrame.addButton(
        "RTIScope" .. tostring(scope) .. tostring(target or ""),
        x,
        y,
        texture,
        tip
    )

    setButtonAmount(button, amount)
    state.scopeButtons[key] = button
    state.scopeDefaults[key] = { texture = texture, amount = amount }

    -- The toolbar strip is vertical and already sits near the left screen edge, so its picker opens
    -- sideways and to the right, towards the middle of the screen.
    local menu = addIconStrip(
        parentFrame,
        "RTIDropdown" .. tostring(scope) .. tostring(target or ""),
        x + ICON_STRIP_WIDTH,
        y,
        texture,
        amount,
        scopeIconTip,
        localizedTip(
            "tips.rti.default.title",
            "Clear Marker",
            "tips.rti.default.body.scope",
            "Clears the marker stored for this scope."
        ),
        function(icon)
            applyScopeExclusivity(state, scope)
            state.selectedIcons[key] = icon

            if scope == "GROUP" then
                state.selectedGroups[tostring(target or "")] = true
            end

            updateScopeButtonVisual(state, scope, target, icon)
        end,
        function()
            clearScopeSelection(state, scope, target)
            resetScopeButtonVisual(state, key)
        end
    )

    state.menus[key] = menu

    button.doLeft = function()
        applyMarkerClick(
            state.selectedIcons[key],
            MultiBot.L("info.rti.no_scope_icon", "Pick a raid marker for this scope first (right-click).")
        )
    end

    button.doRight = function()
        -- The strip stays open across picks (_mbSkipAutoCollapse), so the raid can be reshuffled
        -- between two of them: re-read availability whenever a picker is opened, not only when the
        -- strip itself is.
        refreshScopeAvailability(state)
        toggleMenu(state, menu)
    end

    return button
end

local function hasSelectedGroups(state)
    for groupIndex = 1, 8 do
        if state.selectedGroups[tostring(groupIndex)] then
            return true
        end
    end

    return false
end

-- The scope set every strip-level action works on: the raid groups that carry a marker, or "all
-- bots" when none of them does. Attack, Pull and the CC assignment all read the same rule, so it
-- lives in one place instead of being spelled out three times.
local function forEachSelectedScope(state, handler)
    local handled = false

    if hasSelectedGroups(state) then
        for groupIndex = 1, 8 do
            local groupKey = tostring(groupIndex)

            if state.selectedGroups[groupKey] and handler("GROUP", groupKey) then
                handled = true
            end
        end

        return handled
    end

    return handler("ALL", "") and true or false
end

local function runScopeWithStoredIcon(state, scope, target, command)
    local icon = state.selectedIcons[scopeKey(scope, target)]

    -- Both assignments are re-asserted on every action: a bot that relogged is back on the
    -- playerbots defaults ("skull" / "moon"), and re-sending is the only way the addon can know its
    -- stored marker is the one the bot actually holds. Both are silent - the user clicked one
    -- button, so only the attack/pull half may report.
    if icon and not sendRTI(scope, target, "rti " .. icon.key, true) then
        return false
    end

    if state.ccIcon and not sendRTI(scope, target, "rti cc " .. state.ccIcon.key, true) then
        return false
    end

    return sendRTI(scope, target, command)
end

local function runSelectedScopes(state, command)
    if not bridgeReady() then
        return false
    end

    return forEachSelectedScope(state, function(scope, target)
        return runScopeWithStoredIcon(state, scope, target, command)
    end)
end

-- Picking a CC marker pushes it out immediately: unlike the attack marker it is not paired with an
-- action button, so the pick IS the command. Not silent - if it reached nobody the user has to hear
-- about it.
local function runCcAssign(state, icon)
    if not icon or not bridgeReady() then
        return false
    end

    return forEachSelectedScope(state, function(scope, target)
        return sendRTI(scope, target, "rti cc " .. icon.key)
    end)
end

-- The CC row is the attack row's twin: same picker, same click contract, same "current scope
-- selection" rule. It is one row rather than nine because playerbots keeps a single `rti cc` value
-- per bot and crowd control is a "one mob in the pack" call, not a per-raid-group one.
local function addCcButton(parentFrame, state, x, y, texture)
    local button = parentFrame.addButton(
        "RTICcMarker",
        x,
        y,
        texture,
        localizedTip(
            "tips.rti.cc.title",
            "Crowd Control Marker",
            "tips.rti.cc.body",
            "The raid marker the Bots should crowd control instead of attacking."
        )
    )

    setButtonAmount(button, "CC")
    state.ccButton = button
    state.ccDefault = { texture = texture, amount = "CC" }

    local menu = addIconStrip(
        parentFrame,
        "RTICcDropdown",
        x + ICON_STRIP_WIDTH,
        y,
        texture,
        "CC",
        function(icon)
            return localizedTip(
                "tips.rti.cc.icon.title",
                "Crowd Control Marker: %s",
                "tips.rti.cc.icon.body",
                "Bots crowd control the %s marker and stop attacking it.",
                iconLabel(icon)
            )
        end,
        localizedTip(
            "tips.rti.default.title",
            "Clear Marker",
            "tips.rti.cc.default.body",
            "Stops re-sending a crowd control marker. Bots keep the last one they were given."
        ),
        function(icon)
            state.ccIcon = icon
            setButtonTexture(button, raidIconTexture(icon.id))
            setButtonAmount(button, "CC")
            runCcAssign(state, icon)
        end,
        function()
            state.ccIcon = nil
            setButtonTexture(button, state.ccDefault.texture)
            setButtonAmount(button, state.ccDefault.amount)
        end
    )

    state.menus["CC"] = menu

    button.doLeft = function()
        applyMarkerClick(
            state.ccIcon,
            MultiBot.L("info.rti.no_cc_icon", "Pick a crowd control marker first (right-click).")
        )
    end

    button.doRight = function()
        refreshScopeAvailability(state)
        toggleMenu(state, menu)
    end

    return button
end

function MultiBot.RunRTIAttackTarget(scope, target)
    return runRTI(scope or "ALL", target or "", "attack rti target")
end

function MultiBot.RunRTIPullTarget(scope, target)
    return runRTI(scope or "ALL", target or "", "pull rti target")
end

-- The bridge validates icon names too (IsAllowedRTIIcon), but rejecting them here keeps a typo from
-- costing a round trip and, now that acks are reported, from surfacing as "No Bot ran: rti bogus".
local function resolveIconKey(icon)
    if type(icon) == "table" then
        return RTI_ICON_BY_KEY[tostring(icon.key or "")]
    end

    -- Accepts either the playerbots name ("skull") or the marker slot (1-8, which is also the
    -- SetRaidTarget index), so a caller can pass whichever handle it happens to hold.
    local id = tonumber(icon)
    if id then
        return RTI_ATTACK_ICONS[id]
    end

    return RTI_ICON_BY_KEY[string.lower(tostring(icon or ""))]
end

function MultiBot.AssignRTIAttackIcon(scope, target, icon)
    local resolved = resolveIconKey(icon)
    if not resolved then
        return false
    end

    return runRTI(scope or "ALL", target or "", "rti " .. resolved.key)
end

function MultiBot.AssignRTICCIcon(scope, target, icon)
    local resolved = resolveIconKey(icon)
    if not resolved then
        return false
    end

    return runRTI(scope or "ALL", target or "", "rti cc " .. resolved.key)
end

function MultiBot.UpdateBotRTIActionButton()
    updateBotRTIActionButton()
end

-- RTI_ACK has always carried `scope~target~token~executed~command`; the addon threw it away, so an
-- order that reached no bot at all was indistinguishable from one that worked. Core/MultiBotComm.lua
-- routes it here now.
function MultiBot.OnRtiCommandApplied(command, executed, silent, scope, target)
    if silent or (tonumber(executed) or 0) > 0 then
        return
    end

    command = tostring(command or "")

    -- Keyed per command so an Attack that reached nobody and a Pull that reached nobody are two
    -- separate reports, while an eight-group fan-out of the same command stays one line.
    if scope == "GROUP" and target and target ~= "" then
        showRTIMessageThrottled(
            "none:" .. command .. ":" .. tostring(target),
            localized("info.rti.none_ran_group", "Raid group %s: no Bot ran %s", tostring(target), command),
            1, 0.2, 0.2
        )
        return
    end

    if scope == "BOT" and target and target ~= "" then
        showRTIMessageThrottled(
            "none:" .. command .. ":bot",
            localized("info.rti.none_ran_bot", "%s did not run %s", tostring(target), command),
            1, 0.2, 0.2
        )
        return
    end

    showRTIMessageThrottled(
        "none:" .. command,
        localized("info.rti.none_ran", "No Bot ran: %s", command),
        1, 0.2, 0.2
    )
end

function MultiBot.RunStoredBotRTISelections(command)
    command = tostring(command or "")

    if command ~= "attack rti target" and command ~= "pull rti target" then
        return false
    end

    local names, markers = storedBotMarkerList()

    if #names <= 0 then
        showRTIMessage(MultiBot.L("info.rti.no_bot_selection", "No Bot has its own raid marker stored."), 1, 0.2, 0.2)
        updateBotRTIActionButton()
        return false
    end

    if not bridgeReady() then
        return false
    end

    local sent = 0
    local skipped = 0

    for _, botName in ipairs(names) do
        -- `rti target` resolves through the group's icon table, so a bot outside the group can never
        -- act on its marker: skip it instead of burning two throttled sends on it.
        if not isGroupedBot(botName) then
            skipped = skipped + 1
        else
            local icon = resolveStoredIcon(markers[botName])

            if icon and sendRTI("BOT", botName, "rti " .. icon.key, true) then
                sendRTI("BOT", botName, command)
                sent = sent + 1
            end
        end
    end

    if sent <= 0 then
        if skipped > 0 then
            showRTIMessage(
                MultiBot.L("info.rti.bots_not_grouped", "The Bots with a stored raid marker are not in your group."),
                1, 0.2, 0.2
            )
        else
            showRTIMessage(MultiBot.L("info.rti.no_bot_selection", "No Bot has its own raid marker stored."), 1, 0.2, 0.2)
        end

        updateBotRTIActionButton()
        return false
    end

    return true
end

-- Nothing else prunes the store: a bot that leaves the pool keeps its entry (and keeps the toolbar
-- button up) forever, and the addon has no reliable "is this still a bot" answer at load time.
-- An explicit reset is the honest way out.
function MultiBot.ClearStoredBotRTISelections()
    local names = storedBotMarkerList()
    local markers = botMarkers()

    for botName in pairs(markers) do
        markers[botName] = nil
    end

    for botName, button in pairs(botMarkerButtons) do
        -- Buttons from EveryBars that have since been rebuilt are dead but harmless: repainting a
        -- hidden frame costs nothing, and the live one is always the last registered under a name.
        if button then
            clearBotRTISelection(botName, button, rtiSelectorTexture())
        end
    end

    updateBotRTIActionButton()

    if #names > 0 then
        showRTIMessage(
            localized("info.rti.cleared_bot_selections", "Cleared the raid marker of %d Bot(s).", #names),
            0.4, 1, 0.4
        )
    end

    return #names
end

function MultiBot.BuildBotRTIActionUI(tLeft, x, y)
    if not tLeft or not tLeft.addButton or not tLeft.addFrame then
        return nil
    end

    local buttonX = x or MultiBot.GetLeftBarSlotX("BotRTI")
    local buttonY = y or 0

    local button = tLeft.addButton(
        "BotRTI",
        buttonX,
        buttonY,
        "achievement_pvp_p_01",
        localizedTip(
            "tips.rti.bot.action.title",
            "Per-Bot Marker Actions",
            "tips.rti.bot.action.body",
            "Orders every Bot that has its own raid marker stored to attack or pull the target carrying it."
        )
    ).doHide()

    -- Three rows of 30: Attack, Pull, Clear All.
    local frame = tLeft.addFrame("BotRTIAction", buttonX - 4, buttonY + 34, 24, 30, 94)
    frame._mbDropdownManaged = true
    frame:Hide()

    frame.addButton(
        "Attack",
        0,
        0,
        "ability_warrior_offensivestance",
        localizedTip(
            "tips.rti.bot.action.attack.title",
            "Attack Marked Targets",
            "tips.rti.bot.action.attack.body",
            "Every Bot with its own raid marker stored attacks the target carrying it."
        )
    ).doLeft = function()
        MultiBot.RunStoredBotRTISelections("attack rti target")
    end

    frame.addButton(
        "Pull",
        0,
        30,
        "ability_hunter_markedfordeath",
        localizedTip(
            "tips.rti.bot.action.pull.title",
            "Pull Marked Targets",
            "tips.rti.bot.action.pull.body",
            "Every Bot with its own raid marker stored pulls the target carrying it."
        )
    ).doLeft = function()
        MultiBot.RunStoredBotRTISelections("pull rti target")
    end

    frame.addButton(
        "ClearAll",
        0,
        60,
        rtiSelectorTexture(),
        localizedTip(
            "tips.rti.bot.action.clear.title",
            "Clear All Stored Markers",
            "tips.rti.bot.action.clear.body",
            "Forgets every per-Bot raid marker and hides this button again."
        )
    ).doLeft = function()
        MultiBot.ClearStoredBotRTISelections()
    end

    button.doRight = function(owner)
        MultiBot.ShowHideSwitch(owner.parent.frames["BotRTIAction"])
    end


    MultiBot.RTIBotActionButton = button
    MultiBot.RTIBotActionFrame = frame
    updateBotRTIActionButton()

    return {
        mainButton = button,
        frame = frame,
    }
end

-- Lives on the left toolbar now, not inside the Units ("PlayerBot Main Menu") panel: assigning an
-- RTI icon and firing attack/pull is a mid-pull action, and having to open the roster window first
-- made it two windows deep. The scope buttons are a vertical strip growing up off the bar (All,
-- raid groups 1-8, then Attack and Pull), matching every other toolbar dropdown.
function MultiBot.BuildRTIControlUI(tLeft, x, y)
    if not tLeft or not tLeft.addButton or not tLeft.addFrame then
        return nil
    end

    local buttonX = x or MultiBot.GetLeftBarSlotX("RTI")
    local buttonY = y or 0

    local mainButton = tLeft.addButton(
        "RTI",
        buttonX,
        buttonY,
        "Spell_ChargePositive",
        MultiBot.L("tips.units.rti", "RTI / Pull control")
    )

    -- 12 rows of 24px. Deliberately NOT _mbDropdownManaged: picking a scope opens that scope's
    -- icon menu, so the strip has to stay put instead of closing on the first click.
    local rtiFrame = tLeft.addFrame("RTIControl", buttonX - 5, buttonY + 34, 24, 24, RTI_STRIP_HEIGHT)
    rtiFrame:Hide()
    rtiFrame._mbSkipAutoCollapse = true

    local state = makeState()

    addScopeButton(
        rtiFrame,
        state,
        "ALL",
        "",
        0,
        RTI_ROW_ALL,
        "achievement_bg_winsoa",
        localizedTip(
            "tips.rti.all.title",
            "All Bots",
            "tips.rti.all.body",
            "The raid marker every Bot should focus."
        ),
        "A"
    )

    for groupIndex = 1, 8 do
        local groupKey = tostring(groupIndex)

        addScopeButton(
            rtiFrame,
            state,
            "GROUP",
            groupKey,
            0,
            groupIndex * RTI_ROW_STEP,
            "achievement_pvp_p_01",
            localizedTip(
                "tips.rti.group.title",
                "Raid Group %s",
                "tips.rti.group.body",
                "The raid marker raid group %s should focus.",
                groupKey
            ),
            groupKey
        )
    end

    addCcButton(rtiFrame, state, 0, RTI_ROW_CC, "spell_nature_polymorph")

    local attackButton = rtiFrame.addButton(
        "AttackSelectedRTITargets",
        0,
        RTI_ROW_ATTACK,
        "ability_warrior_offensivestance",
        localizedTip(
            "tips.rti.attack.target.title",
            "Attack Marked Target",
            "tips.rti.attack.target.body",
            "Orders the raid groups that carry a marker, or every Bot when none does, to attack it."
        )
    )
    attackButton.doLeft = function()
        runSelectedScopes(state, "attack rti target")
    end

    local pullButton = rtiFrame.addButton(
        "PullSelectedRTITargets",
        0,
        RTI_ROW_PULL,
        "ability_hunter_markedfordeath",
        localizedTip(
            "tips.rti.pull.target.title",
            "Pull Marked Target",
            "tips.rti.pull.target.body",
            "Orders the raid groups that carry a marker, or every Bot when none does, to pull it."
        )
    )
    pullButton.doLeft = function()
        runSelectedScopes(state, "pull rti target")
    end

    mainButton.doRight = function()
        if MultiBot.ShowHideSwitch(rtiFrame) then
            -- Only meaningful while the strip is up, and the raid can be reshuffled between two
            -- openings, so this is re-read every time instead of being hooked to roster events.
            refreshScopeAvailability(state)
            return
        end

        -- The strip is not _mbDropdownManaged, so closing it has to take its icon pickers with it.
        hideAllMenus(state, true)
    end

    return {
        rootButton = mainButton,
        frame = rtiFrame,
    }
end

function MultiBot.BuildBotRTIUI(parentFrame, botName, x, y)
    if not parentFrame or not parentFrame.addButton or not parentFrame.addFrame or not botName or botName == "" then
        return nil
    end

    local buttonX = x or 394
    local buttonY = y or 0
    local defaultTexture = rtiSelectorTexture()

    local rootButton = parentFrame.addButton(
        "RTI",
        buttonX,
        buttonY,
        defaultTexture,
        localizedTip(
            "tips.rti.bot.button.title",
            "Raid Marker",
            "tips.rti.bot.button.body",
            "The raid marker %s should focus.",
            botName
        )
    )

    -- One roster row up (rows are 34px apart) instead of the old 274px downward column, which left
    -- the screen entirely for the lower roster rows.
    local menuFrame = addIconStrip(
        parentFrame,
        "RTI",
        buttonX,
        buttonY + 34,
        defaultTexture,
        "",
        function(icon)
            return makeTip(
                localized("tips.rti.bot.icon.title", "Raid Marker: %s", iconLabel(icon)),
                localized("tips.rti.bot.icon.body", "Stores this raid marker for %s.", botName)
            )
        end,
        localizedTip(
            "tips.rti.default.title",
            "Clear Marker",
            "tips.rti.bot.default.body",
            "Clears the raid marker stored for %s.",
            botName
        ),
        function(icon)
            rememberBotRTISelection(botName, rootButton, icon)
            updateBotRTIActionButton()
        end,
        function()
            clearBotRTISelection(botName, rootButton, defaultTexture)
            updateBotRTIActionButton()
        end
    )

    restoreBotRTISelection(botName, rootButton, defaultTexture)
    botMarkerButtons[botName] = rootButton

    rootButton.doLeft = function()
        applyMarkerClick(
            rootButton._mbRtiSelectedIcon,
            localized("info.rti.no_bot_icon", "Pick a raid marker for %s first (right-click).", botName)
        )
    end

    rootButton.doRight = function()
        if MultiBot.ShowHideSwitch then
            MultiBot.ShowHideSwitch(menuFrame)
        elseif menuFrame:IsShown() then
            menuFrame:Hide()
        else
            menuFrame:Show()
        end
    end

    return {
        rootButton = rootButton,
        frame = menuFrame,
    }
end

if not MultiBot then return end

local PASSIVE_ICON = "Interface\\AddOns\\MultiBot\\Icons\\mode_passive.blp"
local GRIND_ICON = "Interface\\AddOns\\MultiBot\\Icons\\mode_grind.blp"
local STAY_ICON = "Interface\\AddOns\\MultiBot\\Icons\\command_stay.blp"
local FOLLOW_ICON = "Interface\\AddOns\\MultiBot\\Icons\\command_follow.blp"
local RTSC_ICON = "ability_hunter_markedfordeath"

-- Optional toolbar buttons: shown only when ticked in Options -> Layout. They sit at the far
-- (left) end of the bar, so toggling one never shifts the always-visible controls.
local OPTIONAL_TOOLBAR_BUTTONS = {
    { name = "Loot", frameName = "LootMenu" },
    { name = "Creator", frameName = "Creator" },
    { name = "Beast", frameName = "Beast" },
}

-- Passive / Grind / Stay / Follow all cancel each other server-side, so the lit state has to be
-- mirrored across the four buttons or the bar ends up claiming two mutually exclusive stances are
-- running at once. Filled in as each group of buttons is created; read at click time.
local stanceButtons = {}

local function slotX(name)
    if MultiBot.GetLeftBarSlotX then
        return MultiBot.GetLeftBarSlotX(name)
    end

    return 0
end

local function setStanceLit(key, lit)
    local button = stanceButtons[key]
    if not button then
        return
    end

    if lit then
        button.setEnable()
    else
        button.setDisable()
    end
end

-- "Combat Modes" used to be a single button whose meaning was picked from a right-click dropdown,
-- so the bar never showed which mode was actually live (and enabling the other one meant two
-- clicks in a submenu). Passive and Grind are two independent toggles now: what is lit is what is
-- running.
local function createCombatModeUI(tLeft)
    local passiveButton = tLeft.addButton("Passive", slotX("Passive"), 0, PASSIVE_ICON, MultiBot.L("tips.mode.passive")).setDisable()
    local grindButton = tLeft.addButton("Grind", slotX("Grind"), 0, GRIND_ICON, MultiBot.L("tips.mode.grind")).setDisable()

    stanceButtons.passive = passiveButton
    stanceButtons.grind = grindButton

    passiveButton.doLeft = function(button)
        if MultiBot.OnOffSwitch(button) then
            MultiBot.ActionToGroup("co +passive,?")
        else
            MultiBot.ActionToGroup("co -passive,?")
        end
    end

    grindButton.doLeft = function(button)
        if MultiBot.OnOffSwitch(button) then
            MultiBot.ActionToGroup("grind")
            -- A grinding bot picks its own targets and stops following, so neither Passive nor a
            -- stay/follow stance survives it.
            setStanceLit("passive", false)
            setStanceLit("stay", false)
            setStanceLit("follow", false)
            return
        end

        -- Leaving grind hands the bots back to the master, i.e. exactly the Follow stance.
        MultiBot.ActionToGroup("follow")
        setStanceLit("stay", false)
        setStanceLit("follow", true)
    end
end

-- Stay and Follow are two permanently visible buttons that light each other off. They replace the
-- old four-button arrangement (Stay/Follow swapped in place, plus a duplicate ExpandStay/
-- ExpandFollow pair selected by a main-menu "Expand" toggle).
local function createStayFollowUI(tLeft)
    local stayButton = tLeft.addButton("Stay", slotX("Stay"), 0, STAY_ICON, MultiBot.L("tips.expand.stay")).setDisable()
    local followButton = tLeft.addButton("Follow", slotX("Follow"), 0, FOLLOW_ICON, MultiBot.L("tips.expand.follow")).setEnable()

    stanceButtons.stay = stayButton
    stanceButtons.follow = followButton

    stayButton.doLeft = function(button)
        if MultiBot.ActionToGroup("stay") then
            followButton.setDisable()
            button.setEnable()
            -- Documented in tips.mode.passive: stay/follow cancel Passive Mode, and they end a
            -- grind run too.
            setStanceLit("passive", false)
            setStanceLit("grind", false)
        end
    end

    followButton.doLeft = function(button)
        if MultiBot.ActionToGroup("follow") then
            stayButton.setDisable()
            button.setEnable()
            setStanceLit("passive", false)
            setStanceLit("grind", false)
        end
    end
end

-- Moved off the "AddOn Configuration Menu": RTSC is a play-time toggle, so it belongs on the bar
-- next to the other combat controls. The RTSC row itself is anchored below the MultiBar and is
-- simply shown/hidden -- it never shoves the toolbar up and down the way the very first version
-- did, which is what made the toggle feel so odd.
local function toggleRTSC(button)
    local multiBar = MultiBot.frames and MultiBot.frames["MultiBar"]
    local rtscFrame = multiBar and multiBar.frames and multiBar.frames["RTSC"]
    if not rtscFrame then
        return
    end

    if MultiBot.OnOffSwitch(button) then
        rtscFrame:Show()
        -- Trains the master's marker spell and pulls the bots' real RTSC state (see
        -- UI/MultiBotRTSCUI.lua); falls back to the old chat command if that file is missing.
        if MultiBot.RTSCOnPanelOpen then
            MultiBot.RTSCOnPanelOpen()
        else
            MultiBot.ActionToGroup("rtsc")
        end
        return
    end

    rtscFrame:Hide()
    -- Deliberately NOT "rtsc reset": that wipes every saved location on every bot and untrains the
    -- master's marker spell. Closing the panel only drops the selection.
    if MultiBot.RTSCOnPanelClose then
        MultiBot.RTSCOnPanelClose()
    else
        MultiBot.ActionToGroup("rtsc cancel")
    end
end

local function createRTSCToggle(tLeft)
    local button = tLeft.addButton("RTSC", slotX("RTSC"), 0, RTSC_ICON, MultiBot.L("tips.main.rtsc")).setDisable()

    button.doRight = function(owner)
        toggleRTSC(owner)
    end

    return button
end

-- Show/hide the optional toolbar buttons from the saved Options -> Layout choice. Hiding a button
-- also closes its dropdown, which is what the removed main-menu toggles used to do.
function MultiBot.ApplyToolbarVisibility()
    local multibar = MultiBot.frames and MultiBot.frames["MultiBar"]
    local leftRoot = multibar and multibar.frames and multibar.frames["Left"]
    if not leftRoot then
        return false
    end

    for _, definition in ipairs(OPTIONAL_TOOLBAR_BUTTONS) do
        local visible = MultiBot.GetToolbarButtonVisible and MultiBot.GetToolbarButtonVisible(definition.name) or false
        local button = leftRoot.buttons and leftRoot.buttons[definition.name]
        local frame = leftRoot.frames and leftRoot.frames[definition.frameName]

        if frame and not visible then
            frame:Hide()
            if MultiBot.RequestClickBlockerUpdate then
                MultiBot.RequestClickBlockerUpdate(frame)
            end
        end

        if button then
            if visible then
                button.doShow()
            else
                button.doHide()
            end
        end
    end

    return true
end

function MultiBot.InitializeLeftCoreUI(tLeft)
    if not tLeft or not tLeft.addButton or not tLeft.addFrame then
        return nil
    end

    if MultiBot.BuildBotRTIActionUI then
        MultiBot.BuildBotRTIActionUI(tLeft, slotX("BotRTI"), 0)
    end

    if MultiBot.BuildRTIControlUI then
        MultiBot.BuildRTIControlUI(tLeft, slotX("RTI"), 0)
    end

    if MultiBot.BuildDisperseUI then
        MultiBot.BuildDisperseUI(tLeft)
    end

    if MultiBot.BuildLootUI then
        MultiBot.BuildLootUI(tLeft)
    end

    tLeft.addButton("Tanker", slotX("Tanker"), 0, "ability_warrior_shieldbash", MultiBot.L("tips.tanker.master")).doLeft = function()
        if MultiBot.isTarget() then
            MultiBot.ActionToGroup("@tank do attack my target")
        end
    end

    createCombatModeUI(tLeft)
    createStayFollowUI(tLeft)
    createRTSCToggle(tLeft)

    if MultiBot.BindShiftRightSwapButtons then
        MultiBot.BindShiftRightSwapButtons(tLeft, "LeftRoot", {
            { name = "BotRTI", id = "BotRTIActionButton", frameName = "BotRTIAction" },
            { name = "RTI", frameName = "RTIControl" },
            { name = "RTSC" },
            { name = "Disperse", frameName = "DisperseMenu" },
            { name = "Tanker" },
            { name = "Passive" },
            { name = "Grind" },
            { name = "Stay" },
            { name = "Follow" },
        })
    end

    return tLeft
end

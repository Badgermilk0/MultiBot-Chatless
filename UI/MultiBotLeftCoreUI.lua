if not MultiBot then return end

local MODE_FRAME_NAME = "Mode"
local MODE_BUTTON_NAME = "Mode"
local MODE_BUTTON_ICON = "Interface\\AddOns\\MultiBot\\Icons\\mode_passive.blp"
local MODE_FRAME_Y = 34

local STAY_ICON = "Interface\\AddOns\\MultiBot\\Icons\\command_stay.blp"
local FOLLOW_ICON = "Interface\\AddOns\\MultiBot\\Icons\\command_follow.blp"

-- Optional toolbar buttons: shown only when ticked in Options -> Layout. They sit at the far
-- (left) end of the bar, so toggling one never shifts the always-visible controls.
local OPTIONAL_TOOLBAR_BUTTONS = {
    { name = "Creator", frameName = "Creator" },
    { name = "Beast", frameName = "Beast" },
}

local function slotX(name)
    if MultiBot.GetLeftBarSlotX then
        return MultiBot.GetLeftBarSlotX(name)
    end

    return 0
end

local function bindModeToggleAction(modeButton, enableCommand, disableCommand)
    modeButton.setEnable().doLeft = function(button)
        if MultiBot.OnOffSwitch(button) then
            MultiBot.ActionToGroup(enableCommand)
        else
            MultiBot.ActionToGroup(disableCommand)
        end
    end
end

local function createModeUI(tLeft)
    local modeX = slotX(MODE_BUTTON_NAME)
    local modeButton = tLeft.addButton(MODE_BUTTON_NAME, modeX, 0, MODE_BUTTON_ICON, MultiBot.L("tips.mode.master")).setDisable()

    modeButton.doRight = function(button)
        MultiBot.ShowHideSwitch(button.parent.frames[MODE_FRAME_NAME])
    end

    modeButton.doLeft = function(button)
        if MultiBot.OnOffSwitch(button) then
            MultiBot.ActionToGroup("co +passive,?")
        else
            MultiBot.ActionToGroup("co -passive,?")
        end
    end

    local modeFrame = tLeft.addFrame(MODE_FRAME_NAME, modeX - 2, MODE_FRAME_Y)
    modeFrame:Hide()

    modeFrame.addButton("Passive", 0, 0, MODE_BUTTON_ICON, MultiBot.L("tips.mode.passive")).doLeft = function(button)
        if MultiBot.SelectToGroup(button.parent.parent, MODE_FRAME_NAME, button.texture, "co +passive,?") then
            bindModeToggleAction(button.parent.parent.buttons[MODE_BUTTON_NAME], "co +passive,?", "co -passive,?")
        end
    end

    modeFrame.addButton("Grind", 0, 30, "Interface\\AddOns\\MultiBot\\Icons\\mode_grind.blp", MultiBot.L("tips.mode.grind")).doLeft = function(button)
        if MultiBot.SelectToGroup(button.parent.parent, MODE_FRAME_NAME, button.texture, "grind") then
            bindModeToggleAction(button.parent.parent.buttons[MODE_BUTTON_NAME], "grind", "follow")
        end
    end
end

-- Stay and Follow are two permanently visible buttons that light each other off. They replace the
-- old four-button arrangement (Stay/Follow swapped in place, plus a duplicate ExpandStay/
-- ExpandFollow pair selected by a main-menu "Expand" toggle).
local function createStayFollowUI(tLeft)
    local stayButton = tLeft.addButton("Stay", slotX("Stay"), 0, STAY_ICON, MultiBot.L("tips.expand.stay")).setDisable()
    local followButton = tLeft.addButton("Follow", slotX("Follow"), 0, FOLLOW_ICON, MultiBot.L("tips.expand.follow")).setEnable()

    stayButton.doLeft = function(button)
        if MultiBot.ActionToGroup("stay") then
            followButton.setDisable()
            button.setEnable()
        end
    end

    followButton.doLeft = function(button)
        if MultiBot.ActionToGroup("follow") then
            stayButton.setDisable()
            button.setEnable()
        end
    end
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

    createModeUI(tLeft)
    createStayFollowUI(tLeft)

    if MultiBot.BindShiftRightSwapButtons then
        MultiBot.BindShiftRightSwapButtons(tLeft, "LeftRoot", {
            { name = "BotRTI", id = "BotRTIActionButton", frameName = "BotRTIAction" },
            { name = "Disperse", frameName = "DisperseMenu" },
            { name = "Loot", frameName = "LootMenu" },
            { name = "Tanker" },
            { name = "Mode", frameName = "Mode" },
            { name = "Stay" },
            { name = "Follow" },
        })
    end

    return tLeft
end

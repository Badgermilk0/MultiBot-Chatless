if not MultiBot then return end

local BEAST_ACTIONS = {
    { name = "Release", y = 0, icon = "spell_nature_spiritwolf", tip = "tips.beast.release", command = "cast 2641" },
    { name = "Revive", y = 30, icon = "ability_hunter_beastsoothe", tip = "tips.beast.revive", command = "cast 982" },
    { name = "Heal", y = 60, icon = "ability_hunter_mendpet", tip = "tips.beast.heal", command = "cast 48990" },
    { name = "Feed", y = 90, icon = "ability_hunter_beasttraining", tip = "tips.beast.feed", command = "cast 6991" },
    { name = "Call", y = 120, icon = "ability_hunter_beastcall", tip = "tips.beast.call", command = "cast 883" },
}

local BEAST_FRAME_NAME = "Beast"
local BEAST_FRAME_Y = 34
local BEAST_ROOT_ICON = "ability_mount_swiftredwindrider"

local function addBeastAction(beastFrame, definition)
    local button = beastFrame.addButton(definition.name, 0, definition.y, definition.icon, MultiBot.L(definition.tip))

    button.doLeft = function()
        MultiBot.ActionToTargetOrGroup(definition.command)
    end

    return button
end

function MultiBot.InitializeBeastUI(tLeft)
    if not tLeft or not tLeft.addButton or not tLeft.addFrame then
        return nil
    end

    local buttonX = MultiBot.GetLeftBarSlotX("Beast")
    -- Hidden until Options -> Layout says otherwise (MultiBot.ApplyToolbarVisibility).
    local rootButton = tLeft.addButton("Beast", buttonX, 0, BEAST_ROOT_ICON, MultiBot.L("tips.beast.master")).doHide()
    local beastFrame = tLeft.addFrame(BEAST_FRAME_NAME, buttonX - 2, BEAST_FRAME_Y)
    beastFrame:Hide()

    rootButton.doLeft = function(owner)
        MultiBot.ShowHideSwitch(owner.parent.frames[BEAST_FRAME_NAME])
    end

    for _, definition in ipairs(BEAST_ACTIONS) do
        addBeastAction(beastFrame, definition)
    end

    return {
        rootButton = rootButton,
        frame = beastFrame,
    }
end
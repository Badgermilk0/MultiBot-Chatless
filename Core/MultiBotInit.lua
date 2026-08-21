MultiBot.MB_PAGE_DEFAULT = string.format("%d/%d", 0, 0)

-- One-time left-toolbar layout invalidation. The bar has been re-slotted twice now (v2: Stay/Follow
-- collapsed from four buttons to two and the optional buttons moved to the far end; v3: the "Combat
-- Modes" button split into standalone Passive/Grind toggles, RTI and RTSC moved onto the bar, and
-- Loot became an optional button), so a layout saved by shift+right-click swapping on an older grid
-- would now stack buttons on top of each other; v4 re-ordered the whole bar. Drop it once per
-- revision; individual swaps can simply be redone. This has to run before InitializeLeftCoreUI,
-- which is where BindShiftRightSwapButtons reads the saved value back.
do
	local LEFT_BAR_SLOT_VERSION = 4
	local save = _G.MultiBotSave

	if type(save) == "table" and (tonumber(save.leftBarSlotVersion) or 0) < LEFT_BAR_SLOT_VERSION then
		save["ButtonLayout:LeftRoot"] = nil
		save.leftBarSlotVersion = LEFT_BAR_SLOT_VERSION

		if MultiBot.SetSavedLayoutValue then
			MultiBot.SetSavedLayoutValue("ButtonLayout:LeftRoot", nil)
		end
	end
end

-- MULTIBAR --
local tMultiBar = MultiBot.addFrame("MultiBar", -363, 144, 36)
MultiBot.PromoteFrame(tMultiBar)
tMultiBar:SetMovable(true)
tMultiBar:SetClampedToScreen(true)

-- LEFT --
local tLeft = tMultiBar.addFrame("Left", -76, 2, 32)
MultiBot.PromoteFrame(tLeft)

if MultiBot.InitializeLeftCoreUI then
	MultiBot.InitializeLeftCoreUI(tLeft)
end

MultiBot.BuildAttackUI(tLeft)

MultiBot.BuildFleeUI(tLeft)

if MultiBot.BuildFormationUI then
	MultiBot.BuildFormationUI(tLeft)
elseif MultiBot.dprint then
	MultiBot.dprint("INIT", "BuildFormationUI missing at init time")
end

if MultiBot.InitializeBeastUI then
	MultiBot.InitializeBeastUI(tLeft)
end

if MultiBot.InitializeCreatorUI then
	MultiBot.InitializeCreatorUI(tLeft)
end

-- Creator/Beast are optional toolbar buttons; apply the saved Options -> Layout choice now that
-- both exist.
if MultiBot.ApplyToolbarVisibility then
	MultiBot.ApplyToolbarVisibility()
end

if MultiBot.InitializeUnitsRootUI then
	MultiBot.InitializeUnitsRootUI(tMultiBar)
end

if MultiBot.InitializeMainUI then
	MultiBot.InitializeMainUI(tMultiBar)
end

MultiBot.BuildGmUI(tMultiBar)

-- RIGHT --
local tRight = tMultiBar.addFrame("Right", 34, 2, 32)
MultiBot.PromoteFrame(tRight)

MultiBot._lastIncMode  = "WHISPER"
MultiBot._lastCompMode = "WHISPER"
MultiBot._lastAllMode       = "WHISPER"
MultiBot._awaitingQuestsAll = false
MultiBot._buildingAllQuests = false
MultiBot._blockOtherQuests = false

if MultiBot.InitializeQuestsMenu then
    MultiBot.InitializeQuestsMenu(tRight)
end

if MultiBot.InitializeGroupActionsUI then
	MultiBot.InitializeGroupActionsUI(tRight)
end

MultiBot.InitializeInventoryFrame()

MultiBot.InitializeItemusFrame()

MultiBot.InitializeIconosFrame()

MultiBot.InitializeSpellBookFrame()

if MultiBot.InitializeCharacterInfoFrame then
	MultiBot.InitializeCharacterInfoFrame()
end

if MultiBot.InitializeBankFrame then
	MultiBot.InitializeBankFrame()
end

if MultiBot.InitializeRewardFrame then
	MultiBot.InitializeRewardFrame()
end

if MultiBot.InitializeTalentFrameModule then
    MultiBot.InitializeTalentFrameModule()
end

if MultiBot.InitializeRTSCUI then
	MultiBot.InitializeRTSCUI(tMultiBar)
end

MultiBot.state = true
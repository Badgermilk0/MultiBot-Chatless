-- Luacheck configuration
-- The game client runs stock Lua 5.1 (see the wotlk-335a-lua skill): checking against 5.3
-- accepted syntax and library calls that do not exist in-game.
std = "lua51"

exclude_files = {
   "Libs/**"
}

globals = {
    "MultiBot", "GetLocale", "GetSpellInfo", "GetSpellLink", "MultiBotSave", "SendChatMessage", "CreateFrame", "UIParent",
    "MultiBotGlobalSave", "DEFAULT_CHAT_FRAME", "C_Timer_After", "IsInRaid", "GetNumRaidMembers", "IsInGroup", "GetNumPartyMembers",
    "GetNumGroupMembers", "GetNumSubgroupMembers", "C_Timer", "UnitClass", "InspectUnit", "InspectFrame", "HideUIPanel",
    "tinsert", "strtrim", "wipe", "UnitName", "GetRealmName", "GameTooltip", "GameTooltip_Hide", "MultiBotDB", "SlashCmdList",
    "GetScreenWidth", "strsub", "strlen", "GetNumTalents", "UnitLevel", "IsSpellKnown", "GetInventoryItemLink",
    "GetItemInfo", "floor", "GetMacroInfo", "InCombatLockdown",
    "CreateMacro", "PickupMacro", "UnitSex", "UnitRace", "StaticPopupDialogs", "ACCEPT", "CANCEL", "StaticPopup_Show",
    "MultiBotPVPFrame", "GetItemIcon", "OKAY", "_MB_getIcon", "_MB_applyDesat", "_MB_applyDesatToTexture", "unpack",
	"CheckInteractDistance", "Minimap", "GetScreenHeight", "GetCursorPosition", "InterfaceOptionsFrame_OpenToCategory", "TimerAfter",
	"UnitExists", "UnitIsPlayer", "GuildRoster", "ShowFriends", "GetNumGuildMembers", "GetGuildRosterInfo", "GetNumFriends", "GetFriendInfo",
	"UnitFactionGroup", "IsUnitOnQuest", "GetNumQuestLogEntries", "GetQuestLink", "YES", "NO", "GetQuestLogTitle", "GetNumQuestLeaderBoards",
	"GetNumQuestLogEntries", "SelectQuestLogEntry", "SetAbandonQuest", "QuestLogPushQuest", "UIErrorsFrame", "SendAll", "CancelTrade", "InitiateTrade",
	"GetNumMacroIcons", "GetActiveTalentGroup", "GetTalentInfo", "GetUnspentTalentPoints", "GetTalentLink", "GetCursorInfo", "strsplit",
	"GetSpellTexture", "ClearCursor", "MBHunterPetPreview", "InterfaceOptionsFrame", "INTERFACEOPTIONS_ADDONCATEGORIES", "InterfaceOptionsFrame_AddCategory",
	"InterfaceOptions_AddCategory", "UIDropDownMenu_JustifyText", "UIDropDownMenu_SetSelectedValue", "UIDropDownMenu_SetButtonWidth", "UIDropDownMenu_SetWidth",
	"UIDropDownMenu_Initialize", "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo", "UIDropDownMenu_SetSelectedID", "SetRaidSubgroup", "GetRaidRosterInfo",
	"MouseIsOver", "UninviteUnit", "UnitInRaid", "UnitInGroup", "GetNumQuestChoices", "GetQuestItemLink", "GetQuestItemInfo", "SwapRaidSubgroup", "WorldMapButton",
	"UnitIsConnected", "event", "arg1", "arg2", "MultiBotSaved", "GetUnitName", "GetTime", "GetNumMacros", "ReloadUI", "GetQuestLogLeaderBoard", "AbandonQuest",
	"GetMacroIconInfo", "GetPlayerInfoByGUID", "UnitGUID", "ConvertToRaid", "UnitXPMax", "UnitXP", "UnitManaMax", "UnitMana",
	"GetCurrentMapContinent", "GetCurrentMapAreaID", "SLASH_MULTIBOT1", "SLASH_MULTIBOT2", "SLASH_MULTIBOT3", "SLASH_MULTIBOTOPTIONS1", "SLASH_MBFAKEGM1",
	"SLASH_MBCLASS1", "SLASH_MBCLASSTEST1", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth", "UIDropDownMenu_Initialize", "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton", "UIDropDownMenu_SetSelectedValue", "time", "ToggleDropDownMenu", "LibStub", "SendAddonMessage", "WorldFrame", "GetMouseFocus",
	"IsShiftKeyDown", "RAID_CLASS_COLORS", "ITEM", "UISpecialFrames", "IsControlKeyDown", "IsShiftKeyDown", "INV_SLOT_MAINHAND", "LoadAddOn", "ShowUIPanel", "HandleModifiedItemClick",
	"ChatFontNormal", "UnitIsDead", "GameFontHighlightSmall", "GameFontNormalSmall", "SEARCH", "UnitIsUnit", "INVENTORY_TOOLTIP", "BAGSLOT", "GetItemInfoInstant",
	"LE_ITEM_CLASS_QUESTITEM", "ITEMS", "LOADING", "QUEST_LOG", "INSPECT", "SPELLBOOK", "MB_TAB_TITLE_DEFAULT", "IsInGuild", "GetGuildInfo", "GetGuildRosterShowOffline",
	"SetGuildRosterShowOffline", "PLAYER","Ambiguate", "ChatFrame_AddMessageEventFilter", "ChatTypeInfo", "CLASS_ICON_TCOORDS", "GetLootSlotLink", "GetLootSlotInfo", "GetLootMethod", "GetMasterLootCandidate",
	"LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE", "date", "LootSlotIsCoin", "LootSlotIsItem", "GetNumLootItems", "GetItemQualityColor", "GiveMasterLoot", "GetLootThreshold",
	"QuestFrameRewardPanel", "QuestFrame", "GetFactionInfoByID", "PanelTemplates_SetTab", "PanelTemplates_SetNumTabs", "ABANDON_QUEST", "GetCoinTextureString",
	"RETRIEVING_ITEM_INFO", "SetRaidTarget", "GetRaidTargetIndex", "IsRaidLeader", "IsRaidOfficer"
	
}

read_globals = {
   math = {
      fields = {
         atan2 = {}
      }
   }
}

-- Disallow tab indentation
no_tab_indent = true

-- Indent with 4 spaces
indent_size = 4

-- Code-cleanliness options
unused_args = false
unused_vars = false
redefined_vars = false
unused_values = false

-- Disallow implicit globals
allow_defined_top = false

-- Treat 'self' as automatically used
self = true

-- Line length limit
max_line_length = 900
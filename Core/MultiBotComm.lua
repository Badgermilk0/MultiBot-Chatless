local MultiBot = _G.MultiBot
if not MultiBot then
  return
end

MultiBot.bridge = MultiBot.bridge or {}

local Comm = MultiBot.Comm or {}
MultiBot.Comm = Comm

Comm.prefix = "MBOT"
Comm.version = "2" -- v2: ROSTER streamed (ROSTER_BEGIN/ITEM/END); DETAILS/STATES always terminated.

local function safeNow()
  if type(GetTime) == "function" then
    return GetTime()
  end

  return 0
end

local function safeDelay(delaySeconds, callback)
  if type(callback) ~= "function" then
    return
  end

  if MultiBot and type(MultiBot.TimerAfter) == "function" then
    MultiBot.TimerAfter(delaySeconds or 0, callback)
    return
  end

  callback()
end

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end

  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function splitOnce(value, separator)
  if type(value) ~= "string" or value == "" then
    return "", ""
  end

  local startIndex, endIndex = string.find(value, separator, 1, true)
  if not startIndex then
    return value, ""
  end

  return string.sub(value, 1, startIndex - 1), string.sub(value, endIndex + 1)
end

local function urlDecodeField(value)
  if type(value) ~= "string" or value == "" then
    return ""
  end

  return (value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16) or 0)
  end))
end

local function urlEncodeField(value)
  value = tostring(value or "")
  return (value:gsub("([%%~\r\n])", function(ch)
    return string.format("%%%02X", string.byte(ch))
  end))
end

local function getPlayerName()
  if type(UnitName) ~= "function" then
    return nil
  end

  local name = UnitName("player")
  if type(name) ~= "string" or name == "" then
    return nil
  end

  return name
end

local function ensureBridgeState()
  local state = MultiBot.bridge
  state.connected = state.connected or false
  state.protocol = state.protocol or nil
  state.server = state.server or nil
  state.lastSendAt = state.lastSendAt or 0
  state.lastHelloAt = state.lastHelloAt or 0
  state.lastPingAt = state.lastPingAt or 0
  state.lastPongAt = state.lastPongAt or 0
  state.lastPingToken = state.lastPingToken or nil
  state.lastError = state.lastError or nil
  state.roster = state.roster or {}
  state.states = state.states or {}
  state.details = state.details or {}
  state.professions = state.professions or {}
  state.pvpStats = state.pvpStats or {}
  state.stats = state.stats or {}
  state.quests = state.quests or {}
  state.questSeq = state.questSeq or 0
  state.questActive = state.questActive or {}
  state.gameObjects = state.gameObjects or {}
  state.gameObjectSeq = state.gameObjectSeq or 0
  state.gameObjectActive = state.gameObjectActive or {}
  state.talentSpecs = state.talentSpecs or {}
  state.talentSpecSeq = state.talentSpecSeq or 0
  state.talentSpecActive = state.talentSpecActive or nil
  state.bootstrapPending = state.bootstrapPending or false
  state.bootstrapDeadline = state.bootstrapDeadline or 0
  state.inventorySeq = state.inventorySeq or 0
  state.inventoryActive = state.inventoryActive or nil
  state.bankItems = state.bankItems or {}
  state.bankSeq = state.bankSeq or 0
  state.bankActive = state.bankActive or nil
  state.guildBankItems = state.guildBankItems or {}
  state.guildBankSeq = state.guildBankSeq or 0
  state.guildBankActive = state.guildBankActive or nil
  state.inventoryItemActionSeq = state.inventoryItemActionSeq or 0
  state.inventoryItemActions = state.inventoryItemActions or {}
  state.spellbookSeq = state.spellbookSeq or 0
  state.spellbookActive = state.spellbookActive or nil
  state.botSkills = state.botSkills or {}
  state.botSkillSeq = state.botSkillSeq or 0
  state.botSkillActive = state.botSkillActive or nil
  state.botReputations = state.botReputations or {}
  state.botReputationSeq = state.botReputationSeq or 0
  state.botReputationActive = state.botReputationActive or nil
  state.botEmblems = state.botEmblems or {}
  state.botEmblemMoney = state.botEmblemMoney or {}
  state.botEmblemSeq = state.botEmblemSeq or 0
  state.botEmblemActive = state.botEmblemActive or nil
  state.professionRecipes = state.professionRecipes or {}
  state.professionRecipeSeq = state.professionRecipeSeq or 0
  state.professionRecipeActive = state.professionRecipeActive or nil
  state.professionRecipeCraftSeq = state.professionRecipeCraftSeq or 0
  state.professionRecipeCrafts = state.professionRecipeCrafts or {}
  state.outfitSeq = state.outfitSeq or 0
  state.outfitActive = state.outfitActive or nil
  state.outfitCommands = state.outfitCommands or {}
  state.trainerSeq = state.trainerSeq or 0
  state.trainerActive = state.trainerActive or nil
  state.trainerCommands = state.trainerCommands or {}
  state.trainerSpells = state.trainerSpells or {}
  state.glyphs = state.glyphs or {}
  state.glyphSeq = state.glyphSeq or 0
  state.glyphActive = state.glyphActive or nil
  state.rtiSeq = state.rtiSeq or 0
  state.combatSeq = state.combatSeq or 0
  state.positionSeq = state.positionSeq or 0
  state.lootSeq = state.lootSeq or 0
  return state
end

local function debugPrint(...)
  if MultiBot and MultiBot.dprint then
    MultiBot.dprint(...)
  end
end

local function L(key, fallback)
  if MultiBot and type(MultiBot.L) == "function" then
    return MultiBot.L(key, fallback)
  end

  return fallback or key
end

local function systemMessage(message)
  message = trim(message)
  if message == "" then
    return
  end

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(message)
  elseif type(print) == "function" then
    print(message)
  end
end

local function buildMessage(opcode, payload)
  local message = trim(opcode)
  if payload ~= nil and payload ~= "" then
    message = message .. "~" .. tostring(payload)
  end
  return message
end

-- Bridge send pacing (A2): a FIFO token-bucket so bursts of GET~/RUN~ requests
-- (bootstrap, or opening a bot's full panel which fires ~9 requests) are spread
-- out instead of being silently dropped by the client's addon-message throttle.
-- Reuses the same rate/burst the chat throttle (MultiBotThrottle.lua) uses.
local sendQueue = {}
local sendTokens = nil
local sendLastRefill = nil
local sendFlushArmed = false

local function throttleRate()
  local v = MultiBot and type(MultiBot.GetThrottleRate) == "function" and MultiBot.GetThrottleRate()
  if type(v) == "number" and v > 0 then
    return v
  end
  return 5
end

local function throttleBurst()
  local v = MultiBot and type(MultiBot.GetThrottleBurst) == "function" and MultiBot.GetThrottleBurst()
  if type(v) == "number" and v > 0 then
    return v
  end
  return 8
end

local function rawSend(item)
  if item.channel == "WHISPER" then
    SendAddonMessage(Comm.prefix, item.message, item.channel, item.target)
  else
    SendAddonMessage(Comm.prefix, item.message, item.channel)
  end

  -- Re-stamp the tracked request at actual transmission time: the send queue can hold a
  -- burst for several seconds, and the watchdog (SweepStaleRequests) must measure the wait
  -- for the REPLY, not time spent queued locally — otherwise a queued request could expire
  -- before it was ever sent and its reply would be rejected as stale.
  if item.pending and type(item.pending) == "table" then
    item.pending.startedAt = safeNow()
  end

  if MultiBot.bridge then
    MultiBot.bridge.lastSendAt = safeNow()
  end
  debugPrint("ADDON:TX", item.channel, item.opcode, item.payload or "")
end

local function drainSendQueue()
  local burst = throttleBurst()
  local now = safeNow()
  if sendTokens == nil then
    sendTokens = burst
    sendLastRefill = now
  else
    sendTokens = math.min(burst, sendTokens + (now - (sendLastRefill or now)) * throttleRate())
    sendLastRefill = now
  end

  while sendTokens >= 1 and #sendQueue > 0 do
    rawSend(table.remove(sendQueue, 1))
    sendTokens = sendTokens - 1
  end
end

-- Keep exactly one flush timer pending while the queue drains: sendFlushArmed only flips
-- inside the timer callback, so direct calls from Comm.Send never schedule duplicate timers.
local function scheduleFlush()
  if #sendQueue == 0 or sendFlushArmed or type(MultiBot.TimerAfter) ~= "function" then
    return
  end

  sendFlushArmed = true
  MultiBot.TimerAfter(1 / math.max(throttleRate(), 1), function()
    sendFlushArmed = false
    drainSendQueue()
    scheduleFlush()
  end)
end

-- `pending` (optional) is the watchdog-tracked request entry for this message; rawSend
-- re-stamps its startedAt when the message actually leaves the send queue.
function Comm.Send(opcode, payload, pending)
  ensureBridgeState()
  local playerName = getPlayerName()
  if not playerName or type(SendAddonMessage) ~= "function" then
    return false
  end

  local channel = "WHISPER"
  if type(GetNumRaidMembers) == "function" and GetNumRaidMembers() and GetNumRaidMembers() > 0 then
    channel = "RAID"
  elseif type(GetNumPartyMembers) == "function" and GetNumPartyMembers() and GetNumPartyMembers() > 0 then
    channel = "PARTY"
  end

  sendQueue[#sendQueue + 1] = {
    message = buildMessage(opcode, payload),
    channel = channel,
    target = playerName,
    opcode = opcode,
    payload = payload,
    pending = type(pending) == "table" and pending or nil,
  }
  drainSendQueue()
  scheduleFlush()
  return true
end

function Comm.SendHello()
  local state = ensureBridgeState()
  state.lastHelloAt = safeNow()
  return Comm.Send("HELLO", Comm.version)
end

function Comm.SendPing()
  local state = ensureBridgeState()
  local token = tostring(math.floor(safeNow() * 1000))
  state.lastPingToken = token
  state.lastPingAt = safeNow()
  return Comm.Send("PING", token)
end

function Comm.RequestRoster()
  return Comm.Send("GET", "ROSTER")
end

function Comm.RequestState(name)
  name = trim(name)
  if name == "" then
    return false
  end

  return Comm.Send("GET", "STATE~" .. name)
end

function Comm.RequestStates()
  return Comm.Send("GET", "STATES")
end

function Comm.RequestBotDetail(name)
  name = trim(name)
  if name == "" then
    return false
  end

  return Comm.Send("GET", "DETAIL~" .. name)
end

function Comm.RequestBotDetails()
  return Comm.Send("GET", "DETAILS")
end

function Comm.RequestStats(name)
  ensureBridgeState()

  name = trim(name)
  if name ~= "" then
    return Comm.Send("GET", "STATS~" .. name)
  end

  return Comm.Send("GET", "STATS")
end

function Comm.RequestTalentSpecList(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  if name == "" then
    return false
  end

  state.talentSpecSeq = (tonumber(state.talentSpecSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.talentSpecSeq)
  state.talentSpecActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "TALENT_SPEC_LIST~" .. name .. "~" .. token, state.talentSpecActive) then
    state.talentSpecActive = nil
    return false
  end

  return token
end

function Comm.RunRtiCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.rtiSeq = (tonumber(state.rtiSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.rtiSeq)

  return Comm.Send("RUN", "RTI~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RunCombatCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "BOT"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.combatSeq = (tonumber(state.combatSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.combatSeq)

  return Comm.Send("RUN", "COMBAT~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RunLootCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.lootSeq = (tonumber(state.lootSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-loot-" .. tostring(state.lootSeq)

  return Comm.Send("RUN", "LOOT~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RunPositionCommand(scope, target, command)
  local state = ensureBridgeState()

  if not state.connected then
    return false
  end

  command = trim(command or "")
  if command == "" then
    return false
  end

  scope = string.upper(trim(scope or "ALL"))
  target = trim(target or "")

  if scope ~= "ALL" and scope ~= "GROUP" and scope ~= "BOT" then
    return false
  end

  state.positionSeq = (tonumber(state.positionSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-position-" .. tostring(state.positionSeq)

  return Comm.Send("RUN", "POSITION~" .. scope .. "~" .. urlEncodeField(target) .. "~" .. token .. "~" .. urlEncodeField(command))
end

function Comm.RequestOutfits(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.outfitSeq = (tonumber(state.outfitSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.outfitSeq)
  state.outfitActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    lines = {},
  }

  if not Comm.Send("GET", "OUTFITS~" .. name .. "~" .. token, state.outfitActive) then
    state.outfitActive = nil
    return false
  end

  return true
end

function Comm.RunOutfitCommand(name, commandSuffix, persist)
  local state = ensureBridgeState()
  name = trim(name)
  commandSuffix = trim(commandSuffix)
  if name == "" or commandSuffix == "" or not state.connected then
    return false
  end

  state.outfitSeq = (tonumber(state.outfitSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-cmd-" .. tostring(state.outfitSeq)
  state.outfitCommands[token] = {
    botName = name,
    botNameKey = string.lower(name),
    command = commandSuffix,
    startedAt = safeNow(),
  }

  local persistToken = persist and "1" or "0"
  if not Comm.Send("RUN", "OUTFIT~" .. name .. "~" .. token .. "~" .. urlEncodeField(commandSuffix) .. "~" .. persistToken, state.outfitCommands[token]) then
    state.outfitCommands[token] = nil
    return false
  end

  return true
end

function Comm.RequestTrainer(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.trainerSeq = (tonumber(state.trainerSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-trainer-" .. tostring(state.trainerSeq)
  state.trainerActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    trainerEntry = 0,
    trainerName = "",
    startedAt = safeNow(),
    spells = {},
  }

  if not Comm.Send("GET", "TRAINER~" .. name .. "~" .. token, state.trainerActive) then
    state.trainerActive = nil
    return false
  end

  return true
end

function Comm.RunTrainerLearn(name, trainerEntry, spellId)
  local state = ensureBridgeState()
  name = trim(name)
  trainerEntry = tonumber(trainerEntry or 0) or 0

  local spellToken = trim(spellId)
  if spellToken == "" and tonumber(spellId or 0) then
    spellToken = tostring(tonumber(spellId or 0) or 0)
  end
  if string.upper(spellToken) ~= "ALL" then
    local numericSpellId = tonumber(spellToken or "0") or 0
    if numericSpellId <= 0 then
      return false
    end
    spellToken = tostring(numericSpellId)
  else
    spellToken = "ALL"
  end

  if name == "" or trainerEntry <= 0 or not state.connected then
    return false
  end

  state.trainerSeq = (tonumber(state.trainerSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-trainer-learn-" .. tostring(state.trainerSeq)
  state.trainerCommands[token] = {
    botName = name,
    botNameKey = string.lower(name),
    trainerEntry = trainerEntry,
    spellId = spellToken,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "TRAINER_LEARN~" .. name .. "~" .. token .. "~" .. trainerEntry .. "~" .. spellToken, state.trainerCommands[token]) then
    state.trainerCommands[token] = nil
    return false
  end

  return true
end

function Comm.RequestGlyphs(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  if name == "" then
    return false
  end

  state.glyphSeq = (tonumber(state.glyphSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.glyphSeq)
  state.glyphActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "GLYPHS~" .. name .. "~" .. token, state.glyphActive) then
    state.glyphActive = nil
    return false
  end

  return token
end

function Comm.RequestQuests(mode, name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  mode = string.upper(trim(mode or "ALL"))
  if mode ~= "INCOMPLETED" and mode ~= "COMPLETED" and mode ~= "ALL" then
    mode = "ALL"
  end

  name = trim(name)
  state.questSeq = (tonumber(state.questSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.questSeq)

  state.questActive[token] = {
    mode = mode,
    botName = name,
    isGroup = name == "",
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "QUESTS~" .. mode .. "~" .. name .. "~" .. token, state.questActive[token]) then
    state.questActive[token] = nil
    return false
  end

  return token
end

function Comm.RequestGameObjects(name)
  local state = ensureBridgeState()
  if not state.connected and not state.bootstrapPending then
    return false
  end

  name = trim(name)
  state.gameObjectSeq = (tonumber(state.gameObjectSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-gob-" .. tostring(state.gameObjectSeq)

  state.gameObjectActive[token] = {
    botName = name,
    isGroup = name == "",
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "GAMEOBJECTS~" .. name .. "~" .. token, state.gameObjectActive[token]) then
    state.gameObjectActive[token] = nil
    return false
  end

  return token
end

function Comm.RequestPvpStats(name)
  ensureBridgeState()

  name = trim(name)
  if name ~= "" then
    return Comm.Send("GET", "PVP_STATS~" .. name)
  end

  return Comm.Send("GET", "PVP_STATS")
end

function Comm.RequestInventory(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.inventorySeq = (tonumber(state.inventorySeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.inventorySeq)
  state.inventoryActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "INVENTORY~" .. name .. "~" .. token, state.inventoryActive) then
    state.inventoryActive = nil
    return false
  end

  return true
end

function Comm.RequestBank(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.bankSeq = (tonumber(state.bankSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-bank-" .. tostring(state.bankSeq)
  state.bankActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    error = nil,
  }

  if not Comm.Send("GET", "BANK~" .. name .. "~" .. token, state.bankActive) then
    state.bankActive = nil
    return false
  end

  return token
end

function Comm.RequestGuildBank(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.guildBankSeq = (tonumber(state.guildBankSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-gbank-" .. tostring(state.guildBankSeq)
  state.guildBankActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    error = nil,
  }

  if not Comm.Send("GET", "GBANK~" .. name .. "~" .. token, state.guildBankActive) then
    state.guildBankActive = nil
    return false
  end

  return token
end

function Comm.RequestSpellbook(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.spellbookSeq = (tonumber(state.spellbookSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.spellbookSeq)
  state.spellbookActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
  }

  if not Comm.Send("GET", "SPELLBOOK~" .. name .. "~" .. token, state.spellbookActive) then
    state.spellbookActive = nil
    return false
  end

  return true
end

function Comm.RequestBotSkills(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botSkillSeq = (tonumber(state.botSkillSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.botSkillSeq)
  state.botSkillActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
  }

  if not Comm.Send("GET", "BOT_SKILLS~" .. name .. "~" .. token, state.botSkillActive) then
    state.botSkillActive = nil
    return false
  end

  return true
end

function Comm.RequestBotReputations(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botReputationSeq = (tonumber(state.botReputationSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-rep-" .. tostring(state.botReputationSeq)
  state.botReputationActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
  }

  if not Comm.Send("GET", "BOT_REPUTATIONS~" .. name .. "~" .. token, state.botReputationActive) then
    state.botReputationActive = nil
    return false
  end

  return true
end

function Comm.RequestBotEmblems(name)
  local state = ensureBridgeState()
  name = trim(name)
  if name == "" or not state.connected then
    return false
  end

  state.botEmblemSeq = (tonumber(state.botEmblemSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-emblem-" .. tostring(state.botEmblemSeq)
  state.botEmblemActive = {
    botName = name,
    botNameKey = string.lower(name),
    token = token,
    startedAt = safeNow(),
    items = {},
    money = nil,
  }

  if not Comm.Send("GET", "BOT_EMBLEMS~" .. name .. "~" .. token, state.botEmblemActive) then
    state.botEmblemActive = nil
    return false
  end

  return true
end

function Comm.RequestProfessionRecipes(name, skillId)
  local state = ensureBridgeState()
  name = trim(name)
  skillId = tonumber(skillId or 0) or 0
  if name == "" or skillId <= 0 or not state.connected then
    return false
  end

  state.professionRecipeSeq = (tonumber(state.professionRecipeSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-" .. tostring(state.professionRecipeSeq)
  state.professionRecipeActive = {
    botName = name,
    botNameKey = string.lower(name),
    skillId = skillId,
    token = token,
    startedAt = safeNow(),
    recipes = {},
  }

  if not Comm.Send("GET", "PROFESSION_RECIPES~" .. name .. "~" .. skillId .. "~" .. token, state.professionRecipeActive) then
    state.professionRecipeActive = nil
    return false
  end

  return true
end

function Comm.RunProfessionRecipeCraft(name, skillId, spellId, itemId)
  local state = ensureBridgeState()
  name = trim(name)
  skillId = tonumber(skillId or 0) or 0
  spellId = tonumber(spellId or 0) or 0
  itemId = tonumber(itemId or 0) or 0
  if name == "" or skillId <= 0 or spellId <= 0 or itemId < 0 or not state.connected then
    return false
  end

  state.professionRecipeCraftSeq = (tonumber(state.professionRecipeCraftSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-craft-" .. tostring(state.professionRecipeCraftSeq)
  state.professionRecipeCrafts[token] = {
    botName = name,
    botNameKey = string.lower(name),
    skillId = skillId,
    spellId = spellId,
    itemId = itemId,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "CRAFT_RECIPE~" .. name .. "~" .. token .. "~" .. skillId .. "~" .. spellId .. "~" .. itemId, state.professionRecipeCrafts[token]) then
    state.professionRecipeCrafts[token] = nil
    return false
  end

  return token
end

function Comm.RunInventoryItemAction(name, action, itemId, count)
  local state = ensureBridgeState()
  name = trim(name)
  action = string.upper(trim(action))
  itemId = tonumber(itemId or 0) or 0
  count = tonumber(count or 0) or 0
  if name == "" or action == "" or itemId <= 0 or count < 0 or not state.connected then
    return false
  end

  state.inventoryItemActionSeq = (tonumber(state.inventoryItemActionSeq) or 0) + 1
  local token = tostring(math.floor(safeNow() * 1000)) .. "-item-" .. tostring(state.inventoryItemActionSeq)
  state.inventoryItemActions[token] = {
    botName = name,
    botNameKey = string.lower(name),
    action = action,
    itemId = itemId,
    count = count,
    startedAt = safeNow(),
  }

  if not Comm.Send("RUN", "ITEM_ACTION~" .. name .. "~" .. token .. "~" .. action .. "~" .. itemId .. "~" .. count, state.inventoryItemActions[token]) then
    state.inventoryItemActions[token] = nil
    return false
  end

  return token
end

-- Active bridge requests (D2/A1): single-shot slots hold one in-flight request each
-- (overwritten when a newer request of the same kind starts); the multi-tables hold
-- many keyed by token. Both entries carry startedAt, so a watchdog can expire any
-- whose reply never arrived (server restart, dropped addon message) instead of
-- leaking the multi-table entry forever and leaving the UI stuck "loading".
local SINGLE_SHOT_REQUEST_SLOTS = {
  "talentSpecActive", "inventoryActive", "bankActive", "guildBankActive",
  "spellbookActive", "botSkillActive", "botReputationActive", "botEmblemActive",
  "professionRecipeActive", "outfitActive", "trainerActive", "glyphActive",
}

local MULTI_REQUEST_TABLES = {
  "questActive", "gameObjectActive", "inventoryItemActions",
  "professionRecipeCrafts", "outfitCommands", "trainerCommands",
}

local function clearActiveRequests(state)
  for _, slot in ipairs(SINGLE_SHOT_REQUEST_SLOTS) do
    state[slot] = nil
  end
  for _, name in ipairs(MULTI_REQUEST_TABLES) do
    state[name] = {}
  end
end

local function requestTimeoutSeconds()
  local v = MultiBot and type(MultiBot.GetRequestTimeout) == "function" and MultiBot.GetRequestTimeout()
  if type(v) == "number" and v > 0 then
    return v
  end
  return 10
end

local function expireRequestEntry(kind, entry)
  debugPrint("ADDON:TIMEOUT", kind, entry and entry.botName or "")
  if type(MultiBot.OnBridgeRequestTimeout) == "function" then
    MultiBot.OnBridgeRequestTimeout(kind, entry)
  end
end

function Comm.SweepStaleRequests()
  local state = ensureBridgeState()
  local now = safeNow()
  local timeout = requestTimeoutSeconds()

  for _, slot in ipairs(SINGLE_SHOT_REQUEST_SLOTS) do
    local entry = state[slot]
    if type(entry) == "table" and type(entry.startedAt) == "number" and (now - entry.startedAt) > timeout then
      state[slot] = nil
      expireRequestEntry(slot, entry)
    end
  end

  for _, name in ipairs(MULTI_REQUEST_TABLES) do
    local tbl = state[name]
    if type(tbl) == "table" then
      for token, entry in pairs(tbl) do
        if type(entry) == "table" and type(entry.startedAt) == "number" and (now - entry.startedAt) > timeout then
          tbl[token] = nil
          expireRequestEntry(name, entry)
        end
      end
    end
  end
end

function Comm.StartRequestWatchdog()
  local state = ensureBridgeState()
  if state.watchdogArmed or type(MultiBot.TimerAfter) ~= "function" then
    return
  end
  state.watchdogArmed = true

  local function tick()
    Comm.SweepStaleRequests()
    MultiBot.TimerAfter(2.5, tick)
  end

  MultiBot.TimerAfter(2.5, tick)
end

-- Human-readable labels for the watchdog request kinds (slot / multi-table names).
local REQUEST_TIMEOUT_KIND_LABELS = {
  talentSpecActive = "talent specs",
  inventoryActive = "inventory",
  bankActive = "bank",
  guildBankActive = "guild bank",
  spellbookActive = "spellbook",
  botSkillActive = "skills",
  botReputationActive = "reputations",
  botEmblemActive = "emblems",
  professionRecipeActive = "profession recipes",
  outfitActive = "outfits",
  trainerActive = "trainer",
  glyphActive = "glyphs",
  questActive = "quests",
  gameObjectActive = "game objects",
  inventoryItemActions = "item action",
  professionRecipeCrafts = "recipe craft",
  outfitCommands = "outfit command",
  trainerCommands = "trainer learn",
}

local requestTimeoutLastNotifyAt = {}

-- If the Bank/Guild-Bank window is open on the request that just expired, replace its
-- "Loading..." status so the user is not left staring at a stuck panel.
local function notifyBankFrameTimeout(kind, entry)
  local frame = MultiBot.bankFrame
  if not (frame and frame.status and frame.status.SetText) then
    return
  end
  if frame.IsShown and not frame:IsShown() then
    return
  end

  local mode = (kind == "guildBankActive") and "gbank" or "bank"
  if frame.mode ~= mode then
    return
  end

  local botName = entry and entry.botName
  if botName and frame.botName and string.lower(tostring(frame.botName)) ~= string.lower(tostring(botName)) then
    return
  end

  frame.status:SetText(L("bridge.request.timeout.panel", "Request timed out (no bridge reply)."))
end

-- Called by expireRequestEntry when a tracked GET~/RUN~ request never got its reply
-- (server restart, dropped addon message). Without this the expiry was silent and any
-- panel waiting on the reply stayed on "Loading..." with no explanation.
function MultiBot.OnBridgeRequestTimeout(kind, entry)
  if kind == "bankActive" or kind == "guildBankActive" then
    notifyBankFrameTimeout(kind, entry)
  end

  -- One chat line per kind per 10s: a dead server expires several requests at once and
  -- the watchdog keeps sweeping, so unthrottled output would spam the chat frame.
  local now = safeNow()
  local lastAt = requestTimeoutLastNotifyAt[kind]
  if lastAt and (now - lastAt) < 10 then
    return
  end
  requestTimeoutLastNotifyAt[kind] = now

  local label = REQUEST_TIMEOUT_KIND_LABELS[kind] or tostring(kind or "request")
  local botName = entry and entry.botName
  local message
  if type(botName) == "string" and botName ~= "" then
    message = string.format(L("bridge.request.timeout.bot", "MultiBot: %s request for %s timed out (no bridge reply)."), label, botName)
  else
    message = string.format(L("bridge.request.timeout", "MultiBot: %s request timed out (no bridge reply)."), label)
  end

  systemMessage(message)
end

function Comm.MarkDisconnected(reason)
  local state = ensureBridgeState()
  state.connected = false
  state.server = nil
  state.protocol = nil
  state.lastError = reason or nil
  state.lastRosterSignature = nil
  state.rosterStream = nil
  clearActiveRequests(state)
end

local function parseBridgeDetailPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local race, rest2 = splitOnce(rest or "", "~")
  local gender, rest3 = splitOnce(rest2 or "", "~")
  local className, rest4 = splitOnce(rest3 or "", "~")
  local level, rest5 = splitOnce(rest4 or "", "~")
  local talent1, rest6 = splitOnce(rest5 or "", "~")
  local talent2, rest7 = splitOnce(rest6 or "", "~")
  local talent3, score = splitOnce(rest7 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    race = urlDecodeField(race),
    gender = urlDecodeField(gender),
    className = urlDecodeField(className),
    level = tonumber(level or "0") or 0,
    talent1 = tonumber(talent1 or "0") or 0,
    talent2 = tonumber(talent2 or "0") or 0,
    talent3 = tonumber(talent3 or "0") or 0,
    score = tonumber(score or "0") or 0,
    lastUpdateAt = safeNow(),
  }
end

local function parseBridgeProfessionPayload(payload)
  local name, professionPayload = splitOnce(payload or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  local professions = {}
  for token in string.gmatch(professionPayload or "", "([^;]+)") do
    token = trim(urlDecodeField(token))

    local profession, value = splitOnce(token, ":")
    profession = string.lower(trim(profession or ""))

    if profession ~= "" then
      professions[profession] = value ~= "" and value or true
    end
  end

  return {
    name = name,
    professions = professions,
    lastUpdateAt = safeNow(),
  }
end

local function parseRosterEntry(entry)
  local fields = {}
  for value in string.gmatch(entry or "", "([^,]+)") do
    fields[#fields + 1] = value
  end

  -- A7: a well-formed entry has 7 fields; log truncated/garbled ones instead of silently
  -- dropping them (still parsed leniently below, missing fields defaulting to 0).
  if #fields < 7 then
    debugPrint("ADDON:RX", "ROSTER_ENTRY_MALFORMED", entry or "")
  end

  -- The name is URL-encoded by the server (protocol v2); decoding a plain v1 name is a
  -- no-op, so this stays compatible with a single-message ROSTER from an older bridge.
  local name = trim(urlDecodeField(fields[1] or ""))
  if name == "" then
    return nil
  end

  return {
    name = name,
    classId = tonumber(fields[2] or "0") or 0,
    level = tonumber(fields[3] or "0") or 0,
    mapId = tonumber(fields[4] or "0") or 0,
    alive = fields[5] == "1",
    hpPct = tonumber(fields[6] or "0") or 0,
    mpPct = tonumber(fields[7] or "0") or 0,
  }
end

local function pruneCacheByRoster(cache, nameSet)
  if type(cache) ~= "table" then
    return
  end
  for key in pairs(cache) do
    if not nameSet[key] then
      cache[key] = nil
    end
  end
end

-- Shared roster commit: prune per-bot caches (A3), refresh the UI, and only re-pull
-- bot details when membership actually changed (A5). Used by both the legacy single
-- ROSTER message and the v2 ROSTER_BEGIN/ITEM/END stream.
local function commitRoster(state, roster)
  state.roster = roster

  local nameSet = {}
  local names = {}
  for _, entry in ipairs(roster) do
    local key = string.lower(entry.name)
    if not nameSet[key] then
      nameSet[key] = true
      names[#names + 1] = key
    end
  end

  pruneCacheByRoster(state.states, nameSet)
  pruneCacheByRoster(state.details, nameSet)
  pruneCacheByRoster(state.stats, nameSet)
  pruneCacheByRoster(state.pvpStats, nameSet)

  if MultiBot.SyncBridgeRosterToPlayers then
    MultiBot.SyncBridgeRosterToPlayers(roster)
  end

  table.sort(names)
  local signature = table.concat(names, ",")
  if state.connected and Comm.RequestBotDetails and signature ~= state.lastRosterSignature then
    state.lastRosterSignature = signature
    Comm.RequestBotDetails()
  end

  debugPrint("ADDON:RX", "ROSTER", tostring(#roster))
  return roster
end

-- Legacy single-message ROSTER (protocol v1): "name,class,...;name,class,..." .
function Comm.ApplyRosterPayload(payload)
  local state = ensureBridgeState()
  local roster = {}

  if type(payload) == "string" and payload ~= "" then
    for entry in string.gmatch(payload, "([^;]+)") do
      local parsed = parseRosterEntry(entry)
      if parsed then
        roster[#roster + 1] = parsed
      end
    end
  end

  return commitRoster(state, roster)
end

-- v2 chunked ROSTER stream: accumulate one ROSTER_ITEM per bot between BEGIN and END so
-- a large raid roster can never be truncated by the addon-message length limit.
function Comm.BeginRosterStream()
  ensureBridgeState().rosterStream = {}
end

function Comm.AppendRosterStreamItem(payload)
  local state = ensureBridgeState()
  if type(state.rosterStream) ~= "table" then
    state.rosterStream = {}
  end
  local parsed = parseRosterEntry(payload)
  if parsed then
    state.rosterStream[#state.rosterStream + 1] = parsed
  end
end

function Comm.EndRosterStream()
  local state = ensureBridgeState()
  local roster = state.rosterStream or {}
  state.rosterStream = nil
  return commitRoster(state, roster)
end

function Comm.ApplyStatePayload(payload)
  local state = ensureBridgeState()
  local name, rest = splitOnce(payload or "", "~")
  local combat, normal = splitOnce(rest or "", "~")

  name = trim(name)
  if name == "" then
    return nil
  end

  local entry = {
    name = name,
    combat = combat or "",
    normal = normal or "",
    lastUpdateAt = safeNow(),
  }

  state.states[string.lower(name)] = entry

  if MultiBot.ApplyBridgeBotState then
    MultiBot.ApplyBridgeBotState(name, entry.combat, entry.normal)
  end

  debugPrint("ADDON:RX", "STATE", name, entry.combat, entry.normal)
  return entry
end

-- v1/back-compat: a v2 server sends per-bot STATE packets plus an empty STATES terminator, never a
-- ';'-joined aggregate. Kept so a v2 addon still understands an older single-message bridge.
function Comm.ApplyStatesPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^;]+)") do
      if Comm.ApplyStatePayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "STATES", tostring(applied))
  return applied
end

function Comm.ApplyBotDetailPayload(payload)
  local state = ensureBridgeState()
  local detail = parseBridgeDetailPayload(payload)
  if not detail then
    return nil
  end

  local key = string.lower(detail.name)
  local existing = state.details[key]
  local professionEntry = state.professions[key]

  if type(existing) == "table" and type(existing.professions) == "table" then
    detail.professions = existing.professions
  end

  if type(professionEntry) == "table" and type(professionEntry.professions) == "table" then
    detail.professions = professionEntry.professions
  end

  state.details[key] = detail

  if MultiBot.ApplyBridgeBotDetail then
    MultiBot.ApplyBridgeBotDetail(detail)
  end

  debugPrint("ADDON:RX", "DETAIL", detail.name, detail.className or "", tostring(detail.level or 0), tostring(detail.score or 0))
  return detail
end

function Comm.ApplyBotProfessionPayload(payload)
  local state = ensureBridgeState()
  local entry = parseBridgeProfessionPayload(payload)
  if not entry then
    return nil
  end

  local key = string.lower(entry.name)
  state.professions[key] = entry

  local detail = state.details[key]
  if type(detail) == "table" then
    detail.professions = entry.professions
    detail.lastProfessionUpdateAt = entry.lastUpdateAt
  end

  if MultiBot.ApplyBridgeBotProfession then
    MultiBot.ApplyBridgeBotProfession(entry.name, entry.professions)
  end

  debugPrint("ADDON:RX", "PROFESSION", entry.name)
  return entry
end

-- v1/back-compat: a v2 server sends per-bot PROFESSION packets plus an empty PROFESSIONS terminator,
-- never a '|'-joined aggregate. Kept so a v2 addon still understands an older single-message bridge.
function Comm.ApplyBotProfessionsPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^|]+)") do
      if Comm.ApplyBotProfessionPayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "PROFESSIONS", tostring(applied))
  return applied
end

function Comm.ApplyBotDetailsPayload(payload)
  local applied = 0

  if type(payload) == "string" and payload ~= "" then
    for entryPayload in string.gmatch(payload, "([^;]+)") do
      if Comm.ApplyBotDetailPayload(entryPayload) then
        applied = applied + 1
      end
    end
  end

  debugPrint("ADDON:RX", "DETAILS", tostring(applied))
  return applied
end

local function parseStatsPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local level, rest2 = splitOnce(rest or "", "~")
  local gold, rest3 = splitOnce(rest2 or "", "~")
  local silver, rest4 = splitOnce(rest3 or "", "~")
  local copper, rest5 = splitOnce(rest4 or "", "~")
  local bagUsed, rest6 = splitOnce(rest5 or "", "~")
  local bagTotal, rest7 = splitOnce(rest6 or "", "~")
  local durabilityPct, rest8 = splitOnce(rest7 or "", "~")
  local xpPct, manaPct = splitOnce(rest8 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    level = tonumber(level or "0") or 0,
    gold = tonumber(gold or "0") or 0,
    silver = tonumber(silver or "0") or 0,
    copper = tonumber(copper or "0") or 0,
    bagUsed = tonumber(bagUsed or "0") or 0,
    bagTotal = tonumber(bagTotal or "0") or 0,
    durabilityPct = tonumber(durabilityPct or "0") or 0,
    xpPct = tonumber(xpPct or "0") or 0,
    manaPct = tonumber(manaPct or "0") or 0,
    lastUpdateAt = safeNow(),
  }
end

function Comm.ApplyStatsPayload(payload)
  local state = ensureBridgeState()
  local stats = parseStatsPayload(payload)
  if not stats then
    return nil
  end

  state.stats[string.lower(stats.name)] = stats

  if MultiBot.ApplyBridgeStats then
    MultiBot.ApplyBridgeStats(stats)
  end

  debugPrint(
    "ADDON:RX",
    "STATS",
    stats.name,
    tostring(stats.level or 0),
    tostring(stats.bagUsed or 0) .. "/" .. tostring(stats.bagTotal or 0),
    tostring(stats.durabilityPct or 0)
  )

  return stats
end

local function parsePvpStatsPayload(payload)
  local name, rest = splitOnce(payload or "", "~")
  local arenaPoints, rest2 = splitOnce(rest or "", "~")
  local honorPoints, rest3 = splitOnce(rest2 or "", "~")
  local team2v2, rest4 = splitOnce(rest3 or "", "~")
  local rating2v2, rest5 = splitOnce(rest4 or "", "~")
  local team3v3, rest6 = splitOnce(rest5 or "", "~")
  local rating3v3, rest7 = splitOnce(rest6 or "", "~")
  local team5v5, rating5v5 = splitOnce(rest7 or "", "~")

  name = trim(urlDecodeField(name))
  if name == "" then
    return nil
  end

  return {
    name = name,
    arenaPoints = tonumber(arenaPoints or "0") or 0,
    honorPoints = tonumber(honorPoints or "0") or 0,
    teams = {
      ["2v2"] = {
        team = urlDecodeField(team2v2),
        rating = tonumber(rating2v2 or "0") or 0,
      },
      ["3v3"] = {
        team = urlDecodeField(team3v3),
        rating = tonumber(rating3v3 or "0") or 0,
      },
      ["5v5"] = {
        team = urlDecodeField(team5v5),
        rating = tonumber(rating5v5 or "0") or 0,
      },
    },
    lastUpdateAt = safeNow(),
  }
end

function Comm.ApplyPvpStatsPayload(payload)
  local state = ensureBridgeState()
  local stats = parsePvpStatsPayload(payload)
  if not stats then
    return nil
  end

  state.pvpStats[string.lower(stats.name)] = stats

  if MultiBot.ApplyBridgePvpStats then
    MultiBot.ApplyBridgePvpStats(stats)
  end

  debugPrint(
    "ADDON:RX",
    "PVP_STATS",
    stats.name,
    tostring(stats.arenaPoints or 0),
    tostring(stats.honorPoints or 0)
  )

  return stats
end

local function ensureRuntimeTable(key)
  if MultiBot.Store and MultiBot.Store.EnsureRuntimeTable then
    return MultiBot.Store.EnsureRuntimeTable(key)
  end

  MultiBot[key] = type(MultiBot[key]) == "table" and MultiBot[key] or {}
  return MultiBot[key]
end

local function normalizeQuestMode(mode)
  mode = string.upper(trim(mode or "ALL"))
  if mode ~= "INCOMPLETED" and mode ~= "COMPLETED" and mode ~= "ALL" then
    mode = "ALL"
  end
  return mode
end

local function getActiveQuestRequest(token)
  local state = ensureBridgeState()
  token = trim(token)
  if token == "" then
    return nil
  end

  return state.questActive and state.questActive[token] or nil
end

local function buildQuestLink(questID, questName)
  questID = tonumber(questID or 0) or 0
  questName = tostring(questName or questID)
  return "|Hquest:" .. tostring(questID) .. ":0|h[" .. questName .. "]|h"
end

local function clearQuestStoresForMode(botName, mode)
  if type(botName) ~= "string" or botName == "" then
    return
  end

  mode = normalizeQuestMode(mode)

  if mode == "INCOMPLETED" or mode == "ALL" then
    ensureRuntimeTable("BotQuestsIncompleted")[botName] = {}
  end

  if mode == "COMPLETED" or mode == "ALL" then
    ensureRuntimeTable("BotQuestsCompleted")[botName] = {}
  end

  if mode == "ALL" then
    ensureRuntimeTable("BotQuestsAll")[botName] = {}
  end
end

function Comm.ApplyQuestBeginPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, mode = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)

  if botName == "" or not getActiveQuestRequest(token) then
    return false
  end

  clearQuestStoresForMode(botName, mode)
  debugPrint("ADDON:RX", "QUESTS_BEGIN", botName, mode)
  return true
end

function Comm.ApplyQuestItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local mode, rest3 = splitOnce(rest2 or "", "~")
  local status, rest4 = splitOnce(rest3 or "", "~")
  local questID, questName = splitOnce(rest4 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)
  status = string.upper(trim(status))
  questID = tonumber(questID or "0") or 0
  questName = trim(urlDecodeField(questName))
  if questName == "" then
    questName = tostring(questID)
  end

  if botName == "" or questID <= 0 or not getActiveQuestRequest(token) then
    return false
  end

  local incompletedStore = ensureRuntimeTable("BotQuestsIncompleted")
  local completedStore = ensureRuntimeTable("BotQuestsCompleted")
  local allStore = ensureRuntimeTable("BotQuestsAll")

  if status == "I" then
    incompletedStore[botName] = incompletedStore[botName] or {}
    incompletedStore[botName][questID] = questName
  elseif status == "C" then
    completedStore[botName] = completedStore[botName] or {}
    completedStore[botName][questID] = questName
  else
    return false
  end

  if mode == "ALL" then
    allStore[botName] = allStore[botName] or {}
    table.insert(allStore[botName], buildQuestLink(questID, questName))
  end

  debugPrint("ADDON:RX", "QUESTS_ITEM", botName, mode, status, tostring(questID))
  return true
end

function Comm.ApplyQuestEndPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, mode = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  mode = normalizeQuestMode(mode)

  if botName == "" or not getActiveQuestRequest(token) then
    return false
  end

  debugPrint("ADDON:RX", "QUESTS_END", botName, mode)
  return true
end

function Comm.ApplyQuestDonePayload(payload)
  local token, mode = splitOnce(payload or "", "~")
  token = trim(token)
  mode = normalizeQuestMode(mode)

  local state = ensureBridgeState()
  local request = getActiveQuestRequest(token)
  if not request then
    return false
  end

  state.questActive[token] = nil
  state.quests.lastMode = mode
  state.quests.lastDoneAt = safeNow()

  if MultiBot.OnBridgeQuestsDone then
    MultiBot.OnBridgeQuestsDone(mode, request)
  end

  debugPrint("ADDON:RX", "QUESTS_DONE", mode)
  return true
end

local function getActiveGameObjectRequest(token)
  local state = ensureBridgeState()
  token = trim(token)
  if token == "" then
    return nil
  end
  return state.gameObjectActive and state.gameObjectActive[token] or nil
end

function Comm.ApplyGameObjectBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  ensureRuntimeTable("LastGameObjectSearch")[botName] = {}
  debugPrint("ADDON:RX", "GAMEOBJECTS_BEGIN", botName)
  return true
end

function Comm.ApplyGameObjectItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, encodedLine = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  local store = ensureRuntimeTable("LastGameObjectSearch")
  store[botName] = store[botName] or {}
  table.insert(store[botName], urlDecodeField(encodedLine))
  return true
end

function Comm.ApplyGameObjectEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  if botName == "" or not getActiveGameObjectRequest(token) then
    return false
  end
  debugPrint("ADDON:RX", "GAMEOBJECTS_END", botName)
  return true
end

function Comm.ApplyGameObjectDonePayload(payload)
  local token = trim(payload or "")
  local state = ensureBridgeState()
  local request = getActiveGameObjectRequest(token)
  if not request then
    return false
  end
  state.gameObjectActive[token] = nil
  state.gameObjects.lastDoneAt = safeNow()
  if MultiBot.OnBridgeGameObjectsDone then
    MultiBot.OnBridgeGameObjectsDone(request)
  end
  debugPrint("ADDON:RX", "GAMEOBJECTS_DONE")
  return true
end

local function getActiveTalentSpecRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.talentSpecActive
  if type(active) ~= "table" then
    return nil
  end

  if trim(token) ~= trim(active.token or "") then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

function Comm.ApplyTalentSpecBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.talentSpecs[string.lower(botName)] = {}

  if MultiBot.ApplyBridgeTalentSpecBegin then
    MultiBot.ApplyBridgeTalentSpecBegin(botName, token)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_BEGIN", botName)
  return true
end

function Comm.ApplyTalentSpecItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local index, rest3 = splitOnce(rest2 or "", "~")
  local specName, build = splitOnce(rest3 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  index = tonumber(index or "0") or 0
  specName = trim(urlDecodeField(specName))
  build = trim(build)

  if botName == "" or specName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local entry = {
    index = index,
    name = specName,
    build = build,
  }

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.talentSpecs[key] = state.talentSpecs[key] or {}
  table.insert(state.talentSpecs[key], entry)

  if MultiBot.ApplyBridgeTalentSpecItem then
    MultiBot.ApplyBridgeTalentSpecItem(botName, token, entry)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_ITEM", botName, specName, build)
  return true
end

local function getActiveGlyphRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.glyphActive
  if type(active) ~= "table" then
    return nil
  end

  if trim(token) ~= trim(active.token or "") then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function applyBridgeGlyphs(botName, token)
  local state = ensureBridgeState()
  local key = string.lower(botName)
  local glyphs = state.glyphs[key] or {}

  table.sort(glyphs, function(a, b)
    return (tonumber(a.index) or 0) < (tonumber(b.index) or 0)
  end)

  MultiBot.receivedGlyphs = MultiBot.receivedGlyphs or {}
  MultiBot.receivedGlyphs[botName] = glyphs

  if MultiBot.awaitGlyphs == botName then
    MultiBot.awaitGlyphs = nil
  end

  if MultiBot.ApplyBridgeGlyphs then
    MultiBot.ApplyBridgeGlyphs(botName, glyphs, token)
  elseif MultiBot.talent and MultiBot.talent.OnBridgeGlyphs then
    MultiBot.talent.OnBridgeGlyphs(botName, token, glyphs)
  elseif MultiBot.talent and MultiBot.talent.name == botName and MultiBot.FillDefaultGlyphs then
    MultiBot.FillDefaultGlyphs()
  end
end

local function getActiveOutfitRequest(botName, token)
  local active = ensureBridgeState().outfitActive
  if not active then return nil end
  botName = trim(botName)
  token = trim(token)
  if token ~= active.token then return nil end
  if botName ~= "" and string.lower(botName) ~= active.botNameKey then return nil end
  return active
end

local function clearActiveOutfitRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveOutfitRequest(botName, token) then
    state.outfitActive = nil
  end
end

function Comm.ApplyOutfitsBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveOutfitRequest(botName, token) then
    return false
  end

  local active = getActiveOutfitRequest(botName, token)
  if active then
    active.botName = botName
    active.botNameKey = string.lower(botName)
    active.lines = {}
  end

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeBegin then
    MultiBot.OutfitUI:HandleBridgeBegin(botName, token)
  end

  debugPrint("ADDON:RX", "OUTFITS_BEGIN", botName)
  return true
end

function Comm.ApplyOutfitsItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, encodedLine = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  local active = getActiveOutfitRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  local rawLine = urlDecodeField(encodedLine)
  active.lines[#active.lines + 1] = rawLine

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeLine then
    MultiBot.OutfitUI:HandleBridgeLine(botName, token, rawLine)
  end

  debugPrint("ADDON:RX", "OUTFITS_ITEM", botName, rawLine)
  return true
end

function Comm.ApplyOutfitsEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveOutfitRequest(botName, token) then
    return false
  end

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeEnd then
    MultiBot.OutfitUI:HandleBridgeEnd(botName, token)
  end

  clearActiveOutfitRequest(botName, token)
  debugPrint("ADDON:RX", "OUTFITS_END", botName)
  return true
end

function Comm.ApplyOutfitCommandPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, result = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)
  result = trim(result)

  local state = ensureBridgeState()
  local command = state.outfitCommands and state.outfitCommands[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.result = result

  if MultiBot.OutfitUI and MultiBot.OutfitUI.HandleBridgeCommandResult then
    MultiBot.OutfitUI:HandleBridgeCommandResult(command.botName, token, result)
  end

  state.outfitCommands[token] = nil
  debugPrint("ADDON:RX", "OUTFITS_CMD", command.botName, result)
  return true
end

local function getActiveTrainerRequest(botName, token)
  local active = ensureBridgeState().trainerActive
  if not active then return nil end
  botName = trim(botName)
  token = trim(token)
  if token ~= active.token then return nil end
  if botName ~= "" and string.lower(botName) ~= active.botNameKey then return nil end
  return active
end

local function clearActiveTrainerRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveTrainerRequest(botName, token) then
    state.trainerActive = nil
  end
end

function Comm.ApplyTrainerBeginPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, trainerName = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  trainerName = trim(urlDecodeField(trainerName))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  active.botName = botName
  active.botNameKey = string.lower(botName)
  active.trainerEntry = trainerEntry
  active.trainerName = trainerName
  active.spells = {}

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeBegin then
    MultiBot.TrainerUI:HandleBridgeBegin(botName, token, trainerEntry, trainerName)
  end

  debugPrint("ADDON:RX", "TRAINER_BEGIN", botName, trainerEntry)
  return true
end

function Comm.ApplyTrainerItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local cost, canAfford = splitOnce(rest4 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  spellId = tonumber(spellId or "0") or 0
  cost = tonumber(cost or "0") or 0
  canAfford = tostring(canAfford or "0") == "1"

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active or spellId <= 0 then
    return false
  end

  local entry = {
    spellId = spellId,
    cost = cost,
    canAfford = canAfford,
    trainerEntry = trainerEntry,
  }
  active.spells[#active.spells + 1] = entry

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeLine then
    MultiBot.TrainerUI:HandleBridgeLine(botName, token, entry)
  end

  debugPrint("ADDON:RX", "TRAINER_ITEM", botName, spellId, cost, canAfford and 1 or 0)
  return true
end

function Comm.ApplyTrainerErrorPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, reason = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  reason = trim(urlDecodeField(reason))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  active.error = reason
  active.trainerEntry = trainerEntry

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeError then
    MultiBot.TrainerUI:HandleBridgeError(botName, token, reason, trainerEntry)
  end

  debugPrint("ADDON:RX", "TRAINER_ERROR", botName, reason)
  return true
end

function Comm.ApplyTrainerEndPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, trainerName = splitOnce(rest2 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  trainerName = trim(urlDecodeField(trainerName))

  local active = getActiveTrainerRequest(botName, token)
  if botName == "" or not active then
    return false
  end

  local state = ensureBridgeState()
  state.trainerSpells[string.lower(botName)] = active.spells or {}

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeEnd then
    MultiBot.TrainerUI:HandleBridgeEnd(botName, token, trainerEntry, trainerName, active.spells or {}, active.error)
  end

  clearActiveTrainerRequest(botName, token)
  debugPrint("ADDON:RX", "TRAINER_END", botName)
  return true
end

function Comm.ApplyTrainerLearnPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local trainerEntry, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local result, rest5 = splitOnce(rest4 or "", "~")
  local reason, rest6 = splitOnce(rest5 or "", "~")
  local learnedCount, spent = splitOnce(rest6 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  trainerEntry = tonumber(trainerEntry or "0") or 0
  spellId = trim(urlDecodeField(spellId))
  result = trim(result)
  reason = trim(urlDecodeField(reason))
  learnedCount = tonumber(learnedCount or "0") or 0
  spent = tonumber(spent or "0") or 0

  local state = ensureBridgeState()
  local command = state.trainerCommands and state.trainerCommands[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.trainerEntry = trainerEntry
  command.spellId = spellId
  command.result = result
  command.reason = reason
  command.learnedCount = learnedCount
  command.spent = spent

  if MultiBot.TrainerUI and MultiBot.TrainerUI.HandleBridgeLearnResult then
    MultiBot.TrainerUI:HandleBridgeLearnResult(command.botName, token, trainerEntry, spellId, result, reason, learnedCount, spent)
  end

  state.trainerCommands[token] = nil
  debugPrint("ADDON:RX", "TRAINER_LEARN", command.botName, spellId, result, reason)
  return true
end

function Comm.ApplyProfessionRecipeCraftPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local skillId, rest3 = splitOnce(rest2 or "", "~")
  local spellId, rest4 = splitOnce(rest3 or "", "~")
  local itemId, rest5 = splitOnce(rest4 or "", "~")
  local result, reason = splitOnce(rest5 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)
  skillId = tonumber(skillId or "0") or 0
  spellId = tonumber(spellId or "0") or 0
  itemId = tonumber(itemId or "0") or 0
  result = trim(result)
  reason = trim(urlDecodeField(reason))

  local state = ensureBridgeState()
  local command = state.professionRecipeCrafts and state.professionRecipeCrafts[token] or nil
  if not command then
    return false
  end

  command.botName = botName ~= "" and botName or command.botName
  command.botNameKey = string.lower(command.botName or "")
  command.skillId = skillId > 0 and skillId or command.skillId
  command.spellId = spellId > 0 and spellId or command.spellId
  command.itemId = itemId >= 0 and itemId or command.itemId
  command.result = result
  command.reason = reason

  if MultiBot.OnBridgeProfessionRecipeCraftResult then
    MultiBot.OnBridgeProfessionRecipeCraftResult(command.botName, command.skillId, command.spellId, command.itemId, result, reason, command)
  end

  state.professionRecipeCrafts[token] = nil
  debugPrint("ADDON:RX", "PROFESSION_RECIPE_CRAFT", command.botName, command.skillId, command.spellId, result, reason)
  return true
end

function Comm.ApplyGlyphsBeginPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.glyphs[string.lower(botName)] = {}

  debugPrint("ADDON:RX", "GLYPHS_BEGIN", botName)
  return true
end

function Comm.ApplyGlyphsItemPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, rest2 = splitOnce(rest or "", "~")
  local index, rest3 = splitOnce(rest2 or "", "~")
  local itemId, rest4 = splitOnce(rest3 or "", "~")
  local glyphId, rest5 = splitOnce(rest4 or "", "~")
  local spellId, glyphType = splitOnce(rest5 or "", "~")

  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  local entry = {
    index = tonumber(index or "0") or 0,
    id = tonumber(itemId or "0") or 0,
    itemId = tonumber(itemId or "0") or 0,
    glyphId = tonumber(glyphId or "0") or 0,
    spellId = tonumber(spellId or "0") or 0,
    type = trim(urlDecodeField(glyphType or "")),
  }

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.glyphs[key] = state.glyphs[key] or {}
  table.insert(state.glyphs[key], entry)

  debugPrint("ADDON:RX", "GLYPHS_ITEM", botName, entry.index, entry.itemId, entry.glyphId, entry.spellId, entry.type)
  return true
end

-- v1/back-compat: a v2 server streams glyphs as GLYPHS_BEGIN/ITEM/END, never this single
-- 'itemId:glyphId:spellId:type' GLYPHS blob. Kept for an older single-message bridge.
function Comm.ApplyGlyphsPayload(payload)
  local botName, rest = splitOnce(payload or "", "~")
  local token, entries = splitOnce(rest or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" then
    return false
  end

  local state = ensureBridgeState()
  local key = string.lower(botName)
  state.glyphs[key] = {}

  local fields = { strsplit("~", entries or "") }
  for i = 1, #fields do
    local raw = fields[i]
    if raw and raw ~= "" then
      local itemId, r1 = splitOnce(raw, ":")
      local glyphId, r2 = splitOnce(r1 or "", ":")
      local spellId, glyphType = splitOnce(r2 or "", ":")
      table.insert(state.glyphs[key], {
        index = #state.glyphs[key] + 1,
        id = tonumber(itemId or "0") or 0,
        itemId = tonumber(itemId or "0") or 0,
        glyphId = tonumber(glyphId or "0") or 0,
        spellId = tonumber(spellId or "0") or 0,
        type = trim(urlDecodeField(glyphType or "")),
      })
    end
  end

  applyBridgeGlyphs(botName, token)
  debugPrint("ADDON:RX", "GLYPHS", botName, #state.glyphs[key])
  return true
end

function Comm.ApplyGlyphsEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveGlyphRequest(botName, token) then
    return false
  end

  applyBridgeGlyphs(botName, token)

  local state = ensureBridgeState()
  state.glyphActive = nil

  debugPrint("ADDON:RX", "GLYPHS_END", botName)
  return true
end

function Comm.ApplyTalentSpecEndPayload(payload)
  local botName, token = splitOnce(payload or "", "~")
  botName = trim(urlDecodeField(botName))
  token = trim(token)

  if botName == "" or not getActiveTalentSpecRequest(botName, token) then
    return false
  end

  local state = ensureBridgeState()
  state.talentSpecActive = nil

  if MultiBot.ApplyBridgeTalentSpecEnd then
    MultiBot.ApplyBridgeTalentSpecEnd(botName, token)
  end

  debugPrint("ADDON:RX", "TALENT_SPEC_END", botName)
  return true
end

local function getActiveInventoryRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.inventoryActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(botName)) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveInventoryRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveInventoryRequest(botName, token) then
    state.inventoryActive = nil
  end
end

local function getActiveBankRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.bankActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(urlDecodeField(botName))) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveBankRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveBankRequest(botName, token) then
    state.bankActive = nil
  end
end

local function getActiveGuildBankRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.guildBankActive
  if not active then
    return nil
  end

  if trim(token) ~= trim(active.token) then
    return nil
  end

  if string.lower(trim(urlDecodeField(botName))) ~= tostring(active.botNameKey or "") then
    return nil
  end

  return active
end

local function clearActiveGuildBankRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveGuildBankRequest(botName, token) then
    state.guildBankActive = nil
  end
end

local function getInventoryFrame()
  return MultiBot and MultiBot.inventory or nil
end

local function getActiveSpellbookRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.spellbookActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function clearActiveSpellbookRequest(botName, token)
  local state = ensureBridgeState()
  if getActiveSpellbookRequest(botName, token) then
    state.spellbookActive = nil
  end
end

local function getSpellbookFrame()
  return MultiBot and MultiBot.spellbook or nil
end

local function getActiveBotSkillRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botSkillActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveBotReputationRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botReputationActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveBotEmblemRequest(botName, token)
  local state = ensureBridgeState()
  local active = state.botEmblemActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  return active
end

local function getActiveProfessionRecipeRequest(botName, token, skillId)
  local state = ensureBridgeState()
  local active = state.professionRecipeActive
  if type(active) ~= "table" then
    return nil
  end

  if botName and botName ~= "" and string.lower(trim(botName)) ~= trim(active.botNameKey or "") then
    return nil
  end

  if token and token ~= "" and tostring(token) ~= tostring(active.token or "") then
    return nil
  end

  if skillId and tonumber(skillId or 0) ~= tonumber(active.skillId or 0) then
    return nil
  end

  return active
end

local function parseRecipeMaterials(raw)
  local materials = {}
  for token in string.gmatch(raw or "", "([^;]+)") do
    local itemId, rest = splitOnce(token, ":")
    local required, available = splitOnce(rest or "", ":")
    table.insert(materials, {
      itemId = tonumber(itemId or "0") or 0,
      required = tonumber(required or "0") or 0,
      available = tonumber(available or "0") or 0,
    })
  end
  return materials
end

function Comm.HandleAddonMessage(prefix, message, distribution, sender)
  if prefix ~= Comm.prefix then
    return false
  end

  -- The bridge always routes its replies back to the requester, so a legitimate message's sender
  -- is always ourselves. Reject anything else (e.g. a grouped player whispering/party-broadcasting
  -- a crafted MBOT message) so it can't inject fake roster/state/etc. data into our UI. Fail open
  -- when the sender is unknown to avoid dropping any edge-case delivery path.
  if type(sender) == "string" and sender ~= "" then
    local selfName = getPlayerName()
    if selfName then
      local senderShort = (sender:gsub("%-.*$", ""))
      local selfShort = (selfName:gsub("%-.*$", ""))
      if senderShort ~= selfShort then
        debugPrint("ADDON:RX", "REJECT_SENDER", sender)
        return false
      end
    end
  end

  local state = ensureBridgeState()
  local opcode, payload = splitOnce(message or "", "~")
  opcode = string.upper(trim(opcode))

  if opcode == "HELLO_ACK" then
    local protocol, serverName = splitOnce(payload, "~")
    local wasConnected = state.connected == true

    state.connected = true
    state.protocol = protocol ~= "" and protocol or nil
    state.server = serverName ~= "" and serverName or nil
    state.lastError = nil
    debugPrint("ADDON:RX", "HELLO_ACK", payload or "")

    if (not wasConnected or state.bootstrapPending) and state.protocol then
      safeDelay(0.10, function()
        if MultiBot and MultiBot.bridge and MultiBot.bridge.connected then
          state.bootstrapPending = false
          state.bootstrapDeadline = 0
          if Comm.RequestRoster then
            Comm.RequestRoster()
          end
          if Comm.RequestStates then
            Comm.RequestStates()
          end
          if Comm.RequestBotDetails then
            Comm.RequestBotDetails()
          end
        end
      end)
    else
      state.bootstrapPending = false
      state.bootstrapDeadline = 0
    end

    return true
  end

  if opcode == "PONG" then
    state.connected = true
    state.lastPongAt = safeNow()
    state.lastError = nil
    state.bootstrapPending = false
    state.bootstrapDeadline = 0
    debugPrint("ADDON:RX", "PONG", payload or "")
    return true
  end

  if opcode == "ROSTER" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyRosterPayload(payload)
    return true
  end

  if opcode == "ROSTER_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.BeginRosterStream()
    return true
  end

  if opcode == "ROSTER_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.AppendRosterStreamItem(payload)
    return true
  end

  if opcode == "ROSTER_END" then
    state.connected = true
    state.lastError = nil
    Comm.EndRosterStream()
    return true
  end

  if opcode == "STATE" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatePayload(payload)
    return true
  end

  if opcode == "STATES" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatesPayload(payload)
    return true
  end

  if opcode == "DETAIL" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotDetailPayload(payload)
    return true
  end

  if opcode == "DETAILS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotDetailsPayload(payload)
    return true
  end

  if opcode == "PROFESSION" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotProfessionPayload(payload)
    return true
  end

  if opcode == "PROFESSIONS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyBotProfessionsPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecBeginPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecItemPayload(payload)
    return true
  end

  if opcode == "TALENT_SPEC_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyTalentSpecEndPayload(payload)
    return true
  end

  if opcode == "OUTFITS_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsBeginPayload(payload)
  end

  if opcode == "OUTFITS_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsItemPayload(payload)
  end

  if opcode == "OUTFITS_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitsEndPayload(payload)
  end

  if opcode == "OUTFITS_CMD" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyOutfitCommandPayload(payload)
  end

  if opcode == "TRAINER_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerBeginPayload(payload)
  end

  if opcode == "TRAINER_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerItemPayload(payload)
  end

  if opcode == "TRAINER_ERROR" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerErrorPayload(payload)
  end

  if opcode == "TRAINER_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerEndPayload(payload)
  end

  if opcode == "TRAINER_LEARN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyTrainerLearnPayload(payload)
  end

  if opcode == "GLYPHS_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsBeginPayload(payload)
    return true
  end

  if opcode == "GLYPHS_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsItemPayload(payload)
    return true
  end

  if opcode == "GLYPHS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsPayload(payload)
    return true
  end

  if opcode == "GLYPHS_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyGlyphsEndPayload(payload)
    return true
  end

  if opcode == "QUESTS_BEGIN" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestBeginPayload(payload)
    return true
  end

  if opcode == "QUESTS_ITEM" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestItemPayload(payload)
    return true
  end

  if opcode == "QUESTS_END" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestEndPayload(payload)
    return true
  end

  if opcode == "QUESTS_DONE" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyQuestDonePayload(payload)
    return true
  end

  if opcode == "PVP_STATS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyPvpStatsPayload(payload)
    return true
  end

  if opcode == "STATS" then
    state.connected = true
    state.lastError = nil
    Comm.ApplyStatsPayload(payload)
    return true
  end

  if opcode == "GAMEOBJECTS_BEGIN" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectBeginPayload(payload)
  end

  if opcode == "GAMEOBJECTS_ITEM" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectItemPayload(payload)
  end

  if opcode == "GAMEOBJECTS_END" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectEndPayload(payload)
  end

  if opcode == "GAMEOBJECTS_DONE" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyGameObjectDonePayload(payload)
  end

  if opcode == "INV_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      if inventory and inventory.beginPayload then
        inventory:beginPayload(trim(botName))
      end
    end

    return true
  end

  if opcode == "INV_SUMMARY" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local gold, rest3 = splitOnce(rest2 or "", "~")
    local silver, rest4 = splitOnce(rest3 or "", "~")
    local copper, rest5 = splitOnce(rest4 or "", "~")
    local bagUsed, bagTotal = splitOnce(rest5 or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      if inventory and inventory.applySummaryData then
        inventory:applySummaryData({
          gold = tonumber(gold or "0") or 0,
          silver = tonumber(silver or "0") or 0,
          copper = tonumber(copper or "0") or 0,
          bagUsed = tonumber(bagUsed or "0") or 0,
          bagTotal = tonumber(bagTotal or "0") or 0,
        })
      end
    end

    return true
  end

  if opcode == "INV_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      local itemsFrame = inventory and inventory.frames and inventory.frames.Items or nil
      if itemsFrame and itemsFrame.addChatItem then
        -- L-1: only accumulate here; INV_END repaints the canvas once for the whole batch.
        itemsFrame:addChatItem(urlDecodeField(encodedLine))
      end
    end

    return true
  end

  if opcode == "INV_END" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveInventoryRequest(botName, token) then
      local inventory = getInventoryFrame()
      local itemsFrame = inventory and inventory.frames and inventory.frames.Items or nil
      if itemsFrame then
        if itemsFrame.updateCanvas then
          itemsFrame:updateCanvas()
        end
        if itemsFrame.updateLayout then
          itemsFrame:updateLayout()
        end
      end
    end

    clearActiveInventoryRequest(botName, token)
    return true
  end

  if opcode == "BANK_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      active.items = {}
      active.error = nil
      if MultiBot.OnBridgeBankBegin then
        MultiBot.OnBridgeBankBegin(botName, token)
      end
    end

    return true
  end

  if opcode == "BANK_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      table.insert(active.items, urlDecodeField(encodedLine))
    end

    return true
  end

  if opcode == "BANK_ERROR" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, reason = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    reason = trim(urlDecodeField(reason))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      active.error = reason ~= "" and reason or "FAILED"
    end

    return true
  end

  if opcode == "BANK_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveBankRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.bankItems[key] = active.items or {}
      if MultiBot.OnBridgeBankItems then
        MultiBot.OnBridgeBankItems(botName, state.bankItems[key], active.error, token)
      end
    end

    clearActiveBankRequest(botName, token)
    return true
  end

  if opcode == "GBANK_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.items = {}
      active.error = nil
      if MultiBot.OnBridgeGuildBankBegin then
        MultiBot.OnBridgeGuildBankBegin(botName, token)
      end
    end

    return true
  end

  if opcode == "GBANK_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, encodedLine = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      table.insert(active.items, urlDecodeField(encodedLine))
    end

    return true
  end

  if opcode == "GBANK_ERROR" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, reason = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    reason = trim(urlDecodeField(reason))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.error = reason ~= "" and reason or "FAILED"
    end

    return true
  end

  if opcode == "GBANK_RIGHTS" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local canWithdraw, remaining = splitOnce(rest2 or "", "~")
    botName = trim(urlDecodeField(botName))
    canWithdraw = trim(canWithdraw)
    remaining = tonumber(remaining or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      active.rights = {
        canWithdraw = canWithdraw == "1" or string.lower(canWithdraw) == "true",
        remaining = remaining,
      }
    end

    return true
  end

  if opcode == "GBANK_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    state.connected = true
    state.lastError = nil

    local active = getActiveGuildBankRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.guildBankItems[key] = active.items or {}
      if MultiBot.OnBridgeGuildBankItems then
        MultiBot.OnBridgeGuildBankItems(botName, state.guildBankItems[key], active.error, token, active.rights)
      end
    end

    clearActiveGuildBankRequest(botName, token)
    return true
  end

  if opcode == "INVENTORY_ITEM_ACTION" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local action, rest3 = splitOnce(rest2 or "", "~")
    local itemId, rest4 = splitOnce(rest3 or "", "~")
    local result, rest5 = splitOnce(rest4 or "", "~")
    local reason, moved = splitOnce(rest5 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    action = string.upper(trim(action))
    itemId = tonumber(itemId or "0") or 0
    result = trim(result)
    reason = trim(urlDecodeField(reason))
    moved = tonumber(moved or "0") or 0
    state.connected = true
    state.lastError = nil

    local command = state.inventoryItemActions and state.inventoryItemActions[token] or nil
    if command then
      command.botName = botName ~= "" and botName or command.botName
      command.action = action ~= "" and action or command.action
      command.itemId = itemId > 0 and itemId or command.itemId
      command.result = result
      command.reason = reason
      command.moved = moved

      if MultiBot.OnBridgeInventoryItemActionResult then
        MultiBot.OnBridgeInventoryItemActionResult(command.botName, command.action, command.itemId, result, reason, moved, command)
      end

      state.inventoryItemActions[token] = nil
    end

    debugPrint("ADDON:RX", "INVENTORY_ITEM_ACTION", botName, action, itemId, result, reason, moved)
    return true
  end

  if opcode == "SB_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.beginPayload then
        spellbook:beginPayload(trim(botName))
      elseif MultiBot and MultiBot.beginSpellbookCollection then
        MultiBot.beginSpellbookCollection(trim(botName))
      end
    end

    return true
  end

  if opcode == "SB_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, spellId = splitOnce(rest or "", "~")

    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.appendSpellId then
        spellbook:appendSpellId(tonumber(spellId or "0") or 0, trim(botName))
      elseif MultiBot and MultiBot.addSpellById then
        MultiBot.addSpellById(tonumber(spellId or "0") or 0, trim(botName))
      end
    end

    return true
  end

  if opcode == "SB_END" then
    local botName, token = splitOnce(payload or "", "~")
    state.connected = true
    state.lastError = nil

    if getActiveSpellbookRequest(botName, token) then
      local spellbook = getSpellbookFrame()
      if spellbook and spellbook.finishPayload then
        spellbook:finishPayload()
      elseif MultiBot and MultiBot.finishSpellbookCollection then
        MultiBot.finishSpellbookCollection()
      end
    end

    clearActiveSpellbookRequest(botName, token)
    return true
  end

  if opcode == "BOT_SKILLS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      active.items = {}
    end

    return true
  end

  if opcode == "BOT_SKILLS_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local category, rest3 = splitOnce(rest2 or "", "~")
    local skillId, rest4 = splitOnce(rest3 or "", "~")
    local key, rest5 = splitOnce(rest4 or "", "~")
    local skillName, rest6 = splitOnce(rest5 or "", "~")
    local value, maxValue = splitOnce(rest6 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      table.insert(active.items, {
        category = trim(urlDecodeField(category)),
        skillId = tonumber(skillId or "0") or 0,
        key = trim(urlDecodeField(key)),
        name = trim(urlDecodeField(skillName)),
        value = tonumber(value or "0") or 0,
        max = tonumber(maxValue or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_SKILLS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotSkillRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botSkills[key] = active.items or {}
      if MultiBot.OnBridgeBotSkills then
        MultiBot.OnBridgeBotSkills(botName, state.botSkills[key], token)
      end
      state.botSkillActive = nil
    end

    return true
  end

  if opcode == "BOT_REPUTATIONS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      active.items = {}
    end

    return true
  end

  if opcode == "BOT_REPUTATION_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local factionId, rest3 = splitOnce(rest2 or "", "~")
    local factionName, rest4 = splitOnce(rest3 or "", "~")
    local rank, rest5 = splitOnce(rest4 or "", "~")
    local value, maxValue = splitOnce(rest5 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      table.insert(active.items, {
        factionId = tonumber(factionId or "0") or 0,
        name = trim(urlDecodeField(factionName)),
        rank = tonumber(rank or "0") or 0,
        value = tonumber(value or "0") or 0,
        max = tonumber(maxValue or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_REPUTATIONS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotReputationRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botReputations[key] = active.items or {}
      if MultiBot.OnBridgeBotReputations then
        MultiBot.OnBridgeBotReputations(botName, state.botReputations[key], token)
      end
      state.botReputationActive = nil
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_BEGIN" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      active.items = {}
      active.money = nil
    end

    return true
  end

  if opcode == "BOT_EMBLEM_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local itemId, count = splitOnce(rest2 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      table.insert(active.items, {
        itemId = tonumber(itemId or "0") or 0,
        count = tonumber(count or "0") or 0,
      })
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_MONEY" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, money = splitOnce(rest or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      active.money = tonumber(money or "0") or 0
    end

    return true
  end

  if opcode == "BOT_EMBLEMS_END" then
    local botName, token = splitOnce(payload or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    state.connected = true
    state.lastError = nil

    local active = getActiveBotEmblemRequest(botName, token)
    if active then
      local key = string.lower(botName)
      state.botEmblems[key] = active.items or {}
      state.botEmblemMoney[key] = active.money
      if MultiBot.OnBridgeBotEmblems then
        MultiBot.OnBridgeBotEmblems(botName, state.botEmblems[key], token, state.botEmblemMoney[key])
      end
      state.botEmblemActive = nil
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_BEGIN" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, skillId = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      active.recipes = {}
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_ITEM" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, rest2 = splitOnce(rest or "", "~")
    local skillId, rest3 = splitOnce(rest2 or "", "~")
    local spellId, rest4 = splitOnce(rest3 or "", "~")
    local itemId, rest5 = splitOnce(rest4 or "", "~")
    local difficulty, rest6 = splitOnce(rest5 or "", "~")
    local craftable, materials = splitOnce(rest6 or "", "~")

    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      table.insert(active.recipes, {
        skillId = skillId,
        spellId = tonumber(spellId or "0") or 0,
        itemId = tonumber(itemId or "0") or 0,
        difficulty = trim(urlDecodeField(difficulty)),
        craftable = tonumber(craftable or "0") or 0,
        materials = parseRecipeMaterials(urlDecodeField(materials)),
      })
    end

    return true
  end

  if opcode == "PROFESSION_RECIPES_END" then
    local botName, rest = splitOnce(payload or "", "~")
    local token, skillId = splitOnce(rest or "", "~")
    botName = trim(urlDecodeField(botName))
    token = trim(token)
    skillId = tonumber(skillId or "0") or 0
    state.connected = true
    state.lastError = nil

    local active = getActiveProfessionRecipeRequest(botName, token, skillId)
    if active then
      local key = string.lower(botName) .. ":" .. tostring(skillId)
      state.professionRecipes[key] = active.recipes or {}
      if MultiBot.OnBridgeProfessionRecipes then
        MultiBot.OnBridgeProfessionRecipes(botName, skillId, state.professionRecipes[key], token)
      end
      state.professionRecipeActive = nil
    end

    return true
  end

  if opcode == "PROFESSION_RECIPE_CRAFT" then
    state.connected = true
    state.lastError = nil
    return Comm.ApplyProfessionRecipeCraftPayload(payload)
  end

  if opcode == "RTI_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "RTI_ACK", payload or "")
    return true
  end

  if opcode == "COMBAT_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "COMBAT_ACK", payload or "")
    return true
  end

  if opcode == "POSITION_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "POSITION_ACK", payload or "")

    local rest = select(2, splitOnce(payload or "", "~"))
    local rest2 = select(2, splitOnce(rest, "~"))
    local rest3 = select(2, splitOnce(rest2, "~"))
    local executedText, encodedCommand = splitOnce(rest3, "~")
    local executed = tonumber(executedText) or 0
    local command = trim(urlDecodeField(encodedCommand))

    if executed > 0 then
      local distance = string.match(command, "^disperse set%s+(.+)$")

      if distance then
        systemMessage(string.format(
          L("disperse.confirm.set", "Disperse set to %s yards."),
          distance
        ))
      elseif command == "disperse disable" then
        systemMessage(L("disperse.confirm.disable", "Disperse disabled."))
      end
    end

    return true
  end

  if opcode == "LOOT_ACK" then
    state.connected = true
    state.lastError = nil
    debugPrint("ADDON:RX", "LOOT_ACK", payload or "")

    local rest = select(2, splitOnce(payload or "", "~"))
    local rest2 = select(2, splitOnce(rest, "~"))
    local rest3 = select(2, splitOnce(rest2, "~"))
    local executedText, encodedCommand = splitOnce(rest3, "~")
    local executed = tonumber(executedText) or 0
    local command = string.lower(trim(urlDecodeField(encodedCommand)))

    if executed <= 0 then
      systemMessage(L("loot.confirm.none", "Loot command was not applied to any bot."))
      return true
    end

    if MultiBot.OnLootCommandApplied then
      MultiBot.OnLootCommandApplied(command, executed)
    end

    if command == "nc +loot" then
      systemMessage(string.format(L("loot.confirm.enable", "Loot enabled for %d bot(s)."), executed))
      return true
    end

    if command == "nc -loot" then
      systemMessage(string.format(L("loot.confirm.disable", "Loot disabled for %d bot(s)."), executed))
      return true
    end

    local profile = command:match("^ll%s+([%w_%-]+)$")
    if profile then
      local profileName = ({
        all = L("loot.profile.all", "All"),
        normal = L("loot.profile.normal", "Normal"),
        gray = L("loot.profile.gray", "Gray"),
        quest = L("loot.profile.quest", "Quest"),
        skill = L("loot.profile.skill", "Skill"),
      })[profile] or profile

      systemMessage(string.format(L("loot.confirm.profile", "Loot profile set to %s for %d bot(s)."), profileName, executed))
    end

    return true
  end

  if opcode == "ERR" then
    state.lastError = payload
    debugPrint("ADDON:RX", "ERR", payload or "")
    return true
  end

  debugPrint("ADDON:RX", opcode, payload or "")
  return true
end

local function dispatchBootstrapRequests()
  Comm.SendHello()
  Comm.SendPing()
  Comm.RequestRoster()
  if Comm.RequestStates then
    Comm.RequestStates()
  end
  if Comm.RequestBotDetails then
    Comm.RequestBotDetails()
  end
end

function Comm.OnPlayerEnteringWorld()
  local state = ensureBridgeState()
  -- Reset snapshot caches (per-bot data). In-flight request slots/tables are cleared by
  -- Comm.MarkDisconnected -> clearActiveRequests below, so they're not repeated here.
  state.states = {}
  state.details = {}
  state.stats = {}
  state.pvpStats = {}
  state.quests = {}
  state.gameObjects = {}
  state.talentSpecs = {}
  state.botSkills = {}
  state.botReputations = {}
  state.botEmblems = {}
  state.botEmblemMoney = {}
  state.professionRecipes = {}
  state.trainerSpells = {}
  Comm.MarkDisconnected(nil)
  Comm.StartRequestWatchdog()
  state.bootstrapPending = true
  state.bootstrapDeadline = safeNow() + 4.0

  local function expireBootstrap()
    local bridge = ensureBridgeState()
    if not bridge.connected and bridge.bootstrapPending and bridge.bootstrapDeadline > 0 and safeNow() >= bridge.bootstrapDeadline then
      bridge.bootstrapPending = false
      bridge.bootstrapDeadline = 0
    end
  end

  if not MultiBot.TimerAfter then
    dispatchBootstrapRequests()
    expireBootstrap()
    return
  end

  dispatchBootstrapRequests()

  MultiBot.TimerAfter(1.0, function()
    dispatchBootstrapRequests()
  end)

  MultiBot.TimerAfter(4.1, expireBootstrap)
end

ensureBridgeState()
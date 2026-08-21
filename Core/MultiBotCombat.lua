-- MultiBotCombat.lua
-- Combat-lockdown shim.
--
-- Some MultiBot buttons are built from a *secure* template: every button on the RTSC row passes
-- "SecureActionButtonTemplate" to `newButton` explicitly, `catButton` uses it always, and
-- `newButton`'s own default is ActionButtonTemplate. That is what makes `addMacro`'s
-- SetAttribute("type1", "macro") actually cast -- the RTSC marker spell depends on it. The client
-- flags such frames "protected": while the player is in combat (`InCombatLockdown()`), insecure
-- code may not show, hide, move, resize, reparent or re-attribute them. The blocked call raises
-- ADDON_ACTION_BLOCKED, and that error aborts the *whole* script handler it happened in. Which
-- buttons end up protected is decided by the client, not guessed at here: every wrapper below
-- asks `IsProtected()` at call time.
--
-- That is what made button presses "do nothing in combat". `newButton`'s PostClick script opens
-- with the pressed-look SetPoint/SetSize, so in combat the block killed the handler before it
-- ever reached `doLeft`/`doRight` -- the actual action. OnLeave (restore the size) and any
-- roster relayout that ran mid-fight had the same problem.
--
-- `MultiBot.MakeCombatSafe(widget)` swaps the protected widget methods for wrappers that run the
-- call when it is legal, and otherwise remember it and replay it on PLAYER_REGEN_ENABLED. Nothing
-- throws any more, so the click action always runs and the cosmetic half catches up when combat
-- drops. On an unprotected widget every wrapper is a straight pass-through, so it is safe to
-- apply to anything.
--
-- Applied at the two factories that can produce a protected frame -- `MultiBot.newButton` and
-- `MultiBot.catButton` in MultiBotEngine.lua -- and nowhere else. `newFrame`/`wowButton`/
-- `movButton`/`boxButton` build insecure widgets on parents that chain up to the (unprotected)
-- MultiBot root, so they can never be protected; wrapping them would only put insecure closures
-- in front of methods Blizzard code calls itself (MultiBot windows sit in UISpecialFrames, which
-- ESC walks from a secure path) for no gain.
--
-- What this cannot fix:
-- * A *protected client API* the action itself needs (CreateMacro, PickupMacro, ...). Those are
--   blocked whatever frame asks, so they have to say so -- see MultiBot.WarnCombatLocked below.
-- * Showing, hiding or moving a protected button *during* the fight. The call is remembered and
--   applied the moment combat ends, but no addon can make it happen sooner without rebuilding the
--   bar on SecureHandler state drivers. What a click *does* is unaffected -- only a button
--   appearing, vanishing or sliding mid-combat waits.

MultiBot = MultiBot or {}

-- Deferred calls are keyed, so a mid-fight burst of relayouts replays once per slot instead of
-- hundreds of times. The cap is a backstop against a runaway loop; it is not expected to be hit.
local PENDING_LIMIT = 4000

local pending = {}
local pendingByKey = {}
local pendingCount = 0

-- Explicit length, so nils in the middle of an argument list survive the round trip
-- (SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", x, y) has optional holes).
local function pack(...)
  return { n = select("#", ...), ... }
end

local function debugPrint(message)
  local debugApi = MultiBot and MultiBot.Debug
  if type(debugApi) == "table" and type(debugApi.Print) == "function" then
    debugApi.Print("core", message)
  end
end

-- Which pending call a new one replaces.
-- * SetPoint and SetAttribute own one slot *per first argument*: the click blocker anchors both
--   BOTTOMRIGHT and TOPLEFT, and a cast button sets "type1", "shift-type1" and "ctrl-type1".
--   Keying those by method alone would silently drop all but the last.
-- * Show and Hide share one slot, so a Show/Hide/Show burst replays as a single Show instead of
--   replaying the first Show and then the stale Hide.
local function callKey(widget, method, first)
  if method == "SetPoint" or method == "SetAttribute" then
    return tostring(widget) .. "/" .. method .. "/" .. tostring(first)
  end

  if method == "Show" or method == "Hide" then
    return tostring(widget) .. "/visibility"
  end

  return tostring(widget) .. "/" .. method
end

-- ClearAllPoints wipes the anchors, so every SetPoint still waiting on this widget is dead: keep
-- them and the replay would re-apply anchors the caller had just thrown away.
local function dropQueuedAnchors(widget)
  for index = 1, #pending do
    local entry = pending[index]
    if entry and not entry.dead and entry.widget == widget
      and (entry.method == "SetPoint" or entry.method == "SetAllPoints") then
      entry.dead = true
      pendingByKey[entry.key] = nil
      pendingCount = pendingCount - 1
    end
  end
end

local function queueCall(widget, method, ...)
  if method == "ClearAllPoints" then
    dropQueuedAnchors(widget)
  end

  local key = callKey(widget, method, ...)
  local entry = pendingByKey[key]

  -- Replaced in place, never appended: the queue has to replay in the order the calls were first
  -- made, or a ClearAllPoints queued early would run after the SetPoint that followed it.
  if entry then
    entry.method = method
    entry.args = pack(...)
    return
  end

  if pendingCount >= PENDING_LIMIT then
    return
  end

  entry = { widget = widget, method = method, args = pack(...), key = key }
  pending[#pending + 1] = entry
  pendingByKey[key] = entry
  pendingCount = pendingCount + 1
end

local function flushPending()
  if #pending == 0 then
    return
  end

  local queued = pending
  local replayed = pendingCount

  pending = {}
  pendingByKey = {}
  pendingCount = 0

  for index = 1, #queued do
    local entry = queued[index]
    if entry and not entry.dead then
      local widget = entry.widget
      local natives = widget and widget._mbNatives
      local native = natives and natives[entry.method]
      -- The native, not the wrapper: a widget destroyed or reparented mid-fight must not be able
      -- to re-queue itself out of the replay loop.
      if native then
        pcall(native, widget, unpack(entry.args, 1, entry.args.n))
      end
    end
  end

  debugPrint("combat: replayed " .. tostring(replayed) .. " deferred widget calls")
end

-- The frame methods the client refuses from insecure code during combat. Everything not listed
-- (SetTexture, SetDesaturated, SetVertexColor, SetAlpha, SetText, ...) is never blocked and is
-- deliberately left alone.
local PROTECTED_METHODS = {
  "Show", "Hide",
  "SetPoint", "ClearAllPoints", "SetAllPoints",
  "SetSize", "SetWidth", "SetHeight", "SetScale",
  "SetParent", "SetFrameLevel", "SetFrameStrata", "Raise", "Lower",
  "EnableMouse", "EnableKeyboard", "RegisterForClicks", "RegisterForDrag",
  "SetAttribute", "SetID",
}

-- One shared wrapper per method, never a closure per widget: a full 40-man roster is well over a
-- thousand buttons. The wrapper reaches the real method through `_mbNatives`, a table shared by
-- every widget of the same object type.
local wrappers = {}
local nativesByType = {}

local function isLocked(widget)
  if type(InCombatLockdown) ~= "function" or not InCombatLockdown() then
    return false
  end

  -- Ask the widget instead of assuming from the template: protection is inherited down the
  -- parent chain, and an unprotected widget has to keep taking the direct path.
  if type(widget.IsProtected) ~= "function" then
    return false
  end

  return widget:IsProtected() and true or false
end

for index = 1, #PROTECTED_METHODS do
  local method = PROTECTED_METHODS[index]

  wrappers[method] = function(self, ...)
    local natives = self._mbNatives
    local native = natives and natives[method]

    if not native then
      return
    end

    if isLocked(self) then
      queueCall(self, method, ...)
      return
    end

    return native(self, ...)
  end
end

-- Idempotent, and safe on any widget: unprotected ones simply never take the deferred branch.
-- Call it right after CreateFrame, before the first SetPoint/Show, so a widget built *during*
-- combat defers its own construction instead of erroring halfway through it.
function MultiBot.MakeCombatSafe(widget)
  if type(widget) ~= "table" or widget._mbCombatSafe then
    return widget
  end

  local objectType = (type(widget.GetObjectType) == "function" and widget:GetObjectType()) or "Frame"
  local natives = nativesByType[objectType]

  if not natives then
    natives = {}
    nativesByType[objectType] = natives
  end

  for index = 1, #PROTECTED_METHODS do
    local method = PROTECTED_METHODS[index]
    local native = widget[method]

    if type(native) == "function" then
      if natives[method] == nil then
        natives[method] = native
      end
      widget[method] = wrappers[method]
    end
  end

  widget._mbNatives = natives
  widget._mbCombatSafe = true

  return widget
end

function MultiBot.IsCombatLocked()
  return (type(InCombatLockdown) == "function" and InCombatLockdown()) and true or false
end

-- For the handful of actions frame wrapping cannot rescue, because the *API* they call is itself
-- protected. Silently doing nothing is what reads as "the addon is broken".
function MultiBot.WarnCombatLocked()
  local text = (type(MultiBot.L) == "function" and MultiBot.L("info.combat_locked")) or "Not while in combat."

  if UIErrorsFrame and UIErrorsFrame.AddMessage then
    UIErrorsFrame:AddMessage(text, 1, 0.25, 0.25, 1)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MultiBot|r " .. text)
  end

  return false
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
-- This client runs without `SET scriptErrors "1"`, so a blocked call leaves no trace at all on
-- screen -- the handler just stops. Route the event into the debug channel (`/mbdebug on core`) so
-- anything this shim still misses can be named instead of guessed at.
driver:RegisterEvent("ADDON_ACTION_BLOCKED")
driver:SetScript("OnEvent", function(_, event, addonName, functionName)
  if event == "ADDON_ACTION_BLOCKED" then
    debugPrint("combat: blocked " .. tostring(addonName) .. " -> " .. tostring(functionName))
    return
  end

  flushPending()
end)

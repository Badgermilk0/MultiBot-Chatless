-- String table for the addon. This build ships English only: Locales/MultiBotAceLocale-enUS.lua
-- is the single locale file and registers itself as the AceLocale default, so every client
-- locale resolves to it. Add new strings there, never hardcoded in the UI files.
MultiBot = MultiBot or {}

local aceLocale = LibStub and LibStub("AceLocale-3.0", true)
local LOCALE_NAMESPACE = "MultiBot"

local function sanitizeLocaleTable(values)
  if type(values) ~= "table" then
    return nil
  end

  local sanitized = {}
  for key, value in pairs(values) do
    if type(key) == "string" and type(value) == "string" then
      sanitized[key] = value
    end
  end

  return sanitized
end

local function registerDefaultStrings(values)
  local defaults = MultiBot._localeDefaults or {}
  for key, value in pairs(values) do
    defaults[key] = value
  end
  MultiBot._localeDefaults = defaults
end

function MultiBot.RegisterLocaleStrings(locale, values, isDefault)
  local normalized = sanitizeLocaleTable(values)
  if not normalized then
    return nil
  end

  if isDefault then
    registerDefaultStrings(normalized)
  end

  if not aceLocale then
    return nil
  end

  local localeTable = aceLocale:NewLocale(LOCALE_NAMESPACE, locale, isDefault)
  if not localeTable then
    return nil
  end

  for key, value in pairs(normalized) do
    localeTable[key] = value
  end

  return localeTable
end

-- Resolved once and cached: MultiBot.L runs on every tooltip build and every status line,
-- and the namespace's locale table never changes after the locale file has registered.
local activeLocaleTable = nil

local function getActiveLocaleTable()
  if activeLocaleTable then
    return activeLocaleTable
  end

  if not aceLocale then
    return nil
  end

  local resolved = aceLocale:GetLocale(LOCALE_NAMESPACE, true)
  if type(resolved) == "table" then
    activeLocaleTable = resolved
  end

  return activeLocaleTable
end

function MultiBot.GetLocaleString(key, fallback)
  if type(key) ~= "string" then
    return fallback
  end

  local activeLocale = getActiveLocaleTable()
  if activeLocale then
    local activeValue = rawget(activeLocale, key)
    if type(activeValue) == "string" then
      return activeValue
    end
  end

  local defaults = MultiBot._localeDefaults
  local defaultValue = defaults and defaults[key]
  if type(defaultValue) == "string" then
    return defaultValue
  end

  if type(fallback) == "string" then
    return fallback
  end

  return key
end


-- Removed: ApplyLocaleKeyValues / setValueByPath.
-- They exploded every dotted locale key into nested tables ON THE MultiBot GLOBAL
-- (MultiBot.tips.every.loot = "...", and so on for ~1000 keys). Nothing read them —
-- every lookup goes through MultiBot.L — while the first path segment of a key silently
-- pre-created MultiBot.inventory / .talent / .spellbook / .spec as string tables before
-- the real UI frames claimed those fields. Strings live in AceLocale only.

MultiBot.L = MultiBot.GetLocaleString

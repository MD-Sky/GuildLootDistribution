local _, NS = ...

local GLD = NS.GLD
local CLASS_DATA = NS.CLASS_DATA or {}

local ARMOR_BY_CLASS = {
  WARRIOR = {4},
  PALADIN = {4},
  DEATHKNIGHT = {4},
  HUNTER = {3},
  SHAMAN = {3},
  ROGUE = {2},
  DRUID = {2},
  MONK = {2},
  DEMONHUNTER = {2},
  PRIEST = {1},
  MAGE = {1},
  WARLOCK = {1},
  EVOKER = {3},
}

local ITEM_CLASS_ARMOR = 4
local ITEM_CLASS_WEAPON = 2
local ARMOR_TRINKET = 0
local ARMOR_RING = 11
local ARMOR_NECK = 2
local ARMOR_SHIELD = 6

local ARMOR_SUBCLASS_BY_NAME = {}
if ITEM_SUBCLASS_ARMOR_CLOTH then
  ARMOR_SUBCLASS_BY_NAME[ITEM_SUBCLASS_ARMOR_CLOTH] = 1
end
if ITEM_SUBCLASS_ARMOR_LEATHER then
  ARMOR_SUBCLASS_BY_NAME[ITEM_SUBCLASS_ARMOR_LEATHER] = 2
end
if ITEM_SUBCLASS_ARMOR_MAIL then
  ARMOR_SUBCLASS_BY_NAME[ITEM_SUBCLASS_ARMOR_MAIL] = 3
end
if ITEM_SUBCLASS_ARMOR_PLATE then
  ARMOR_SUBCLASS_BY_NAME[ITEM_SUBCLASS_ARMOR_PLATE] = 4
end

local WEAPON_SUBCLASS_BY_NAME = {}
if ITEM_SUBCLASS_WEAPON_AXE then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_AXE] = 0
end
if ITEM_SUBCLASS_WEAPON_AXE2 then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_AXE2] = 1
end
if ITEM_SUBCLASS_WEAPON_BOW then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_BOW] = 2
end
if ITEM_SUBCLASS_WEAPON_GUN then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_GUN] = 3
end
if ITEM_SUBCLASS_WEAPON_MACE then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_MACE] = 4
end
if ITEM_SUBCLASS_WEAPON_MACE2 then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_MACE2] = 5
end
if ITEM_SUBCLASS_WEAPON_POLEARM then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_POLEARM] = 6
end
if ITEM_SUBCLASS_WEAPON_SWORD then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_SWORD] = 7
end
if ITEM_SUBCLASS_WEAPON_SWORD2 then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_SWORD2] = 8
end
if ITEM_SUBCLASS_WEAPON_WARGLAIVE then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_WARGLAIVE] = 9
end
if ITEM_SUBCLASS_WEAPON_STAFF then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_STAFF] = 10
end
if ITEM_SUBCLASS_WEAPON_FIST then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_FIST] = 13
end
if ITEM_SUBCLASS_WEAPON_DAGGER then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_DAGGER] = 15
end
if ITEM_SUBCLASS_WEAPON_CROSSBOW then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_CROSSBOW] = 18
end
if ITEM_SUBCLASS_WEAPON_WAND then
  WEAPON_SUBCLASS_BY_NAME[ITEM_SUBCLASS_WEAPON_WAND] = 19
end

local WEAPON_CATEGORY_SUBCLASS_IDS = {
  ["Axes"] = {0, 1},
  ["Swords"] = {7, 8},
  ["Maces"] = {4, 5},
  ["Polearms"] = {6},
  ["Staves"] = {10},
  ["Daggers"] = {15},
  ["Fist Weapons"] = {13},
  ["Warglaives"] = {9},
  ["Bows"] = {2},
  ["Guns"] = {3},
  ["Crossbows"] = {18},
  ["Wands"] = {19},
  ["One-Handed"] = {0, 4, 7},
  ["Two-Handed"] = {1, 5, 8},
}

local WEAPON_BY_CLASS = {}
local SHIELD_BY_CLASS = {}

local function AddUnique(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return
    end
  end
  list[#list + 1] = value
end

local function AddList(list, values)
  for _, value in ipairs(values) do
    AddUnique(list, value)
  end
end

for classFile, data in pairs(CLASS_DATA) do
  local allowed = {}
  local hasWeapon = false
  for _, weaponName in ipairs(data.weapons or {}) do
    if weaponName == "Shields" then
      SHIELD_BY_CLASS[classFile] = true
    else
      local ids = WEAPON_CATEGORY_SUBCLASS_IDS[weaponName]
      if ids then
        AddList(allowed, ids)
        hasWeapon = true
      end
    end
  end
  if hasWeapon then
    WEAPON_BY_CLASS[classFile] = allowed
  end
end

local CLASS_NAME_TO_FILE = {}
if LOCALIZED_CLASS_NAMES_MALE then
  for classFile, className in pairs(LOCALIZED_CLASS_NAMES_MALE) do
    if className then
      CLASS_NAME_TO_FILE[string.lower(className)] = classFile
    end
  end
end
if LOCALIZED_CLASS_NAMES_FEMALE then
  for classFile, className in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
    if className then
      CLASS_NAME_TO_FILE[string.lower(className)] = classFile
    end
  end
end

local TRINKET_DPS_ROLE_BY_CLASS_SPEC = {
  WARRIOR = { Arms = "MELEEDPS", Fury = "MELEEDPS" },
  PALADIN = { Retribution = "MELEEDPS" },
  DEATHKNIGHT = { Frost = "MELEEDPS", Unholy = "MELEEDPS" },
  HUNTER = { ["Beast Mastery"] = "RANGEDPS", Marksmanship = "RANGEDPS", Survival = "MELEEDPS" },
  SHAMAN = { Elemental = "RANGEDPS", Enhancement = "MELEEDPS" },
  DRUID = { Balance = "RANGEDPS", Feral = "MELEEDPS" },
  MONK = { Windwalker = "MELEEDPS" },
  DEMONHUNTER = { Havoc = "MELEEDPS", Devourer = "RANGEDPS" },
  MAGE = { Arcane = "RANGEDPS", Fire = "RANGEDPS", Frost = "RANGEDPS" },
  PRIEST = { Shadow = "RANGEDPS" },
  WARLOCK = { Affliction = "RANGEDPS", Demonology = "RANGEDPS", Destruction = "RANGEDPS" },
  EVOKER = { Devastation = "RANGEDPS", Augmentation = "RANGEDPS" },
}

local CLASS_DEFAULT_DPS_ROLE = {
  MAGE = "RANGEDPS",
  WARLOCK = "RANGEDPS",
  ROGUE = "MELEEDPS",
  DEMONHUNTER = "MELEEDPS",
  EVOKER = "RANGEDPS",
}

local function StripColor(text)
  if not text then
    return text
  end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|r", "")
  return text
end

local function Trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function GetClassesPrefix()
  if ITEM_CLASSES_ALLOWED then
    return ITEM_CLASSES_ALLOWED:match("^(.-)%%s")
  end
  return "Classes: "
end

local function GetItemSetPrefix()
  if ITEM_SET_NAME then
    return ITEM_SET_NAME:match("^(.-)%%s")
  end
  return "Set: "
end

local function ParseClassRestriction(text)
  if not text or text == "" then
    return nil
  end
  local cleanText = Trim(StripColor(text))
  local prefix = GetClassesPrefix()
  if not cleanText:find(prefix, 1, true) then
    return nil
  end
  local rest = Trim(cleanText:sub(#prefix + 1))
  if rest == "" then
    return nil
  end
  if ALL and rest:lower() == tostring(ALL):lower() then
    return false
  end
  local allowed = {}
  local count = 0
  for name in rest:gmatch("[^,]+") do
    local key = Trim(name):lower()
    local classFile = CLASS_NAME_TO_FILE[key]
    if classFile and not allowed[classFile] then
      allowed[classFile] = true
      count = count + 1
    end
  end
  if count > 0 then
    return allowed
  end
  return nil
end

local function Contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

local function NormalizeSpecName(specName)
  if not specName then
    return nil
  end
  return tostring(specName):lower()
end

local function GetItemId(item)
  if not item then
    return nil
  end
  if type(item) == "number" then
    return item
  end
  if type(item) == "string" then
    return tonumber(item:match("item:(%d+)")) or tonumber(item:match("^%d+$"))
  end
  return nil
end

local function ParseItemSetName(text)
  if not text or text == "" then
    return nil
  end
  local cleanText = Trim(StripColor(text))
  local prefix = GetItemSetPrefix()
  if not cleanText:find(prefix, 1, true) then
    return nil
  end
  local rest = Trim(cleanText:sub(#prefix + 1))
  if rest == "" then
    return nil
  end
  return rest
end

local function ExtractItemName(item)
  if not item then
    return nil
  end
  if type(item) == "string" then
    local name = item:match("%[(.-)%]")
    if name and name ~= "" then
      return name
    end
  end
  return GetItemInfo(item)
end

function GLD:IsItemInfoTrinket(item)
  if not item then
    return false
  end
  local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(item)
  if equipLoc == "INVTYPE_TRINKET" then
    return true
  end
  if itemSubType and ITEM_SUBCLASS_ARMOR_TRINKET and itemSubType == ITEM_SUBCLASS_ARMOR_TRINKET then
    return true
  end
  if itemSubType and tostring(itemSubType):lower() == "trinket" then
    return true
  end
  if itemType and tostring(itemType):lower() == "trinket" then
    return true
  end
  return false
end

function GLD:RequestItemData(item)
  if not item then
    return
  end
  if type(item) == "table" and item.GetEquipmentSlot then
    C_Item.RequestLoadItemData(item)
    return
  end

  local itemID = nil
  if type(item) == "number" then
    itemID = item
  elseif type(item) == "string" then
    itemID = tonumber(item:match("item:(%d+)")) or tonumber(item:match("^%d+$"))
  end

  if itemID then
    C_Item.RequestLoadItemDataByID(itemID)
  end
end

function GLD:GetItemClassRestrictions(item)
  if not item then
    return nil
  end

  local itemID = C_Item.GetItemInfoInstant(item)
  if not itemID then
    self:RequestItemData(item)
    return nil
  end

  self._classRestrictionCache = self._classRestrictionCache or {}
  if self._classRestrictionCache[itemID] ~= nil then
    return self._classRestrictionCache[itemID] or nil
  end

  local itemLink = item
  if type(item) == "number" then
    itemLink = "item:" .. tostring(item)
  elseif type(item) == "string" and item:match("^%d+$") then
    itemLink = "item:" .. item
  end

  local restriction = nil
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink and itemLink then
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if data and data.lines then
      for _, line in ipairs(data.lines) do
        local text = line.leftText or line.text
        restriction = ParseClassRestriction(text)
        if restriction ~= nil then
          break
        end
      end
    end
  end

  if restriction == nil and GameTooltip and itemLink then
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetHyperlink(itemLink)
    for i = 1, GameTooltip:NumLines() do
      local line = _G["GameTooltipTextLeft" .. i]
      local text = line and line:GetText() or nil
      restriction = ParseClassRestriction(text)
      if restriction ~= nil then
        break
      end
    end
    GameTooltip:Hide()
  end

  if restriction == nil then
    self._classRestrictionCache[itemID] = false
    return nil
  end

  self._classRestrictionCache[itemID] = restriction
  return restriction
end

function GLD:GetItemSetName(item)
  if not item then
    return nil
  end
  local itemId = GetItemId(item)
  self._itemSetCache = self._itemSetCache or {}
  if itemId and self._itemSetCache[itemId] ~= nil then
    return self._itemSetCache[itemId] or nil
  end

  local itemLink = item
  if type(item) == "number" then
    itemLink = "item:" .. tostring(item)
  elseif type(item) == "string" and item:match("^%d+$") then
    itemLink = "item:" .. item
  end

  local setName = nil
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink and itemLink then
    local data = C_TooltipInfo.GetHyperlink(itemLink)
    if data and data.lines then
      for _, line in ipairs(data.lines) do
        local text = line.leftText or line.text
        setName = ParseItemSetName(text)
        if setName then
          break
        end
      end
    end
  end

  if not setName and GameTooltip and itemLink then
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:SetHyperlink(itemLink)
    for i = 1, GameTooltip:NumLines() do
      local line = _G["GameTooltipTextLeft" .. i]
      local text = line and line:GetText() or nil
      setName = ParseItemSetName(text)
      if setName then
        break
      end
    end
    GameTooltip:Hide()
  end

  if itemId then
    self._itemSetCache[itemId] = setName or false
  end
  return setName
end

function GLD:GetTrinketRoleRestriction(itemId)
  if not itemId then
    return nil
  end
  local map = self.db and self.db.config and self.db.config.trinketRoleMap
  if type(map) ~= "table" then
    return nil
  end
  local value = map[tostring(itemId)]
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    local roles = {}
    for key, enabled in pairs(value) do
      if enabled then
        roles[key] = true
      end
    end
    if roles.DPS then
      roles.DPS = nil
      roles.RANGEDPS = true
      roles.MELEEDPS = true
    end
    return roles
  end
  if type(value) == "string" then
    if value == "DPS" then
      return { RANGEDPS = true, MELEEDPS = true }
    end
    return { [value] = true }
  end
  return nil
end

function GLD:GetTrinketRoleKey(classFile, specName)
  if not classFile then
    return nil
  end
  local classToken = tostring(classFile):upper()
  local specKey = NormalizeSpecName(specName)
  local classData = CLASS_DATA[classToken]
  local foundSpec = false
  if specKey and classData and classData.specs then
    for name, data in pairs(classData.specs) do
      if name and name:lower() == specKey then
        foundSpec = true
        local role = data and data.role or nil
        if role == "Tank" then
          return "TANK"
        end
        if role == "Healer" then
          return "HEALER"
        end
        if role == "DPS" then
          local mapping = TRINKET_DPS_ROLE_BY_CLASS_SPEC[classToken]
          if mapping then
            for specNameKey, dpsRole in pairs(mapping) do
              if specNameKey and specNameKey:lower() == specKey then
                return dpsRole
              end
            end
          end
          if self and self.IsDebugEnabled and self:IsDebugEnabled() then
            self:Debug(
              "Trinket role fallback: class="
                .. tostring(classToken)
                .. " spec="
                .. tostring(specName)
                .. " role="
                .. tostring(CLASS_DEFAULT_DPS_ROLE[classToken] or "DPS")
            )
          end
          return CLASS_DEFAULT_DPS_ROLE[classToken] or "DPS"
        end
      end
    end
  end
  if specKey and classData and classData.specs and not foundSpec then
    if self and self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug(
        "Unknown spec fallback: class="
          .. tostring(classToken)
          .. " spec="
          .. tostring(specName)
          .. " role="
          .. tostring(CLASS_DEFAULT_DPS_ROLE[classToken] or "DPS")
      )
    end
  end
  return CLASS_DEFAULT_DPS_ROLE[classToken] or nil
end

function GLD:BuildTrinketLookup(raidId)
  if not raidId then
    return nil
  end
  if not self.GetTrinketLootEncountersForRaid or not self.GetEncounterTrinketLinks then
    return nil
  end
  self._trinketLookupByRaid = self._trinketLookupByRaid or {}
  if self._trinketLookupByRaid[raidId] then
    return self._trinketLookupByRaid[raidId]
  end

  local encounters = self:GetTrinketLootEncountersForRaid(raidId)
  if not encounters or #encounters == 0 then
    return nil
  end

  local lookup = { byId = {}, byName = {} }
  for _, encounter in ipairs(encounters or {}) do
    local trinkets = self:GetEncounterTrinketLinks(raidId, encounter)
    for _, trinket in ipairs(trinkets or {}) do
      if trinket.itemId then
        lookup.byId[trinket.itemId] = true
      end
      local name = trinket.name or (trinket.link and trinket.link:match("%[(.-)%]")) or nil
      if name and name ~= "" then
        lookup.byName[name] = true
      end
    end
  end

  self._trinketLookupByRaid[raidId] = lookup
  return lookup
end

function GLD:IsKnownTrinket(item)
  local raidId = self.GetSelectedTrinketLootRaidId and self:GetSelectedTrinketLootRaidId() or nil
  local itemId = GetItemId(item)
  if itemId and self:GetTrinketRoleRestriction(itemId) then
    return true
  end
  if not raidId then
    return false
  end
  local lookup = self:BuildTrinketLookup(raidId)
  if not lookup then
    return false
  end
  if itemId and lookup.byId[itemId] then
    return true
  end
  local name = ExtractItemName(item)
  if name and lookup.byName[name] then
    return true
  end
  return false
end

function GLD:IsTrinketEligibleForNeed(classFile, item, specName, rolesOverride)
  local itemId = GetItemId(item)
  local roles = rolesOverride or self:GetTrinketRoleRestriction(itemId)
  if roles then
    local roleKey = self:GetTrinketRoleKey(classFile, specName)
    if roleKey == "DPS" then
      return roles.RANGEDPS == true or roles.MELEEDPS == true
    end
    return roleKey and roles[roleKey] == true
  end
  return true
end

local function DebugNeedDenied(self, item, equipLoc, rule)
  if not self or not self.IsDebugEnabled or not self:IsDebugEnabled() then
    return
  end
  local itemType, itemSubType = nil, nil
  if GetItemInfo then
    itemType, itemSubType = select(6, GetItemInfo(item))
  end
  self:Debug(
    "Need denied: item="
      .. tostring(item)
      .. " equipLoc="
      .. tostring(equipLoc)
      .. " type="
      .. tostring(itemType)
      .. "/"
      .. tostring(itemSubType)
      .. " rule="
      .. tostring(rule)
  )
end

function GLD:IsEligibleForNeed(classFile, item, specName, context)
  if not classFile or not item then
    return false, "missing_input"
  end
  local trinketRoles = context and context.trinketRoles or nil
  local isTrinketByInfo = self.IsItemInfoTrinket and self:IsItemInfoTrinket(item) or false
  local isTrinketSnapshot = trinketRoles ~= nil
  local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(item)
  if not classID then
    if isTrinketSnapshot or isTrinketByInfo or self:IsKnownTrinket(item) then
      local ok = self:IsTrinketEligibleForNeed(classFile, item, specName, trinketRoles)
      if ok then
        return true, nil
      end
      DebugNeedDenied(self, item, equipLoc, "trinket_role")
      return false, "ineligible_trinket_role"
    end
    self:RequestItemData(item)
    return false, "item_data_missing"
  end
  if not equipLoc or equipLoc == "" or subClassID == nil then
    self:RequestItemData(item)
    return false, "item_data_missing"
  end

  local classRestriction = self:GetItemClassRestrictions(item)
  if classRestriction then
    if classRestriction[classFile] == true then
      return true, nil
    end
    local reason = "ineligible_class_restriction"
    if self.GetItemSetName then
      local setName = self:GetItemSetName(item)
      if setName and setName ~= "" then
        reason = "ineligible_tier"
      end
    end
    DebugNeedDenied(self, item, equipLoc, reason == "ineligible_tier" and "tier" or "class_restriction")
    return false, reason
  end

  if classID == ITEM_CLASS_ARMOR then
    if subClassID == ARMOR_TRINKET or equipLoc == "INVTYPE_TRINKET" or isTrinketByInfo then
      local ok = self:IsTrinketEligibleForNeed(classFile, item, specName, trinketRoles)
      if ok then
        return true, nil
      end
      DebugNeedDenied(self, item, equipLoc, "trinket_role")
      return false, "ineligible_trinket_role"
    end
    if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_CLOAK" or equipLoc == "INVTYPE_NECK" then
      return true, nil
    end
    if equipLoc == "INVTYPE_SHIELD" or subClassID == ARMOR_SHIELD then
      if SHIELD_BY_CLASS[classFile] then
        return true, nil
      end
      DebugNeedDenied(self, item, equipLoc, "shield")
      return false, "ineligible_shield"
    end
    local allowed = ARMOR_BY_CLASS[classFile]
    if allowed and Contains(allowed, subClassID) then
      return true, nil
    end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item)
    local fallbackSub = itemSubType and ARMOR_SUBCLASS_BY_NAME[itemSubType]
    if allowed and fallbackSub and Contains(allowed, fallbackSub) then
      return true, nil
    end
    DebugNeedDenied(self, item, equipLoc, "armor")
    return false, "ineligible_armor"
  end

  if classID == ITEM_CLASS_WEAPON then
    local allowed = WEAPON_BY_CLASS[classFile]
    if allowed and Contains(allowed, subClassID) then
      return true, nil
    end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(item)
    local fallbackSub = itemSubType and WEAPON_SUBCLASS_BY_NAME[itemSubType]
    if allowed and fallbackSub and Contains(allowed, fallbackSub) then
      return true, nil
    end
    DebugNeedDenied(self, item, equipLoc, "weapon")
    return false, "ineligible_weapon"
  end

  if isTrinketSnapshot or isTrinketByInfo or self:IsKnownTrinket(item) then
    local ok = self:IsTrinketEligibleForNeed(classFile, item, specName, trinketRoles)
    if ok then
      return true, nil
    end
    DebugNeedDenied(self, item, equipLoc, "trinket_role")
    return false, "ineligible_trinket_role"
  end
  DebugNeedDenied(self, item, equipLoc, "unknown_slot")
  return false, "ineligible_item_type"
end

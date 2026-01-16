local _, NS = ...

local GLD = NS.GLD

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

local WEAPON_BY_CLASS = {
  WARRIOR = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  PALADIN = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  DEATHKNIGHT = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  HUNTER = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  SHAMAN = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  ROGUE = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  DRUID = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  MONK = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  DEMONHUNTER = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  PRIEST = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  MAGE = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  WARLOCK = {0, 1, 2, 3, 4, 5, 6, 7, 8},
  EVOKER = {0, 1, 2, 3, 4, 5, 6, 7, 8},
}

local ITEM_CLASS_ARMOR = 4
local ITEM_CLASS_WEAPON = 2
local ARMOR_TRINKET = 0
local ARMOR_RING = 11
local ARMOR_NECK = 2

local function Contains(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
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

function GLD:IsEligibleForNeed(classFile, item)
  if not classFile or not item then
    return false
  end
  local classID, subClassID, _, equipLoc = C_Item.GetItemInfoInstant(item)
  if not classID then
    self:RequestItemData(item)
    return false
  end

  if classID == ITEM_CLASS_ARMOR then
    if subClassID == ARMOR_TRINKET or subClassID == ARMOR_RING or subClassID == ARMOR_NECK then
      return true
    end
    local allowed = ARMOR_BY_CLASS[classFile]
    return allowed and Contains(allowed, subClassID)
  end

  if classID == ITEM_CLASS_WEAPON then
    local allowed = WEAPON_BY_CLASS[classFile]
    return allowed and Contains(allowed, subClassID)
  end

  return false
end

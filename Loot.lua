local _, NS = ...

local GLD = NS.GLD

function GLD:InitLoot()
  self.activeRolls = {}
  self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
end

function GLD:OnStartLootRoll(rollID, rollTime, lootHandle)
  local texture, name, count, quality, bop, canNeed, canGreed, canDE, canTransmog, reason = GetLootRollItemInfo(rollID)
  local link = GetLootRollItemLink(rollID)

  local session = {
    rollID = rollID,
    rollTime = rollTime,
    itemLink = link,
    itemName = name,
    quality = quality,
    canNeed = canNeed,
    canGreed = canGreed,
    canTransmog = canTransmog,
    votes = {},
  }
  self.activeRolls[rollID] = session

  if link then
    self:RequestItemData(link)
  end

  if self.UI then
    self.UI:ShowRollPopup(session)
  end
end

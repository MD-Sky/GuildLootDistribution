local _, NS = ...

local GLD = NS.GLD

function GLD:InitSpec()
  self.specCache = self.specCache or {}
  self.inspectQueue = self.inspectQueue or {}
  self._inspectTicker = self._inspectTicker or nil
end

local function GetUnitKey(unit)
  return NS:GetPlayerKeyFromUnit(unit)
end

function GLD:UpdatePlayerSpecFromId(player, specId)
  if not player then
    return
  end
  if not specId or specId == 0 then
    return
  end
  local _, name = GetSpecializationInfoByID(specId)
  player.specId = specId
  player.specName = name
end

function GLD:UpdateSelfSpec()
  local specIndex = GetSpecialization()
  if not specIndex then
    return
  end
  local specId = GetSpecializationInfo(specIndex)
  if not specId then
    return
  end
  local key = NS:GetPlayerKeyFromUnit("player")
  if key and self.db.players and self.db.players[key] then
    self:UpdatePlayerSpecFromId(self.db.players[key], specId)
  end
end

function GLD:QueueInspect(unit)
  if not unit or not UnitExists(unit) then
    return
  end
  if not CanInspect or not CanInspect(unit) then
    return
  end
  if UnitIsDeadOrGhost(unit) then
    return
  end
  if InCombatLockdown and InCombatLockdown() then
    return
  end
  local key = GetUnitKey(unit)
  if not key then
    return
  end
  self.inspectQueue[key] = unit
  if not self._inspectTicker then
    self._inspectTicker = C_Timer.NewTicker(0.3, function()
      GLD:ProcessInspectQueue()
    end)
  end
end

function GLD:ProcessInspectQueue()
  if not self.inspectQueue then
    return
  end
  for key, unit in pairs(self.inspectQueue) do
    if unit and UnitExists(unit) and CanInspect(unit) then
      NotifyInspect(unit)
      return
    else
      self.inspectQueue[key] = nil
    end
  end
  if self._inspectTicker then
    self._inspectTicker:Cancel()
    self._inspectTicker = nil
  end
end

function GLD:OnInspectReady(_, guid)
  if not guid then
    return
  end
  local unit = nil
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local u = "raid" .. i
      if UnitGUID(u) == guid then
        unit = u
        break
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local u = "party" .. i
      if UnitGUID(u) == guid then
        unit = u
        break
      end
    end
    if not unit and UnitGUID("player") == guid then
      unit = "player"
    end
  else
    if UnitGUID("player") == guid then
      unit = "player"
    end
  end

  local specId = GetInspectSpecialization(unit)
  if specId and specId > 0 then
    local key = NS:GetPlayerKeyFromUnit(unit)
    if key and self.db.players and self.db.players[key] then
      self:UpdatePlayerSpecFromId(self.db.players[key], specId)
      if self.UI and self.UI.RefreshMain then
        self.UI:RefreshMain()
      end
      if NS.TestUI and NS.TestUI.RefreshTestPanel then
        NS.TestUI:RefreshTestPanel()
      end
    end
  end

  if self.inspectQueue then
    for k, u in pairs(self.inspectQueue) do
      if u and UnitGUID(u) == guid then
        self.inspectQueue[k] = nil
        break
      end
    end
  end
end

function GLD:QueueGroupSpecSync()
  if not IsInGroup() and not IsInRaid() then
    self:UpdateSelfSpec()
    return
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      self:QueueInspect("raid" .. i)
    end
  else
    for i = 1, GetNumSubgroupMembers() do
      self:QueueInspect("party" .. i)
    end
    self:QueueInspect("player")
  end
end

function GLD:OnPlayerSpecChanged(_, unit)
  if not unit then
    return
  end
  if unit == "player" then
    self:UpdateSelfSpec()
  else
    self:QueueInspect(unit)
  end
end

function GLD:FinalSpecSyncBeforePull()
  if self.QueueGroupSpecSync then
    self:QueueGroupSpecSync()
  end
end

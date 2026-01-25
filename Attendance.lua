local _, NS = ...

local GLD = NS.GLD

function GLD:InitAttendance()
  if not self.db.session then
    self.db.session = {
      active = false,
      startedAt = 0,
      attended = {},
      raidSessionId = nil,
      currentBoss = nil,
    }
  end
end

function GLD:GetActiveRaidSession()
  local sessionId = self.db.session and self.db.session.raidSessionId
  if not sessionId then
    return nil
  end
  for _, entry in ipairs(self.db.raidSessions or {}) do
    if entry.id == sessionId then
      return entry
    end
  end
  return nil
end

function GLD:StartRaidSession()
  local instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
  local id = tostring(GetServerTime()) .. "-" .. tostring(math.random(1000, 9999))
  local entry = {
    id = id,
    startedAt = GetServerTime(),
    endedAt = nil,
    raidName = instanceName or "Unknown",
    instanceType = instanceType or "unknown",
    difficultyID = difficultyID,
    difficultyName = difficultyName,
    instanceID = instanceID,
    bosses = {},
    loot = {},
  }
  self.db.raidSessions = self.db.raidSessions or {}
  table.insert(self.db.raidSessions, 1, entry)
  self.db.session.raidSessionId = id
  self.db.session.currentBoss = nil
  return entry
end

function GLD:StartSession()
  if self.db.session.active then
    return
  end
  if self.SetSessionAuthority then
    self:SetSessionAuthority(UnitGUID("player"), self:GetUnitFullName("player"))
  end
  self.db.session.active = true
  self.db.session.startedAt = GetServerTime()
  self.db.session.attended = {}
  self:StartRaidSession()
  if self.RebuildGroupRoster then
    self:RebuildGroupRoster()
  end
  if self.WelcomeGuestsFromGroup then
    self:WelcomeGuestsFromGroup()
  end
  self:AutoMarkCurrentGroup()
  self:EnsureQueuePositions()
  self:BroadcastSnapshot()
  self:Print("Session started")
end

function GLD:EndSession()
  if not self.db.session.active then
    return
  end
  self.db.session.active = false
  if self.ClearSessionAuthority then
    self:ClearSessionAuthority()
  end
  local raidSession = self:GetActiveRaidSession()
  if raidSession then
    raidSession.endedAt = GetServerTime()
  end
  self.db.session.raidSessionId = nil
  self.db.session.currentBoss = nil
  self:BroadcastSnapshot()
  self:Print("Session ended")
end

function GLD:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
  if not self.db.session.active or success ~= 1 then
    return
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Boss kill detected: " .. tostring(encounterName or encounterID or "Unknown"))
  end
  local raidSession = self:GetActiveRaidSession()
  if not raidSession then
    return
  end
  local killedAt = GetServerTime()
  local bossEntry = {
    encounterID = encounterID,
    encounterName = encounterName,
    difficultyID = difficultyID,
    groupSize = groupSize,
    killedAt = killedAt,
    loot = {},
  }
  table.insert(raidSession.bosses, bossEntry)
  self.db.session.currentBoss = {
    encounterID = encounterID,
    encounterName = encounterName,
    killedAt = killedAt,
  }
end

function GLD:AutoMarkCurrentGroup()
  if not IsInGroup() then
    return
  end
  local presentKeys = {}
  if IsInRaid() then
    local count = GetNumGroupMembers()
    for i = 1, count do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitIsConnected(unit) then
        local playerKey = self:UpsertPlayerFromUnit(unit)
        if playerKey then
          presentKeys[playerKey] = true
          if self.db.session.active and not self.db.session.attended[playerKey] then
            local player = self.db.players[playerKey]
            player.attendanceCount = (player.attendanceCount or 0) + 1
            self.db.session.attended[playerKey] = true
          end
          self:SetAttendance(playerKey, "PRESENT")
        end
      end
    end
  else
    local count = GetNumSubgroupMembers()
    for i = 1, count do
      local unit = "party" .. i
      if UnitExists(unit) and UnitIsConnected(unit) then
        local playerKey = self:UpsertPlayerFromUnit(unit)
        if playerKey then
          presentKeys[playerKey] = true
          if self.db.session.active and not self.db.session.attended[playerKey] then
            local player = self.db.players[playerKey]
            player.attendanceCount = (player.attendanceCount or 0) + 1
            self.db.session.attended[playerKey] = true
          end
          self:SetAttendance(playerKey, "PRESENT")
        end
      end
    end
    if UnitIsConnected("player") then
      local playerKey = self:UpsertPlayerFromUnit("player")
      if playerKey then
        presentKeys[playerKey] = true
        if self.db.session.active and not self.db.session.attended[playerKey] then
          local player = self.db.players[playerKey]
          player.attendanceCount = (player.attendanceCount or 0) + 1
          self.db.session.attended[playerKey] = true
        end
        self:SetAttendance(playerKey, "PRESENT")
      end
    end
  end

  for key, player in pairs(self.db.players) do
    if player.attendance == "PRESENT" and not presentKeys[key] then
      self:SetAttendance(key, "ABSENT")
    end
  end
end

function GLD:OnGroupRosterUpdate()
  local _, _, added = nil, nil, nil
  if self.RebuildGroupRoster then
    _, _, added = self:RebuildGroupRoster()
  end
  if self.WelcomeGuestsFromGroup then
    self:WelcomeGuestsFromGroup()
  end
  if self:IsAuthority() and self.db.session.active and IsInRaid() and self.BroadcastActiveRollsSnapshot then
    if added and #added > 0 then
      self:BroadcastActiveRollsSnapshot(added)
    end
  end
  if not self.db.session.active then
    if self.QueueGroupSpecSync then
      self:QueueGroupSpecSync()
    end
    if self.UI then
      self.UI:RefreshMain()
    end
    return
  end
  self:AutoMarkCurrentGroup()
  if self.QueueGroupSpecSync then
    self:QueueGroupSpecSync()
  end
  self:BroadcastSnapshot()
  if self.UI then
    self.UI:RefreshMain()
  end
end

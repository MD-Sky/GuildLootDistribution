local _, NS = ...

local GLD = NS.GLD
local RAID_STATE_REFRESH_SECONDS = 20

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
  if self.MarkDBChanged then
    self:MarkDBChanged("raid_session_start")
  end
  if self.UI and self.UI.RefreshHistoryIfOpen then
    self.UI:RefreshHistoryIfOpen()
  end
  return entry
end

function GLD:StartSession()
  if self.db.session.active then
    return
  end
  if not IsInRaid() then
    self:Print("You must be in a raid to start a session.")
    return
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:Print("you do not have Guild Permission to access this panel")
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
  if self.MarkDBChanged then
    self:MarkDBChanged("session_start")
  end
  self:BroadcastSnapshot()
  self:Print("Session started")
end

function GLD:EndSession()
  if not self.db.session.active then
    return
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:Print("you do not have Guild Permission to access this panel")
    return
  end
  self.db.session.active = false
  if self.shadow then
    self.shadow.sessionActive = false
  end
  if self.ClearSessionAuthority then
    self:ClearSessionAuthority()
  end
  local raidSession = self:GetActiveRaidSession()
  if raidSession then
    raidSession.endedAt = GetServerTime()
  end
  self.db.session.raidSessionId = nil
  self.db.session.currentBoss = nil
  if self.MarkDBChanged then
    self:MarkDBChanged("session_end")
  end
  if self.UI and self.UI.RefreshHistoryIfOpen then
    self.UI:RefreshHistoryIfOpen()
  end
  self:BroadcastSnapshot(true)
  self:Print("Session ended")
end

function GLD:OnEncounterEnd(_, encounterID, encounterName, difficultyID, groupSize, success)
  local sessionActive = nil
  if self.shadow and self.shadow.sessionActive ~= nil then
    sessionActive = self.shadow.sessionActive == true
  else
    sessionActive = self.db.session.active == true
  end
  if not sessionActive or success ~= 1 then
    return
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Boss kill detected: " .. tostring(encounterName or encounterID or "Unknown"))
  end
  if encounterName or encounterID then
    local bossLabel = encounterName or ("Encounter " .. tostring(encounterID))
    self:TraceStep("Boss defeated: " .. tostring(bossLabel))
  else
    self:TraceStep("Boss defeated.")
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
  if self.UI and self.UI.RefreshHistoryIfOpen then
    self.UI:RefreshHistoryIfOpen()
  end
end

function GLD:AutoMarkCurrentGroup()
  if not IsInRaid() then
    return
  end
  local changed = false
  local presentKeys = {}
  local count = GetNumGroupMembers()
  for i = 1, count do
    local unit = "raid" .. i
    if UnitExists(unit) and UnitIsConnected(unit) then
      local playerKey, isNew = self:UpsertPlayerFromUnit(unit)
      if playerKey then
        presentKeys[playerKey] = true
        if isNew then
          changed = true
        end
        if self.db.session.active and not self.db.session.attended[playerKey] then
          local player = self.db.players[playerKey]
          player.attendanceCount = (player.attendanceCount or 0) + 1
          self.db.session.attended[playerKey] = true
          if self.MarkDBChanged then
            self:MarkDBChanged("attendance_count")
          end
        end
        if self.SetAttendance and self:SetAttendance(playerKey, "PRESENT") then
          changed = true
        end
      end
    end
  end

  for key, player in pairs(self.db.players) do
    local state = (player.attendance or ""):upper()
    if state == "PRESENT" and not presentKeys[key] then
      if self.SetAttendance and self:SetAttendance(key, "ABSENT") then
        changed = true
      end
    end
  end
  return changed
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

function GLD:IsSessionActiveLocal()
  if self:IsAuthority() then
    return self.db and self.db.session and self.db.session.active == true
  end
  if self.shadow and self.shadow.sessionActive ~= nil then
    return self.shadow.sessionActive == true
  end
  return false
end

function GLD:InitRaidStateTicker()
  if self.raidStateTicker then
    return
  end
  if not C_Timer or not C_Timer.NewTicker then
    return
  end
  self.raidStateTicker = C_Timer.NewTicker(RAID_STATE_REFRESH_SECONDS, function()
    if self.OnRaidStateTick then
      self:OnRaidStateTick()
    end
  end)
end

function GLD:OnRaidStateTick()
  if not IsInRaid() then
    return
  end

  local sessionActive = self:IsSessionActiveLocal()
  if sessionActive and self:IsAuthority() and self.AutoMarkCurrentGroup then
    local changed = self:AutoMarkCurrentGroup()
    if changed and self.UI then
      self.UI:RefreshMain()
    end
  end

  if not self:IsAuthority() then
    local shouldPing = sessionActive
    if not shouldPing then
      local roster = self.shadow and self.shadow.roster or nil
      if not roster or next(roster) == nil then
        shouldPing = true
      end
    end
    if shouldPing and self.SendRevisionCheck then
      self:SendRevisionCheck()
    end
  end
end

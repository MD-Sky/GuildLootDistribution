local _, NS = ...

local GLD = NS.GLD
local RAID_STATE_REFRESH_SECONDS = 20
local LEAVE_ZONE_WARNING_SECONDS = 60
local START_SESSION_POPUP = "GLD_START_SESSION_CONFIRM"
local END_SESSION_POPUP = "GLD_END_SESSION_CONFIRM"

function GLD:InitAttendance()
  if not self.db.session then
    self.db.session = {
      active = false,
      startedAt = 0,
      attended = {},
      raidSessionId = nil,
      currentBoss = nil,
      zoneInstanceID = nil,
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

function GLD:GetRaidMemberCounts()
  local guildCount, nonGuildCount, total = 0, 0, 0
  if not IsInRaid() then
    return guildCount, nonGuildCount, total
  end
  local ourGuild = self.GetOurGuildName and self:GetOurGuildName() or nil
  for i = 1, GetNumGroupMembers() do
    local unit = "raid" .. i
    if UnitExists(unit) and UnitIsConnected(unit) then
      total = total + 1
      local isGuild = false
      if UnitIsInMyGuild then
        isGuild = UnitIsInMyGuild(unit)
      elseif ourGuild then
        local guildName = GetGuildInfo(unit)
        isGuild = guildName and guildName == ourGuild or false
      end
      if isGuild then
        guildCount = guildCount + 1
      else
        nonGuildCount = nonGuildCount + 1
      end
    end
  end
  return guildCount, nonGuildCount, total
end

function GLD:PromptStartSession()
  if self.db.session.active then
    return
  end
  if not IsInRaid() then
    self:Print("You must be in a raid to start a session.")
    return
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:ShowPermissionDeniedPopup()
    return
  end
  local guildCount, nonGuildCount, total = self:GetRaidMemberCounts()
  if not StaticPopupDialogs then
    self:StartSession()
    return
  end
  StaticPopupDialogs[START_SESSION_POPUP] = StaticPopupDialogs[START_SESSION_POPUP] or {}
  local dialog = StaticPopupDialogs[START_SESSION_POPUP]
  dialog.text = string.format("Start Raid session?\nGuild: %d / Total: %d\nNon-guild: %d", guildCount, total, nonGuildCount)
  dialog.button1 = "Confirm"
  dialog.button2 = "Cancel"
  dialog.timeout = 0
  dialog.whileDead = true
  dialog.hideOnEscape = true
  dialog.OnAccept = function()
    if GLD and GLD.StartSession then
      GLD:StartSession()
    end
  end
  StaticPopup_Show(START_SESSION_POPUP)
end

function GLD:PromptEndSession()
  if not self.db.session.active then
    return
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:ShowPermissionDeniedPopup()
    return
  end
  if not StaticPopupDialogs then
    self:EndSession()
    return
  end
  StaticPopupDialogs[END_SESSION_POPUP] = StaticPopupDialogs[END_SESSION_POPUP] or {}
  local dialog = StaticPopupDialogs[END_SESSION_POPUP]
  dialog.text = "End Raid session? Are you sure?"
  dialog.button1 = "Confirm"
  dialog.button2 = "Cancel"
  dialog.timeout = 0
  dialog.whileDead = true
  dialog.hideOnEscape = true
  dialog.OnAccept = function()
    if GLD and GLD.EndSession then
      GLD:EndSession()
    end
  end
  StaticPopup_Show(END_SESSION_POPUP)
end

function GLD:StartLeaveZoneTimer()
  if self.leaveZoneTimer or not C_Timer or not C_Timer.NewTimer then
    return
  end
  self:Print("You left the raid zone. Session will end in 60 seconds. Return or end manually.")
  self.leaveZoneTimer = C_Timer.NewTimer(LEAVE_ZONE_WARNING_SECONDS, function()
    self.leaveZoneTimer = nil
    if self.PromptEndSession then
      self:PromptEndSession()
    elseif self.EndSession then
      self:EndSession()
    end
  end)
end

function GLD:CancelLeaveZoneTimer()
  if self.leaveZoneTimer then
    self.leaveZoneTimer:Cancel()
    self.leaveZoneTimer = nil
  end
end

function GLD:CheckSessionZoneStatus()
  if not self.db or not self.db.session or not self.db.session.active then
    self:CancelLeaveZoneTimer()
    return
  end
  if not self:IsAuthority() then
    self:CancelLeaveZoneTimer()
    return
  end
  local raidSession = self.GetActiveRaidSession and self:GetActiveRaidSession() or nil
  local sessionInstanceId = raidSession and raidSession.instanceID or self.db.session.zoneInstanceID
  if not sessionInstanceId or sessionInstanceId == 0 then
    return
  end
  local _, _, _, _, _, _, _, instanceId = GetInstanceInfo()
  if instanceId ~= sessionInstanceId then
    self:StartLeaveZoneTimer()
  else
    self:CancelLeaveZoneTimer()
  end
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
    self:ShowPermissionDeniedPopup()
    return
  end
  if self.SetSessionAuthority then
    self:SetSessionAuthority(UnitGUID("player"), self:GetUnitFullName("player"))
  end
  self.db.session.active = true
  self.db.session.startedAt = GetServerTime()
  self.db.session.attended = {}
  local raidSession = self:StartRaidSession()
  self.db.session.zoneInstanceID = raidSession and raidSession.instanceID or nil
  if self.CancelLeaveZoneTimer then
    self:CancelLeaveZoneTimer()
  end
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
  if self.LogAuditEvent then
    local actor = self:GetUnitFullName("player") or UnitName("player") or "Unknown"
    self:LogAuditEvent("SESSION_START", { actor = actor })
  end
  if self.BroadcastSessionState then
    self:BroadcastSessionState()
  end
  self:BroadcastSnapshot()
  self:Print("Session started")
end

function GLD:EndSession()
  if not self.db.session.active then
    return
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:ShowPermissionDeniedPopup()
    return
  end
  if self.AutoMarkCurrentGroup then
    self:AutoMarkCurrentGroup()
  end
  if self.LogRaidAttendanceAudit then
    self:LogRaidAttendanceAudit()
  end
  if self.LogAuditEvent then
    local actor = self:GetUnitFullName("player") or UnitName("player") or "Unknown"
    self:LogAuditEvent("SESSION_END", { actor = actor })
  end
  if self.CancelLeaveZoneTimer then
    self:CancelLeaveZoneTimer()
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
  self.db.session.zoneInstanceID = nil
  if self.MarkDBChanged then
    self:MarkDBChanged("session_end")
  end
  if self.BroadcastSessionState then
    self:BroadcastSessionState(true)
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
      local shouldTrack = true
      if self.IsGuest and self:IsGuest(unit) then
        local existingPlayer = nil
        if self.GetDBPlayerForUnit then
          existingPlayer = select(1, self:GetDBPlayerForUnit(unit))
        end
        if not existingPlayer then
          shouldTrack = false
        end
      end
      if shouldTrack then
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

function GLD:LogRaidAttendanceAudit()
  if not self.db or not self.db.session or not self.db.session.attended then
    return
  end
  if not self.LogAuditEvent then
    return
  end
  for key, present in pairs(self.db.session.attended) do
    if present then
      local player = self.db.players and self.db.players[key]
      local isGuest = false
      if player and self.IsGuestEntry then
        isGuest = self:IsGuestEntry(player)
      end
      local classFile = player and (player.classFile or player.classFileName or player.class)
      local specName = player and (player.specName or player.spec)
      local targetName = player and player.name or key
      self:LogAuditEvent("RAID_ATTENDED", {
        target = targetName,
        isGuest = isGuest,
        class = classFile,
        spec = specName,
      })
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
  local sessionActive = self.db and self.db.session and self.db.session.active == true
  if self:IsAuthority() and sessionActive and IsInRaid() and self.BroadcastActiveRollsSnapshot then
    if added and #added > 0 then
      self:BroadcastActiveRollsSnapshot(added)
    end
  end
  if sessionActive and self.AutoMarkCurrentGroup then
    self:AutoMarkCurrentGroup()
  end
  if self.QueueGroupSpecSync then
    self:QueueGroupSpecSync()
  end
  if self.BroadcastSnapshot then
    self:BroadcastSnapshot()
  end
  if sessionActive and self.CheckSessionZoneStatus then
    self:CheckSessionZoneStatus()
  end
  if self.MaybeAutoAuditAddons then
    self:MaybeAutoAuditAddons()
  end
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

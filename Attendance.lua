local _, NS = ...

local GLD = NS.GLD

function GLD:InitAttendance()
  if not self.db.session then
    self.db.session = {
      active = false,
      startedAt = 0,
      attended = {},
    }
  end
end

function GLD:StartSession()
  if self.db.session.active then
    return
  end
  self.db.session.active = true
  self.db.session.startedAt = GetServerTime()
  self.db.session.attended = {}
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
  self:BroadcastSnapshot()
  self:Print("Session ended")
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
  if not self.db.session.active then
    return
  end
  self:AutoMarkCurrentGroup()
  self:BroadcastSnapshot()
  if self.UI then
    self.UI:RefreshMain()
  end
end

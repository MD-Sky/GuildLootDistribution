local _, NS = ...

local GLD = NS.GLD

local function NormalizeAttendanceState(state)
  if state == "Absent" or state == "ABSENT" then
    return "Absent"
  end
  if state == "Present" or state == "PRESENT" then
    return "Present"
  end
  return state
end

local function IsPresentState(state)
  return NormalizeAttendanceState(state) ~= "Absent"
end

local function GetHoldPos(player)
  if not player then
    return nil
  end
  if player.holdPos ~= nil then
    return player.holdPos
  end
  return player.savedPos
end

local function SetHoldPos(player, pos)
  if not player then
    return
  end
  player.holdPos = pos
  player.savedPos = pos
end

local function ClearHoldPos(player)
  if not player then
    return
  end
  player.holdPos = nil
  player.savedPos = nil
end

function GLD:RemoveFromQueue(key)
  if not key then
    return
  end
  self.db.queue = self.db.queue or {}
  for i, k in ipairs(self.db.queue) do
    if k == key then
      table.remove(self.db.queue, i)
      break
    end
  end
  local player = self.db.players[key]
  if player then
    player.queuePos = nil
  end
  if self.CompactQueue then
    self:CompactQueue()
  end
end

function GLD:InsertToQueue(key, position)
  if not key then
    return
  end
  self.db.queue = self.db.queue or {}
  local count = #self.db.queue
  local pos = tonumber(position)
  if not pos or pos < 1 or pos > count + 1 then
    pos = count + 1
  end
  table.insert(self.db.queue, pos, key)
  self:CompactQueue()
end

function GLD:CompactQueue()
  self.db.queue = self.db.queue or {}
  local newQueue = {}
  local seen = {}
  for _, key in ipairs(self.db.queue) do
    local player = self.db.players[key]
    if player then
      local normalized = NormalizeAttendanceState(player.attendance)
      if (normalized == "Present" or normalized == "Absent") and normalized ~= player.attendance then
        player.attendance = normalized
      end
    end
    if player and IsPresentState(player.attendance) and not seen[key] then
      table.insert(newQueue, key)
      seen[key] = true
    end
  end
  self.db.queue = newQueue
  for i, key in ipairs(self.db.queue) do
    local player = self.db.players[key]
    if player then
      player.queuePos = i
    end
  end
end

function GLD:SetAttendance(key, state)
  if not key then
    return
  end
  local player = self.db.players[key]
  if not player then
    return
  end

  local normalized = NormalizeAttendanceState(state)
  if normalized ~= "Absent" then
    normalized = "Present"
  end

  local current = NormalizeAttendanceState(player.attendance)
  if current ~= "Absent" then
    current = "Present"
  end

  if normalized == "Absent" then
    if current ~= "Absent" then
      if player.queuePos then
        SetHoldPos(player, player.queuePos)
      end
      self:RemoveFromQueue(key)
    end
    player.attendance = "Absent"
    return
  end

  if current == "Absent" then
    local desiredPos = nil
    local holdPos = GetHoldPos(player)
    if holdPos and holdPos >= 1 then
      desiredPos = holdPos
    end
    player.attendance = "Present"
    self:InsertToQueue(key, desiredPos)
    ClearHoldPos(player)
    return
  end

  player.attendance = "Present"
end

function GLD:EnsureQueuePositions()
  self.db.queue = self.db.queue or {}
  local inQueue = {}
  for _, key in ipairs(self.db.queue) do
    inQueue[key] = true
  end
  for key, player in pairs(self.db.players or {}) do
    if player and IsPresentState(player.attendance) and not inQueue[key] then
      table.insert(self.db.queue, key)
      inQueue[key] = true
    end
  end
  self:CompactQueue()
end

function GLD:MoveToQueueBottom(key)
  if not key then
    return
  end
  self:RemoveFromQueue(key)
  self:InsertToQueue(key)
end

function GLD:OnAwardedItem(key)
  if not key then
    return false
  end
  local player = self.db.players[key]
  if not player then
    return false
  end
  if not IsPresentState(player.attendance) then
    return false
  end
  player.attendance = NormalizeAttendanceState(player.attendance) or "Present"
  player.numAccepted = (player.numAccepted or 0) + 1
  self:MoveToQueueBottom(key)
  return true
end

function GLD:RemovePlayerFromDatabase(key)
  if not key or not self.db or not self.db.players then
    return false
  end

  if self.RemoveFromQueue then
    self:RemoveFromQueue(key)
  end

  if self.db.queue then
    for i = #self.db.queue, 1, -1 do
      if self.db.queue[i] == key then
        table.remove(self.db.queue, i)
      end
    end
  end

  if self.db.session and self.db.session.attended then
    self.db.session.attended[key] = nil
  end

  self.db.players[key] = nil

  if self.CompactQueue then
    self:CompactQueue()
  end

  return true
end

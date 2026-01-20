local _, NS = ...

local GLD = NS.GLD

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
    if player and player.attendance == "PRESENT" and not seen[key] then
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

  if state == "ABSENT" then
    if player.attendance ~= "ABSENT" then
      player.savedPos = player.queuePos or player.savedPos
      self:RemoveFromQueue(key)
    end
    player.attendance = "ABSENT"
    return
  end

  if state == "PRESENT" then
    if player.attendance ~= "PRESENT" then
      player.attendance = "PRESENT"
      self:InsertToQueue(key, player.savedPos)
    end
    return
  end

  player.attendance = state
end

function GLD:EnsureQueuePositions()
  self.db.queue = self.db.queue or {}
  local inQueue = {}
  for _, key in ipairs(self.db.queue) do
    inQueue[key] = true
  end
  for key, player in pairs(self.db.players or {}) do
    if player and player.attendance == "PRESENT" and not inQueue[key] then
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

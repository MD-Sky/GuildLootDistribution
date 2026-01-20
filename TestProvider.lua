local _, NS = ...

local GLD = NS.GLD

local TestProvider = {}
NS.TestProvider = TestProvider

function TestProvider:GetPlayers()
  return GLD.testDb and GLD.testDb.players or {}
end

function TestProvider:GetPlayer(key)
  local players = self:GetPlayers()
  return players and players[key] or nil
end

function TestProvider:GetPlayerKeyByName(name, realm)
  if GLD.FindTestPlayerKeyByName then
    return GLD:FindTestPlayerKeyByName(name, realm)
  end
  return nil
end

function TestProvider:GetQueuePos(key)
  local player = self:GetPlayer(key)
  return player and player.queuePos or 99999
end

function TestProvider:GetHeldPos(key)
  local player = self:GetPlayer(key)
  return player and player.savedPos or 0
end

function TestProvider:GetPlayerName(key)
  local player = self:GetPlayer(key)
  if player and player.name then
    if player.realm and player.realm ~= "" then
      return player.name .. "-" .. player.realm
    end
    return player.name
  end
  return key
end

function TestProvider:UpdateAward(key, itemContext)
  local player = self:GetPlayer(key)
  if not player then
    return
  end
  player.numAccepted = (player.numAccepted or 0) + 1
  player.lastWinAt = GetServerTime()
end

function TestProvider:GetEligiblePlayers(itemContext)
  local list = {}
  for key, player in pairs(self:GetPlayers() or {}) do
    if player and player.attendance ~= "ABSENT" then
      list[#list + 1] = player
    end
  end
  return list
end

function TestProvider:BuildExpectedVoters()
  local list = {}
  for key in pairs(self:GetPlayers() or {}) do
    list[#list + 1] = key
  end
  return list
end

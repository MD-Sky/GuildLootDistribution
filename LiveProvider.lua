local _, NS = ...

local GLD = NS.GLD

local LiveProvider = {}
NS.LiveProvider = LiveProvider

function LiveProvider:GetPlayers()
  return GLD.db and GLD.db.players or {}
end

function LiveProvider:GetPlayer(key)
  local players = self:GetPlayers()
  return players and players[key] or nil
end

function LiveProvider:GetPlayerKeyByName(name, realm)
  if GLD.FindPlayerKeyByName then
    return GLD:FindPlayerKeyByName(name, realm)
  end
  return nil
end

function LiveProvider:GetQueuePos(key)
  local player = self:GetPlayer(key)
  return player and player.queuePos or 99999
end

function LiveProvider:GetHeldPos(key)
  local player = self:GetPlayer(key)
  return player and player.savedPos or 0
end

function LiveProvider:GetPlayerName(key)
  local player = self:GetPlayer(key)
  if player and player.name then
    if player.realm and player.realm ~= "" then
      return player.name .. "-" .. player.realm
    end
    return player.name
  end
  return key
end

function LiveProvider:UpdateAward(key, itemContext)
  local player = self:GetPlayer(key)
  if not player then
    return
  end
  player.numAccepted = (player.numAccepted or 0) + 1
  player.lastWinAt = GetServerTime()
end

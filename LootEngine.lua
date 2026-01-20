local _, NS = ...

local LootEngine = {}
NS.LootEngine = LootEngine

local DEFAULT_PRIORITY = { "NEED", "GREED", "TRANSMOG" }

function LootEngine:BuildEligiblePlayers(itemContext, provider)
  if provider and provider.GetEligiblePlayers then
    return provider:GetEligiblePlayers(itemContext)
  end
  if provider and provider.GetPlayers then
    local list = {}
    for _, player in pairs(provider:GetPlayers() or {}) do
      list[#list + 1] = player
    end
    return list
  end
  return {}
end

function LootEngine:ApplyRestrictions(players, sessionState)
  return players or {}
end

function LootEngine:ComputeQueue(players)
  return players or {}
end

function LootEngine:RecordVote(session, playerKey, voteType)
  if not session or not playerKey then
    return
  end
  session.votes = session.votes or {}
  session.votes[playerKey] = voteType
end

function LootEngine:ResolveWinner(votes, provider, rules)
  if not provider then
    return nil
  end
  local priority = (rules and rules.priority) or DEFAULT_PRIORITY
  local winnerKey = nil
  local bestPos = nil
  local bestName = nil

  local function getQueuePos(key)
    if provider.GetQueuePos then
      return provider:GetQueuePos(key)
    end
    return 99999
  end

  local function getName(key)
    if provider.GetPlayerName then
      return provider:GetPlayerName(key)
    end
    return key
  end

  for _, voteType in ipairs(priority) do
    for key, vote in pairs(votes or {}) do
      if vote == voteType then
        local pos = getQueuePos(key) or 99999
        local name = getName(key) or key
        if not winnerKey or pos < bestPos or (pos == bestPos and name < (bestName or "~")) then
          winnerKey = key
          bestPos = pos
          bestName = name
        end
      end
    end
    if winnerKey then
      return winnerKey
    end
  end
  return nil
end

function LootEngine:CommitAward(winnerKey, itemContext, provider)
  if not winnerKey or not provider then
    return
  end
  if provider.UpdateAward then
    provider:UpdateAward(winnerKey, itemContext)
  end
end

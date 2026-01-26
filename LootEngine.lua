local _, NS = ...

local LootEngine = {}
NS.LootEngine = LootEngine

local GLD = NS.GLD

local DEFAULT_PRIORITY = { "NEED", "GREED", "TRANSMOG" }

local function DebugLog(msg)
  if GLD and GLD.IsDebugEnabled and GLD:IsDebugEnabled() then
    GLD:Debug(msg)
  end
end

local function GetItemReference(itemContext)
  if not itemContext then
    return nil
  end
  return itemContext.itemLink or itemContext.itemID or itemContext.itemName
end

local function IsItemDataReady(itemRef)
  if not itemRef or not C_Item or not C_Item.GetItemInfoInstant then
    return false
  end
  local itemId = C_Item.GetItemInfoInstant(itemRef)
  return itemId ~= nil
end

local function GetPlayerClassFile(player)
  if not player then
    return nil
  end
  return player.classFile or player.classFileName or player.classToken or player.class
end

local function GetPlayerSpecName(player)
  if not player then
    return nil
  end
  return player.specName or player.spec
end

local function GetEligibilityChecker(voteType)
  if not GLD then
    return nil
  end
  if voteType == "NEED" then
    return GLD.IsEligibleForNeed
  end
  if voteType == "TRANSMOG" then
    return GLD.IsEligibleForTransmog or GLD.IsEligibleForNeed
  end
  return nil
end

local function ShouldFilterVoteType(voteType)
  return voteType == "NEED" or voteType == "TRANSMOG"
end

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

function LootEngine:ResolveWinner(votes, provider, rules, itemContext)
  if not provider then
    return nil
  end
  local priority = (rules and rules.priority) or DEFAULT_PRIORITY
  local itemRef = GetItemReference(itemContext)
  local itemReady = IsItemDataReady(itemRef)
  if itemRef and not itemReady and GLD and GLD.RequestItemData then
    GLD:RequestItemData(itemRef)
  end

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

  local function buildCandidates(voteType)
    local candidates = {}
    for key, vote in pairs(votes or {}) do
      if vote == voteType then
        candidates[#candidates + 1] = key
      end
    end
    return candidates
  end

  local function filterEligible(voteType, candidates)
    local beforeCount = #candidates
    if beforeCount == 0 then
      return candidates, beforeCount, 0
    end
    if not ShouldFilterVoteType(voteType) then
      return candidates, beforeCount, beforeCount
    end

    local checker = GetEligibilityChecker(voteType)
    if not checker then
      DebugLog("Eligibility skipped for " .. tostring(voteType) .. " (no checker).")
      return candidates, beforeCount, beforeCount
    end
    if not itemRef then
      DebugLog("Eligibility skipped for " .. tostring(voteType) .. " (no item context).")
      return candidates, beforeCount, beforeCount
    end
    if not itemReady then
      DebugLog("Eligibility skipped for " .. tostring(voteType) .. " (item data missing).")
      return candidates, beforeCount, beforeCount
    end

    local eligible = {}
    for _, key in ipairs(candidates) do
      local player = provider.GetPlayer and provider:GetPlayer(key) or nil
      local classFile = GetPlayerClassFile(player)
      if classFile and classFile ~= "" then
        classFile = tostring(classFile):upper()
        local specName = GetPlayerSpecName(player)
        local ok = checker(GLD, classFile, itemRef, specName)
        if ok then
          eligible[#eligible + 1] = key
        else
          DebugLog(
            "Excluded "
              .. tostring(getName(key) or key)
              .. " from "
              .. tostring(voteType)
              .. " (ineligible)."
          )
        end
      else
        DebugLog("Eligibility skipped for " .. tostring(getName(key) or key) .. " (missing class).")
        eligible[#eligible + 1] = key
      end
    end
    return eligible, beforeCount, #eligible
  end

  for _, voteType in ipairs(priority) do
    local candidates = buildCandidates(voteType)
    local eligible, beforeCount, afterCount = filterEligible(voteType, candidates)
    if GLD and GLD.IsDebugEnabled and GLD:IsDebugEnabled() then
      DebugLog(
        "Resolve " .. tostring(voteType) .. ": candidates=" .. tostring(beforeCount) .. " eligible=" .. tostring(afterCount)
      )
    end
    if #eligible > 0 then
      local winnerKey = nil
      local bestPos = nil
      local bestName = nil
      for _, key in ipairs(eligible) do
        local pos = getQueuePos(key) or 99999
        local name = getName(key) or key
        if not winnerKey or pos < bestPos or (pos == bestPos and name < (bestName or "~")) then
          winnerKey = key
          bestPos = pos
          bestName = name
        end
      end
      if winnerKey then
        DebugLog("ResolveWinner selected: " .. tostring(getName(winnerKey) or winnerKey) .. " via " .. tostring(voteType))
        return winnerKey
      end
    end
  end
  DebugLog("ResolveWinner selected: none")
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

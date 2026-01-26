local _, NS = ...

local GLD = NS.GLD
local LootEngine = NS.LootEngine
local LiveProvider = NS.LiveProvider
local TestProvider = NS.TestProvider

function GLD:InitLoot()
  self.activeRolls = {}
  self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
  if C_Timer and C_Timer.NewTicker then
    -- Periodic cleanup to keep roll data from growing in long sessions.
    self.cleanupTicker = C_Timer.NewTicker(300, function()
      if self.CleanupActiveRolls then
        self:CleanupActiveRolls(1800)
      else
        self:CleanupOldTestRolls(1800)
      end
    end)
  end
end

local function GetRollRemainingTimeMs(session)
  if not session then
    return nil
  end
  if session.rollExpiresAt then
    local remaining = (session.rollExpiresAt - GetServerTime()) * 1000
    if remaining < 0 then
      remaining = 0
    end
    return remaining
  end
  return session.rollTime
end

local function CountActiveRolls(activeRolls)
  local count = 0
  for _ in pairs(activeRolls or {}) do
    count = count + 1
  end
  return count
end

local function IsPlayerGuidKey(key)
  return type(key) == "string" and key:find("^Player%-") ~= nil
end

function GLD:GetWhisperTargetForPlayerKey(key)
  if not key then
    return nil
  end
  if IsPlayerGuidKey(key) then
    if IsInRaid() then
      for i = 1, GetNumGroupMembers() do
        local unit = "raid" .. i
        if UnitExists(unit) and UnitGUID(unit) == key then
          return self:GetUnitFullName(unit) or UnitName(unit)
        end
      end
    end
    local name = LiveProvider and LiveProvider.GetPlayerName and LiveProvider:GetPlayerName(key) or nil
    if name and name ~= key then
      return name
    end
    return nil
  end
  return key
end

function GLD:GetRaidWhisperTargets()
  local targets = {}
  local seen = {}
  if not IsInRaid() then
    return targets
  end
  for i = 1, GetNumGroupMembers() do
    local unit = "raid" .. i
    if UnitExists(unit) then
      local name = self:GetUnitFullName(unit) or UnitName(unit)
      if name and not seen[name] then
        targets[#targets + 1] = name
        seen[name] = true
      end
    end
  end
  return targets
end

function GLD:GetMissingAckTargetsForSession(session)
  if not session then
    return {}
  end
  local targets = {}
  local seen = {}
  local expected = session.expectedVoters or {}
  local acks = session.acks or {}
  if #expected == 0 then
    return self:GetRaidWhisperTargets()
  end
  for _, key in ipairs(expected) do
    if key and not acks[key] then
      local name = self:GetWhisperTargetForPlayerKey(key)
      if name and not seen[name] then
        targets[#targets + 1] = name
        seen[name] = true
      end
    end
  end
  if #targets == 0 then
    return self:GetRaidWhisperTargets()
  end
  return targets
end

function GLD:GetMissingAckTargetsForActiveRolls()
  local targets = {}
  local seen = {}
  for _, session in pairs(self.activeRolls or {}) do
    if session and not session.locked and not session.isTest then
      for _, name in ipairs(self:GetMissingAckTargetsForSession(session)) do
        if name and not seen[name] then
          targets[#targets + 1] = name
          seen[name] = true
        end
      end
    end
  end
  return targets
end

function GLD:BuildRollSessionPayload(session, options)
  if not session then
    return nil
  end
  local votes = nil
  if session.votes then
    votes = {}
    for k, v in pairs(session.votes) do
      votes[k] = v
    end
  end
  local expected = nil
  if session.expectedVoters then
    expected = {}
    for i, key in ipairs(session.expectedVoters) do
      expected[i] = key
    end
  end
  local expectedClasses = nil
  if session.expectedVoterClasses then
    expectedClasses = {}
    for k, v in pairs(session.expectedVoterClasses) do
      expectedClasses[k] = v
    end
  end

  return {
    rollID = session.rollID,
    rollKey = session.rollKey,
    rollTime = GetRollRemainingTimeMs(session),
    rollExpiresAt = session.rollExpiresAt,
    itemLink = session.itemLink,
    itemName = session.itemName,
    itemID = session.itemID,
    itemIcon = session.itemIcon,
    quality = session.quality,
    count = session.count,
    canNeed = session.canNeed,
    canGreed = session.canGreed,
    canTransmog = session.canTransmog,
    expectedVoters = expected,
    expectedVoterClasses = expectedClasses,
    createdAt = session.createdAt,
    votes = votes,
    authorityGUID = self:GetAuthorityGUID(),
    authorityName = self:GetAuthorityName(),
    reopen = options and options.reopen or nil,
    snapshot = options and options.snapshot or nil,
  }
end

function GLD:BroadcastRollSession(session, options, target)
  if not session or session.isTest then
    return
  end
  if self:IsAuthority() then
    session.acks = session.acks or {}
    local myKey = NS:GetPlayerKeyFromUnit("player")
    if myKey then
      session.acks[myKey] = true
    end
  end
  local payload = self:BuildRollSessionPayload(session, options)
  if not payload then
    return
  end
  if target and target ~= "" then
    self:SendCommMessageSafe(NS.MSG.ROLL_SESSION, payload, "WHISPER", target)
    return
  end
  if not IsInRaid() then
    return
  end
  self:SendCommMessageSafe(NS.MSG.ROLL_SESSION, payload, "RAID")
  if self:IsAuthority() and self.ScheduleRollSessionResend then
    self:ScheduleRollSessionResend(session)
  end
end

function GLD:ScheduleRollSessionResend(session)
  if not session or session.isTest then
    return
  end
  if not self:IsAuthority() or not IsInRaid() then
    return
  end
  if session.resendScheduled then
    return
  end
  session.resendScheduled = true

  local function checkAndResend()
    if not self:IsAuthority() or not IsInRaid() then
      return
    end
    if not session or session.locked then
      return
    end
    local active = self.activeRolls and session.rollKey and self.activeRolls[session.rollKey] or nil
    if active ~= session then
      return
    end
    local targets = self:GetMissingAckTargetsForSession(session)
    if #targets == 0 then
      return
    end
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug(
        "Roll resend check: rollID="
          .. tostring(session.rollID)
          .. " rollKey="
          .. tostring(session.rollKey)
          .. " missing="
          .. tostring(#targets)
      )
    end
    for _, target in ipairs(targets) do
      self:BroadcastRollSession(session, { snapshot = true, reopen = true }, target)
    end
  end

  C_Timer.After(1, checkAndResend)
  C_Timer.After(3, checkAndResend)
end

function GLD:BroadcastActiveRollsSnapshot(targets, options)
  if not self:IsAuthority() then
    return
  end
  if not self.db or not self.db.session or not self.db.session.active then
    return
  end
  if not IsInRaid() then
    return
  end
  if not self.activeRolls then
    return
  end
  local snapshotOptions = options or {}
  for _, session in pairs(self.activeRolls) do
    if session and not session.locked and not session.isTest then
      if targets and #targets > 0 then
        for _, target in ipairs(targets) do
          self:BroadcastRollSession(session, { snapshot = true, reopen = snapshotOptions.reopen }, target)
        end
      else
        self:BroadcastRollSession(session, { snapshot = true, reopen = snapshotOptions.reopen })
      end
    end
  end
end

function GLD:ForcePendingVotesWindow()
  if not self:IsAuthority() then
    return false
  end
  if not IsInRaid() then
    return false
  end
  if self.BroadcastActiveRollsSnapshot then
    local targets = self:GetMissingAckTargetsForActiveRolls()
    if #targets == 0 then
      targets = self:GetRaidWhisperTargets()
    end
    if #targets > 0 then
      self:BroadcastActiveRollsSnapshot(targets, { reopen = true })
    else
      self:BroadcastActiveRollsSnapshot()
    end
  end
  local payload = {
    authorityGUID = self:GetAuthorityGUID(),
    authorityName = self:GetAuthorityName(),
    requestedAt = GetServerTime(),
  }
  self:SendCommMessageSafe(NS.MSG.FORCE_PENDING, payload, "RAID")
  if self.UI and self.UI.ShowPendingFrame then
    self.UI:ShowPendingFrame()
  end
  self:TraceStep("Force pending votes window sent to raid.")
  return true
end

function GLD:CleanupActiveRolls(maxAgeSeconds)
  if not self.activeRolls then
    return
  end
  local now = GetServerTime()
  local maxAge = maxAgeSeconds or 1800
  for rollKey, session in pairs(self.activeRolls) do
    if not session or (self.IsRollSessionExpired and self:IsRollSessionExpired(session, now, maxAge)) then
      self.activeRolls[rollKey] = nil
    end
  end
end

function GLD:CleanupOldTestRolls(maxAgeSeconds)
  self:CleanupActiveRolls(maxAgeSeconds)
end

function GLD:GetActiveTestSession()
  if not self.testDb or not self.testDb.testSession or not self.testDb.testSession.currentId then
    return nil
  end
  for _, entry in ipairs(self.testDb.testSessions or {}) do
    if entry.id == self.testDb.testSession.currentId then
      return entry
    end
  end
  return nil
end

local function RollTypeToVote(rollType)
  if rollType == LOOT_ROLL_TYPE_NEED then
    return "NEED"
  end
  if rollType == LOOT_ROLL_TYPE_GREED then
    return "GREED"
  end
  if rollType == LOOT_ROLL_TYPE_PASS then
    return "PASS"
  end
  if LOOT_ROLL_TYPE_TRANSMOG and rollType == LOOT_ROLL_TYPE_TRANSMOG then
    return "TRANSMOG"
  end
  return nil
end

function GLD:BuildExpectedVoters()
  local list = {}
  local seen = {}

  local function addUnit(unit)
    if not UnitExists(unit) or not UnitIsConnected(unit) then
      return
    end
    local key = NS:GetPlayerKeyFromUnit(unit)
    if key and not seen[key] then
      table.insert(list, key)
      seen[key] = true
    end
  end

  if IsInRaid() then
    local count = GetNumGroupMembers()
    for i = 1, count do
      addUnit("raid" .. i)
    end
  else
    addUnit("player")
  end

  return list
end

function GLD:FindPlayerKeyByName(name, realm)
  if not name then
    return nil
  end
  local realmName = realm and realm ~= "" and realm or GetRealmName()
  for key, player in pairs(self.db.players or {}) do
    if player and player.name == name and (player.realm == realmName or not player.realm) then
      return key
    end
  end
  return nil
end

function GLD:GetRollCandidateKey(sender)
  if not sender then
    return nil
  end
  if type(sender) == "string" and sender:find("^Player%-") then
    return sender
  end
  local name, realm = NS:SplitNameRealm(sender)
  local key = self:FindPlayerKeyByName(name, realm)
  if key then
    return key
  end
  if self.GetGuidForSender then
    local guid = self:GetGuidForSender(sender)
    if guid then
      return guid
    end
  end
  return sender
end

function GLD:AnnounceRollResult(result)
  if not result then
    return
  end
  if not IsInRaid() then
    return
  end
  local channel = "RAID"
  local winnerName = result.winnerName or "None"
  local itemText = result.itemLink or result.itemName or "Item"
  local msg = string.format("GLD Result: %s -> %s", itemText, winnerName)
  SendChatMessage(msg, channel)
end

function GLD:RecordRollHistory(result)
  if not result then
    return
  end
  self.db.rollHistory = self.db.rollHistory or {}
  table.insert(self.db.rollHistory, 1, result)
  if #self.db.rollHistory > 200 then
    table.remove(self.db.rollHistory)
  end
end

function GLD:ResolveRollWinner(session)
  if not session or session.locked then
    return nil
  end
  if LootEngine and LootEngine.ResolveWinner then
    local provider = session.isTest and TestProvider or LiveProvider
    return LootEngine:ResolveWinner(session.votes or {}, provider, session.rules, session)
  end
  return nil
end

local function NormalizeVoteKey(provider, key)
  if provider and provider.GetPlayerName then
    local name = provider:GetPlayerName(key)
    if name and name ~= "" then
      return name
    end
  end
  return key
end

local function SnapshotVotes(votes, provider)
  local snapshot = {}
  local counts = { NEED = 0, GREED = 0, TRANSMOG = 0, PASS = 0 }
  if votes then
    for key, vote in pairs(votes) do
      local displayKey = NormalizeVoteKey(provider, key)
      snapshot[displayKey] = vote
      if vote and counts[vote] ~= nil then
        counts[vote] = counts[vote] + 1
      end
    end
  end
  return snapshot, counts
end

local function BuildMissingAtLock(expectedVoters, votes, provider)
  if not expectedVoters then
    return nil
  end
  local missing = {}
  for _, key in ipairs(expectedVoters) do
    local displayKey = key and NormalizeVoteKey(provider, key) or nil
    if displayKey and not (votes and votes[displayKey]) then
      missing[#missing + 1] = displayKey
    end
  end
  if #missing == 0 then
    return nil
  end
  return missing
end

local function CountVotes(votes)
  local count = 0
  for _ in pairs(votes or {}) do
    count = count + 1
  end
  return count
end

local function NormalizeMoveMode(mode)
  local value = tostring(mode or ""):upper()
  if value == "BOTTOM" then
    return "END"
  end
  if value == "END" or value == "MIDDLE" or value == "NONE" then
    return value
  end
  return "END"
end

function GLD:GetMoveModeForVoteType(voteType)
  local config = self.db and self.db.config or {}
  if voteType == "TRANSMOG" then
    return NormalizeMoveMode(config.transmogWinnerMove or "NONE")
  end
  if voteType == "GREED" then
    return NormalizeMoveMode(config.greedWinnerMove or "NONE")
  end
  return "END"
end

function GLD:ApplyWinnerMove(winnerKey, voteType)
  if not winnerKey then
    return nil
  end
  local mode = self:GetMoveModeForVoteType(voteType)
  local player = self.db and self.db.players and self.db.players[winnerKey] or nil
  local oldPos = player and player.queuePos or nil
  if mode == "NONE" then
    -- no movement
  elseif mode == "MIDDLE" then
    if self.MoveToQueueMiddle then
      self:MoveToQueueMiddle(winnerKey)
    end
  else
    if self.MoveToQueueBottom then
      self:MoveToQueueBottom(winnerKey)
    end
  end
  local newPos = player and player.queuePos or nil
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug(
      "Winner move: vote="
        .. tostring(voteType)
        .. " mode="
        .. tostring(mode)
        .. " pos="
        .. tostring(oldPos)
        .. "->"
        .. tostring(newPos)
    )
  end
  return mode
end

function GLD:FinalizeRoll(session)
  if not session or session.locked then
    return
  end
  if not session.isTest and not self:IsAuthority() then
    return
  end
  local winnerKey = self:ResolveRollWinner(session)
  if self:IsDebugEnabled() then
    local totalVotes = CountVotes(session.votes)
    local expectedCount = session.expectedVoters and #session.expectedVoters or 0
    self:Debug(
      "Finalize roll: rollID="
        .. tostring(session.rollID)
        .. " votes="
        .. tostring(totalVotes)
        .. "/"
        .. tostring(expectedCount)
        .. " winnerKey="
        .. tostring(winnerKey)
    )
  end
  local provider = session.isTest and TestProvider or LiveProvider
  if LootEngine and LootEngine.CommitAward then
    LootEngine:CommitAward(winnerKey, session, provider)
  end

  local winnerPlayer = winnerKey and provider and provider.GetPlayer and provider:GetPlayer(winnerKey) or nil
  local winnerName = winnerPlayer and winnerPlayer.name or (winnerKey or "None")
  local winnerFull = winnerName
  if winnerPlayer and winnerPlayer.realm and winnerPlayer.realm ~= "" then
    winnerFull = winnerPlayer.name .. "-" .. winnerPlayer.realm
  end
  local winnerVote = session.votes and winnerKey and session.votes[winnerKey] or nil

  local resolvedAt = GetServerTime()
  local voteSnapshot, voteCounts = SnapshotVotes(session.votes, provider)
  if self:IsDebugEnabled() then
    self:Debug(
      "Finalize roll votes: rollID="
        .. tostring(session.rollID)
        .. " NEED="
        .. tostring(voteCounts and voteCounts.NEED)
        .. " GREED="
        .. tostring(voteCounts and voteCounts.GREED)
        .. " TRANSMOG="
        .. tostring(voteCounts and voteCounts.TRANSMOG)
        .. " PASS="
        .. tostring(voteCounts and voteCounts.PASS)
    )
  end
  local missingAtLock = BuildMissingAtLock(session.expectedVoters, voteSnapshot, provider)
  local startedAt = session.createdAt or resolvedAt
  local resolvedBy = session.resolvedBy or "NORMAL"
  local result = {
    rollID = session.rollID,
    rollKey = session.rollKey,
    itemLink = session.itemLink,
    itemName = session.itemName,
    winnerKey = winnerKey,
    winnerName = winnerFull,
    votes = voteSnapshot,
    voteCounts = voteCounts,
    missingAtLock = missingAtLock,
    startedAt = startedAt,
    resolvedAt = resolvedAt,
    resolvedBy = resolvedBy,
  }

  session.locked = true
  session.result = result
  if self:IsDebugEnabled() then
    self:Debug("Result locked: rollID=" .. tostring(session.rollID) .. " winner=" .. tostring(winnerFull))
  end

  if not session.isTest then
    self:RecordRollHistory(result)
  end
  if session.isTest then
    self:RecordTestSessionLoot(result, session)
  else
    self:RecordSessionLoot(result, session)
  end
  if session.isTest and winnerKey and self.MoveTestPlayerToQueueBottom then
    self:MoveTestPlayerToQueueBottom(winnerKey)
    if NS.TestUI and NS.TestUI.RefreshTestPanel then
      NS.TestUI:RefreshTestPanel()
    end
  end
  if self:IsAuthority() and not session.isTest then
    self:AnnounceRollResult(result)
    if winnerKey then
      self:ApplyWinnerMove(winnerKey, winnerVote)
      self:BroadcastSnapshot()
    end
    if IsInRaid() then
      self:SendCommMessageSafe(NS.MSG.ROLL_RESULT, result, "RAID")
    end
    if self:IsDebugEnabled() then
      self:Debug("Result broadcast: rollID=" .. tostring(session.rollID))
    end
  end
  local activeKey = session.rollKey
  if not activeKey and self.FindActiveRoll then
    activeKey = select(1, self:FindActiveRoll(nil, session.rollID))
  end
  if activeKey and self.activeRolls then
    self.activeRolls[activeKey] = nil
  end
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end
  if self:IsDebugEnabled() then
    self:Debug(
      "Roll resolved: rollID="
        .. tostring(session.rollID)
        .. " rollKey="
        .. tostring(session.rollKey)
        .. " active="
        .. tostring(CountActiveRolls(self.activeRolls))
    )
  end
  if self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow()
  end
end

function GLD:ApplyAdminOverride(session, winnerKey)
  if not session or session.locked then
    return false
  end
  if not self:IsAuthority() then
    return false
  end

  local overrideBy = self:GetAuthorityName() or self:GetUnitFullName("player") or UnitName("player") or "Unknown"
  local isPass = not winnerKey or winnerKey == "" or winnerKey == "GLD_FORCE_PASS"
  if isPass then
    winnerKey = nil
  end

  local provider = session.isTest and TestProvider or LiveProvider
  local winnerPlayer = winnerKey and provider and provider.GetPlayer and provider:GetPlayer(winnerKey) or nil
  local winnerName = winnerPlayer and winnerPlayer.name or (winnerKey or "None")
  local winnerFull = winnerName
  if winnerPlayer and winnerPlayer.realm and winnerPlayer.realm ~= "" then
    winnerFull = winnerPlayer.name .. "-" .. winnerPlayer.realm
  end
  if isPass then
    winnerFull = "Unclaimed"
  end
  local winnerVote = session.votes and winnerKey and session.votes[winnerKey] or nil

  if winnerKey and LootEngine and LootEngine.CommitAward then
    LootEngine:CommitAward(winnerKey, session, provider)
  end

  local resolvedAt = GetServerTime()
  local voteSnapshot, voteCounts = SnapshotVotes(session.votes, provider)
  local missingAtLock = BuildMissingAtLock(session.expectedVoters, voteSnapshot, provider)
  local startedAt = session.createdAt or resolvedAt
  local authorityGUID = self:GetAuthorityGUID()
  local authorityName = self:GetAuthorityName()
  local result = {
    rollID = session.rollID,
    rollKey = session.rollKey,
    itemLink = session.itemLink,
    itemName = session.itemName,
    winnerKey = winnerKey,
    winnerName = winnerFull,
    votes = voteSnapshot,
    voteCounts = voteCounts,
    missingAtLock = missingAtLock,
    startedAt = startedAt,
    resolvedAt = resolvedAt,
    resolvedBy = "OVERRIDE",
    overrideBy = overrideBy,
    authorityGUID = authorityGUID,
    authorityName = authorityName,
  }

  session.locked = true
  session.result = result
  if self:IsDebugEnabled() then
    self:Debug(
      "Override applied: rollID="
        .. tostring(session.rollID)
        .. " item="
        .. tostring(session.itemLink or session.itemName or "Item")
        .. " winner="
        .. tostring(winnerFull)
        .. " by="
        .. tostring(overrideBy)
    )
  end

  if not session.isTest then
    self:RecordRollHistory(result)
  end
  if session.isTest then
    self:RecordTestSessionLoot(result, session)
  else
    self:RecordSessionLoot(result, session)
  end
  if session.isTest and winnerKey and self.MoveTestPlayerToQueueBottom then
    self:MoveTestPlayerToQueueBottom(winnerKey)
    if NS.TestUI and NS.TestUI.RefreshTestPanel then
      NS.TestUI:RefreshTestPanel()
    end
  end
  if self:IsAuthority() and not session.isTest then
    self:AnnounceRollResult(result)
    if winnerKey then
      self:ApplyWinnerMove(winnerKey, winnerVote)
      self:BroadcastSnapshot()
    end
    if IsInRaid() then
      self:SendCommMessageSafe(NS.MSG.ROLL_RESULT, result, "RAID")
    end
    if self:IsDebugEnabled() then
      self:Debug("Override result broadcast: rollID=" .. tostring(session.rollID))
    end
  end
  local activeKey = session.rollKey
  if not activeKey and self.FindActiveRoll then
    activeKey = select(1, self:FindActiveRoll(nil, session.rollID))
  end
  if activeKey and self.activeRolls then
    self.activeRolls[activeKey] = nil
  end
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end
  if self:IsDebugEnabled() then
    self:Debug(
      "Roll resolved: rollID="
        .. tostring(session.rollID)
        .. " rollKey="
        .. tostring(session.rollKey)
        .. " active="
        .. tostring(CountActiveRolls(self.activeRolls))
    )
  end
  if self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow()
  end
  return true
end

function GLD:RecordTestSessionLoot(result, session)
  if not result or not self.testDb or not self.testDb.testSession or not self.testDb.testSession.active then
    return
  end
  local testSession = self:GetActiveTestSession()
  if not testSession then
    return
  end

  local lootEntry = {
    rollID = result.rollID,
    itemLink = result.itemLink,
    itemName = result.itemName,
    winnerKey = result.winnerKey,
    winnerName = result.winnerName,
    votes = result.votes,
    voteCounts = result.voteCounts,
    missingAtLock = result.missingAtLock,
    startedAt = result.startedAt,
    resolvedAt = result.resolvedAt or GetServerTime(),
    resolvedBy = result.resolvedBy or "NORMAL",
    overrideBy = result.overrideBy,
  }

  if self:IsDebugEnabled() then
    self:Debug("Test history entry saved votes: rollID=" .. tostring(result.rollID) .. " votes=" .. tostring(CountVotes(lootEntry.votes)))
  end

  testSession.loot = testSession.loot or {}
  table.insert(testSession.loot, 1, lootEntry)

  local encounterId = session and session.testEncounterId or nil
  local encounterName = session and session.testEncounterName or nil
  if encounterId or encounterName then
    testSession.bosses = testSession.bosses or {}
    local bossEntry = nil
    for _, boss in ipairs(testSession.bosses) do
      if encounterId and boss.encounterId == encounterId then
        bossEntry = boss
        break
      end
      if not encounterId and encounterName and boss.encounterName == encounterName then
        bossEntry = boss
        break
      end
    end
    if not bossEntry then
      bossEntry = {
        encounterId = encounterId,
        encounterName = encounterName or "Encounter",
        killedAt = GetServerTime(),
        loot = {},
      }
      table.insert(testSession.bosses, bossEntry)
    end
    bossEntry.loot = bossEntry.loot or {}
    table.insert(bossEntry.loot, 1, lootEntry)
  end
end

function GLD:RecordSessionLoot(result, session)
  if not result or not self.db.session or not self.db.session.active then
    return
  end
  local raidSession = self.GetActiveRaidSession and self:GetActiveRaidSession() or nil
  if not raidSession then
    return
  end

  local lootEntry = {
    rollID = result.rollID,
    itemLink = result.itemLink,
    itemName = result.itemName,
    winnerKey = result.winnerKey,
    winnerName = result.winnerName,
    votes = result.votes,
    voteCounts = result.voteCounts,
    missingAtLock = result.missingAtLock,
    startedAt = result.startedAt,
    resolvedAt = result.resolvedAt or GetServerTime(),
    resolvedBy = result.resolvedBy or "NORMAL",
    overrideBy = result.overrideBy,
  }

  if self:IsDebugEnabled() then
    self:Debug("History entry saved votes: rollID=" .. tostring(result.rollID) .. " votes=" .. tostring(CountVotes(lootEntry.votes)))
  end

  raidSession.loot = raidSession.loot or {}
  table.insert(raidSession.loot, 1, lootEntry)

  local bossCtx = self.db.session.currentBoss
  if bossCtx and bossCtx.encounterID and bossCtx.killedAt then
    for _, boss in ipairs(raidSession.bosses or {}) do
      if boss.encounterID == bossCtx.encounterID and boss.killedAt == bossCtx.killedAt then
        boss.loot = boss.loot or {}
        table.insert(boss.loot, 1, lootEntry)
        break
      end
    end
  end
  if self.UI and self.UI.RefreshHistoryIfOpen then
    self.UI:RefreshHistoryIfOpen()
  end
end

function GLD:CheckRollCompletion(session)
  if not session or session.locked then
    return
  end
  local expected = session.expectedVoters or {}
  local votes = session.votes or {}
  local count = 0
  for _, key in ipairs(expected) do
    if votes[key] then
      count = count + 1
    end
  end
  if count >= #expected and #expected > 0 then
    self:FinalizeRoll(session)
  end
end

function GLD:NoteMismatch(session, playerName, expectedVote, actualVote)
  if not session then
    return
  end
  session.mismatches = session.mismatches or {}
  table.insert(session.mismatches, {
    name = playerName,
    expected = expectedVote,
    actual = actualVote,
  })
  if self:IsAuthority() then
    local msg = string.format("GLD mismatch: %s declared %s but rolled %s", tostring(playerName), tostring(expectedVote), tostring(actualVote))
    if IsInRaid() then
      SendChatMessage(msg, "RAID")
      self:SendCommMessageSafe(NS.MSG.ROLL_MISMATCH, {
        rollID = session.rollID,
        rollKey = session.rollKey,
        name = playerName,
        expected = expectedVote,
        actual = actualVote,
      }, "RAID")
    end
  end
end

function GLD:OnStartLootRoll(event, rollID, rollTime, lootHandle)
  local debugEnabled = self:IsDebugEnabled()
  if type(rollID) ~= "number" then
    if debugEnabled then
      self:Debug("Ignoring START_LOOT_ROLL (invalid rollID): event=" .. tostring(event) .. " rollID=" .. tostring(rollID))
    end
    return
  end
  if not IsInRaid() or not self.db or not self.db.session or not self.db.session.active then
    if debugEnabled then
      self:Debug("Ignoring START_LOOT_ROLL (not in active raid session): inRaid=" .. tostring(IsInRaid()) .. " hasDB=" .. tostring(self.db ~= nil) .. " sessionActive=" .. tostring(self.db and self.db.session and self.db.session.active))
    end
    return
  end
  if not self:IsAuthority() then
    if debugEnabled then
      self:Debug("Ignoring START_LOOT_ROLL (not authority): leader=" .. tostring(UnitIsGroupLeader("player")) .. " assistant=" .. tostring(UnitIsGroupAssistant("player")))
    end
    return
  end

  self.activeRolls = self.activeRolls or {}
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end
  local existingKey = nil
  local existingSession = nil
  if self.FindActiveRoll then
    existingKey, existingSession = self:FindActiveRoll(nil, rollID)
  end
  if existingSession and not (self.IsRollSessionExpired and self:IsRollSessionExpired(existingSession, nil, 1800)) then
    if self:IsDebugEnabled() then
      self:Debug("Duplicate START_LOOT_ROLL ignored: rollID=" .. tostring(rollID))
    end
    return
  end
  if existingKey and existingSession then
    self.activeRolls[existingKey] = nil
  end

  local texture, name, count, quality, bop, canNeed, canGreed, canDE, canTransmog, reason = GetLootRollItemInfo(rollID)
  local link = GetLootRollItemLink(rollID)
  if debugEnabled and not link and not name then
    self:Debug("START_LOOT_ROLL missing item info: rollID=" .. tostring(rollID) .. " reason=" .. tostring(reason) .. " bop=" .. tostring(bop))
  end
  local itemID = nil
  if link and GetItemInfoInstant then
    itemID = select(1, GetItemInfoInstant(link))
  end

  local rollTimeMs = tonumber(rollTime) or 120000
  local createdAt = GetServerTime()
  local rollExpiresAt = rollTimeMs > 0 and (createdAt + math.floor(rollTimeMs / 1000)) or nil

  local rollKey = nil
  if self.BuildRollNonce and self.MakeRollKey then
    rollKey = self:MakeRollKey(rollID, self:BuildRollNonce())
    if rollKey and self.activeRolls[rollKey] then
      rollKey = self:MakeRollKey(rollID, self:BuildRollNonce())
    end
  end
  rollKey = rollKey or (self.GetLegacyRollKey and self:GetLegacyRollKey(rollID)) or (tostring(rollID) .. "@legacy")

  local session = {
    rollID = rollID,
    rollKey = rollKey,
    rollTime = rollTimeMs,
    rollExpiresAt = rollExpiresAt,
    itemLink = link,
    itemName = name,
    itemID = itemID,
    itemIcon = texture,
    quality = quality,
    count = count,
    canNeed = canNeed,
    canGreed = canGreed,
    canTransmog = canTransmog,
    votes = {},
    expectedVoters = self:BuildExpectedVoters(),
    createdAt = createdAt,
  }
  self.activeRolls[rollKey] = session

  if self:IsDebugEnabled() then
    self:Debug("Roll started detected: rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey) .. " item=" .. tostring(link or name or "Unknown"))
    self:Debug("Active rolls: " .. tostring(CountActiveRolls(self.activeRolls)))
  end

  if link then
    self:RequestItemData(link)
  end

  self:BroadcastRollSession(session)

  if self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow({ forceShow = true })
  end

  local delay = (tonumber(rollTimeMs) or 120000) / 1000
  session.timerStarted = true
  C_Timer.After(delay, function()
    local active = self.activeRolls and rollKey and self.activeRolls[rollKey] or nil
    if active and not active.locked then
      self:FinalizeRoll(active)
    end
  end)

  C_Timer.After(delay + 1, function()
    self:OnLootHistoryRollChanged()
  end)
  C_Timer.After(delay + 6, function()
    self:OnLootHistoryRollChanged()
  end)
end

function GLD:OnLootHistoryRollChanged()
  if not C_LootHistory or not C_LootHistory.GetItem then
    return
  end
  if not self.activeRolls then
    return
  end
  local numItems = C_LootHistory.GetNumItems and C_LootHistory.GetNumItems() or 0
  if numItems <= 0 then
    return
  end
  -- Index active rolls by item link to avoid scanning all rolls per loot history item.
  local sessionsByLink = nil
  for _, session in pairs(self.activeRolls) do
    if session and session.itemLink and session.votes then
      sessionsByLink = sessionsByLink or {}
      local list = sessionsByLink[session.itemLink]
      if not list then
        list = {}
        sessionsByLink[session.itemLink] = list
      end
      list[#list + 1] = session
    end
  end
  if not sessionsByLink then
    return
  end
  for itemIndex = 1, numItems do
    local lootID, itemLink, itemQuality, itemGUID, numPlayers = C_LootHistory.GetItem(itemIndex)
    if itemLink and numPlayers and numPlayers > 0 then
      local sessions = sessionsByLink[itemLink]
      if sessions then
        for _, session in ipairs(sessions) do
          for playerIndex = 1, numPlayers do
            local name, class, rollType = C_LootHistory.GetPlayerInfo(itemIndex, playerIndex)
            local declaredKey = self:GetRollCandidateKey(name)
            local declaredVote = declaredKey and session.votes[declaredKey] or nil
            local actualVote = RollTypeToVote(rollType)
            if declaredVote and actualVote and declaredVote ~= actualVote then
              self:NoteMismatch(session, name, declaredVote, actualVote)
            end
          end
        end
      end
    end
  end
end

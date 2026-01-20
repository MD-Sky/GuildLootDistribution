local _, NS = ...

local GLD = NS.GLD
local LootEngine = NS.LootEngine
local LiveProvider = NS.LiveProvider
local TestProvider = NS.TestProvider

function GLD:InitLoot()
  self.activeRolls = {}
  self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
  if C_Timer and C_Timer.NewTicker then
    -- Periodic cleanup to keep test roll data from growing in long sessions.
    self.cleanupTicker = C_Timer.NewTicker(300, function()
      self:CleanupOldTestRolls(1800)
    end)
  end
end

function GLD:CleanupOldTestRolls(maxAgeSeconds)
  if not self.activeRolls then
    return
  end
  local now = GetServerTime()
  local cutoff = now - (maxAgeSeconds or 1800)
  for rollID, session in pairs(self.activeRolls) do
    if session and session.isTest then
      local createdAt = session.createdAt or 0
      if session.locked or createdAt == 0 or createdAt < cutoff then
        self.activeRolls[rollID] = nil
      end
    end
  end
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
  elseif IsInGroup() then
    local count = GetNumSubgroupMembers()
    for i = 1, count do
      addUnit("party" .. i)
    end
    addUnit("player")
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
  local name, realm = NS:SplitNameRealm(sender)
  return self:FindPlayerKeyByName(name, realm) or sender
end

function GLD:AnnounceRollResult(result)
  if not result then
    return
  end
  local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
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
    return LootEngine:ResolveWinner(session.votes or {}, provider, session.rules)
  end
  return nil
end

function GLD:FinalizeRoll(session)
  if not session or session.locked then
    return
  end
  local winnerKey = self:ResolveRollWinner(session)
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

  local result = {
    rollID = session.rollID,
    itemLink = session.itemLink,
    itemName = session.itemName,
    winnerKey = winnerKey,
    winnerName = winnerFull,
    votes = session.votes or {},
    resolvedAt = GetServerTime(),
  }

  session.locked = true
  session.result = result

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
      self:MoveToQueueBottom(winnerKey)
      self:BroadcastSnapshot()
    end
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    self:SendCommMessageSafe(NS.MSG.ROLL_RESULT, result, channel)
  end
  if self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow()
  end
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
    resolvedAt = result.resolvedAt or GetServerTime(),
  }

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
    resolvedAt = result.resolvedAt or GetServerTime(),
  }

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
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    SendChatMessage(msg, channel)
    self:SendCommMessageSafe(NS.MSG.ROLL_MISMATCH, {
      rollID = session.rollID,
      name = playerName,
      expected = expectedVote,
      actual = actualVote,
    }, channel)
  end
end

function GLD:OnStartLootRoll(rollID, rollTime, lootHandle)
  local texture, name, count, quality, bop, canNeed, canGreed, canDE, canTransmog, reason = GetLootRollItemInfo(rollID)
  local link = GetLootRollItemLink(rollID)

  local session = {
    rollID = rollID,
    rollTime = rollTime,
    itemLink = link,
    itemName = name,
    quality = quality,
    canNeed = canNeed,
    canGreed = canGreed,
    canTransmog = canTransmog,
    votes = {},
    expectedVoters = self:BuildExpectedVoters(),
    createdAt = GetServerTime(),
  }
  self.activeRolls[rollID] = session

  if link then
    self:RequestItemData(link)
  end

  if self.UI then
    self.UI:ShowRollPopup(session)
    if self.UI.RefreshLootWindow then
      self.UI:RefreshLootWindow({ forceShow = true })
    end
  end

  if not self:IsAuthority() then
    local authority = self:GetAuthorityName()
    if authority then
      self:SendCommMessageSafe(NS.MSG.ROLL_SESSION, {
        rollID = rollID,
        rollTime = rollTime,
        itemLink = link,
        itemName = name,
        canNeed = canNeed,
        canGreed = canGreed,
        canTransmog = canTransmog,
      }, "WHISPER", authority)
    end
  else
    local delay = (tonumber(rollTime) or 120000) / 1000
    C_Timer.After(delay, function()
      local active = self.activeRolls and self.activeRolls[rollID]
      if active and not active.locked then
        self:FinalizeRoll(active)
      end
    end)
  end

  local delay = (tonumber(rollTime) or 120000) / 1000
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

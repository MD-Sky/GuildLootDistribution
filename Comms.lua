local _, NS = ...

local GLD = NS.GLD

local function HashString(input)
  local hash = 5381
  local str = tostring(input or "")
  for i = 1, #str do
    hash = ((hash * 33) + str:byte(i)) % 4294967296
  end
  return hash
end

local function StableStringify(value, depth)
  depth = (depth or 0) + 1
  if depth > 10 then
    return "<maxdepth>"
  end
  local t = type(value)
  if t == "table" then
    local keys = {}
    for k in pairs(value) do
      table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = tostring(k) .. "=" .. StableStringify(value[k], depth)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(value)
end

function GLD:ComputeRosterHashFromSnapshot(roster)
  if not roster then
    return nil
  end
  local keys = {}
  local entries = {}
  for _, entry in ipairs(roster) do
    local key = entry.key or (entry.name and (entry.name .. "-" .. (entry.realm or ""))) or ""
    keys[#keys + 1] = key
    entries[key] = entry
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    local entry = entries[key]
    parts[#parts + 1] = table.concat({
      key,
      tostring(entry.name or ""),
      tostring(entry.realm or ""),
      tostring(entry.class or ""),
      tostring(entry.attendance or ""),
      tostring(entry.queuePos or ""),
      tostring(entry.savedPos or ""),
      tostring(entry.numAccepted or ""),
      tostring(entry.attendanceCount or ""),
      tostring(entry.isGuest == true),
    }, "|")
  end
  return HashString(table.concat(parts, "#"))
end

function GLD:ComputeRosterHashFromDB()
  local roster = {}
  for key, player in pairs(self.db.players or {}) do
    roster[#roster + 1] = {
      key = key,
      name = player.name,
      realm = player.realm,
      class = player.class,
      attendance = player.attendance,
      queuePos = player.queuePos,
      savedPos = player.savedPos,
      numAccepted = player.numAccepted,
      attendanceCount = player.attendanceCount,
      isGuest = player.isGuest == true or player.source == "guest",
    }
  end
  return self:ComputeRosterHashFromSnapshot(roster)
end

function GLD:ComputeConfigHash()
  if not self.db or not self.db.config then
    return nil
  end
  return HashString(StableStringify(self.db.config))
end

function GLD:InitComms()
  self:RegisterComm(NS.COMM_PREFIX)
  self.commHandlers = {}

  self.commHandlers[NS.MSG.STATE_SNAPSHOT] = function(sender, payload)
    self:HandleStateSnapshot(sender, payload)
  end
  self.commHandlers[NS.MSG.DELTA] = function(sender, payload)
    self:HandleDelta(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_SESSION] = function(sender, payload)
    self:HandleRollSession(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_VOTE] = function(sender, payload)
    self:HandleRollVote(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_RESULT] = function(sender, payload)
    self:HandleRollResult(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_MISMATCH] = function(sender, payload)
    self:HandleRollMismatch(sender, payload)
  end
  self.commHandlers[NS.MSG.FORCE_PENDING] = function(sender, payload)
    self:HandleForcePending(sender, payload)
  end
  self.commHandlers[NS.MSG.REV_CHECK] = function(sender, payload)
    self:HandleRevisionCheck(sender, payload)
  end
  self.commHandlers[NS.MSG.ADMIN_REQUEST] = function(sender, payload)
    self:HandleAdminRequest(sender, payload)
  end
end

function GLD:SendCommMessageSafe(msgType, payload, channel, target)
  local message = { type = msgType, payload = payload }
  local serialized = self:Serialize(message)
  self:SendCommMessage(NS.COMM_PREFIX, serialized, channel or "RAID", target)
end

function GLD:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= NS.COMM_PREFIX then
    return
  end
  local success, data = self:Deserialize(message)
  if not success or type(data) ~= "table" then
    return
  end
  local handler = self.commHandlers[data.type]
  if handler then
    handler(sender, data.payload)
  end
end

function GLD:HandleStateSnapshot(sender, payload)
  if not payload then
    return
  end
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized edit from " .. tostring(sender))
      return
    end
  end
  local localRosterHash = self:ComputeRosterHashFromDB()
  local localConfigHash = self:ComputeConfigHash()
  if payload.rosterHash and localRosterHash and payload.rosterHash ~= localRosterHash then
    self:Debug("Sync mismatch: your roster differs from authority. Using authority data.")
  end
  if payload.configHash and localConfigHash and payload.configHash ~= localConfigHash then
    self:Debug("Sync mismatch: your config differs from authority.")
  end
  self.shadow.lastSyncAt = GetServerTime()
  self.shadow.meta = self.shadow.meta or {}
  if payload.revision ~= nil then
    self.shadow.meta.revision = payload.revision
  end
  if payload.lastChanged ~= nil then
    self.shadow.meta.lastChanged = payload.lastChanged
  end
  if payload.my and self:IsAuthority() then
    self.shadow.my = payload.my
  end
  if payload.roster then
    self.shadow.roster = payload.roster
    if self.UpdateShadowMyFromRoster then
      self:UpdateShadowMyFromRoster(self.shadow.roster)
    end
  elseif payload.my then
    self.shadow.my = payload.my
  end
  if payload.sessionActive ~= nil then
    self.shadow.sessionActive = payload.sessionActive == true
  end
  if payload.sessionActive == false and (payload.authorityGUID == nil or payload.authorityGUID == "") then
    if self.ClearSessionAuthority then
      self:ClearSessionAuthority()
    end
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local rosterCount = (self.shadow and self.shadow.roster and #self.shadow.roster) or 0
    local my = self.shadow and self.shadow.my or nil
    local rev = self.shadow and self.shadow.meta and self.shadow.meta.revision or "nil"
    self:Debug(
      "Snapshot received: rosterSource=shadow.roster rosterCount="
        .. tostring(rosterCount)
        .. " myQueue="
        .. tostring(my and my.queuePos or "nil")
        .. " myHeld="
        .. tostring(my and my.savedPos or "nil")
        .. " revision="
        .. tostring(rev)
    )
  end
  if self.UI then
    self.UI:RefreshMain()
  end
end

function GLD:HandleDelta(sender, payload)
  if not payload then
    return
  end
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized edit from " .. tostring(sender))
      return
    end
  end
  if payload.my and self:IsAuthority() then
    self.shadow.my = payload.my
  end
  if payload.roster then
    self.shadow.roster = payload.roster
    if self.UpdateShadowMyFromRoster then
      self:UpdateShadowMyFromRoster(self.shadow.roster)
    end
  elseif payload.my then
    self.shadow.my = payload.my
  end
  if payload.revision ~= nil then
    self.shadow.meta = self.shadow.meta or {}
    self.shadow.meta.revision = payload.revision
  end
  if payload.lastChanged ~= nil then
    self.shadow.meta = self.shadow.meta or {}
    self.shadow.meta.lastChanged = payload.lastChanged
  end
  if self.UI then
    self.UI:RefreshMain()
  end
end

function GLD:BuildSnapshot()
  local my = {
    queuePos = nil,
    savedPos = nil,
    numAccepted = nil,
    attendance = nil,
    attendanceCount = nil,
  }

    if not self.db or not self.db.players then
      -- DB not ready yet; return a safe empty snapshot.
      local sessionActive = self.db and self.db.session and self.db.session.active == true
      return {
        my = my,
        roster = {},
        rosterHash = nil,
        configHash = self:ComputeConfigHash(),
        sessionActive = sessionActive,
        revision = self.db and self.db.meta and self.db.meta.revision or 0,
        lastChanged = self.db and self.db.meta and self.db.meta.lastChanged or 0,
        authorityGUID = self:GetAuthorityGUID(),
        authorityName = self:GetAuthorityName(),
      }
    end

  local roster = {}
  for key, player in pairs(self.db.players) do
    local snapshotRole = nil
    if self.GetRole then
      snapshotRole = self:GetRole(player)
    end
    if not snapshotRole and NS.GetRoleForPlayer then
      snapshotRole = NS:GetRoleForPlayer(player.name)
    end
    table.insert(roster, {
      key = key,
      name = player.name,
      realm = player.realm,
      class = player.class,
      queuePos = player.queuePos,
      savedPos = player.savedPos,
      numAccepted = player.numAccepted,
      attendance = player.attendance,
      attendanceCount = player.attendanceCount,
      role = snapshotRole,
      isGuest = player.isGuest == true or player.source == "guest",
    })
  end

    local rosterHash = self:ComputeRosterHashFromSnapshot(roster)
    local configHash = self:ComputeConfigHash()
    local sessionActive = self.db and self.db.session and self.db.session.active == true
    local revision = self.db and self.db.meta and self.db.meta.revision or 0
    local lastChanged = self.db and self.db.meta and self.db.meta.lastChanged or 0

  local myKey = NS:GetPlayerKeyFromUnit("player")
  if myKey then
    local me = self.db.players[myKey]
    if me then
      my.queuePos = me.queuePos
      my.savedPos = me.savedPos
      my.numAccepted = me.numAccepted
      my.attendance = me.attendance
      my.attendanceCount = me.attendanceCount
    end
  end

    return {
      my = my,
      roster = roster,
      rosterHash = rosterHash,
      configHash = configHash,
      sessionActive = sessionActive,
      revision = revision,
      lastChanged = lastChanged,
      authorityGUID = self:GetAuthorityGUID(),
      authorityName = self:GetAuthorityName(),
    }
  end

function GLD:BroadcastSnapshot(force)
  if not force and not self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  local snapshot = self:BuildSnapshot()
  self:SendCommMessageSafe(NS.MSG.STATE_SNAPSHOT, snapshot, "RAID")
end

function GLD:SendRevisionCheck()
  if self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  local revision = self.shadow and self.shadow.meta and self.shadow.meta.revision or 0
  self:SendCommMessageSafe(NS.MSG.REV_CHECK, {
    revision = revision,
    requestedAt = GetServerTime(),
  }, "RAID")
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Revision ping sent: revision=" .. tostring(revision))
  end
end

function GLD:RequestAdminAction(action)
  if not action or action == "" then
    return false
  end
  if self:IsAuthority() then
    if action == "START_SESSION" and self.StartSession then
      self:StartSession()
      return true
    end
    if action == "END_SESSION" and self.EndSession then
      self:EndSession()
      return true
    end
    return false
  end
  if not IsInRaid() then
    self:Print("You must be in a raid to request this action.")
    return false
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:Print("you do not have Guild Permission to access this panel")
    return false
  end
  self:SendCommMessageSafe(NS.MSG.ADMIN_REQUEST, {
    action = action,
    requestedAt = GetServerTime(),
  }, "RAID")
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Admin request sent: action=" .. tostring(action))
  end
  return true
end

function GLD:HandleRevisionCheck(sender, payload)
  if not self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  if not self.IsSenderInRaid or not self:IsSenderInRaid(sender) then
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug("Revision ping ignored (sender not in raid): " .. tostring(sender))
    end
    return
  end
  local clientRev = payload and tonumber(payload.revision) or nil
  local serverRev = self.db and self.db.meta and self.db.meta.revision or 0
  local shouldSend = (clientRev == nil) or (clientRev < serverRev)
  if shouldSend then
    self:BroadcastSnapshot()
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local outcome = shouldSend and "snapshot_sent" or "up_to_date"
    self:Debug(
      "Revision ping handled: sender="
        .. tostring(sender)
        .. " clientRev="
        .. tostring(clientRev)
        .. " serverRev="
        .. tostring(serverRev)
        .. " outcome="
        .. outcome
    )
  end
end

function GLD:HandleAdminRequest(sender, payload)
  if not self:IsAuthority() then
    return
  end
  if not payload or not payload.action then
    return
  end
  local ok, reason = false, "missing validation"
  if self.ValidateAdminRequestSender then
    ok, reason = self:ValidateAdminRequestSender(sender, payload.action)
  end
  if not ok then
    local label = reason or "rejected"
    self:Print("Admin request rejected from " .. tostring(sender) .. ": " .. tostring(label))
    return
  end
  local action = payload.action
  if action == "START_SESSION" then
    if self.StartSession then
      self:StartSession()
    end
    return
  end
  if action == "END_SESSION" then
    if self.EndSession then
      self:EndSession()
    end
    return
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Admin request ignored (unknown action): " .. tostring(action))
  end
end

function GLD:HandleRollSession(sender, payload)
  if not payload or not payload.rollID then
    return
  end

  local isTest = payload.test == true
  if not isTest then
    local sessionActive = nil
    if self.shadow and self.shadow.sessionActive ~= nil then
      sessionActive = self.shadow.sessionActive == true
    elseif self:IsAuthority() then
      sessionActive = self.db and self.db.session and self.db.session.active == true
    end
    if sessionActive == nil then
      sessionActive = true
    end
    if not sessionActive or not IsInRaid() then
      if self.IsDebugEnabled and self:IsDebugEnabled() then
        self:Debug("Ignoring roll session (not in active raid session).")
      end
      return
    end
    if self.IsAuthorizedSender then
      local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
      if not ok then
        self:Debug("Blocked unauthorized roll session from " .. tostring(sender))
        return
      end
    end
  end

  local rollID = payload.rollID
  local rollKey = self.GetRollKeyFromPayload and self:GetRollKeyFromPayload(payload) or nil
  if not rollKey then
    return
  end

  self.activeRolls = self.activeRolls or {}
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end

  local session = self.activeRolls[rollKey]
  if not session and payload.rollKey and self.GetLegacyRollKey then
    local legacyKey = self:GetLegacyRollKey(rollID)
    session = self.activeRolls[legacyKey]
    if session then
      self.activeRolls[legacyKey] = nil
      self.activeRolls[rollKey] = session
    end
  end
  if session and self.IsRollSessionExpired and self:IsRollSessionExpired(session, nil, 1800) then
    self.activeRolls[rollKey] = nil
    session = nil
  end
  if not session then
    session = {
      rollID = rollID,
      rollKey = rollKey,
      votes = {},
    }
    self.activeRolls[rollKey] = session
  end
  session.rollID = rollID or session.rollID
  session.rollKey = rollKey

  session.isTest = isTest
  session.rollTime = payload.rollTime or session.rollTime
  session.rollExpiresAt = payload.rollExpiresAt or session.rollExpiresAt
  if not session.rollExpiresAt and payload.rollTime then
    session.rollExpiresAt = GetServerTime() + math.floor((tonumber(payload.rollTime) or 0) / 1000)
  end
  session.itemLink = payload.itemLink or session.itemLink
  session.itemName = payload.itemName or session.itemName
  session.itemID = payload.itemID or session.itemID
  session.itemIcon = payload.itemIcon or session.itemIcon
  session.quality = payload.quality or session.quality
  session.count = payload.count or session.count
  if payload.canNeed ~= nil then
    session.canNeed = payload.canNeed
  end
  if payload.canGreed ~= nil then
    session.canGreed = payload.canGreed
  end
  if payload.canTransmog ~= nil then
    session.canTransmog = payload.canTransmog
  end
  if payload.expectedVoters then
    session.expectedVoters = payload.expectedVoters
  elseif not session.expectedVoters then
    session.expectedVoters = self:BuildExpectedVoters()
  end
  if payload.expectedVoterClasses then
    session.expectedVoterClasses = payload.expectedVoterClasses
  end
  session.createdAt = payload.createdAt or session.createdAt or GetServerTime()
  if payload.votes then
    session.votes = session.votes or {}
    for k, v in pairs(payload.votes) do
      session.votes[k] = v
    end
  end

  if isTest then
    local name, realm = UnitName("player")
    if name then
      session.testVoterName = realm and realm ~= "" and (name .. "-" .. realm) or name
    end
  end

  session.trace = session.trace or {}
  if not session.trace.rollReceived then
    session.trace.rollReceived = true
    local itemLabel = payload.itemLink or payload.itemName or session.itemLink or session.itemName or "Item"
    if payload.snapshot then
      self:TraceStep("Roll snapshot received: " .. tostring(itemLabel))
    else
      self:TraceStep("Loot roll received: " .. tostring(itemLabel) .. ". Vote window should appear.")
    end
  end

  if isTest and self.UI then
    self.UI:ShowRollPopup(session)
  end

  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local itemLabel = payload.itemLink or payload.itemName or "Unknown"
    self:Debug("Roll broadcast received: rollID=" .. tostring(rollID) .. " item=" .. tostring(itemLabel))
    local count = 0
    for _ in pairs(self.activeRolls or {}) do
      count = count + 1
    end
    self:Debug("Roll session tracked: rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey) .. " active=" .. tostring(count))
  end

  if not isTest and self:IsAuthority() and not session.timerStarted then
    session.timerStarted = true
    local delay = (tonumber(payload.rollTime) or 120000) / 1000
    C_Timer.After(delay, function()
      local activeKey = session and session.rollKey
      local active = self.activeRolls and activeKey and self.activeRolls[activeKey] or nil
      if active and not active.locked then
        self:FinalizeRoll(active)
      end
    end)
  end

  if self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow({ forceShow = true })
  elseif self.UI and self.UI.ShowPendingFrame then
    self.UI:ShowPendingFrame()
  end
end

function GLD:HandleRollVote(sender, payload)
  if not payload then
    return
  end

  local isAuthority = self:IsAuthority()
  if not isAuthority then
    if not payload.broadcast then
      return
    end
    if self.IsAuthorizedSender then
      local ok = self:IsAuthorizedSender(sender)
      if not ok then
        return
      end
    end
  end

  if isAuthority and payload.broadcast then
    return
  end

  local rollID = payload.rollID
  local rollKey = self.GetRollKeyFromPayload and self:GetRollKeyFromPayload(payload) or nil
  local session = nil
  if self.FindActiveRoll then
    _, session = self:FindActiveRoll(rollKey, rollID)
  end
  if not session then
    session = self.activeRolls and rollKey and self.activeRolls[rollKey] or nil
  end
  if not session or session.locked then
    return
  end

  local key = payload.voterKey or payload.voterName or self:GetRollCandidateKey(sender)
  if not key then
    return
  end

  session.votes = session.votes or {}
  session.votes[key] = payload.vote
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug(
      "Vote received: rollID="
        .. tostring(rollID)
        .. " voter="
        .. tostring(key)
        .. " vote="
        .. tostring(payload.vote)
        .. " sender="
        .. tostring(sender)
        .. " broadcast="
        .. tostring(payload.broadcast == true)
    )
  end

  if isAuthority then
    self:CheckRollCompletion(session)
    if IsInRaid() then
      self:SendCommMessageSafe(NS.MSG.ROLL_VOTE, {
        rollID = rollID,
        rollKey = session.rollKey or rollKey,
        vote = payload.vote,
        voterKey = key,
        broadcast = true,
      }, "RAID")
    end
  end

  if self.UI and self.UI.RefreshPendingVotes then
    self.UI:RefreshPendingVotes()
  end
end

function GLD:HandleRollResult(sender, payload)
  if not payload then
    return
  end
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized roll result from " .. tostring(sender))
      return
    end
  end
  local rollID = payload.rollID
  local rollKey = self.GetRollKeyFromPayload and self:GetRollKeyFromPayload(payload) or nil
  local sessionKey = nil
  local session = nil
  if self.FindActiveRoll then
    sessionKey, session = self:FindActiveRoll(rollKey, rollID)
  end
  if not session then
    sessionKey = rollKey
    session = self.activeRolls and rollKey and self.activeRolls[rollKey] or nil
  end
  if session then
    session.locked = true
    session.result = payload
  end
  self:RecordRollHistory(payload)
  local itemLabel = tostring(payload.itemName or payload.itemLink or "Item")
  local winnerLabel = tostring(payload.winnerName or "None")
  local detail = ""
  if payload.resolvedBy == "OVERRIDE" then
    local by = payload.overrideBy or payload.authorityName or sender or "Authority"
    detail = " (override by " .. tostring(by) .. ")"
  end
  self:TraceStep("Winner decided: " .. itemLabel .. " -> " .. winnerLabel .. detail)
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Result broadcast received: rollID=" .. tostring(payload.rollID) .. " rollKey=" .. tostring(rollKey))
  end
  if sessionKey and self.activeRolls then
    self.activeRolls[sessionKey] = nil
  end
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local count = 0
    for _ in pairs(self.activeRolls or {}) do
      count = count + 1
    end
    self:Debug("Roll result pruned: rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey) .. " active=" .. tostring(count))
  end
  if self.UI and self.UI.ShowRollResultPopup then
    self.UI:ShowRollResultPopup(payload)
  end
  if self.UI and self.UI.RefreshPendingVotes then
    self.UI:RefreshPendingVotes()
  end
end

function GLD:HandleRollMismatch(sender, payload)
  if not payload then
    return
  end
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender)
    if not ok then
      self:Debug("Blocked unauthorized edit from " .. tostring(sender))
      return
    end
  end
  self:Print("GLD mismatch: " .. tostring(payload.name) .. " declared " .. tostring(payload.expected) .. " but rolled " .. tostring(payload.actual))
end

function GLD:HandleForcePending(sender, payload)
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload and payload.authorityGUID, payload and payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized pending request from " .. tostring(sender))
      return
    end
  end
  if self.UI and self.UI.ShowPendingFrame then
    self.UI:ShowPendingFrame()
  elseif self.UI and self.UI.RefreshLootWindow then
    self.UI:RefreshLootWindow({ forceShow = true })
  end
  local fromName = payload and (payload.authorityName or sender) or sender
  self:TraceStep("Pending votes window requested by " .. tostring(fromName))
end

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

local AUDIT_QUERY = "AUDIT_Q"
local AUDIT_RESPONSE = "AUDIT_R"
local AUDIT_TIMEOUT_SECONDS = 3

local function ParseBuildValue(value)
  if value == nil then
    return nil
  end
  if type(value) == "number" then
    return { value }
  end
  local str = tostring(value)
  local parts = {}
  for num in str:gmatch("%d+") do
    parts[#parts + 1] = tonumber(num)
  end
  if #parts == 0 then
    return nil
  end
  return parts
end

local function DeriveRollKey(self, payload)
  if not payload then
    return nil
  end
  if payload.rollKey and payload.rollKey ~= "" then
    return tostring(payload.rollKey)
  end
  if self.GetRollKeyFromPayload then
    local key = self:GetRollKeyFromPayload(payload)
    if key and key ~= "" then
      return tostring(key)
    end
  end
  if payload.rollID ~= nil then
    if self.GetLegacyRollKey then
      return self:GetLegacyRollKey(payload.rollID)
    end
    return tostring(payload.rollID) .. "@legacy"
  end
  return nil
end

function GLD:GetAddonBuildString()
  if NS.BUILD ~= nil then
    return tostring(NS.BUILD)
  end
  if NS.VERSION ~= nil then
    return tostring(NS.VERSION)
  end
  if NS.REVISION ~= nil then
    return tostring(NS.REVISION)
  end
  return "0"
end

function GLD:CompareBuilds(a, b)
  local ap = ParseBuildValue(a)
  local bp = ParseBuildValue(b)
  if not ap or not bp then
    local sa = tostring(a or "")
    local sb = tostring(b or "")
    if sa == sb then
      return 0
    end
    return sa < sb and -1 or 1
  end
  local max = #ap
  if #bp > max then
    max = #bp
  end
  for i = 1, max do
    local av = ap[i] or 0
    local bv = bp[i] or 0
    if av < bv then
      return -1
    end
    if av > bv then
      return 1
    end
  end
  return 0
end

function GLD:BuildAuditNonce()
  self._auditNonce = (self._auditNonce or 0) + 1
  local now = (GetServerTime and GetServerTime()) or time()
  return tostring(now) .. "-" .. tostring(math.random(1000, 9999)) .. "-" .. tostring(self._auditNonce)
end

function GLD:CanRunAddonAudit()
  if not IsInGuild() then
    return false
  end
  local _, _, rankIndex = GetGuildInfo("player")
  if rankIndex == nil then
    return false
  end
  return rankIndex <= 2
end

function GLD:IsValidAuditSender(sender)
  if not sender or sender == "" then
    return false, nil
  end
  if not IsInRaid() then
    return false, nil
  end
  local unit = self:GetUnitForSender(sender)
  if not unit then
    return false, nil
  end
  local ourGuild = self:GetOurGuildName()
  if not ourGuild then
    return false, unit
  end
  local guildName = GetGuildInfo(unit)
  if not guildName or guildName ~= ourGuild then
    return false, unit
  end
  return true, unit
end

function GLD:IsAuditQuerySenderAllowed(sender)
  local ok, unit = self:IsValidAuditSender(sender)
  if not ok or not unit then
    return false
  end
  local _, _, rankIndex = GetGuildInfo(unit)
  if rankIndex == nil then
    return false
  end
  return rankIndex <= 2
end

function GLD:SendAuditMessage(payload)
  if not payload or payload == "" then
    return
  end
  if not IsInRaid() then
    return
  end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(NS.COMM_PREFIX, payload, "RAID")
  elseif SendAddonMessage then
    SendAddonMessage(NS.COMM_PREFIX, payload, "RAID")
  end
end

function GLD:BuildAuditRoster()
  local roster = {}
  local order = {}
  if not IsInRaid() then
    return roster, order
  end
  for i = 1, 40 do
    local unit = "raid" .. i
    if UnitExists(unit) then
      local key = NS:GetPlayerKeyFromUnit(unit) or self:GetUnitFullName(unit) or UnitName(unit) or unit
      if key and not roster[key] then
        local fullName = self:GetUnitFullName(unit) or UnitName(unit) or tostring(key)
        roster[key] = {
          key = key,
          name = fullName,
          displayName = (NS.GetPlayerDisplayName and NS:GetPlayerDisplayName(fullName)) or fullName,
          unit = unit,
        }
        order[#order + 1] = key
      end
    end
  end
  return roster, order
end

function GLD:StartAddonAudit(manual, silent)
  if not IsInRaid() then
    if not silent then
      self:Print("You must be in a raid to audit addons.")
    end
    return false
  end
  if not self:CanRunAddonAudit() then
    if not silent then
      self:ShowPermissionDeniedPopup()
    end
    return false
  end
  local requiredBuild = self:GetAddonBuildString()
  local nonce = self:BuildAuditNonce()
  local roster, order = self:BuildAuditRoster()
  self.auditState = self.auditState or {}
  local state = self.auditState
  if state.timer and state.timer.Cancel then
    state.timer:Cancel()
  end
  state.timer = nil
  state.nonce = nonce
  state.requiredBuild = requiredBuild
  state.expected = roster
  state.order = order
  state.responses = {}
  state.results = {}
  state.summary = { ok = 0, outdated = 0, missing = 0 }
  state.pending = true
  state.startedAt = (GetServerTime and GetServerTime()) or time()
  state.responseCount = 0
  state.lastManual = manual == true
  self:SendAuditMessage(string.format("%s|%s|%s", AUDIT_QUERY, nonce, requiredBuild))
  if C_Timer and C_Timer.NewTimer then
    state.timer = C_Timer.NewTimer(AUDIT_TIMEOUT_SECONDS, function()
      if GLD and GLD.FinalizeAddonAudit then
        GLD:FinalizeAddonAudit(nonce)
      end
    end)
  elseif C_Timer and C_Timer.After then
    C_Timer.After(AUDIT_TIMEOUT_SECONDS, function()
      if GLD and GLD.FinalizeAddonAudit then
        GLD:FinalizeAddonAudit(nonce)
      end
    end)
  end
  self:NotifyAddonAuditUpdated()
  return true
end

function GLD:FinalizeAddonAudit(nonce)
  local state = self.auditState
  if not state or state.nonce ~= nonce then
    return
  end
  state.pending = false
  if state.timer and state.timer.Cancel then
    state.timer:Cancel()
  end
  state.timer = nil
  local results = {}
  local okCount, outdatedCount, missingCount = 0, 0, 0
  local requiredBuild = state.requiredBuild
  local order = state.order or {}
  for _, key in ipairs(order) do
    local expected = state.expected and state.expected[key] or nil
    local response = state.responses and state.responses[key] or nil
    local name = expected and (expected.displayName or expected.name) or tostring(key)
    local status = "MISSING"
    local version = nil
    if response and response.build then
      version = response.build
      local cmp = self:CompareBuilds(version, requiredBuild)
      if cmp >= 0 then
        status = "OK"
        okCount = okCount + 1
      else
        status = "OUTDATED"
        outdatedCount = outdatedCount + 1
      end
    else
      missingCount = missingCount + 1
    end
    results[#results + 1] = {
      key = key,
      name = name,
      status = status,
      version = version,
    }
  end
  state.results = results
  state.summary = { ok = okCount, outdated = outdatedCount, missing = missingCount }
  state.completedAt = (GetServerTime and GetServerTime()) or time()
  self:NotifyAddonAuditUpdated()
end

function GLD:HandleAuditQuery(sender, nonce, requiredBuild, distribution)
  if distribution ~= "RAID" then
    return
  end
  if not IsInRaid() then
    return
  end
  if not nonce or nonce == "" then
    return
  end
  if not self:IsAuditQuerySenderAllowed(sender) then
    return
  end
  local build = self:GetAddonBuildString()
  self:SendAuditMessage(string.format("%s|%s|%s", AUDIT_RESPONSE, nonce, build))
end

function GLD:HandleAuditResponse(sender, nonce, build, distribution)
  if distribution ~= "RAID" then
    return
  end
  if not IsInRaid() then
    return
  end
  local state = self.auditState
  if not state or state.nonce ~= nonce then
    return
  end
  local ok, unit = self:IsValidAuditSender(sender)
  if not ok then
    return
  end
  local key = nil
  if unit then
    key = NS:GetPlayerKeyFromUnit(unit) or self:GetUnitFullName(unit)
    if key and state.expected and not state.expected[key] then
      local alt = self:GetUnitFullName(unit)
      if alt and state.expected[alt] then
        key = alt
      end
    end
  end
  key = key or sender
  state.responses = state.responses or {}
  if not state.responses[key] then
    state.responseCount = (state.responseCount or 0) + 1
  end
  state.responses[key] = {
    build = build,
    sender = sender,
  }
  if state.pending then
    self:NotifyAddonAuditUpdated()
  end
end

function GLD:HandleAuditCommMessage(sender, message, distribution)
  if type(message) ~= "string" then
    return false
  end
  if not message:find("^AUDIT_") then
    return false
  end
  local tag, nonce, build = strsplit("|", message, 3)
  if tag == AUDIT_QUERY then
    self:HandleAuditQuery(sender, nonce, build, distribution)
    return true
  end
  if tag == AUDIT_RESPONSE then
    self:HandleAuditResponse(sender, nonce, build, distribution)
    return true
  end
  return false
end

function GLD:GetAddonAuditSummaryText()
  local state = self.auditState
  if not state or not state.startedAt then
    return "No audit run yet."
  end
  if state.pending then
    local count = state.responseCount or 0
    return string.format("Audit in progress... (%d replies)", count)
  end
  local summary = state.summary or {}
  local required = state.requiredBuild or "?"
  return string.format(
    "Required build: %s | OK: %d  OUTDATED: %d  MISSING: %d",
    tostring(required),
    summary.ok or 0,
    summary.outdated or 0,
    summary.missing or 0
  )
end

function GLD:GetAddonAuditRows()
  local state = self.auditState
  local rows = {}
  if not state or not state.results then
    return rows
  end
  if state.pending and (not state.results or #state.results == 0) then
    rows[#rows + 1] = "Awaiting replies..."
    return rows
  end
  for _, entry in ipairs(state.results) do
    local name = entry.name or entry.key or "Unknown"
    local status = entry.status or "?"
    local version = entry.version or "-"
    rows[#rows + 1] = string.format("%s | %s | %s", name, status, version)
  end
  return rows
end

function GLD:NotifyAddonAuditUpdated()
  if self.RefreshAddonAuditOptions and self.options then
    self:RefreshAddonAuditOptions(self.options)
  end
  local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
  if AceConfigRegistry then
    AceConfigRegistry:NotifyChange("GuildLoot")
  end
end

function GLD:MaybeAutoAuditAddons()
  if not IsInRaid() then
    if self.auditState then
      self.auditState.autoRanInRaid = false
    end
    return
  end
  self.auditState = self.auditState or {}
  if self.auditState.autoRanInRaid then
    return
  end
  if not self:CanRunAddonAudit() then
    return
  end
  self.auditState.autoRanInRaid = true
  self:StartAddonAudit(false, true)
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
  self.commHandlers[NS.MSG.ROLL_ACK] = function(sender, payload)
    self:HandleRollAck(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_SESSION_REQUEST] = function(sender, payload)
    self:HandleRollSessionRequest(sender, payload)
  end
  self.commHandlers[NS.MSG.VOTE_CONVERTED] = function(sender, payload)
    self:HandleVoteConverted(sender, payload)
  end
  self.commHandlers[NS.MSG.ROLL_MISMATCH] = function(sender, payload)
    self:HandleRollMismatch(sender, payload)
  end
  self.commHandlers[NS.MSG.FORCE_PENDING] = function(sender, payload)
    self:HandleForcePending(sender, payload)
  end
  self.commHandlers[NS.MSG.SESSION_STATE] = function(sender, payload)
    self:HandleSessionState(sender, payload)
  end
  self.commHandlers[NS.MSG.REV_CHECK] = function(sender, payload)
    self:HandleRevisionCheck(sender, payload)
  end
  self.commHandlers[NS.MSG.ADMIN_REQUEST] = function(sender, payload)
    self:HandleAdminRequest(sender, payload)
  end
  if NS.MSG.NOTICE then
    self.commHandlers[NS.MSG.NOTICE] = function(sender, payload)
      self:HandleNotice(sender, payload)
    end
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
  if type(message) == "string" then
    local rawId, rawText = message:match("^NOTICE|([^|]*)|([%s%S]+)$")
    if rawId and rawText then
      self:HandleNotice(sender, { id = rawId, text = rawText, raw = true })
      return
    end
  end
  if self.HandleAuditCommMessage and self:HandleAuditCommMessage(sender, message, distribution) then
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
    self.shadow.rosterReceived = true
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
    local sessionActive = self.shadow and self.shadow.sessionActive == true
    self:Debug(
      "Snapshot received: rosterSource=shadow.roster rosterCount="
        .. tostring(rosterCount)
        .. " myQueue="
        .. tostring(my and my.queuePos or "nil")
        .. " myHeld="
        .. tostring(my and my.savedPos or "nil")
        .. " revision="
        .. tostring(rev)
        .. " sessionActive="
        .. tostring(sessionActive)
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
    self.shadow.rosterReceived = true
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

function GLD:HandleSessionState(sender, payload)
  if not payload then
    return
  end
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized session state from " .. tostring(sender))
      return
    end
  end
  if payload.revision ~= nil or payload.lastChanged ~= nil then
    self.shadow.meta = self.shadow.meta or {}
    if payload.revision ~= nil then
      self.shadow.meta.revision = payload.revision
    end
    if payload.lastChanged ~= nil then
      self.shadow.meta.lastChanged = payload.lastChanged
    end
  end
  if payload.sessionActive ~= nil then
    self.shadow.sessionActive = payload.sessionActive == true
  end
  if payload.sessionActive == false and self.ClearSessionAuthority then
    self:ClearSessionAuthority()
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

function GLD:BuildSessionStatePayload()
  local sessionActive = self.db and self.db.session and self.db.session.active == true
  local revision = self.db and self.db.meta and self.db.meta.revision or 0
  local lastChanged = self.db and self.db.meta and self.db.meta.lastChanged or 0
  return {
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
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local revision = self.db and self.db.meta and self.db.meta.revision or 0
    local rosterCount = snapshot and snapshot.roster and #snapshot.roster or 0
    self:Debug("Snapshot broadcast: revision=" .. tostring(revision) .. " rosterCount=" .. tostring(rosterCount))
  end
end

function GLD:BroadcastSessionState(force)
  if not force and not self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  local payload = self:BuildSessionStatePayload()
  self:SendCommMessageSafe(NS.MSG.SESSION_STATE, payload, "RAID")
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

function GLD:RequestRollSessionSnapshot(rollKey, rollID)
  if self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  local payload = {
    rollID = rollID,
    rollKey = rollKey,
    requestedAt = GetServerTime(),
  }
  self:SendCommMessageSafe(NS.MSG.ROLL_SESSION_REQUEST, payload, "RAID")
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug(
      "Roll snapshot requested: rollID="
        .. tostring(rollID)
        .. " rollKey="
        .. tostring(rollKey)
        .. " authority=raid"
    )
  end
end

function GLD:RequestAdminAction(action)
  if not action or action == "" then
    return false
  end
  if self:IsAuthority() then
    if action == "START_SESSION" and self.StartSession then
      if self.PromptStartSession then
        self:PromptStartSession()
      else
        self:StartSession()
      end
      return true
    end
    if action == "END_SESSION" and self.EndSession then
      if self.PromptEndSession then
        self:PromptEndSession()
      else
        self:EndSession()
      end
      return true
    end
    return false
  end
  if not IsInRaid() then
    self:Print("You must be in a raid to request this action.")
    return false
  end
  if self.CanAccessAdminUI and not self:CanAccessAdminUI() then
    self:ShowPermissionDeniedPopup()
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

function GLD:BroadcastNotice(id, text, options)
  if not text or text == "" then
    return false
  end
  if not IsInRaid() then
    return false
  end
  options = options or {}
  local channel = options.channel or "RAID"
  local noticeId = id or ""
  if options.raw ~= false then
    local raw = "NOTICE|" .. tostring(noticeId) .. "|" .. tostring(text)
    self:SendCommMessage(NS.COMM_PREFIX, raw, channel)
    return true
  end
  local payload = {
    id = noticeId,
    text = text,
    title = options.title,
    audience = options.audience,
    suppressKey = options.suppressKey,
    allowSuppress = options.allowSuppress,
  }
  self:SendCommMessageSafe(NS.MSG.NOTICE, payload, channel)
  return true
end

function GLD:HandleNotice(sender, payload)
  if not payload or not payload.text then
    return
  end
  if not IsInRaid() then
    return
  end
  if self.IsSenderInRaid and not self:IsSenderInRaid(sender) then
    return
  end

  local audience = payload.audience or "GUESTS"
  if audience == "GUESTS" then
    if self.ShouldShowGuestNotice and not self:ShouldShowGuestNotice() then
      return
    end
  elseif audience == "ADMINS" then
    if not (self.CanAccessAdminUI and self:CanAccessAdminUI()) then
      return
    end
  end

  local title = payload.title or "lilyUI"
  local text = tostring(payload.text)
  local allowSuppress = payload.allowSuppress
  if allowSuppress == nil and payload.raw == true and payload.id and payload.id ~= "" then
    allowSuppress = true
  end
  local suppressKey = payload.suppressKey
  if allowSuppress and not suppressKey and payload.id and payload.id ~= "" then
    suppressKey = "notice:" .. tostring(payload.id)
  end
  if NS and NS.UI and NS.UI.ShowPopup then
    NS.UI:ShowPopup(title, text, { dontShowKey = suppressKey })
  elseif self.Print then
    self:Print(text)
  end
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
    if self.PromptStartSession then
      self:PromptStartSession()
    elseif self.StartSession then
      self:StartSession()
    end
    return
  end
  if action == "END_SESSION" then
    if self.PromptEndSession then
      self:PromptEndSession()
    elseif self.EndSession then
      self:EndSession()
    end
    return
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("Admin request ignored (unknown action): " .. tostring(action))
  end
end

function GLD:HandleRollSession(sender, payload)
  local debugEnabled = self.IsDebugEnabled and self:IsDebugEnabled()
  if debugEnabled then
    self:Debug(
      "Roll session received: sender="
        .. tostring(sender)
        .. " rollID="
        .. tostring(payload and payload.rollID)
        .. " rollKey="
        .. tostring(payload and payload.rollKey)
        .. " item="
        .. tostring(payload and (payload.itemLink or payload.itemName))
        .. " snapshot="
        .. tostring(payload and payload.snapshot == true)
        .. " reopen="
        .. tostring(payload and payload.reopen == true)
    )
  end
  if not payload or payload.rollID == nil then
    if debugEnabled then
      self:Debug("Roll session ignored: missing payload or rollID.")
    end
    return
  end

  local isTest = payload.test == true
  if not isTest then
    local sessionActive = nil
    local sessionSource = "unknown"
    if self.shadow and self.shadow.sessionActive ~= nil then
      sessionActive = self.shadow.sessionActive == true
      sessionSource = "shadow"
    elseif self:IsAuthority() then
      sessionActive = self.db and self.db.session and self.db.session.active == true
      sessionSource = "authority-db"
    end
    if sessionActive == nil then
      sessionActive = true
      sessionSource = "default"
    end
    if not IsInRaid() then
      if debugEnabled then
        self:Debug("Roll session ignored: not in raid.")
      end
      return
    end
    if sessionActive == false and debugEnabled then
      self:Debug("Roll session received while sessionActive=false (source=" .. tostring(sessionSource) .. ").")
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
  local rollKey = DeriveRollKey(self, payload)
  if not rollKey then
    if debugEnabled then
      self:Debug("Roll session ignored: unable to derive rollKey for rollID=" .. tostring(rollID))
    end
    return
  end

  self.activeRolls = self.activeRolls or {}
  if self.CleanupActiveRolls then
    self:CleanupActiveRolls(1800)
  end

  local session = self.activeRolls[rollKey]
  local created = false
  local rekeyed = false
  if not session and payload.rollKey and self.GetLegacyRollKey then
    local legacyKey = self:GetLegacyRollKey(rollID)
    session = self.activeRolls[legacyKey]
    if session then
      self.activeRolls[legacyKey] = nil
      self.activeRolls[rollKey] = session
      rekeyed = true
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
    created = true
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
  if not session.itemID and session.itemLink and C_Item and C_Item.GetItemInfoInstant then
    session.itemID = select(1, C_Item.GetItemInfoInstant(session.itemLink))
  end
  if self.RequestItemData and (session.itemID or session.itemLink) then
    self:RequestItemData(session.itemID or session.itemLink)
  end
  if payload.restrictionSnapshot then
    session.restrictionSnapshot = {}
    for k, v in pairs(payload.restrictionSnapshot) do
      session.restrictionSnapshot[k] = v
    end
  end
  if payload.canNeed ~= nil then
    session.canNeed = payload.canNeed
  end
  if payload.canGreed ~= nil then
    session.canGreed = payload.canGreed
  end
  if payload.canTransmog ~= nil then
    session.canTransmog = payload.canTransmog
  end
  if payload.blizzNeedAllowed ~= nil then
    session.blizzNeedAllowed = payload.blizzNeedAllowed
  end
  if payload.blizzGreedAllowed ~= nil then
    session.blizzGreedAllowed = payload.blizzGreedAllowed
  end
  if payload.blizzTransmogAllowed ~= nil then
    session.blizzTransmogAllowed = payload.blizzTransmogAllowed
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

  if debugEnabled then
    self:Debug(
      "Roll session state: rollID="
        .. tostring(rollID)
        .. " rollKey="
        .. tostring(rollKey)
        .. " created="
        .. tostring(created)
        .. " rekeyed="
        .. tostring(rekeyed)
    )
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

  if not isTest and IsInRaid() and not session.localAcked then
    local playerKey = NS:GetPlayerKeyFromUnit("player")
    if playerKey then
      session.localAcked = true
      self:SendCommMessageSafe(NS.MSG.ROLL_ACK, {
        rollID = rollID,
        rollKey = rollKey,
        voterKey = playerKey,
      }, "RAID")
      if debugEnabled then
        self:Debug("Roll ack sent: rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey))
      end
    elseif debugEnabled then
      self:Debug("Roll ack skipped: missing local playerKey.")
    end
  end

  if self.ApplyCoverStateForRoll then
    self:ApplyCoverStateForRoll(rollID)
  end

  if self.UI and self.UI.RefreshLootWindow then
    local options = { forceShow = true }
    if payload.reopen == true then
      options.reopen = true
    end
    self.UI:RefreshLootWindow(options)
    if debugEnabled then
      self:Debug("Loot window refresh: forceShow=true reopen=" .. tostring(payload.reopen == true))
    end
  elseif self.UI and self.UI.ShowPendingFrame then
    self.UI:ShowPendingFrame()
    if debugEnabled then
      self:Debug("Pending frame shown (RefreshLootWindow unavailable).")
    end
  elseif debugEnabled then
    self:Debug("No UI available to show loot window.")
  end
end

function GLD:HandleRollVote(sender, payload)
  if not payload then
    return
  end

  local debugEnabled = self.IsDebugEnabled and self:IsDebugEnabled()
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
  local rollKey = DeriveRollKey(self, payload)
  local session = nil
  if self.FindActiveRoll then
    _, session = self:FindActiveRoll(rollKey, rollID)
  end
  if not session then
    session = self.activeRolls and rollKey and self.activeRolls[rollKey] or nil
  end
  if not session then
    if debugEnabled then
      self:Debug(
        "Vote received for missing roll session: rollID="
          .. tostring(rollID)
          .. " rollKey="
          .. tostring(rollKey)
          .. " sender="
          .. tostring(sender)
      )
    end
    if self.RequestRollSessionSnapshot then
      self:RequestRollSessionSnapshot(rollKey, rollID)
    end
    return
  end
  if session.locked then
    if debugEnabled then
      self:Debug("Vote ignored (session locked): rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey))
    end
    return
  end

  local key = payload.voterKey
  if key and self.GetRollCandidateKey then
    key = self:GetRollCandidateKey(key) or key
  end
  if not key and payload.voterName then
    key = self:GetRollCandidateKey(payload.voterName)
  end
  if not key and sender then
    key = self:GetRollCandidateKey(sender)
  end
  if not key then
    if debugEnabled then
      self:Debug(
        "Vote ignored: missing voter key for rollID="
          .. tostring(rollID)
          .. " rollKey="
          .. tostring(rollKey)
          .. " sender="
          .. tostring(sender)
      )
    end
    return
  end

  local originalVote = payload.voteOriginal or payload.vote
  local effectiveVote = payload.voteEffective or payload.vote
  local reason = payload.reason
  local reasonText = payload.reasonText
  if isAuthority and self.GetEligibilityForVote then
    local eligible, reasonCode = self:GetEligibilityForVote(session, key, originalVote, { log = true })
    if not eligible then
      reason = reasonCode
      if originalVote == "NEED" then
        effectiveVote = "GREED"
        local greedEligible, greedReason = self:GetEligibilityForVote(session, key, "GREED")
        if not greedEligible then
          effectiveVote = "PASS"
          if not reason then
            reason = greedReason
          end
        end
      elseif originalVote == "GREED" or originalVote == "TRANSMOG" then
        effectiveVote = "PASS"
      else
        effectiveVote = "PASS"
      end
    end
  end

  session.votes = session.votes or {}
  session.votes[key] = effectiveVote
  session.voteDetails = session.voteDetails or {}
  session.voteDetails[key] = {
    voteOriginal = originalVote,
    voteEffective = effectiveVote,
    reason = reason,
    reasonText = reasonText,
  }
  if isAuthority and effectiveVote ~= originalVote then
    reasonText = self.GetEligibilityReasonText and self:GetEligibilityReasonText(reason, session) or nil
    session.voteDetails[key].reasonText = reasonText
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug(
        "Vote converted: rollID="
          .. tostring(rollID)
          .. " voter="
          .. tostring(key)
          .. " "
          .. tostring(originalVote)
          .. "->"
          .. tostring(effectiveVote)
          .. (reason and (" reason=" .. tostring(reason)) or "")
      )
    end
    local msg = "Your " .. tostring(originalVote) .. " was converted to " .. tostring(effectiveVote)
    if reasonText then
      msg = msg .. " (reason: " .. tostring(reasonText) .. ")"
    end
    local localKey = NS.GetPlayerKeyFromUnit and NS:GetPlayerKeyFromUnit("player") or nil
    if localKey and localKey == key then
      self:Print(msg)
    else
      if IsInRaid() then
        self:SendCommMessageSafe(NS.MSG.VOTE_CONVERTED, {
          rollID = rollID,
          rollKey = session.rollKey or rollKey,
          voteOriginal = originalVote,
          voteEffective = effectiveVote,
          reason = reason,
          reasonText = reasonText,
          voterKey = key,
        }, "RAID")
      else
        self:Print(msg)
      end
    end
  end
  if debugEnabled then
    self:Debug(
      "Vote received: rollID="
        .. tostring(rollID)
        .. " voter="
        .. tostring(key)
        .. " vote="
        .. tostring(effectiveVote)
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
        vote = effectiveVote,
        voteOriginal = originalVote,
        voteEffective = effectiveVote,
        reason = reason,
        reasonText = reasonText,
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
  if self.ClearCoverOverridesForRoll then
    self:ClearCoverOverridesForRoll(payload.rollID)
  end
  local debugEnabled = self.IsDebugEnabled and self:IsDebugEnabled()
  if self.IsAuthorizedSender then
    local ok = self:IsAuthorizedSender(sender, payload.authorityGUID, payload.authorityName)
    if not ok then
      self:Debug("Blocked unauthorized roll result from " .. tostring(sender))
      return
    end
  end
  local rollID = payload.rollID
  local rollKey = DeriveRollKey(self, payload)
  if not rollKey and debugEnabled then
    self:Debug("Roll result missing rollKey: rollID=" .. tostring(rollID))
  end
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
  if debugEnabled then
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
    local localKey = NS.GetPlayerKeyFromUnit and NS:GetPlayerKeyFromUnit("player") or nil
    local localFull = self.GetUnitFullName and self:GetUnitFullName("player") or nil
    local localShort = UnitName("player")
    local isWinner = false
    if localKey and payload.winnerKey and payload.winnerKey == localKey then
      isWinner = true
    elseif localFull and payload.winnerName and payload.winnerName == localFull then
      isWinner = true
    elseif localShort and payload.winnerShortName and payload.winnerShortName == localShort then
      isWinner = true
    end

    local function CountQueueFromRoster(roster)
      local count = 0
      for _, entry in ipairs(roster or {}) do
        if entry and entry.queuePos then
          count = count + 1
        end
      end
      return count
    end

    local function CountQueueFromDb(players)
      local count = 0
      for _, player in pairs(players or {}) do
        if player and player.queuePos then
          count = count + 1
        end
      end
      return count
    end

    local function FindQueuePosInRoster(roster, key, name)
      if not roster then
        return nil
      end
      for _, entry in ipairs(roster) do
        if entry then
          if key and entry.key == key then
            return entry.queuePos
          end
          if name then
            if entry.name == name then
              return entry.queuePos
            end
            if entry.realm and (entry.name .. "-" .. entry.realm) == name then
              return entry.queuePos
            end
          end
        end
      end
      return nil
    end

    local oldPos = nil
    local winnerOldPos = nil
    local queueCount = nil
    local isAuthority = self.IsAuthority and self:IsAuthority()
    if isAuthority then
      local players = self.db and self.db.players or nil
      oldPos = localKey and players and players[localKey] and players[localKey].queuePos or nil
      winnerOldPos = payload.winnerKey and players and players[payload.winnerKey] and players[payload.winnerKey].queuePos or nil
      queueCount = CountQueueFromDb(players)
    else
      if self.shadow and self.shadow.my then
        oldPos = self.shadow.my.queuePos
      end
      local roster = self.shadow and self.shadow.roster or nil
      if winnerOldPos == nil then
        winnerOldPos = FindQueuePosInRoster(roster, payload.winnerKey, payload.winnerName or payload.winnerShortName)
      end
      if oldPos == nil then
        oldPos = FindQueuePosInRoster(roster, localKey, localFull or localShort)
      end
      queueCount = CountQueueFromRoster(roster)
    end

    local moveMode = "END"
    if not payload.winnerKey then
      moveMode = "NONE"
    elseif self.GetMoveModeForVoteType then
      moveMode = self:GetMoveModeForVoteType(payload.winnerVote)
    end

    local function GetWinnerNewPos()
      if not winnerOldPos or not queueCount or moveMode == "NONE" then
        return winnerOldPos
      end
      if moveMode == "MIDDLE" then
        local pos = math.floor(queueCount / 2)
        if pos < 1 then
          pos = 1
        end
        return pos
      end
      return queueCount
    end

    local newPos = oldPos
    if oldPos and winnerOldPos and queueCount and moveMode ~= "NONE" and payload.winnerKey then
      local winnerNewPos = GetWinnerNewPos()
      if oldPos == winnerOldPos then
        newPos = winnerNewPos
      elseif winnerNewPos then
        local pos = oldPos
        if oldPos > winnerOldPos then
          pos = pos - 1
        end
        if winnerNewPos <= pos then
          pos = pos + 1
        end
        newPos = pos
      end
    end

    if GetItemInfo and payload.itemLink and not payload.itemIcon then
      payload.itemIcon = select(10, GetItemInfo(payload.itemLink))
    end
    payload.isWinner = isWinner
    payload.oldPosition = oldPos
    payload.newPosition = newPos
    payload.winnerRoll = payload.winnerRoll or payload.winningRoll
    self.UI:ShowRollResultPopup(payload)
  end
  if self.UI and self.UI.RefreshPendingVotes then
    self.UI:RefreshPendingVotes()
  end
end

function GLD:HandleVoteConverted(sender, payload)
  if not payload then
    return
  end
  local targetKey = payload.voterKey
  if targetKey then
    local localKey = NS.GetPlayerKeyFromUnit and NS:GetPlayerKeyFromUnit("player") or nil
    if not localKey or localKey ~= targetKey then
      return
    end
  end
  local originalVote = payload.voteOriginal or payload.vote
  local effectiveVote = payload.voteEffective or payload.vote
  if not originalVote or not effectiveVote then
    return
  end
  local reasonText = payload.reasonText
  if not reasonText and payload.reason and self.GetEligibilityReasonText then
    local _, session = self:FindActiveRoll(payload.rollKey, payload.rollID)
    reasonText = self:GetEligibilityReasonText(payload.reason, session)
  end
  local msg = "Your " .. tostring(originalVote) .. " was converted to " .. tostring(effectiveVote)
  if reasonText then
    msg = msg .. " (reason: " .. tostring(reasonText) .. ")"
  end
  self:Print(msg)
end

function GLD:HandleRollAck(sender, payload)
  if not payload then
    return
  end
  if not self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  if self.IsSenderInRaid and not self:IsSenderInRaid(sender) then
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug("Roll ack ignored (sender not in raid): " .. tostring(sender))
    end
    return
  end
  local rollID = payload.rollID
  local rollKey = DeriveRollKey(self, payload)
  if not rollKey then
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug("Roll ack ignored: missing rollKey for rollID=" .. tostring(rollID))
    end
    return
  end
  local _, session = self.FindActiveRoll and self:FindActiveRoll(rollKey, rollID)
  if not session then
    session = self.activeRolls and self.activeRolls[rollKey] or nil
  end
  if not session then
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug("Roll ack ignored: no session for rollID=" .. tostring(rollID) .. " rollKey=" .. tostring(rollKey))
    end
    return
  end
  session.acks = session.acks or {}
  local voterKey = payload.voterKey or (self.GetRollCandidateKey and self:GetRollCandidateKey(sender)) or sender
  if voterKey then
    session.acks[voterKey] = true
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug(
      "Roll ack received: rollID="
        .. tostring(rollID)
        .. " rollKey="
        .. tostring(rollKey)
        .. " voter="
        .. tostring(voterKey)
        .. " sender="
        .. tostring(sender)
    )
  end
end

function GLD:HandleRollSessionRequest(sender, payload)
  if not self:IsAuthority() then
    return
  end
  if not IsInRaid() then
    return
  end
  if self.IsSenderInRaid and not self:IsSenderInRaid(sender) then
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug("Roll session request ignored (sender not in raid): " .. tostring(sender))
    end
    return
  end
  if not payload then
    return
  end
  local rollID = payload.rollID
  local rollKey = DeriveRollKey(self, payload)
  local _, session = self.FindActiveRoll and self:FindActiveRoll(rollKey, rollID)
  if not session then
    session = self.activeRolls and rollKey and self.activeRolls[rollKey] or nil
  end
  if session then
    self:BroadcastRollSession(session, { snapshot = true, reopen = true })
    if self.IsDebugEnabled and self:IsDebugEnabled() then
      self:Debug(
        "Roll session resend: rollID="
          .. tostring(session.rollID)
          .. " rollKey="
          .. tostring(session.rollKey)
          .. " target=raid"
      )
    end
    return
  end
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug(
      "Roll session request ignored: no session for rollID="
        .. tostring(rollID)
        .. " rollKey="
        .. tostring(rollKey)
    )
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

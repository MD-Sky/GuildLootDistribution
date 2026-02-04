local _, NS = ...

local GLD = NS.GLD

local DEFAULT_CONFIG = {
  trinketRoleMap = {},
  bossDisabled = {},
  trinketLootRaidId = nil,
  trinketLootRaidName = "The Voidspire",
  trinketLootRole = "DPS",
  transmogWinnerMove = "NONE",
  greedWinnerMove = "NONE",
  debugLogs = false,
  tutorialSeen = false,
  tutorialVersion = 1,
  popupDismissed = {},
  minimap = {
    hide = false,
    angle = 220,
  },
}

local function InitGuestDB()
  if not GLT_DB or type(GLT_DB) ~= "table" then
    GLT_DB = {}
  end
  GLT_DB.seenGuests = GLT_DB.seenGuests or {}
  GLT_DB.lastGuestWelcomeAt = GLT_DB.lastGuestWelcomeAt or {}
end

local function InitMasterDB()
  if not GuildLootDB or type(GuildLootDB) ~= "table" then
    GuildLootDB = {}
  end

  GuildLootDB.version = GuildLootDB.version or 1
  GuildLootDB.meta = GuildLootDB.meta or {
    revision = 0,
    lastChanged = 0,
  }
  GuildLootDB.config = GuildLootDB.config or DEFAULT_CONFIG
  GuildLootDB.config.popupDismissed = GuildLootDB.config.popupDismissed or {}
  GuildLootDB.players = GuildLootDB.players or {}
  GuildLootDB.queue = GuildLootDB.queue or {}
  GuildLootDB.rollHistory = GuildLootDB.rollHistory or {}
  GuildLootDB.raidSessions = GuildLootDB.raidSessions or {}
  GuildLootDB.auditLog = GuildLootDB.auditLog or {}
  GuildLootDB.testSessions = GuildLootDB.testSessions or {}
  GuildLootDB.testSession = GuildLootDB.testSession or {
    active = false,
    currentId = nil,
  }
  GuildLootDB.session = GuildLootDB.session or {
    active = false,
    startedAt = 0,
    attended = {},
    raidSessionId = nil,
    currentBoss = nil,
    authorityGUID = nil,
    authorityName = nil,
    zoneInstanceID = nil,
  }
end

local function InitShadowDB()
  if not GuildLootShadow or type(GuildLootShadow) ~= "table" then
    GuildLootShadow = {}
  end

  GuildLootShadow.version = GuildLootShadow.version or 1
  GuildLootShadow.meta = GuildLootShadow.meta or {
    revision = 0,
    lastChanged = 0,
  }
  GuildLootShadow.lastSyncAt = GuildLootShadow.lastSyncAt or 0
  GuildLootShadow.rosterReceived = GuildLootShadow.rosterReceived or false
  GuildLootShadow.sessionActive = GuildLootShadow.sessionActive or false
  GuildLootShadow.my = GuildLootShadow.my or {
    queuePos = nil,
    savedPos = nil,
    numAccepted = nil,
    attendance = nil,
    attendanceCount = nil,
  }
  GuildLootShadow.roster = GuildLootShadow.roster or {}
end

function GLD:InitDB()
  InitMasterDB()
  InitShadowDB()
  InitGuestDB()
  self.db = GuildLootDB
  self.shadow = GuildLootShadow
  self.guestDB = GLT_DB
end

function GLD:MarkDBChanged(reason)
  if not self.db then
    return
  end
  self.db.meta = self.db.meta or {}
  self.db.meta.revision = (tonumber(self.db.meta.revision) or 0) + 1
  self.db.meta.lastChanged = (GetServerTime and GetServerTime() or time())
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    local label = reason and (" reason=" .. tostring(reason)) or ""
    self:Debug("DB revision bumped to " .. tostring(self.db.meta.revision) .. label)
  end
end

local AUDIT_LOG_MAX = 5000

function GLD:AppendAuditLog(entry)
  if not self.db then
    return
  end
  self.db.auditLog = self.db.auditLog or {}
  table.insert(self.db.auditLog, 1, entry)
  if #self.db.auditLog > AUDIT_LOG_MAX then
    for i = #self.db.auditLog, AUDIT_LOG_MAX + 1, -1 do
      table.remove(self.db.auditLog, i)
    end
  end
end

function GLD:LogAuditEvent(eventType, data)
  if not self.db then
    return
  end
  local entry = {
    timestamp = GetServerTime(),
    type = eventType,
    actor = data and data.actor or nil,
    target = data and data.target or nil,
    isGuest = data and data.isGuest or nil,
    class = data and data.class or nil,
    spec = data and data.spec or nil,
    playerKey = data and (data.playerKey or data.rosterKey or data.key or data.id) or nil,
    details = data and data.details or nil,
  }
  self:AppendAuditLog(entry)
end

function GLD:GetConfig()
  return self.db.config
end

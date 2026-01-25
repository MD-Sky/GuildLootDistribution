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
  GuildLootDB.config = GuildLootDB.config or DEFAULT_CONFIG
  GuildLootDB.players = GuildLootDB.players or {}
  GuildLootDB.queue = GuildLootDB.queue or {}
  GuildLootDB.rollHistory = GuildLootDB.rollHistory or {}
  GuildLootDB.raidSessions = GuildLootDB.raidSessions or {}
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
  }
end

local function InitShadowDB()
  if not GuildLootShadow or type(GuildLootShadow) ~= "table" then
    GuildLootShadow = {}
  end

  GuildLootShadow.version = GuildLootShadow.version or 1
  GuildLootShadow.lastSyncAt = GuildLootShadow.lastSyncAt or 0
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

function GLD:GetConfig()
  return self.db.config
end

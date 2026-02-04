local ADDON_NAME, NS = ...

NS.ADDON_NAME = ADDON_NAME
NS.VERSION = "0.2.1"
NS.COMM_PREFIX = "GLD1"
NS.COVER_COMM_PREFIX = "GLD1COV"
NS.MSG = {
  STATE_SNAPSHOT = "STATE_SNAPSHOT",
  DELTA = "DELTA",
  ROLL_SESSION = "ROLL_SESSION",
  ROLL_VOTE = "ROLL_VOTE",
  ROLL_RESULT = "ROLL_RESULT",
  ROLL_MISMATCH = "ROLL_MISMATCH",
  ROLL_ACK = "ROLL_ACK",
  ROLL_SESSION_REQUEST = "ROLL_SESSION_REQUEST",
  VOTE_CONVERTED = "VOTE_CONVERTED",
  FORCE_PENDING = "FORCE_PENDING",
  SESSION_STATE = "SESSION_STATE",
  REV_CHECK = "REV_CHECK",
  ADMIN_REQUEST = "ADMIN_REQUEST",
  NOTICE = "NOTICE",
}

local function SafeGetLib(name)
  if not LibStub then
    return nil
  end
  return LibStub(name, true)
end

local AceAddon = SafeGetLib("AceAddon-3.0")
if not AceAddon then
  DEFAULT_CHAT_FRAME:AddMessage("GuildLootDistribution: Ace3 libraries not found. Add them to Libs/.")
  return
end

local GLD = AceAddon:NewAddon(ADDON_NAME, "AceEvent-3.0", "AceComm-3.0", "AceSerializer-3.0")
NS.GLD = GLD

function GLD:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GuildLoot|r " .. tostring(msg))
end

function GLD:TraceStep(msg)
  if msg == nil then
    return
  end
  self:Print("Step: " .. tostring(msg))
end

function GLD:IsDebugEnabled()
  return self.db and self.db.config and self.db.config.debugLogs == true
end

function GLD:Debug(msg)
  if not self:IsDebugEnabled() then
    return
  end
  if self.UI and self.UI.AppendDebugLine then
    self.UI:AppendDebugLine(msg)
    return
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GuildLoot|r " .. tostring(msg))
end

function GLD:IsAdmin()
  if self.CanLocalSeeAdminUI then
    return self:CanLocalSeeAdminUI()
  end
  return false
end

function GLD:OnInitialize()
  self:InitDB()
  if self.InitTestDB then
    self:InitTestDB()
  end
  self:InitConfig()
  self:InitComms()
  self:InitUI()
  self:InitTestUI()
  self:InitMinimapButton()
  self:InitAttendance()
  self:InitLoot()
  if self.InitSpec then
    self:InitSpec()
  end
  self:RegisterSlashCommands()
end

function GLD:OnEnable()
  self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnGroupRosterUpdate")
  self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "OnGroupRosterUpdate")
  self:RegisterEvent("PLAYER_GUILD_UPDATE", "OnGroupRosterUpdate")
  self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
  self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
  self:RegisterEvent("INSPECT_READY", "OnInspectReady")
  self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecChanged")
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")
  if self.TryCreateGuildUIButton then
    self:TryCreateGuildUIButton()
  end
  if self.InitRaidStateTicker then
    self:InitRaidStateTicker()
  end
  self:Print("Commands: /gld (main UI), /disadmin (admin), /gldtest (seed test), /gldadmintest (admin test panel), /glddebug (debug window)")
end

function GLD:RegisterSlashCommands()
  SLASH_GLD1 = "/gld"
  SLASH_GLD2 = "/disloot"
  SlashCmdList["GLD"] = function()
    self.UI:ToggleMain()
  end

  SLASH_GLDTUTORIAL1 = "/gldtutorial"
  SlashCmdList["GLDTUTORIAL"] = function()
    GLD.db.config.tutorialSeen = false
    GLD:MarkDBChanged("tutorialReplay")
    GLD.UI:ToggleMain()
    if GLD.UI.Tutorial then
      GLD.UI.Tutorial:Start(true)
    end
  end

  SLASH_DISADMIN1 = "/disadmin"
  SlashCmdList["DISADMIN"] = function()
    if not self.CanAccessAdminUI or not self:CanAccessAdminUI() then
      self:ShowPermissionDeniedPopup()
      return
    end
    self.UI:OpenAdmin()
  end

  SLASH_GLDTEST1 = "/gldtest"
  SlashCmdList["GLDTEST"] = function()
    if not self.CanMutateState or not self:CanMutateState() then
      self:ShowPermissionDeniedPopup()
      return
    end
    self:SeedTestData()
  end

  SLASH_GLDADMINTEST1 = "/gldadmintest"
  SlashCmdList["GLDADMINTEST"] = function()
    if not self.CanAccessAdminUI or not self:CanAccessAdminUI() then
      self:ShowPermissionDeniedPopup()
      return
    end
    NS.TestUI:ToggleTestPanel()
  end

  SLASH_GLDDEBUG1 = "/glddebug"
  SLASH_GLDDEBUG2 = "/gldlogs"
  SlashCmdList["GLDDEBUG"] = function()
    if self.UI and self.UI.ToggleDebugFrame then
      self.UI:ToggleDebugFrame()
    end
  end
end

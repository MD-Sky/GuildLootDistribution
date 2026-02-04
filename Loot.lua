local _, NS = ...

local GLD = NS.GLD
local LootEngine = NS.LootEngine
local LiveProvider = NS.LiveProvider
local TestProvider = NS.TestProvider

local function LBDebugEnabled()
  return GLD and GLD.lbDebug == true
end

local function LBPrint(msg, force)
  if not force and not LBDebugEnabled() then
    return
  end
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("[LB] " .. tostring(msg))
  end
end

do
  local version = NS.VERSION
  if not version and GetAddOnMetadata and NS.ADDON_NAME then
    version = GetAddOnMetadata(NS.ADDON_NAME, "Version")
  end
  local build = nil
  if GetBuildInfo then
    build = select(4, GetBuildInfo())
  end
  local stamp = date and date("%Y-%m-%d %H:%M:%S") or "unknown time"
  LBPrint(
    "Covers module loaded (version="
      .. tostring(version or "unknown")
      .. ", build="
      .. tostring(build or "unknown")
      .. ", time="
      .. tostring(stamp)
      .. ")",
    true
  )
end

function GLD:InitLoot()
  self.activeRolls = {}
  self:RegisterEvent("START_LOOT_ROLL", "OnStartLootRoll")
  self:RegisterEvent("CANCEL_LOOT_ROLL", "OnCancelLootRoll")
  self:RegisterEvent("PLAYER_LOGIN", "OnCoverLogin")
  if self.lbDebug == nil then
    self.lbDebug = false
  end
  SLASH_LBDEBUG1 = "/lbdebug"
  SlashCmdList["LBDEBUG"] = function()
    self.lbDebug = not self.lbDebug
    LBPrint("Debug " .. (self.lbDebug and "enabled" or "disabled"), true)
  end
  SLASH_LBLOCK1 = "/lblock"
  SlashCmdList["LBLOCK"] = function(msg)
    local mode = tostring(msg or ""):lower():gsub("%s+", "")
    if mode == "" then
      mode = "lock_all"
    end
    local mapped = {
      lock_all = "LOCK_ALL",
      unlock_all = "UNLOCK_ALL",
      winner = "WINNER",
      loser = "LOSER",
    }
    local applyMode = mapped[mode]
    if not applyMode then
      LBPrint("Unknown mode: " .. tostring(msg), true)
      return
    end
    local rollFrame = nil
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 8) do
      local frame = _G["GroupLootFrame" .. i] or _G["LootRollFrame" .. i]
      if frame and frame.IsShown and frame:IsShown() then
        rollFrame = frame
        break
      end
    end
    if not rollFrame then
      LBPrint("No visible roll frame found for manual test", true)
      return
    end
    RollBlockers.SetMode(rollFrame, applyMode)
    LBPrint("Manual apply " .. applyMode .. " to " .. tostring(rollFrame:GetName() or rollFrame), true)
  end
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
  if self.InitCoverAuthority then
    self:InitCoverAuthority()
  end
end

local RollBlockers = {
  byFrame = setmetatable({}, { __mode = "k" }),
}

GLD.RollBlockers = RollBlockers

local LibCustomGlow = LibStub and LibStub("LibCustomGlow-1.0", true) or nil
local BLOCKER_TOOLTIP_TEXT = "Waiting for loot decision..."

local function GetTransmogOrDisenchantButton(rollFrame)
  if not rollFrame then
    return nil
  end
  return rollFrame.TransmogButton or rollFrame.DisenchantButton or rollFrame.Disenchant
end

local function GetPassButton(rollFrame)
  if not rollFrame then
    return nil
  end
  return rollFrame.PassButton or rollFrame.Pass
end

local function SyncBlocker(blocker, button)
  if not blocker or not button then
    return
  end
  if blocker.GetParent and blocker:GetParent() ~= UIParent then
    blocker:SetParent(UIParent)
  end
  blocker:ClearAllPoints()
  blocker:SetAllPoints(button)
  blocker:SetFrameStrata("FULLSCREEN_DIALOG")
  local level = button.GetFrameLevel and button:GetFrameLevel() or 0
  blocker:SetFrameLevel(level + 200)
end

local function CreateBlocker(button)
  if not button then
    return nil
  end
  local blocker = CreateFrame("Frame", nil, UIParent)
  blocker:EnableMouse(true)
  blocker:SetAllPoints(button)
  blocker:SetFrameStrata("FULLSCREEN_DIALOG")
  local level = button.GetFrameLevel and button:GetFrameLevel() or 0
  blocker:SetFrameLevel(level + 200)
  if blocker.SetPropagateMouseClicks then
    blocker:SetPropagateMouseClicks(false)
  end
  blocker:SetScript("OnMouseDown", function(self)
    if LBDebugEnabled() then
      local name = self._gldButtonName or "unknown"
      LBPrint("blocker clicked over " .. tostring(name))
    end
  end)
  blocker:SetScript("OnMouseUp", function() end)
  if GameTooltip then
    blocker:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(BLOCKER_TOOLTIP_TEXT)
      GameTooltip:Show()
    end)
    blocker:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
  end
  local texture = blocker:CreateTexture(nil, "BACKGROUND")
  texture:SetAllPoints()
  texture:SetTexture("Interface\\AddOns\\lilyUI\\Media\\ClickDenied.tga")
  texture:SetAlpha(0.9)
  blocker._gldTexture = texture
  blocker:Hide()
  return blocker
end

local function EnsureBlocker(blockers, key, button)
  if not button then
    return
  end
  if not blockers[key] then
    blockers[key] = CreateBlocker(button)
  end
  SyncBlocker(blockers[key], button)
end

local function SetHighlight(button, on)
  if not button then
    return
  end
  if LibCustomGlow and LibCustomGlow.ButtonGlow_Start and LibCustomGlow.ButtonGlow_Stop then
    if on then
      LibCustomGlow.ButtonGlow_Start(button)
    else
      LibCustomGlow.ButtonGlow_Stop(button)
    end
    return
  end
  if ActionButton_ShowOverlayGlow and ActionButton_HideOverlayGlow then
    if on then
      ActionButton_ShowOverlayGlow(button)
    else
      ActionButton_HideOverlayGlow(button)
    end
  end
end

local function ApplyHighlights(rollFrame, mode)
  if not rollFrame then
    return
  end
  local blockers = RollBlockers.byFrame[rollFrame]
  local buttons = blockers and blockers.buttons or {}
  local function Apply(key, on)
    SetHighlight(buttons[key], on)
  end
  if mode == "WINNER" then
    Apply("need", true)
    Apply("greed", true)
    Apply("transmog", true)
    Apply("pass", false)
    return
  end
  if mode == "LOSER" then
    Apply("need", false)
    Apply("greed", false)
    Apply("transmog", false)
    Apply("pass", true)
    return
  end
  Apply("need", false)
  Apply("greed", false)
  Apply("transmog", false)
  Apply("pass", false)
end

function RollBlockers.EnsureForRollFrame(rollFrame)
  if not rollFrame then
    return nil
  end
  local blockers = RollBlockers.byFrame[rollFrame]
  if not blockers then
    blockers = {}
    RollBlockers.byFrame[rollFrame] = blockers
  end
  if not rollFrame._gldBlockerHooksSet then
    rollFrame:HookScript("OnShow", function()
      if rollFrame._gldBlockerNeedsOnShow then
        local mode = rollFrame._gldBlockerOnShowMode or "LOCK_ALL"
        rollFrame._gldBlockerNeedsOnShow = nil
        rollFrame._gldBlockerOnShowMode = nil
        LBPrint("OnShow reapply " .. tostring(mode) .. " for " .. tostring(rollFrame:GetName() or rollFrame))
        RollBlockers.SetMode(rollFrame, mode)
      end
    end)
    rollFrame:HookScript("OnHide", function()
      ApplyHighlights(rollFrame, "UNLOCK_ALL")
      LBPrint("Roll frame hidden: highlights cleared for " .. tostring(rollFrame:GetName() or rollFrame))
    end)
    rollFrame._gldBlockerHooksSet = true
  end
  blockers.buttons = blockers.buttons or {}
  blockers.buttons.need = rollFrame.NeedButton or rollFrame.Need
  blockers.buttons.greed = rollFrame.GreedButton or rollFrame.Greed
  blockers.buttons.transmog = GetTransmogOrDisenchantButton(rollFrame)
  blockers.buttons.pass = GetPassButton(rollFrame)
  if LBDebugEnabled() then
    local function LogButton(label, button)
      if not button then
        LBPrint(label .. ": nil")
        return
      end
      local w = button.GetWidth and button:GetWidth() or 0
      local h = button.GetHeight and button:GetHeight() or 0
      local strata = button.GetFrameStrata and button:GetFrameStrata() or "?"
      local level = button.GetFrameLevel and button:GetFrameLevel() or 0
      LBPrint(label .. ": " .. tostring(button:GetName() or button) .. " size=" .. tostring(w) .. "x" .. tostring(h) .. " strata=" .. tostring(strata) .. " level=" .. tostring(level))
      if w == 0 or h == 0 then
        LBPrint("button size 0x0: layout not ready; reapply next frame / OnShow hook needed")
      end
    end
    LogButton("need", blockers.buttons.need)
    LogButton("greed", blockers.buttons.greed)
    LogButton("transmog", blockers.buttons.transmog)
    LogButton("pass", blockers.buttons.pass)
    local missing = {}
    if not blockers.buttons.need then
      missing[#missing + 1] = "need"
    end
    if not blockers.buttons.greed then
      missing[#missing + 1] = "greed"
    end
    if not blockers.buttons.transmog then
      missing[#missing + 1] = "transmog"
    end
    if not blockers.buttons.pass then
      missing[#missing + 1] = "pass"
    end
    if #missing > 0 then
      LBPrint("missing buttons: " .. table.concat(missing, ", "))
    end
  end
  EnsureBlocker(blockers, "need", blockers.buttons.need)
  EnsureBlocker(blockers, "greed", blockers.buttons.greed)
  EnsureBlocker(blockers, "transmog", blockers.buttons.transmog)
  EnsureBlocker(blockers, "pass", blockers.buttons.pass)
  return blockers
end

local function SetBlockerVisible(blocker, button, show)
  if not blocker then
    return
  end
  if show then
    if button then
      blocker._gldButton = button
      blocker._gldButtonName = button.GetName and button:GetName() or tostring(button)
      SyncBlocker(blocker, button)
    end
    blocker:Show()
    if blocker.Raise then
      blocker:Raise()
    end
    if LBDebugEnabled() then
      local w = blocker.GetWidth and blocker:GetWidth() or 0
      local h = blocker.GetHeight and blocker:GetHeight() or 0
      if w == 0 or h == 0 then
        LBPrint("blocker has 0 size: anchor timing problem")
      end
    end
  else
    blocker:Hide()
  end
end

function RollBlockers.SetMode(rollFrame, mode)
  local blockers = RollBlockers.EnsureForRollFrame(rollFrame)
  if not blockers then
    return
  end
  if LBDebugEnabled() then
    local name = rollFrame and (rollFrame.GetName and rollFrame:GetName() or tostring(rollFrame)) or "unknown"
    LBPrint("SetMode " .. tostring(mode) .. " for " .. tostring(name))
  end
  if LBDebugEnabled() then
    local name = rollFrame and (rollFrame.GetName and rollFrame:GetName() or tostring(rollFrame)) or "unknown"
    local shown = rollFrame and rollFrame.IsShown and rollFrame:IsShown() or false
    if not shown then
      LBPrint("rollFrame hidden when applying " .. tostring(mode) .. ": " .. tostring(name))
    end
  end
  local buttons = blockers.buttons or {}
  local function ShowForButton(key, show)
    local button = buttons[key]
    local blocker = blockers[key]
    if not button then
      show = false
    end
    if show and blocker and button then
      blocker:ClearAllPoints()
      blocker:SetAllPoints(button)
    end
    SetBlockerVisible(blocker, button, show)
  end
  if mode == "LOCK_ALL" then
    ShowForButton("need", true)
    ShowForButton("greed", true)
    ShowForButton("transmog", true)
    ShowForButton("pass", true)
    ApplyHighlights(rollFrame, mode)
    return
  end
  if mode == "WINNER" then
    ShowForButton("need", false)
    ShowForButton("greed", false)
    ShowForButton("transmog", false)
    ShowForButton("pass", true)
    ApplyHighlights(rollFrame, mode)
    return
  end
  if mode == "LOSER" then
    ShowForButton("need", true)
    ShowForButton("greed", true)
    ShowForButton("transmog", true)
    ShowForButton("pass", false)
    ApplyHighlights(rollFrame, mode)
    return
  end
  ShowForButton("need", false)
  ShowForButton("greed", false)
  ShowForButton("transmog", false)
  ShowForButton("pass", false)
  ApplyHighlights(rollFrame, mode)
end

function RollBlockers.ReleaseForRollFrame(rollFrame)
  if not rollFrame then
    return
  end
  local blockers = RollBlockers.byFrame[rollFrame]
  if not blockers then
    return
  end
  for _, key in ipairs({ "need", "greed", "transmog", "pass" }) do
    local blocker = blockers[key]
    if blocker and blocker.Hide then
      blocker:Hide()
    end
    blockers[key] = nil
  end
  blockers.buttons = nil
  RollBlockers.byFrame[rollFrame] = nil
end

local function FindRollFrameByID(rollID)
  if not rollID then
    return nil
  end
  if GroupLootContainer then
    if GroupLootContainer.GetFrameForLootID then
      local frame = GroupLootContainer:GetFrameForLootID(rollID)
      if LBDebugEnabled() then
        LBPrint("GroupLootContainer:GetFrameForLootID exists, result=" .. tostring(frame and (frame.GetName and frame:GetName() or frame) or "nil"))
      end
      if frame then
        return frame
      end
    elseif LBDebugEnabled() then
      LBPrint("GroupLootContainer:GetFrameForLootID missing")
    end
    if GroupLootContainer.GetFrameForRollID then
      local frame = GroupLootContainer:GetFrameForRollID(rollID)
      if LBDebugEnabled() then
        LBPrint("GroupLootContainer:GetFrameForRollID exists, result=" .. tostring(frame and (frame.GetName and frame:GetName() or frame) or "nil"))
      end
      if frame then
        return frame
      end
    elseif LBDebugEnabled() then
      LBPrint("GroupLootContainer:GetFrameForRollID missing")
    end
  elseif LBDebugEnabled() then
    LBPrint("GroupLootContainer missing; fallback to GroupLootFrame scan")
  end
  local maxFrames = NUM_GROUP_LOOT_FRAMES or NUM_LOOT_ROLLS or 8
  for i = 1, maxFrames do
    local frame = _G["GroupLootFrame" .. i] or _G["LootRollFrame" .. i]
    if frame and (frame.rollID == rollID or frame.lootID == rollID or frame.LootID == rollID) then
      if LBDebugEnabled() then
        LBPrint("Fallback scan matched: " .. tostring(frame:GetName() or frame))
      end
      return frame
    end
  end
  if LBDebugEnabled() then
    LBPrint("Fallback scan: no GroupLootFrame1.." .. tostring(maxFrames) .. " matched rollID=" .. tostring(rollID))
  end
  return nil
end

function RollBlockers.ApplyForRoll(rollID, mode)
  if not rollID then
    return nil
  end
  local rollFrame = (GLD and GLD._rollFrameByRollID and GLD._rollFrameByRollID[rollID]) or FindRollFrameByID(rollID)
  if not rollFrame then
    if LBDebugEnabled() then
      LBPrint("ApplyForRoll: rollFrame nil for rollID=" .. tostring(rollID))
    end
    return nil
  end
  if GLD then
    GLD._rollFrameByRollID = GLD._rollFrameByRollID or {}
    GLD._rollFrameByRollID[rollID] = rollFrame
  end
  RollBlockers.SetMode(rollFrame, mode)
  return rollFrame
end

function GLD:LockLootRollButtons(rollID)
  if not rollID then
    return
  end
  if LBDebugEnabled() then
    LBPrint("START_LOOT_ROLL: rollID=" .. tostring(rollID))
  end
  local rollFrame = FindRollFrameByID(rollID)
  if not rollFrame then
    if LBDebugEnabled() then
      LBPrint("rollFrame nil: lookup mismatch (GroupLootContainer vs GroupLootFrame scan)")
    end
    if C_Timer and C_Timer.After then
      self._pendingRollFrameLookup = self._pendingRollFrameLookup or {}
      if not self._pendingRollFrameLookup[rollID] then
        self._pendingRollFrameLookup[rollID] = true
        C_Timer.After(0, function()
          self._pendingRollFrameLookup[rollID] = nil
          self:LockLootRollButtons(rollID)
        end)
      end
    end
    return
  end
  if LBDebugEnabled() then
    local name = rollFrame.GetName and rollFrame:GetName() or tostring(rollFrame)
    local shown = rollFrame.IsShown and rollFrame:IsShown() or false
    local strata = rollFrame.GetFrameStrata and rollFrame:GetFrameStrata() or "?"
    local level = rollFrame.GetFrameLevel and rollFrame:GetFrameLevel() or 0
    LBPrint("rollFrame=" .. tostring(name) .. " shown=" .. tostring(shown) .. " strata=" .. tostring(strata) .. " level=" .. tostring(level))
  end
  self._rollFrameByRollID = self._rollFrameByRollID or {}
  self._rollFrameByRollID[rollID] = rollFrame
  rollFrame._gldBlockerNeedsOnShow = true
  rollFrame._gldBlockerOnShowMode = "LOCK_ALL"
  RollBlockers.SetMode(rollFrame, "LOCK_ALL")
  if LBDebugEnabled() then
    LBPrint("SetMode LOCK_ALL called")
  end
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      RollBlockers.SetMode(rollFrame, "LOCK_ALL")
      if LBDebugEnabled() then
        LBPrint("Reapplied next frame")
      end
    end)
  end
end

function GLD:UnlockLootRollButtons(rollID)
  if not rollID then
    return
  end
  if LBDebugEnabled() then
    LBPrint("CANCEL_LOOT_ROLL: rollID=" .. tostring(rollID))
  end
  local rollFrame = self._rollFrameByRollID and self._rollFrameByRollID[rollID] or nil
  if not rollFrame then
    rollFrame = FindRollFrameByID(rollID)
  end
  if rollFrame then
    rollFrame._gldBlockerNeedsOnShow = nil
    rollFrame._gldBlockerOnShowMode = nil
    RollBlockers.SetMode(rollFrame, "UNLOCK_ALL")
    if LBDebugEnabled() then
      local name = rollFrame.GetName and rollFrame:GetName() or tostring(rollFrame)
      LBPrint("Unlock rollFrame=" .. tostring(name))
      LBPrint("SetMode UNLOCK_ALL called")
    end
    if RollBlockers.ReleaseForRollFrame then
      RollBlockers.ReleaseForRollFrame(rollFrame)
    end
  elseif LBDebugEnabled() then
    LBPrint("rollFrame not found on CANCEL_LOOT_ROLL")
  end
  if self._rollFrameByRollID then
    self._rollFrameByRollID[rollID] = nil
  end
  if self._pendingRollFrameLookup then
    self._pendingRollFrameLookup[rollID] = nil
  end
end

local function GetResumeMode(self, rollID, playerGUID)
  local mode = self.GetCoverOverrideMode and self:GetCoverOverrideMode(rollID, playerGUID) or nil
  if mode ~= "WINNER" and mode ~= "LOSER" then
    mode = "LOCK_ALL"
  end
  return mode
end

function GLD:ResumeCoverBlockers()
  if not self.FindActiveRoll then
    return
  end
  local playerGUID = UnitGUID("player")
  if not playerGUID then
    return
  end
  local seen = {}
  local function ApplyForFrame(rollID, rollFrame)
    if not rollID or not rollFrame then
      return
    end
    local _, session = self:FindActiveRoll(nil, rollID)
    if not session or session.locked then
      return
    end
    if self.IsRollSessionExpired and self:IsRollSessionExpired(session) then
      return
    end
    self._rollFrameByRollID = self._rollFrameByRollID or {}
    self._rollFrameByRollID[rollID] = rollFrame
    local mode = GetResumeMode(self, rollID, playerGUID)
    rollFrame._gldBlockerNeedsOnShow = true
    rollFrame._gldBlockerOnShowMode = mode
    RollBlockers.SetMode(rollFrame, mode)
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()
        RollBlockers.SetMode(rollFrame, mode)
      end)
    end
  end

  if GroupLootContainer and GroupLootContainer.GetFrameForRollID and self.activeRolls then
    for _, session in pairs(self.activeRolls) do
      local rollID = session and session.rollID or nil
      if rollID and not seen[rollID] then
        local frame = GroupLootContainer:GetFrameForRollID(rollID)
        if frame then
          seen[rollID] = true
          ApplyForFrame(rollID, frame)
        end
      end
    end
  end

  local maxFrames = NUM_GROUP_LOOT_FRAMES or NUM_LOOT_ROLLS or 8
  for i = 1, maxFrames do
    local frame = _G["GroupLootFrame" .. i] or _G["LootRollFrame" .. i]
    if frame and frame.IsShown and frame:IsShown() then
      local rollID = frame.rollID or frame.lootID or frame.LootID
      if rollID and not seen[rollID] then
        seen[rollID] = true
        ApplyForFrame(rollID, frame)
      end
    end
  end
end

function GLD:OnCoverLogin()
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      self:ResumeCoverBlockers()
    end)
  else
    self:ResumeCoverBlockers()
  end
end

local COVER_COMM_PREFIX = NS.COVER_COMM_PREFIX or "GLD1COV"
local COVER_AUTH_PING = "AUTH_PING"
local COVER_AUTH_CLAIM = "AUTH_CLAIM"
local COVER_AUTH_SET = "AUTH_SET"
local COVER_OVR_SET = "OVR_SET"
local COVER_OVR_CLR = "OVR_CLR"
local COVER_HEARTBEAT_SECONDS = 2
local COVER_ELECTION_TIMEOUT = 8
local COVER_FALLBACK_TIMEOUT = 15

local function GetCoverEpochSeconds()
  if GetServerTime then
    return GetServerTime()
  end
  return time()
end

local function GetCoverNow()
  if GetTime then
    return GetTime()
  end
  return GetCoverEpochSeconds()
end

local function CompareCoverCandidates(a, b)
  if a.rankIndex ~= b.rankIndex then
    return a.rankIndex < b.rankIndex
  end
  if a.guid and b.guid and a.guid ~= b.guid then
    return a.guid < b.guid
  end
  local nameA = a.fullName or ""
  local nameB = b.fullName or ""
  return nameA < nameB
end

function GLD:IsHostEligible(unit)
  if not unit or not UnitExists(unit) then
    return false
  end
  local guildName, _, rankIndex = GetGuildInfo(unit)
  if not guildName or rankIndex == nil then
    return false
  end
  return rankIndex <= 2
end

function GLD:IsCoverAuthority()
  local guid = self.coverAuthorityGUID
  return guid and UnitGUID("player") == guid or false
end

function GLD:InitCoverAuthority()
  if self.coverAuthorityInitialized then
    return
  end
  self.coverAuthorityInitialized = true
  self.coverOverrides = self.coverOverrides or {}
  self.coverAppliedModes = self.coverAppliedModes or {}
  self.coverEpoch = self.coverEpoch or 0
  self.coverAuthorityGUID = self.coverAuthorityGUID or nil
  self.coverLastSeen = self.coverLastSeen or GetCoverNow()
  self.coverFallbackActive = false
  self.coverLastElectionAt = 0

  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COVER_COMM_PREFIX)
  end
  self:RegisterEvent("CHAT_MSG_ADDON", "OnCoverAddonMessage")
  if C_Timer and C_Timer.NewTicker and not self.coverAuthorityTicker then
    self.coverAuthorityTicker = C_Timer.NewTicker(COVER_HEARTBEAT_SECONDS, function()
      if self.OnCoverAuthorityTick then
        self:OnCoverAuthorityTick()
      end
    end)
  end
end

function GLD:OnCoverAuthorityTick()
  local now = GetCoverNow()
  if self:IsCoverAuthority() then
    self:SendCoverAuthPing()
    self.coverLastSeen = now
    return
  end

  local lastSeen = self.coverLastSeen or 0
  local since = now - lastSeen
  if since > COVER_FALLBACK_TIMEOUT then
    self:EnableCoverFallback()
  end
  if since > COVER_ELECTION_TIMEOUT and self:IsHostEligible("player") then
    self:RunCoverElection()
  end
end

function GLD:EnableCoverFallback()
  if self.coverFallbackActive then
    return
  end
  self.coverFallbackActive = true
  self:ApplyCoverStatesForAllActiveRolls()
end

function GLD:DisableCoverFallback()
  if not self.coverFallbackActive then
    return
  end
  self.coverFallbackActive = false
  self:ApplyCoverStatesForAllActiveRolls()
end

function GLD:NextCoverEpoch()
  local now = GetCoverEpochSeconds()
  local current = tonumber(self.coverEpoch) or 0
  if now <= current then
    now = current + 1
  end
  return now
end

function GLD:SendCoverMessage(parts)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
    return
  end
  if not IsInRaid() then
    return
  end
  local payload = table.concat(parts, " ")
  C_ChatInfo.SendAddonMessage(COVER_COMM_PREFIX, payload, "RAID")
end

function GLD:SendCoverAuthPing()
  if not self:IsCoverAuthority() then
    return
  end
  if not self:IsHostEligible("player") then
    return
  end
  local epoch = tonumber(self.coverEpoch) or self:NextCoverEpoch()
  self.coverEpoch = epoch
  local guid = self.coverAuthorityGUID or UnitGUID("player")
  if not guid then
    return
  end
  self:SendCoverMessage({ COVER_AUTH_PING, tostring(epoch), guid })
end

function GLD:RunCoverElection()
  if not IsInRaid() then
    return
  end
  local now = GetCoverNow()
  if self.coverLastElectionAt and now - self.coverLastElectionAt < COVER_ELECTION_TIMEOUT then
    return
  end
  self.coverLastElectionAt = now
  local best = self:GetBestCoverCandidate()
  if not best then
    return
  end
  local myGuid = UnitGUID("player")
  if myGuid and best.guid == myGuid then
    local epoch = self:NextCoverEpoch()
    self:SendCoverMessage({ COVER_AUTH_CLAIM, tostring(epoch), myGuid })
    self:SendCoverMessage({ COVER_AUTH_SET, tostring(epoch), myGuid })
    self:ApplyCoverAuthority(epoch, myGuid, "local")
  end
end

function GLD:GetBestCoverCandidate()
  if not IsInRaid() then
    return nil
  end
  local best = nil
  local count = GetNumGroupMembers()
  for i = 1, count do
    local unit = "raid" .. i
    if UnitExists(unit) and self:IsHostEligible(unit) then
      local _, _, rankIndex = GetGuildInfo(unit)
      local candidate = {
        unit = unit,
        guid = UnitGUID(unit),
        fullName = self:GetUnitFullName(unit) or UnitName(unit),
        rankIndex = rankIndex or 99,
      }
      if not best or CompareCoverCandidates(candidate, best) then
        best = candidate
      end
    end
  end
  return best
end

function GLD:ApplyCoverAuthority(epoch, authorityGUID, sender)
  local previousEpoch = tonumber(self.coverEpoch) or 0
  if epoch < previousEpoch then
    return
  end
  local previousAuthority = self.coverAuthorityGUID
  local changedEpoch = epoch ~= previousEpoch
  local changedAuthority = authorityGUID ~= previousAuthority
  local hadFallback = self.coverFallbackActive == true

  self.coverEpoch = epoch
  self.coverAuthorityGUID = authorityGUID
  self.coverLastSeen = GetCoverNow()

  if changedEpoch then
    self.coverOverrides = {}
    self.coverAppliedModes = {}
  end
  if authorityGUID and UnitGUID("player") == authorityGUID then
    if not self.coverIsAuthority then
      self.coverIsAuthority = true
      if self.OnBecameAuthority then
        self:OnBecameAuthority()
      end
    end
  else
    self.coverIsAuthority = false
  end
  if hadFallback then
    self.coverFallbackActive = false
  end

  if changedEpoch or changedAuthority or hadFallback then
    self:ApplyCoverStatesForAllActiveRolls()
  end
end

function GLD:OnBecameAuthority()
  self:Print("You are now host")
  if self.IsDebugEnabled and self:IsDebugEnabled() then
    self:Debug("You are now host")
  end
end

function GLD:GetCoverOverrideMode(rollID, playerGUID)
  if not rollID or not playerGUID then
    return nil
  end
  local rollOverrides = self.coverOverrides and self.coverOverrides[rollID] or nil
  return rollOverrides and rollOverrides[playerGUID] or nil
end

function GLD:GetCoverAutoMode()
  if self.coverFallbackActive then
    return "UNLOCK_ALL"
  end
  return "LOCK_ALL"
end

function GLD:ApplyCoverStateForRoll(rollID)
  if not rollID then
    return
  end
  local guid = UnitGUID("player")
  if not guid then
    return
  end
  local mode = self:GetCoverOverrideMode(rollID, guid) or self:GetCoverAutoMode()
  self.coverAppliedModes = self.coverAppliedModes or {}
  if self.coverAppliedModes[rollID] == mode then
    return
  end
  local rollFrame = RollBlockers.ApplyForRoll(rollID, mode)
  if not rollFrame then
    return
  end
  self.coverAppliedModes[rollID] = mode
end

function GLD:ApplyCoverStatesForAllActiveRolls()
  if not self._rollFrameByRollID then
    return
  end
  for rollID in pairs(self._rollFrameByRollID) do
    self:ApplyCoverStateForRoll(rollID)
  end
end

function GLD:SetCoverOverride(rollID, playerGUID, mode, broadcast)
  if not rollID or not playerGUID then
    return
  end
  self.coverOverrides = self.coverOverrides or {}
  local rollOverrides = self.coverOverrides[rollID]
  if not rollOverrides then
    rollOverrides = {}
    self.coverOverrides[rollID] = rollOverrides
  end
  if mode and mode ~= "" then
    rollOverrides[playerGUID] = mode
  else
    rollOverrides[playerGUID] = nil
  end
  if playerGUID == UnitGUID("player") then
    self:ApplyCoverStateForRoll(rollID)
  end
  if broadcast and self:IsCoverAuthority() then
    local epoch = tonumber(self.coverEpoch) or self:NextCoverEpoch()
    self.coverEpoch = epoch
    if mode and mode ~= "" then
      self:SendCoverMessage({ COVER_OVR_SET, tostring(epoch), tostring(rollID), playerGUID, mode })
    else
      self:SendCoverMessage({ COVER_OVR_CLR, tostring(epoch), tostring(rollID), playerGUID })
    end
  end
end

function GLD:ClearCoverOverridesForRoll(rollID)
  if not rollID then
    return
  end
  if self.coverOverrides then
    self.coverOverrides[rollID] = nil
  end
  if self.coverAppliedModes then
    self.coverAppliedModes[rollID] = nil
  end
  local rollFrame = self._rollFrameByRollID and self._rollFrameByRollID[rollID] or FindRollFrameByID(rollID)
  if rollFrame then
    RollBlockers.SetMode(rollFrame, "UNLOCK_ALL")
  end
end

function GLD:IsCoverSenderEligible(sender)
  if not sender or sender == "" then
    return false
  end
  if not self.GetUnitForSender then
    return false
  end
  local unit = self:GetUnitForSender(sender)
  if not unit then
    return false
  end
  return self:IsHostEligible(unit)
end

function GLD:OnCoverAddonMessage(_, prefix, message, _, sender)
  if prefix ~= COVER_COMM_PREFIX then
    return
  end
  if type(message) ~= "string" then
    return
  end
  local msgType, epochText, arg1, arg2, arg3 = strsplit(" ", message)
  local epoch = tonumber(epochText)
  if not msgType or not epoch then
    return
  end
  if msgType == COVER_AUTH_PING then
    self:HandleCoverAuthPing(sender, epoch, arg1)
  elseif msgType == COVER_AUTH_CLAIM then
    self:HandleCoverAuthClaim(sender, epoch, arg1)
  elseif msgType == COVER_AUTH_SET then
    self:HandleCoverAuthSet(sender, epoch, arg1)
  elseif msgType == COVER_OVR_SET then
    local rollID = tonumber(arg1)
    self:HandleCoverOverrideSet(sender, epoch, rollID, arg2, arg3)
  elseif msgType == COVER_OVR_CLR then
    local rollID = tonumber(arg1)
    self:HandleCoverOverrideClear(sender, epoch, rollID, arg2)
  end
end

function GLD:HandleCoverAuthPing(sender, epoch, authorityGUID)
  if not authorityGUID or authorityGUID == "" then
    return
  end
  if not self:IsCoverSenderEligible(sender) then
    return
  end
  local currentEpoch = tonumber(self.coverEpoch) or 0
  if epoch < currentEpoch then
    return
  end
  local senderGuid = self.GetGuidForSender and self:GetGuidForSender(sender) or nil
  if senderGuid and senderGuid ~= authorityGUID then
    return
  end
  if not self.coverAuthorityGUID or epoch > currentEpoch then
    self:ApplyCoverAuthority(epoch, authorityGUID, sender)
  end
  if self.coverAuthorityGUID == authorityGUID and epoch == (tonumber(self.coverEpoch) or 0) then
    self.coverLastSeen = GetCoverNow()
    if self.coverFallbackActive then
      self:DisableCoverFallback()
    end
  end
end

function GLD:HandleCoverAuthClaim(sender, epoch, candidateGUID)
  if not candidateGUID or candidateGUID == "" then
    return
  end
  if not self:IsCoverSenderEligible(sender) then
    return
  end
  local currentEpoch = tonumber(self.coverEpoch) or 0
  if epoch < currentEpoch then
    return
  end
  self.coverLastClaimAt = GetCoverNow()
  self.coverLastClaimGuid = candidateGUID
end

function GLD:HandleCoverAuthSet(sender, epoch, authorityGUID)
  if not authorityGUID or authorityGUID == "" then
    return
  end
  if not self:IsCoverSenderEligible(sender) then
    return
  end
  local currentEpoch = tonumber(self.coverEpoch) or 0
  if epoch < currentEpoch then
    return
  end
  local senderGuid = self.GetGuidForSender and self:GetGuidForSender(sender) or nil
  if senderGuid and senderGuid ~= authorityGUID then
    return
  end
  self:ApplyCoverAuthority(epoch, authorityGUID, sender)
end

function GLD:HandleCoverOverrideSet(sender, epoch, rollID, playerGUID, mode)
  if not rollID or not playerGUID or not mode or mode == "" then
    return
  end
  if not self:IsCoverSenderEligible(sender) then
    return
  end
  local currentEpoch = tonumber(self.coverEpoch) or 0
  if epoch < currentEpoch then
    return
  end
  local senderGuid = self.GetGuidForSender and self:GetGuidForSender(sender) or nil
  if not self.coverAuthorityGUID and senderGuid then
    self:ApplyCoverAuthority(epoch, senderGuid, sender)
  end
  if senderGuid and self.coverAuthorityGUID and senderGuid ~= self.coverAuthorityGUID then
    return
  end
  if epoch ~= (tonumber(self.coverEpoch) or 0) then
    return
  end
  self:SetCoverOverride(rollID, playerGUID, mode, false)
end

function GLD:HandleCoverOverrideClear(sender, epoch, rollID, playerGUID)
  if not rollID or not playerGUID then
    return
  end
  if not self:IsCoverSenderEligible(sender) then
    return
  end
  local currentEpoch = tonumber(self.coverEpoch) or 0
  if epoch < currentEpoch then
    return
  end
  local senderGuid = self.GetGuidForSender and self:GetGuidForSender(sender) or nil
  if not self.coverAuthorityGUID and senderGuid then
    self:ApplyCoverAuthority(epoch, senderGuid, sender)
  end
  if senderGuid and self.coverAuthorityGUID and senderGuid ~= self.coverAuthorityGUID then
    return
  end
  if epoch ~= (tonumber(self.coverEpoch) or 0) then
    return
  end
  self:SetCoverOverride(rollID, playerGUID, nil, false)
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
  local restrictionSnapshot = nil
  if session.restrictionSnapshot then
    restrictionSnapshot = {}
    for k, v in pairs(session.restrictionSnapshot) do
      restrictionSnapshot[k] = v
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
    blizzNeedAllowed = session.blizzNeedAllowed,
    blizzGreedAllowed = session.blizzGreedAllowed,
    blizzTransmogAllowed = session.blizzTransmogAllowed,
    expectedVoters = expected,
    expectedVoterClasses = expectedClasses,
    createdAt = session.createdAt,
    votes = votes,
    restrictionSnapshot = restrictionSnapshot,
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
    self:BroadcastRollSession(session, { snapshot = true, reopen = true })
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
      self:BroadcastRollSession(session, { snapshot = true, reopen = snapshotOptions.reopen })
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
    self:BroadcastActiveRollsSnapshot(nil, { reopen = true })
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

local TRINKET_ROLE_LABELS = {
  TANK = "Tanks",
  HEALER = "Healers",
  MELEEDPS = "Melee DPS",
  RANGEDPS = "Ranged DPS",
  DPS = "DPS",
}

local TRINKET_ROLE_ORDER = { "TANK", "HEALER", "MELEEDPS", "RANGEDPS", "DPS" }

local function FormatTrinketRoleList(roles)
  if type(roles) ~= "table" then
    return nil
  end
  local list = {}
  for _, key in ipairs(TRINKET_ROLE_ORDER) do
    if roles[key] then
      list[#list + 1] = TRINKET_ROLE_LABELS[key] or key
    end
  end
  if #list == 0 then
    return nil
  end
  return table.concat(list, ", ")
end

local function GetPlayerInfoForVote(self, session, playerKey)
  if not playerKey or not self then
    return nil, nil, nil, nil
  end
  local provider = session and session.isTest and TestProvider or LiveProvider
  local player = provider and provider.GetPlayer and provider:GetPlayer(playerKey) or nil
  local classFile = player and (player.classFile or player.classFileName or player.classToken or player.class) or nil
  local specName = player and (player.specName or player.spec) or nil
  if not classFile and session and session.expectedVoterClasses then
    classFile = session.expectedVoterClasses[playerKey]
  end
  local localKey = NS:GetPlayerKeyFromUnit("player")
  if localKey and playerKey == localKey and (not classFile or classFile == "" or not specName or specName == "") then
    if (not classFile or classFile == "") and UnitClass then
      classFile = select(2, UnitClass("player")) or classFile
    end
    if not specName or specName == "" then
      local specIndex = GetSpecialization and GetSpecialization()
      if specIndex then
        local specId = GetSpecializationInfo and GetSpecializationInfo(specIndex)
        if specId and GetSpecializationInfoByID then
          local _, name = GetSpecializationInfoByID(specId)
          specName = name or specName
        end
      end
    end
    local record = self.db and self.db.players and self.db.players[localKey] or nil
    if record then
      if classFile and not (record.classFile or record.classFileName or record.classToken or record.class) then
        record.classFile = classFile
      end
      if specName and not (record.specName or record.spec) then
        record.specName = specName
      end
    end
  end
  return classFile, specName, player, provider
end

function GLD:BuildRollRestrictionSnapshot(session)
  if not session then
    return nil
  end
  local itemId = session.itemID
  if not itemId and session.itemLink and C_Item and C_Item.GetItemInfoInstant then
    itemId = select(1, C_Item.GetItemInfoInstant(session.itemLink))
  end
  local roles = itemId and self.GetTrinketRoleRestriction and self:GetTrinketRoleRestriction(itemId) or nil
  if roles then
    return {
      trinketRoles = roles,
      itemId = itemId,
    }
  end
  return nil
end

function GLD:GetEligibilityReasonText(reason, session)
  if not reason or reason == "" then
    return nil
  end
  if reason == "need_disabled" then
    return "Not allowed for this roll."
  end
  if reason == "greed_disabled" then
    return "Not allowed for this roll."
  end
  if reason == "transmog_disabled" then
    return "Not allowed for this roll."
  end
  if reason == "ineligible_trinket_role" then
    local roles = session and session.restrictionSnapshot and session.restrictionSnapshot.trinketRoles or nil
    local roleText = FormatTrinketRoleList(roles)
    if roleText then
      return "Trinket reserved for " .. roleText .. "."
    end
    return "Trinket role restriction."
  end
  if reason == "ineligible_tier" then
    return "Tier token not for your class."
  end
  if reason == "ineligible_class_restriction" then
    return "Class restricted item."
  end
  if reason == "ineligible_armor" then
    return "Cannot equip this armor type."
  end
  if reason == "ineligible_weapon" then
    return "Cannot equip this weapon type."
  end
  if reason == "ineligible_shield" then
    return "Cannot equip a shield."
  end
  if reason == "ineligible_item_type" then
    return "Cannot use this item type."
  end
  if reason == "item_data_missing" then
    return "Item data still loading."
  end
  if reason == "eligibility_pending" then
    return "Determining eligibility..."
  end
  return "Ineligible for this vote."
end

function GLD:GetEligibilityForVote(session, playerKey, voteType, opts)
  if not session or not voteType then
    return true, nil, nil
  end
  if voteType == "PASS" then
    return true, nil, nil
  end

  local requireData = opts and opts.requireData == true

  if voteType ~= "NEED" then
    if opts and opts.log and self.Debug then
      local _, _, player, provider = GetPlayerInfoForVote(self, session, playerKey)
      local name = provider and provider.GetPlayerName and provider:GetPlayerName(playerKey) or (player and player.name) or playerKey or "Unknown"
      self:Debug(
        "Eligibility result: rollID="
          .. tostring(session.rollID)
          .. " vote="
          .. tostring(voteType)
          .. " player="
          .. tostring(name)
          .. " eligible=true"
      )
    end
    return true, nil, nil
  end

  local itemRef = session.itemLink or session.itemID or session.itemName
  if not itemRef then
    if requireData then
      return false, "eligibility_pending", "GREED"
    end
    return true, nil, nil
  end

  local classFile, specName, player, provider = GetPlayerInfoForVote(self, session, playerKey)
  if not classFile or classFile == "" then
    if opts and opts.log and self.Debug then
      local name = provider and provider.GetPlayerName and provider:GetPlayerName(playerKey) or playerKey or "Unknown"
      self:Debug("Eligibility skipped: missing class for " .. tostring(name))
    end
    if requireData then
      return false, "eligibility_pending", "GREED"
    end
    return true, nil, nil
  end
  classFile = tostring(classFile):upper()

  local context = nil
  if session.restrictionSnapshot and session.restrictionSnapshot.trinketRoles then
    context = { trinketRoles = session.restrictionSnapshot.trinketRoles }
  end
  if requireData and (not specName or specName == "") then
    local isTrinket = context and context.trinketRoles
    if not isTrinket and self.IsItemInfoTrinket then
      isTrinket = self:IsItemInfoTrinket(itemRef)
    end
    if not isTrinket and self.IsKnownTrinket then
      isTrinket = self:IsKnownTrinket(itemRef)
    end
    if isTrinket then
      return false, "eligibility_pending", "GREED"
    end
  end

  local ok, reason = self:IsEligibleForNeed(classFile, itemRef, specName, context)
  if not ok and reason == "item_data_missing" then
    if opts and opts.log and self.Debug then
      self:Debug("Eligibility skipped: item data missing for rollID=" .. tostring(session.rollID))
    end
    if requireData then
      return false, "eligibility_pending", "GREED"
    end
    return true, nil, nil
  end

  if opts and opts.log and self.Debug then
    local name = provider and provider.GetPlayerName and provider:GetPlayerName(playerKey) or playerKey or "Unknown"
    local roleKey = nil
    local isTrinket = session.restrictionSnapshot and session.restrictionSnapshot.trinketRoles or nil
    if not isTrinket and self.IsItemInfoTrinket then
      isTrinket = self:IsItemInfoTrinket(itemRef)
    end
    if self.GetTrinketRoleKey and isTrinket then
      roleKey = self:GetTrinketRoleKey(classFile, specName)
    end
    if roleKey then
      self:Debug("Eligibility role: " .. tostring(name) .. " -> " .. tostring(roleKey))
    end
    self:Debug(
      "Eligibility result: rollID="
        .. tostring(session.rollID)
        .. " vote="
        .. tostring(voteType)
        .. " player="
        .. tostring(name)
        .. " eligible="
        .. tostring(ok)
        .. (reason and (" reason=" .. tostring(reason)) or "")
    )
  end

  return ok, reason, "GREED"
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

local function IsBlizzFlagKnown(flag)
  return flag == true or flag == false
end

local function HighlightRoll(roll)
  if roll == nil then
    return nil
  end
  return "|cffffd200" .. tostring(roll) .. "|r"
end

function GLD:BuildResultVoteEntries(result, voteType)
  local entries = {}
  if not result or not voteType or not result.votes then
    return entries
  end
  local details = result.voteDetails or {}
  for name, vote in pairs(result.votes) do
    if vote == voteType then
      local detail = details[name]
      entries[#entries + 1] = {
        name = name,
        roll = detail and detail.roll or nil,
        voteOriginal = detail and detail.voteOriginal or nil,
        voteEffective = detail and detail.voteEffective or nil,
        reason = detail and detail.reason or nil,
        reasonText = detail and detail.reasonText or nil,
      }
    end
  end
  table.sort(entries, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)
  return entries
end

function GLD:GetWinnerRoll(result)
  if not result then
    return nil
  end
  if result.winningRoll ~= nil then
    return result.winningRoll
  end
  local details = result.voteDetails or {}
  local winner = result.winnerName
  local entry = winner and details[winner] or nil
  return entry and entry.roll or nil
end

function GLD:ResolveInstructionOverride(result)
  if not result or result.winnerVote ~= "GREED" then
    return nil, nil, nil
  end
  if not IsBlizzFlagKnown(result.blizzNeedAllowed) or not IsBlizzFlagKnown(result.blizzGreedAllowed) then
    return nil, nil, nil
  end
  if result.blizzNeedAllowed == false and result.blizzGreedAllowed == false and result.blizzTransmogAllowed == true then
    return "ROLL_TRANSMOG_REASON_BLIZZARD_GREED_DISABLED", "TRANSMOG", "Blizzard doesn't allow Greed here; please roll TRANSMOG."
  end
  return nil, nil, nil
end

function GLD:BuildRollResultSummaryLine(result)
  if not result then
    return nil
  end
  local winnerName = result.winnerName or "None"
  local winnerVote = result.winnerVote
  if winnerVote == "GREED" or winnerVote == "TRANSMOG" then
    local entries = self:BuildResultVoteEntries(result, winnerVote)
    local parts = {}
    for _, entry in ipairs(entries) do
      local label = entry.name or "?"
      if entry.roll ~= nil then
        label = label .. " " .. tostring(entry.roll)
      end
      parts[#parts + 1] = label
    end
    local listText = #parts > 0 and table.concat(parts, ", ") or "none"
    local winnerRoll = self:GetWinnerRoll(result)
    local winnerSuffix = winnerRoll ~= nil and (" (" .. HighlightRoll(winnerRoll) .. ")") or ""
    return tostring(winnerVote) .. " rolls: " .. listText .. " -> Winner: " .. tostring(winnerName) .. winnerSuffix
  end
  if winnerVote == "NEED" then
    local entries = self:BuildResultVoteEntries(result, "NEED")
    local parts = {}
    for _, entry in ipairs(entries) do
      parts[#parts + 1] = entry.name or "?"
    end
    local listText = #parts > 0 and table.concat(parts, ", ") or "none"
    return "NEED eligible: " .. listText .. " -> Winner: " .. tostring(winnerName) .. " (queue priority)"
  end
  return "Winner: " .. tostring(winnerName)
end

function GLD:BuildRollResultInstructionLine(result)
  if not result or not result.instructionText then
    return nil
  end
  local winnerName = result.winnerName or "None"
  local voteText = result.winnerVote or "ROLL"
  return "Winner via " .. tostring(voteText) .. ": " .. tostring(winnerName) .. " - " .. tostring(result.instructionText)
end

function GLD:BuildRollResultLines(result)
  local lines = {}
  local summary = self:BuildRollResultSummaryLine(result)
  if summary then
    lines[#lines + 1] = summary
  end
  local instruction = self:BuildRollResultInstructionLine(result)
  if instruction then
    lines[#lines + 1] = instruction
  end
  return lines
end

function GLD:AnnounceRollResult(result)
  if not result then
    return
  end
  if not IsInRaid() then
    return
  end
  local channel = "RAID"
  local itemText = result.itemLink or result.itemName or "Item"
  local lines = self:BuildRollResultLines(result)
  local detail = #lines > 0 and table.concat(lines, " | ") or ("Winner: " .. tostring(result.winnerName or "None"))
  local msg = "GLD Result: " .. tostring(itemText) .. " - " .. detail
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

function GLD:LogItemWonAudit(session, winnerKey, winnerVote, provider)
  if not self.LogAuditEvent or not session or session.isTest then
    return
  end
  local targetName = "Unclaimed"
  local isGuest = false
  local classFile = nil
  local specName = nil
  if winnerKey and provider then
    local player = provider.GetPlayer and provider:GetPlayer(winnerKey) or nil
    if player then
      targetName = player.name or targetName
      if self.IsGuestEntry then
        isGuest = self:IsGuestEntry(player)
      end
      classFile = player.classFile or player.classFileName or player.class
      specName = player.specName or player.spec
    else
      local name = provider.GetPlayerName and provider:GetPlayerName(winnerKey) or winnerKey
      if name then
        targetName = name
      end
    end
  end
  local details = {
    itemID = session.itemID,
    itemName = session.itemName,
    voteType = winnerVote,
  }
  if not details.itemID and session.itemLink then
    if C_Item and C_Item.GetItemInfoInstant then
      details.itemID = select(1, C_Item.GetItemInfoInstant(session.itemLink))
    elseif GetItemInfoInstant then
      details.itemID = select(1, GetItemInfoInstant(session.itemLink))
    end
  end
  if not details.itemName and session.itemLink then
    details.itemName = session.itemLink
  end
  local baseName = targetName
  if type(baseName) == "string" and not baseName:match("^Player%-") then
    baseName = NS and NS.GetPlayerBaseName and NS:GetPlayerBaseName(baseName) or baseName
  end
  self:LogAuditEvent("ITEM_WON", {
    target = baseName,
    isGuest = isGuest,
    class = classFile,
    spec = specName,
    details = details,
  })
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

local function SnapshotVoteDetails(details, provider)
  if not details then
    return nil
  end
  local snapshot = {}
  for key, entry in pairs(details or {}) do
    local displayKey = NormalizeVoteKey(provider, key)
    snapshot[displayKey] = {
      voteOriginal = entry.voteOriginal,
      voteEffective = entry.voteEffective,
      reason = entry.reason,
      reasonText = entry.reasonText,
      roll = entry.roll,
      blizzVote = entry.blizzVote,
    }
  end
  return snapshot
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

function GLD:CaptureBlizzardRollData(session)
  if not session or not session.itemLink then
    return nil
  end
  if not C_LootHistory or not C_LootHistory.GetItem or not C_LootHistory.GetPlayerInfo then
    return nil
  end
  local numItems = C_LootHistory.GetNumItems and C_LootHistory.GetNumItems() or 0
  if numItems <= 0 then
    return nil
  end
  local rollMap = nil
  for itemIndex = 1, numItems do
    local _, itemLink, _, _, numPlayers = C_LootHistory.GetItem(itemIndex)
    if itemLink and itemLink == session.itemLink and numPlayers and numPlayers > 0 then
      for playerIndex = 1, numPlayers do
        local name, _, rollType, roll = C_LootHistory.GetPlayerInfo(itemIndex, playerIndex)
        local key = name and self.GetRollCandidateKey and self:GetRollCandidateKey(name) or nil
        if key and session.votes and session.votes[key] then
          rollMap = rollMap or {}
          rollMap[key] = roll
          session.voteDetails = session.voteDetails or {}
          local detail = session.voteDetails[key] or {
            voteOriginal = session.votes[key],
            voteEffective = session.votes[key],
          }
          detail.roll = roll
          if rollType and RollTypeToVote then
            detail.blizzVote = RollTypeToVote(rollType)
          end
          session.voteDetails[key] = detail
        end
      end
      break
    end
  end
  return rollMap
end

function GLD:FinalizeRoll(session)
  if not session or session.locked then
    return
  end
  if not session.isTest and not self:IsAuthority() then
    return
  end
  local rollMap = self:CaptureBlizzardRollData(session)
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
  if not winnerKey then
    winnerName = "Unclaimed"
    winnerFull = "Unclaimed"
  end
  local winnerVote = session.votes and winnerKey and session.votes[winnerKey] or nil
  local winnerRoll = rollMap and winnerKey and rollMap[winnerKey] or nil
  if winnerRoll == nil and winnerKey and session.voteDetails and session.voteDetails[winnerKey] then
    winnerRoll = session.voteDetails[winnerKey].roll
  end
  local winnerShortName = winnerName
  if winnerFull and winnerFull ~= "" and NS and NS.SplitNameRealm then
    local short = select(1, NS:SplitNameRealm(winnerFull))
    if short and short ~= "" then
      winnerShortName = short
    end
  end
  if not winnerKey then
    winnerShortName = "Unclaimed"
  end
  local winnerClassToken = winnerPlayer
    and (winnerPlayer.classToken or winnerPlayer.classFile or winnerPlayer.classFileName or winnerPlayer.class)
    or nil
  if winnerClassToken then
    winnerClassToken = tostring(winnerClassToken):upper()
  end
  local winnerIsGuest = winnerPlayer and self.IsGuestEntry and self:IsGuestEntry(winnerPlayer) or false
  local winnerIsGuest = winnerPlayer and self.IsGuestEntry and self:IsGuestEntry(winnerPlayer) or false

  local resolvedAt = GetServerTime()
  local voteSnapshot, voteCounts = SnapshotVotes(session.votes, provider)
  local voteDetails = SnapshotVoteDetails(session.voteDetails, provider)
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
    winnerShortName = winnerShortName,
    winnerClassToken = winnerClassToken,
    winnerIsGuest = winnerIsGuest,
    votes = voteSnapshot,
    voteCounts = voteCounts,
    voteDetails = voteDetails,
    missingAtLock = missingAtLock,
    startedAt = startedAt,
    resolvedAt = resolvedAt,
    resolvedBy = resolvedBy,
    winnerVote = winnerVote,
    winningRoll = winnerRoll,
    blizzNeedAllowed = session.blizzNeedAllowed,
    blizzGreedAllowed = session.blizzGreedAllowed,
    blizzTransmogAllowed = session.blizzTransmogAllowed,
  }

  self:LogItemWonAudit(session, winnerKey, winnerVote, provider)

  local overrideId, instructionVote, instructionText = self:ResolveInstructionOverride(result)
  if overrideId then
    result.instructionOverride = overrideId
    result.instructionVote = instructionVote
    result.instructionText = instructionText
  end

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
  local rollMap = self:CaptureBlizzardRollData(session)
  local winnerRoll = rollMap and winnerKey and rollMap[winnerKey] or nil
  if winnerRoll == nil and winnerKey and session.voteDetails and session.voteDetails[winnerKey] then
    winnerRoll = session.voteDetails[winnerKey].roll
  end
  local winnerShortName = winnerName
  if winnerFull and winnerFull ~= "" and NS and NS.SplitNameRealm then
    local short = select(1, NS:SplitNameRealm(winnerFull))
    if short and short ~= "" then
      winnerShortName = short
    end
  end
  if isPass then
    winnerShortName = "Unclaimed"
  end
  local winnerClassToken = winnerPlayer
    and (winnerPlayer.classToken or winnerPlayer.classFile or winnerPlayer.classFileName or winnerPlayer.class)
    or nil
  if winnerClassToken then
    winnerClassToken = tostring(winnerClassToken):upper()
  end

  if winnerKey and LootEngine and LootEngine.CommitAward then
    LootEngine:CommitAward(winnerKey, session, provider)
  end

  local resolvedAt = GetServerTime()
  local voteSnapshot, voteCounts = SnapshotVotes(session.votes, provider)
  local voteDetails = SnapshotVoteDetails(session.voteDetails, provider)
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
    winnerShortName = winnerShortName,
    winnerClassToken = winnerClassToken,
    winnerIsGuest = winnerIsGuest,
    votes = voteSnapshot,
    voteCounts = voteCounts,
    voteDetails = voteDetails,
    missingAtLock = missingAtLock,
    startedAt = startedAt,
    resolvedAt = resolvedAt,
    resolvedBy = "OVERRIDE",
    overrideBy = overrideBy,
    authorityGUID = authorityGUID,
    authorityName = authorityName,
    winnerVote = winnerVote,
    winningRoll = winnerRoll,
    blizzNeedAllowed = session.blizzNeedAllowed,
    blizzGreedAllowed = session.blizzGreedAllowed,
    blizzTransmogAllowed = session.blizzTransmogAllowed,
  }

  self:LogItemWonAudit(session, winnerKey, winnerVote, provider)

  local overrideId, instructionVote, instructionText = self:ResolveInstructionOverride(result)
  if overrideId then
    result.instructionOverride = overrideId
    result.instructionVote = instructionVote
    result.instructionText = instructionText
  end

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
    winnerIsGuest = result.winnerIsGuest,
    votes = result.votes,
    voteCounts = result.voteCounts,
    voteDetails = result.voteDetails,
    missingAtLock = result.missingAtLock,
    startedAt = result.startedAt,
    resolvedAt = result.resolvedAt or GetServerTime(),
    resolvedBy = result.resolvedBy or "NORMAL",
    overrideBy = result.overrideBy,
    winnerVote = result.winnerVote,
    winningRoll = result.winningRoll,
    instructionOverride = result.instructionOverride,
    instructionVote = result.instructionVote,
    instructionText = result.instructionText,
    blizzNeedAllowed = result.blizzNeedAllowed,
    blizzGreedAllowed = result.blizzGreedAllowed,
    blizzTransmogAllowed = result.blizzTransmogAllowed,
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
    winnerIsGuest = result.winnerIsGuest,
    votes = result.votes,
    voteCounts = result.voteCounts,
    voteDetails = result.voteDetails,
    missingAtLock = result.missingAtLock,
    startedAt = result.startedAt,
    resolvedAt = result.resolvedAt or GetServerTime(),
    resolvedBy = result.resolvedBy or "NORMAL",
    overrideBy = result.overrideBy,
    winnerVote = result.winnerVote,
    winningRoll = result.winningRoll,
    instructionOverride = result.instructionOverride,
    instructionVote = result.instructionVote,
    instructionText = result.instructionText,
    blizzNeedAllowed = result.blizzNeedAllowed,
    blizzGreedAllowed = result.blizzGreedAllowed,
    blizzTransmogAllowed = result.blizzTransmogAllowed,
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
  if self.LockLootRollButtons then
    self:LockLootRollButtons(rollID)
  end
  if self.ApplyCoverStateForRoll then
    self:ApplyCoverStateForRoll(rollID)
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
    blizzNeedAllowed = canNeed,
    blizzGreedAllowed = canGreed,
    blizzTransmogAllowed = canTransmog,
    votes = {},
    expectedVoters = self:BuildExpectedVoters(),
    createdAt = createdAt,
  }
  session.restrictionSnapshot = self:BuildRollRestrictionSnapshot(session)
  self.activeRolls[rollKey] = session

  if self:IsDebugEnabled() then
    local snapshot = session.restrictionSnapshot
    local roleText = snapshot and FormatTrinketRoleList(snapshot.trinketRoles) or "none"
    self:Debug(
      "Roll restriction snapshot: rollID="
        .. tostring(session.rollID)
        .. " item="
        .. tostring(session.itemLink or session.itemName or "Unknown")
        .. " trinketRoles="
        .. tostring(roleText)
    )
  end

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

function GLD:OnCancelLootRoll(event, rollID)
  if type(rollID) ~= "number" then
    return
  end
  if self.ClearCoverOverridesForRoll then
    self:ClearCoverOverridesForRoll(rollID)
  end
  if self.UnlockLootRollButtons then
    self:UnlockLootRollButtons(rollID)
  end
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
            local name, class, rollType, roll = C_LootHistory.GetPlayerInfo(itemIndex, playerIndex)
            local declaredKey = self:GetRollCandidateKey(name)
            local declaredVote = declaredKey and session.votes[declaredKey] or nil
            local actualVote = RollTypeToVote(rollType)
            if declaredKey and declaredVote and roll ~= nil then
              session.voteDetails = session.voteDetails or {}
              local detail = session.voteDetails[declaredKey] or {
                voteOriginal = declaredVote,
                voteEffective = declaredVote,
              }
              detail.roll = roll
              if rollType then
                detail.blizzVote = RollTypeToVote(rollType)
              end
              session.voteDetails[declaredKey] = detail
            end
            if declaredVote and actualVote and declaredVote ~= actualVote then
              self:NoteMismatch(session, name, declaredVote, actualVote)
            end
          end
        end
      end
    end
  end
end

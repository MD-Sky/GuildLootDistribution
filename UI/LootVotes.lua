local _, NS = ...
local GLD = NS.GLD
local UI = NS.UI
local LiveProvider = NS.LiveProvider
local TestProvider = NS.TestProvider

local WINDOW_WIDTH = 440
local WINDOW_HEIGHT = 480
local ACTIVE_PANEL_HEIGHT = 170
local PADDING = 10
local PENDING_ROW_HEIGHT = 56
local ROW_SPACING = 4
local MAX_MISSING_DISPLAY = 5
local TOOLTIP_CURSOR_OFFSET = 20
local PENDING_BORDER_ACTIVE = { 1, 0.82, 0, 1 }
local PENDING_BORDER_DEFAULT = { 0.3, 0.3, 0.3, 0.9 }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function FormatVoteLabel(vote)
  if not vote or vote == "" then
    return "None"
  end
  local label = tostring(vote)
  return label:sub(1, 1) .. label:sub(2):lower()
end

local function GetDisplayedItemText(session)
  if not session then
    return "Unknown Item"
  end
  local link = session.itemLink
  if link and link ~= "" then
    local name = select(1, GetItemInfo(link))
    if name and name ~= "" then
      return name
    end
  end
  if session.itemName and session.itemName ~= "" then
    return session.itemName
  end
  if link and link ~= "" then
    return link
  end
  return "Unknown Item"
end

local function GetVoteProvider(session)
  if session and session.isTest then
    return TestProvider or LiveProvider
  end
  return LiveProvider
end

local function GetVoterDisplayName(provider, key)
  if not key then
    return nil
  end
  if provider and provider.GetPlayerName then
    local name = provider:GetPlayerName(key)
    if name and name ~= "" then
      return name
    end
  end
  return key
end

local function GetClassColorCode(classToken)
  if not classToken then
    return nil
  end
  local color = nil
  if C_ClassColor and C_ClassColor.GetClassColor then
    color = C_ClassColor.GetClassColor(classToken)
  elseif RAID_CLASS_COLORS then
    color = RAID_CLASS_COLORS[classToken]
  end
  if color and color.r then
    local r = math.floor((color.r or 1) * 255)
    local g = math.floor((color.g or 1) * 255)
    local b = math.floor((color.b or 1) * 255)
    return string.format("|cff%02x%02x%02x", r, g, b)
  end
  return nil
end

local function GetColoredVoterName(provider, key, classHint)
  if not key then
    return nil
  end
  local displayName = GetVoterDisplayName(provider, key) or key
  local player = provider and provider.GetPlayer and provider:GetPlayer(key)
  local classToken = player and (player.class or player.classToken)
  if not classToken and classHint then
    classToken = classHint[key]
  end
  local colorCode = GetClassColorCode(classToken)
  if colorCode then
    return colorCode .. displayName .. "|r"
  end
  return displayName
end

local function FormatMissingDisplayText(missingNames)
  if not missingNames or #missingNames == 0 then
    return ""
  end
  local chunk = math.min(MAX_MISSING_DISPLAY, #missingNames)
  local displayed = {}
  for i = 1, chunk do
    displayed[#displayed + 1] = missingNames[i]
  end
  local text = table.concat(displayed, ", ")
  if #missingNames > MAX_MISSING_DISPLAY then
    text = text .. " +" .. (#missingNames - MAX_MISSING_DISPLAY) .. " more"
  end
  return text
end

local function AdjustPendingRowHeight(row)
  if not row then
    return
  end
  local minHeight = PENDING_ROW_HEIGHT
  local textHeight = row.statusText:GetStringHeight() or 0
  local padding = 30
  local newHeight = math.max(minHeight, textHeight + padding)
  row:SetHeight(newHeight)
end

local function DebugPendingRow(session, hasLocalVoted, missingNames, displayText)
  if not GLD:IsDebugEnabled() then
    return
  end
  local key = session and (session.rollKey or session.rollID or session.key or session.itemLink or session.itemName) or "unknown"
  local missingSummary = ""
  if missingNames and #missingNames > 0 then
    missingSummary = table.concat(missingNames, ", ")
  else
    missingSummary = "none"
  end
  GLD:Debug(
    string.format(
      "Pending row [%s]: localVoted=%s missing=%s text=%s",
      tostring(key),
      tostring(hasLocalVoted),
      missingSummary,
      tostring(displayText)
    )
  )
end

local function GetLootWindowState(self)
  self.lootVoteState = self.lootVoteState or {
    currentVoteItems = {},
    indexByKey = {},
    activeKey = nil,
    activeIndex = nil,
    demoMode = false,
    demoItems = {},
    demoVotes = {},
  }
  return self.lootVoteState
end

local function GetActiveVoteSessions()
  local sessions = {}
  if not GLD.activeRolls then
    return sessions
  end
  for _, session in pairs(GLD.activeRolls) do
    if session and not session.locked then
      sessions[#sessions + 1] = session
    end
  end
  table.sort(sessions, function(a, b)
    return (a.createdAt or 0) < (b.createdAt or 0)
  end)
  return sessions
end

local function GetSessionByKey(itemKey)
  if not itemKey or not GLD.activeRolls then
    return nil
  end
  for _, session in pairs(GLD.activeRolls) do
    if session then
      local key = session.rollKey or session.rollID or session.key or session.itemLink or session.itemName
      if key == itemKey then
        return session
      end
    end
  end
  return nil
end

local function BuildVoteEntries(self, sessions)
  local state = GetLootWindowState(self)
  state.currentVoteItems = {}
  state.indexByKey = {}
  local myKey = NS:GetPlayerKeyFromUnit("player")
  for idx, session in ipairs(sessions or {}) do
    local key = session.rollKey
      or session.rollID
      or session.key
      or session.itemLink
      or (session.itemName and session.itemName .. "_" .. idx)
      or ("pending_" .. idx)
    local vote = nil
    if state.demoMode then
      vote = state.demoVotes and state.demoVotes[key]
    else
      vote = myKey and session.votes and session.votes[myKey] or nil
    end
    state.currentVoteItems[idx] = {
      key = key,
      session = session,
      vote = vote,
    }
    state.indexByKey[key] = idx
  end
end


local function BuildSessionVoteSnapshot(session, state, entryKey)
  local votes = {}
  if session and session.votes then
    for k, v in pairs(session.votes) do
      votes[k] = v
    end
  end
  if state and state.demoMode and state.demoVotes and entryKey then
    local localKey = NS:GetPlayerKeyFromUnit("player")
    if localKey and state.demoVotes[entryKey] then
      votes[localKey] = state.demoVotes[entryKey]
    end
  end
  return votes
end

local function HasLocalPlayerVotedSession(session, votes)
  if not session then
    return false
  end
  local localKey = NS:GetPlayerKeyFromUnit("player")
  if not localKey then
    return false
  end
  votes = votes or session.votes or {}
  return votes[localKey] ~= nil
end

local function HasUnvotedEntries(state, entries)
  if state and state.demoMode then
    return false
  end
  for _, entry in ipairs(entries or {}) do
    if entry and not entry.vote then
      return true
    end
  end
  return false
end

local function HasBlockingVotes(self)
  local state = GetLootWindowState(self)
  if state and state.demoMode then
    return false
  end
  local localKey = NS:GetPlayerKeyFromUnit("player")
  if not localKey then
    return false
  end
  local sessions = GetActiveVoteSessions()
  for _, session in ipairs(sessions) do
    if session and not session.locked then
      local votes = session.votes or {}
      if votes[localKey] == nil then
        return true
      end
    end
  end
  return false
end

local function GetMissingVotersForSession(session, votes)
  local missing = {}
  if not session then
    return missing
  end
  votes = votes or session.votes or {}
  local expected = session.expectedVoters or {}
  local classHint = session.expectedVoterClasses
  local provider = GetVoteProvider(session)
  for _, key in ipairs(expected) do
    if key and not votes[key] then
      missing[#missing + 1] = GetColoredVoterName(provider, key, classHint) or key
    end
  end
  return missing
end

local function BuildAdminOverrideCandidates(session)
  local keys = {}
  local labels = {}
  if not session then
    return keys, labels
  end

  local provider = GetVoteProvider(session)
  local expected = session.expectedVoters or {}
  local classHint = session.expectedVoterClasses
  local itemRef = session.itemLink or session.itemID or session.itemName
  local canFilter = itemRef and GLD and GLD.IsEligibleForNeed
  local itemReady = true
  if canFilter and C_Item and C_Item.GetItemInfoInstant then
    local classID = C_Item.GetItemInfoInstant(itemRef)
    if not classID then
      itemReady = false
      if GLD.RequestItemData then
        GLD:RequestItemData(itemRef)
      end
    end
  end

  local function isEligible(key)
    if not canFilter or not itemReady then
      return true
    end
    local classFile = nil
    local specName = nil
    if provider and provider.GetPlayer then
      local player = provider:GetPlayer(key)
      if player then
        classFile = player.class or player.classToken
        specName = player.specName or player.spec
      end
    end
    if not classFile and classHint then
      classFile = classHint[key]
    end
    if not classFile then
      return true
    end
    return GLD:IsEligibleForNeed(classFile, itemRef, specName)
  end

  for _, key in ipairs(expected) do
    if key and isEligible(key) then
      keys[#keys + 1] = key
      labels[#labels + 1] = GetVoterDisplayName(provider, key) or key
    end
  end

  if #keys == 0 and provider and provider.GetPlayers then
    for key, player in pairs(provider:GetPlayers() or {}) do
      if key and isEligible(key) then
        keys[#keys + 1] = key
        labels[#labels + 1] = (provider.GetPlayerName and provider:GetPlayerName(key))
          or (player and (player.name or player.fullName))
          or tostring(key)
      end
    end
  end

  return keys, labels
end

function UI:GetMissingVotersForItem(itemKey)
  local session = GetSessionByKey(itemKey)
  local votes = session and session.votes or nil
  return GetMissingVotersForSession(session, votes)
end

function UI:HasLocalPlayerVoted(itemKey)
  local session = GetSessionByKey(itemKey)
  local votes = session and session.votes or nil
  return HasLocalPlayerVotedSession(session, votes)
end

local function GetNextUnvotedItemIndex(self, startIndex)
  local state = GetLootWindowState(self)
  local entries = state.currentVoteItems or {}
  local start = math.max(startIndex or 1, 1)
  for i = start, #entries do
    if not entries[i].vote then
      return i
    end
  end
  return nil
end

local function CreatePendingRow(self, window)
  local row = CreateFrame("Frame", nil, window.pendingScrollChild, "BackdropTemplate")
  row:SetHeight(PENDING_ROW_HEIGHT)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(row)
  row.bg:SetColorTexture(0, 0, 0, 0)
  row.bg:Hide()

  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    tile = true,
    tileSize = 4,
    edgeSize = 1,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  row:SetBackdropColor(0, 0, 0, 0)
  row:SetBackdropBorderColor(unpack(PENDING_BORDER_DEFAULT))

  row.hoverHighlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.hoverHighlight:SetAllPoints(row)
  row.hoverHighlight:SetColorTexture(0.18, 0.18, 0.18, 0.65)
  row.hoverHighlight:Hide()

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(24, 24)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.icon:SetTexture(DEFAULT_ICON)

  row.itemText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.itemText:SetWidth(160)
  row.itemText:SetJustifyH("LEFT")

  row.statusText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.statusText:SetPoint("TOPLEFT", row.itemText, "TOPRIGHT", 8, -4)
  row.statusText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -4)
  row.statusText:SetJustifyH("LEFT")
  row.statusText:SetJustifyV("TOP")
  row.statusText:SetWordWrap(true)
  row.statusText:SetWidth(220)
  row.missingTooltipText = nil

  local function AnchorPendingTooltip()
    GameTooltip:ClearAllPoints()
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local uiX = cursorX / scale
    local uiY = cursorY / scale
    local offset = TOOLTIP_CURSOR_OFFSET
    local parentWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
    local tooltipWidth = GameTooltip and GameTooltip.GetWidth and GameTooltip:GetWidth() or nil
    if type(tooltipWidth) ~= "number" or tooltipWidth <= 0 then
      tooltipWidth = 220
    end
    local point = "BOTTOMLEFT"
    local anchorX = uiX + offset
    if parentWidth > 0 and anchorX + tooltipWidth > parentWidth then
      point = "BOTTOMRIGHT"
      anchorX = uiX - offset
    end
    GameTooltip:SetPoint(point, UIParent, "BOTTOMLEFT", anchorX, uiY)
  end

  local function showPendingTooltip(widget)
    local link = row.itemLink
    GameTooltip:SetOwner(row.icon, "ANCHOR_NONE")
    if link and link ~= "" then
      GameTooltip:SetHyperlink(link)
    else
      GameTooltip:SetText(row.itemText:GetText() or "Pending roll")
    end
    if row.missingTooltipText and row.missingTooltipText ~= "" then
      GameTooltip:AddLine("Missing voters:", 1, 0.8, 0, true)
      GameTooltip:AddLine(row.missingTooltipText, 1, 1, 1, true)
    end
    AnchorPendingTooltip()
    GameTooltip:Show()
  end
  local function hidePendingTooltip()
    GameTooltip:Hide()
  end
  local function focusEntry()
    local key = row.entryKey
    if key and self.RefreshLootWindow then
      self:RefreshLootWindow({ activeKey = key })
    end
  end

  row:EnableMouse(true)
  row.icon:EnableMouse(false)
  row.itemText:EnableMouse(false)

  -- make the clickable region span the icon and the item text at the icon's height
  local hitArea = CreateFrame("Button", nil, row)
  hitArea:SetPoint("LEFT", row.icon, "LEFT", 0, 0)
  hitArea:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  hitArea:SetPoint("TOP", row, "TOP", 0, 0)
  hitArea:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
  hitArea:RegisterForClicks("LeftButtonUp")
  hitArea:SetScript("OnEnter", function(widget)
    showPendingTooltip(widget)
    row.hoverHighlight:Show()
  end)
  hitArea:SetScript("OnLeave", function()
    hidePendingTooltip()
    row.hoverHighlight:Hide()
  end)
  hitArea:SetScript("OnClick", focusEntry)
  row.hitArea = hitArea

  return row
end

local function EnsureLootWindow(self)
  local window = self.lootVoteWindow or {}
  if window.frame then
    return window
  end

  local frame = CreateFrame("Frame", "GLDLootVoteWindow", UIParent, "BackdropTemplate")
  frame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
  local parentWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or 0
  local centerOffset = -(parentWidth > 0 and parentWidth * 0.25 or 200)
  frame:SetPoint("CENTER", UIParent, "CENTER", centerOffset, 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("HIGH")
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  frame:SetBackdropColor(0.08, 0.08, 0.08, 0.95)

  local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  title:SetText("Loot Votes")

  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
  closeButton:SetScript("OnClick", function()
    if HasBlockingVotes(self) then
      if GLD and GLD.Print then
        GLD:Print("You must vote or pass before closing.")
      end
      if frame.Raise then
        frame:Raise()
      end
      return
    end
    frame:Hide()
  end)
  frame:SetScript("OnHide", function()
    local state = GetLootWindowState(self)
    state.demoMode = false
    if HasBlockingVotes(self) then
      if C_Timer and C_Timer.After then
        C_Timer.After(0.1, function()
          if frame and not frame:IsShown() then
            frame:Show()
            if frame.Raise then
              frame:Raise()
            end
          end
        end)
      end
    end
  end)

  local activePanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
  activePanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -38)
  activePanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -38)
  activePanel:SetHeight(ACTIVE_PANEL_HEIGHT)

  local activeTitle = activePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  activeTitle:SetPoint("TOPLEFT", activePanel, "TOPLEFT", 8, -6)
  activeTitle:SetText("Active Vote")

  local adminOverrideButton = CreateFrame("Button", nil, activePanel, "UIPanelButtonTemplate")
  adminOverrideButton:SetSize(120, 18)
  adminOverrideButton:SetText("Admin Override")
  adminOverrideButton:SetPoint("TOPRIGHT", activePanel, "TOPRIGHT", -8, -4)
  adminOverrideButton:SetScript("OnClick", function()
    local state = GetLootWindowState(self)
    local entry = state.currentVoteItems[state.activeIndex]
    local session = entry and entry.session
    if not session then
      return
    end
    if not GLD:IsAuthority() then
      GLD:Print("Only the authority can apply overrides.")
      return
    end
    local keys, labels = BuildAdminOverrideCandidates(session)
    UI:ShowAdminVotePopup(session, keys, labels)
  end)
  adminOverrideButton:Hide()

  local forcePendingButton = CreateFrame("Button", nil, activePanel, "UIPanelButtonTemplate")
  forcePendingButton:SetSize(120, 18)
  forcePendingButton:SetText("Force Pending")
  forcePendingButton:SetPoint("TOPRIGHT", adminOverrideButton, "TOPLEFT", -6, 0)
  forcePendingButton:SetScript("OnClick", function()
    if not GLD:IsAuthority() then
      GLD:Print("Only the authority can force pending windows.")
      return
    end
    if GLD.ForcePendingVotesWindow then
      GLD:ForcePendingVotesWindow()
    end
  end)
  forcePendingButton:Hide()

  local activeIcon = activePanel:CreateTexture(nil, "ARTWORK")
  activeIcon:SetSize(36, 36)
  activeIcon:SetPoint("TOPLEFT", activeTitle, "BOTTOMLEFT", 0, -6)
  activeIcon:SetTexture(DEFAULT_ICON)

  local activeItemLabel = activePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  activeItemLabel:SetPoint("LEFT", activeIcon, "RIGHT", 6, 0)
  activeItemLabel:SetPoint("RIGHT", activePanel, "RIGHT", -8, 0)
  activeItemLabel:SetJustifyH("LEFT")
  activeItemLabel:SetJustifyV("TOP")
  activeItemLabel:SetText("No active loot roll.")

  local function showActiveTooltip(widget)
    local link = activeItemLabel.link
    if link and link ~= "" then
      GameTooltip:SetOwner(widget, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end
  local function hideActiveTooltip()
    GameTooltip:Hide()
  end

  activeIcon:EnableMouse(true)
  activeIcon:SetScript("OnEnter", showActiveTooltip)
  activeIcon:SetScript("OnLeave", hideActiveTooltip)
  activeItemLabel:EnableMouse(true)
  activeItemLabel:SetScript("OnEnter", showActiveTooltip)
  activeItemLabel:SetScript("OnLeave", hideActiveTooltip)

  local statusLabel = activePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  statusLabel:SetPoint("TOPLEFT", activeIcon, "BOTTOMLEFT", 0, -6)
  statusLabel:SetPoint("RIGHT", activePanel, "RIGHT", -8, 0)
  statusLabel:SetJustifyH("LEFT")
  statusLabel:SetJustifyV("TOP")
  statusLabel:SetWordWrap(true)
  statusLabel:SetText("Loot votes will appear when items drop.")

  local votedLabel = activePanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  votedLabel:SetPoint("CENTER", activePanel, "CENTER", 0, -6)
  votedLabel:SetText("")
  votedLabel:Hide()

  local buttonRow = CreateFrame("Frame", nil, activePanel)
  buttonRow:SetPoint("BOTTOMLEFT", activePanel, "BOTTOMLEFT", 6, 6)
  buttonRow:SetPoint("BOTTOMRIGHT", activePanel, "BOTTOMRIGHT", -6, 6)
  buttonRow:SetHeight(28)

  local voteButtons = {}
  local function createVoteButton(text, key, anchorPoint, relativeTo, relPoint, offsetX, offsetY)
    local button = CreateFrame("Button", nil, activePanel, "UIPanelButtonTemplate")
    button:SetSize(104, 24)
    button:SetText(text)
    button:SetPoint(anchorPoint, relativeTo, relPoint, offsetX, offsetY)
    button:SetScript("OnClick", function()
      UI:HandleLootVote(key)
    end)
    voteButtons[key] = button
    return button
  end

  local needButton = createVoteButton("Need", "NEED", "BOTTOMLEFT", buttonRow, "BOTTOMLEFT", 0, 0)
  local greedButton = createVoteButton("Greed", "GREED", "BOTTOMRIGHT", buttonRow, "BOTTOMRIGHT", 0, 0)
  createVoteButton("Transmog", "TRANSMOG", "BOTTOMLEFT", needButton, "TOPLEFT", 0, 4)
  createVoteButton("Pass", "PASS", "BOTTOMRIGHT", greedButton, "TOPRIGHT", 0, 4)

  local pendingPanel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
  pendingPanel:SetPoint("TOPLEFT", activePanel, "BOTTOMLEFT", 0, -PADDING)
  pendingPanel:SetPoint("TOPRIGHT", activePanel, "BOTTOMRIGHT", 0, -PADDING)
  pendingPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PADDING, 8)
  pendingPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, 8)

  local pendingTitle = pendingPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  pendingTitle:SetPoint("TOPLEFT", pendingPanel, "TOPLEFT", 8, -6)
  pendingTitle:SetText("Pending Votes")

  local pendingScroll = CreateFrame("ScrollFrame", nil, pendingPanel, "UIPanelScrollFrameTemplate")
  pendingScroll:SetPoint("TOPLEFT", pendingPanel, "TOPLEFT", 6, -24)
  pendingScroll:SetPoint("BOTTOMRIGHT", pendingPanel, "BOTTOMRIGHT", -28, 6)
  local pendingScrollChild = CreateFrame("Frame", nil, pendingScroll)
  pendingScrollChild:SetSize(1, 1)
  pendingScroll:SetScrollChild(pendingScrollChild)

  local pendingEmpty = pendingPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pendingEmpty:SetPoint("TOPLEFT", pendingPanel, "TOPLEFT", 8, -28)
  pendingEmpty:SetText("No active loot votes.")
  pendingEmpty:Hide()

  window.frame = frame
  window.closeButton = closeButton
  window.activeIcon = activeIcon
  window.activeItemLabel = activeItemLabel
  window.activeStatusLabel = statusLabel
  window.activeMessageLabel = votedLabel
  window.adminOverrideButton = adminOverrideButton
  window.forcePendingButton = forcePendingButton
  window.voteButtons = voteButtons
  window.pendingPanel = pendingPanel
  window.pendingScroll = pendingScroll
  window.pendingScrollChild = pendingScrollChild
  window.pendingRows = {}
  window.pendingEmptyLabel = pendingEmpty
  self.lootVoteWindow = window

  return window
end

local function UpdateVoteButtons(window, session, alreadyVoted)
  for vote, button in pairs(window.voteButtons or {}) do
    if not button or not button.SetEnabled then
      -- skip invalid button
    else
      local allow = not alreadyVoted
      if session then
        if vote == "NEED" and session.canNeed == false then
          allow = false
        elseif vote == "GREED" and session.canGreed == false then
          allow = false
        elseif vote == "TRANSMOG" and session.canTransmog == false then
          allow = false
        end
      end
      button:SetEnabled(allow)
    end
  end
end

local function UpdateActivePanel(self, state, window)
  local index = state.activeIndex
  local entry = state.currentVoteItems[index]
  local showOverride = entry and not state.demoMode and GLD.IsAuthority and GLD:IsAuthority()
  local showForce = not state.demoMode and GLD.IsAuthority and GLD:IsAuthority() and IsInRaid()
  if window.adminOverrideButton then
    window.adminOverrideButton:SetShown(showOverride)
    window.adminOverrideButton:SetEnabled(showOverride)
  end
  if window.forcePendingButton then
    window.forcePendingButton:SetShown(showForce)
    window.forcePendingButton:SetEnabled(showForce)
  end
  if not entry then
    window.activeItemLabel:SetText("No active loot roll.")
    window.activeItemLabel.link = nil
    window.activeIcon:SetTexture(DEFAULT_ICON)
    window.activeStatusLabel:SetText("Loot votes will appear when items drop.")
    window.activeMessageLabel:Hide()
    UpdateVoteButtons(window, nil, true)
    return
  end

  local session = entry.session
  local link = session and session.itemLink or nil
  local text = GetDisplayedItemText(session)
  window.activeItemLabel:SetText(text or "Unknown Item")
  window.activeItemLabel.link = link
  local icon = DEFAULT_ICON
  if link then
    local itemIcon = select(10, GetItemInfo(link))
    if itemIcon then
      icon = itemIcon
    elseif session and session.itemIcon then
      icon = session.itemIcon
    else
      GLD:RequestItemData(link)
    end
  elseif session and session.itemIcon then
    icon = session.itemIcon
  end
  window.activeIcon:SetTexture(icon)

  local alreadyVoted = entry.vote and entry.vote ~= ""
  if alreadyVoted then
    local voteText = FormatVoteLabel(entry.vote)
    window.activeStatusLabel:SetText("Vote submitted: " .. voteText .. ". Waiting for results.")
    window.activeMessageLabel:SetText("Voted - waiting for winner")
    window.activeMessageLabel:Show()
  else
    window.activeStatusLabel:SetText("Declare your intent here. Buttons remain enabled until you vote.")
    window.activeMessageLabel:Hide()
  end

  UpdateVoteButtons(window, session, alreadyVoted)
end

local function UpdatePendingRows(self, state, window)
  local entries = state.currentVoteItems
  local rows = window.pendingRows
  local yOffset = 0
  local spacing = ROW_SPACING
  local scrollWidth = 0
  if window.pendingScroll and window.pendingScroll.GetWidth then
    scrollWidth = window.pendingScroll:GetWidth() or 0
  end
  if scrollWidth <= 1 then
    local fallbackWidth = window.pendingPanel and window.pendingPanel.GetWidth and window.pendingPanel:GetWidth() or 0
    if fallbackWidth <= 1 and window.frame and window.frame.GetWidth then
      fallbackWidth = window.frame:GetWidth() or 0
    end
    if fallbackWidth > 1 then
      scrollWidth = math.max(fallbackWidth - 34, 1)
    else
      scrollWidth = 1
    end
    if not state.pendingWidthRetry and C_Timer and C_Timer.After then
      state.pendingWidthRetry = true
      C_Timer.After(0, function()
        state.pendingWidthRetry = false
        if UI and UI.RefreshLootWindow then
          UI:RefreshLootWindow()
        end
      end)
    end
  end
  local childWidth = math.max(scrollWidth, 1)
  window.pendingScrollChild:SetWidth(childWidth)
  for idx, entry in ipairs(entries) do
    local row = rows[idx]
    if not row then
      row = CreatePendingRow(self, window)
      rows[idx] = row
    end
    row.entryKey = entry.key
    local session = entry.session
    local link = session and session.itemLink or nil
    row.itemLink = link
    row.itemText:SetText(GetDisplayedItemText(session))
    local statusWidth = math.max(80, childWidth - 200)
    row.statusText:SetWidth(statusWidth)
    row.itemText:SetWidth(math.max(100, childWidth - statusWidth - 60))
    local entryKey = entry.key
    local votes = BuildSessionVoteSnapshot(session, state, entryKey)
    local missingNames = GetMissingVotersForSession(session, votes)
    local hasLocalVoted = HasLocalPlayerVotedSession(session, votes)
    row.missingTooltipText = (#missingNames > 0) and table.concat(missingNames, "\n") or nil

    local displayText = ""
    if not hasLocalVoted then
      row.statusText:SetFontObject(GameFontNormalLarge)
      row.statusText:SetTextColor(0.2, 1, 0.2)
      displayText = "Waiting for your Vote"
    else
      row.statusText:SetFontObject(GameFontHighlightSmall)
      row.statusText:SetTextColor(0.9, 0.9, 0.9)
      local missingText = FormatMissingDisplayText(missingNames)
      if missingText == "" then
        displayText = "Waiting for votes"
      else
        displayText = "Waiting for votes: " .. missingText
      end
    end
    row.statusText:SetText(displayText)
    DebugPendingRow(session, hasLocalVoted, missingNames, displayText)

    AdjustPendingRowHeight(row)

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", window.pendingScrollChild, "TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", window.pendingScrollChild, "RIGHT", -4, 0)
    row:SetWidth(math.max(1, childWidth - 4))
    yOffset = yOffset + row:GetHeight() + spacing

    local icon = DEFAULT_ICON
    if link then
      local itemIcon = select(10, GetItemInfo(link))
      if itemIcon then
        icon = itemIcon
      elseif session and session.itemIcon then
        icon = session.itemIcon
      else
        GLD:RequestItemData(link)
      end
    elseif session and session.itemIcon then
      icon = session.itemIcon
    end
    row.icon:SetTexture(icon)
    if entry.key == state.activeKey then
      row:SetBackdropBorderColor(unpack(PENDING_BORDER_ACTIVE))
    else
      row:SetBackdropBorderColor(unpack(PENDING_BORDER_DEFAULT))
    end
    row.bg:SetShown(entry.key == state.activeKey)
    row:Show()
  end
  -- Removed the OnEnter/Leave scripts that previously covered the whole row to limit tooltip activation
  for i = #entries + 1, #rows do
    rows[i]:Hide()
  end
  local height = math.max(yOffset + spacing, PENDING_ROW_HEIGHT)
  window.pendingScrollChild:SetHeight(height)
  window.pendingScroll:UpdateScrollChildRect()
  window.pendingEmptyLabel:SetShown(#entries == 0)
end

local function UpdateLootWindowContent(self, state, window)
  UpdateActivePanel(self, state, window)
  UpdatePendingRows(self, state, window)
end

local function UpdateActiveSelection(self, state, options)
  local entries = state.currentVoteItems or {}
  if #entries == 0 then
    state.activeIndex = nil
    state.activeKey = nil
    return
  end
  if options and options.activeKey then
    local idx = state.indexByKey[options.activeKey]
    if idx then
      if options.advance then
        local start = idx + 1
        local nextIndex = GetNextUnvotedItemIndex(self, start)
        if not nextIndex then
          nextIndex = GetNextUnvotedItemIndex(self, 1)
        end
        if nextIndex then
          state.activeIndex = nextIndex
          state.activeKey = entries[nextIndex].key
          return
        end
      else
        state.activeIndex = idx
        state.activeKey = options.activeKey
        return
      end
    end
  end
  if state.activeKey then
    local idx = state.indexByKey[state.activeKey]
    if idx then
      state.activeIndex = idx
      return
    end
  end
  state.activeIndex = 1
  state.activeKey = entries[1].key
end

function UI:RefreshLootWindow(options)
  options = options or {}
  local state = GetLootWindowState(self)
  local sessions = GetActiveVoteSessions()
  if #sessions > 0 and not options.forceDemo then
    state.demoMode = false
  end
  local displaySessions = state.demoMode and (state.demoItems or {}) or sessions
  BuildVoteEntries(self, displaySessions)
  UpdateActiveSelection(self, state, options)
  local sessionActive = nil
  local sessionSource = "unknown"
  if GLD.IsAuthority and GLD:IsAuthority() then
    sessionActive = GLD.db and GLD.db.session and GLD.db.session.active
    sessionSource = "authority-db"
  elseif GLD.shadow and GLD.shadow.sessionActive ~= nil then
    sessionActive = GLD.shadow.sessionActive
    sessionSource = "shadow"
  else
    sessionActive = GLD.db and GLD.db.session and GLD.db.session.active
    sessionSource = "db"
  end
  local inRaid = IsInRaid()
  local shouldShow = options.forceShow
    or state.demoMode
    or (inRaid and #sessions > 0)
  local window = EnsureLootWindow(self)
  local blockClose = HasUnvotedEntries(state, state.currentVoteItems)
  if window.closeButton and window.closeButton.SetEnabled then
    window.closeButton:SetEnabled(not blockClose)
  end
  if GLD.IsDebugEnabled and GLD:IsDebugEnabled() then
    GLD:Debug(
      "Loot window refresh: sessions="
        .. tostring(#sessions)
        .. " shouldShow="
        .. tostring(shouldShow)
        .. " inRaid="
        .. tostring(inRaid)
        .. " sessionActive="
        .. tostring(sessionActive)
        .. " source="
        .. tostring(sessionSource)
        .. " blockClose="
        .. tostring(blockClose)
    )
  end
  if shouldShow and #state.currentVoteItems == 0 then
    state.activeKey = nil
    state.activeIndex = nil
  end
  if shouldShow then
    window.frame:Show()
    if window.frame.Raise and (options.forceShow or options.reopen) then
      window.frame:Raise()
    end
    UpdateLootWindowContent(self, state, window)
    if GLD.IsDebugEnabled and GLD:IsDebugEnabled() then
      GLD:Debug("Loot window shown: items=" .. tostring(#state.currentVoteItems))
    end
  else
    window.frame:Hide()
    if GLD.IsDebugEnabled and GLD:IsDebugEnabled() then
      GLD:Debug("Loot window hidden.")
    end
  end
end

function UI:ShowLootWindowDemo()
  local state = GetLootWindowState(self)
  state.demoMode = true
  state.demoVotes = {}
  state.demoItems = {
    {
      rollID = "demo-loot-a",
      rollKey = "demo-loot-a@demo",
      itemLink = "item:237728",
      itemName = "Voidglass Kris",
      canNeed = true,
      canGreed = true,
      canTransmog = true,
      isTest = true,
      expectedVoters = { "Lily", "Rob", "Steph", "Alex", "Ryan", "Vulthan", "Mira" },
      expectedVoterClasses = {
        Lily = "DRUID",
        Rob = "SHAMAN",
        Steph = "HUNTER",
        Alex = "WARLOCK",
        Ryan = "DEATHKNIGHT",
        Vulthan = "WARRIOR",
        Mira = "MAGE",
      },
      votes = {
        Lily = "NEED",
        Rob = "GREED",
      },
    },
    {
      rollID = "demo-loot-b",
      rollKey = "demo-loot-b@demo",
      itemLink = "item:244234",
      itemName = "Astral Gladiator's Prestigious Cloak",
      canNeed = true,
      canGreed = true,
      canTransmog = true,
      isTest = true,
      expectedVoters = { "Lily" },
      expectedVoterClasses = {
        Lily = "DRUID",
      },
      votes = {},
    },
  }
  state.demoVotes["demo-loot-a@demo"] = "NEED"
  state.activeKey = nil
  self:RefreshLootWindow({ forceShow = true, forceDemo = true })
end

function UI:ShowDemoWinnerNotice(session)
  if not session then
    return
  end
  local window = self.demoWinnerNotice
  if not window then
    window = CreateFrame("Frame", "GLDDemoWinnerNotice", UIParent, "BackdropTemplate")
    window:SetSize(360, 180)
    window:SetPoint("TOP", UIParent, "TOP", 0, -160)
    window:SetFrameStrata("HIGH")
    window:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true,
      tileSize = 32,
      edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    window:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    window:SetClampedToScreen(true)

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", window, "TOP", 0, -18)
    title:SetText("You have won the item!")
    window.title = title

    local itemContainer = CreateFrame("Frame", nil, window)
    itemContainer:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -80, -6)
    itemContainer:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 80, -6)
    itemContainer:SetHeight(60)
    window.itemContainer = itemContainer
    window.itemLines = {}

    local action = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    action:SetPoint("TOP", itemContainer, "BOTTOM", 0, -2)
    action:SetText("|cffFFD200Roll NEED|r")
    window.action = action

    local sub = window:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOP", action, "BOTTOM", 0, -6)
    sub:SetText("In the Blizzard loot roll window.")
    window.sub = sub

    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
    closeButton:SetScript("OnClick", function()
      window:Hide()
    end)

    self.demoWinnerNotice = window
  end

  self.demoWinnerItems = self.demoWinnerItems or {}
  local id = session.rollKey or session.rollID or session.itemLink or session.itemName or tostring(session)
  if not self.demoWinnerItems[id] then
    local itemName = GetDisplayedItemText(session)
    local itemLink = session.itemLink
    local icon = DEFAULT_ICON
    if itemLink then
      local itemIcon = select(10, GetItemInfo(itemLink))
      if itemIcon then
        icon = itemIcon
      else
        GLD:RequestItemData(itemLink)
      end
    end
    self.demoWinnerItems[id] = { name = itemName, icon = icon }
  end

  local items = {}
  for _, entry in pairs(self.demoWinnerItems) do
    items[#items + 1] = entry
  end

  for i, line in ipairs(window.itemLines or {}) do
    line.icon:Hide()
    line.text:Hide()
  end

  local maxLines = math.min(#items, 3)
  for i = 1, maxLines do
    local entry = items[i]
    local line = window.itemLines[i]
    if not line then
      line = {}
      line.frame = CreateFrame("Frame", nil, window.itemContainer)
      line.frame:SetSize(320, 52)
      line.icon = line.frame:CreateTexture(nil, "ARTWORK")
      line.icon:SetSize(36, 36)
      line.text = line.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      line.text:SetJustifyH("CENTER")
      window.itemLines[i] = line
    end
    line.icon:SetTexture(entry.icon or DEFAULT_ICON)
    line.frame:ClearAllPoints()
    line.frame:SetPoint("TOP", window.itemContainer, "TOP", 0, -((i - 1) * 52))
    line.icon:SetPoint("TOP", line.frame, "TOP", 0, 0)
    line.icon:Show()
    line.text:SetPoint("TOP", line.icon, "BOTTOM", 0, -2)
    line.text:SetPoint("LEFT", line.frame, "LEFT", 6, 0)
    line.text:SetPoint("RIGHT", line.frame, "RIGHT", -6, 0)
    line.text:SetText(entry.name or "Item")
    line.text:Show()
  end

  if window.itemContainer then
    window.itemContainer:SetHeight(maxLines * 52)
  end

  if window then
    window:Show()
  end
end

function UI:HandleLootVote(vote)
  local state = GetLootWindowState(self)
  local entry = state.currentVoteItems[state.activeIndex]
  if not entry then
    return
  end
  if state.demoMode then
    state.demoVotes[entry.key] = vote
    if entry.key == "demo-loot-b" and vote ~= "PASS" then
      self:ShowDemoWinnerNotice(entry.session)
    end
    self:RefreshLootWindow({ advance = true, activeKey = entry.key })
    return
  end
  if entry.session then
    self:SubmitRollVote(entry.session, vote, true)
  end
end

function UI:ShowPendingFrame()
  self:RefreshLootWindow({ forceShow = true })
end

function UI:RefreshPendingVotes()
  self:RefreshLootWindow()
end

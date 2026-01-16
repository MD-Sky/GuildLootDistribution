local _, NS = ...

local GLD = NS.GLD
local AceGUI = LibStub("AceGUI-3.0", true)

local TestUI = {}
NS.TestUI = TestUI

local function EJ_Call(name, ...)
  if C_EncounterJournal and C_EncounterJournal[name] then
    return C_EncounterJournal[name](...)
  end
  local legacy = _G["EJ_" .. name]
  if legacy then
    return legacy(...)
  end
  return nil
end

function GLD:InitTestUI()
  TestUI.testFrame = nil
end

function TestUI:ToggleTestPanel()
  if not GLD:IsAdmin() then
    GLD:Print("you do not have Guild Permission to access this panel")
    return
  end
  if not self.testFrame then
    self:CreateTestFrame()
  end
  if self.testFrame:IsShown() then
    self.testFrame:Hide()
  else
    self.testFrame:Show()
    self:RefreshTestPanel()
  end
end

function TestUI:CreateTestFrame()
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("Admin Test Panel")
  frame:SetStatusText("Test Session / Loot / Variables")
  frame:SetWidth(900)
  frame:SetHeight(560)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

  local columns = AceGUI:Create("SimpleGroup")
  columns:SetFullWidth(true)
  columns:SetFullHeight(true)
  columns:SetLayout("Flow")
  frame:AddChild(columns)

  local lootColumn = AceGUI:Create("InlineGroup")
  lootColumn:SetTitle("Test Loot Choices")
  lootColumn:SetWidth(300)
  lootColumn:SetFullHeight(true)
  lootColumn:SetLayout("Flow")
  columns:AddChild(lootColumn)

  local rightColumn = AceGUI:Create("SimpleGroup")
  rightColumn:SetWidth(580)
  rightColumn:SetFullHeight(true)
  rightColumn:SetLayout("Flow")
  columns:AddChild(rightColumn)

  local sessionGroup = AceGUI:Create("SimpleGroup")
  sessionGroup:SetFullWidth(true)
  sessionGroup:SetLayout("Flow")

  local sessionLabel = AceGUI:Create("Heading")
  sessionLabel:SetText("Session Controls")
  sessionLabel:SetFullWidth(true)
  sessionGroup:AddChild(sessionLabel)

  local startBtn = AceGUI:Create("Button")
  startBtn:SetText("Start Session")
  startBtn:SetWidth(150)
  startBtn:SetCallback("OnClick", function()
    GLD:StartSession()
    TestUI:RefreshTestPanel()
  end)
  sessionGroup:AddChild(startBtn)

  local endBtn = AceGUI:Create("Button")
  endBtn:SetText("End Session")
  endBtn:SetWidth(150)
  endBtn:SetCallback("OnClick", function()
    GLD:EndSession()
    TestUI:RefreshTestPanel()
  end)
  sessionGroup:AddChild(endBtn)

  local sessionStatus = AceGUI:Create("Label")
  sessionStatus:SetFullWidth(true)
  sessionStatus:SetText("Session Status: INACTIVE")
  sessionGroup:AddChild(sessionStatus)

  rightColumn:AddChild(sessionGroup)

  local rosterLabel = AceGUI:Create("Heading")
  rosterLabel:SetText("Player Management")
  rosterLabel:SetFullWidth(true)
  rightColumn:AddChild(rosterLabel)

  local rosterScroll = AceGUI:Create("ScrollFrame")
  rosterScroll:SetFullWidth(true)
  rosterScroll:SetHeight(300)
  rosterScroll:SetLayout("Flow")
  rightColumn:AddChild(rosterScroll)

  local instanceSelect = AceGUI:Create("Dropdown")
  instanceSelect:SetLabel("Raid")
  instanceSelect:SetWidth(260)
  lootColumn:AddChild(instanceSelect)

  local encounterSelect = AceGUI:Create("Dropdown")
  encounterSelect:SetLabel("Encounter")
  encounterSelect:SetWidth(260)
  lootColumn:AddChild(encounterSelect)

  local loadLootBtn = AceGUI:Create("Button")
  loadLootBtn:SetText("Load Loot")
  loadLootBtn:SetWidth(120)
  lootColumn:AddChild(loadLootBtn)

  local itemLinkInput = AceGUI:Create("EditBox")
  itemLinkInput:SetLabel("Item Link")
  itemLinkInput:SetWidth(260)
  itemLinkInput:SetText("item:19345")
  lootColumn:AddChild(itemLinkInput)

  local dropBtn = AceGUI:Create("Button")
  dropBtn:SetText("Simulate Loot Roll")
  dropBtn:SetWidth(150)
  dropBtn:SetCallback("OnClick", function()
    TestUI:SimulateLootRoll(itemLinkInput:GetText())
  end)
  lootColumn:AddChild(dropBtn)

  local lootListGroup = AceGUI:Create("InlineGroup")
  lootListGroup:SetTitle("Encounter Loot")
  lootListGroup:SetFullWidth(true)
  lootListGroup:SetLayout("Fill")

  local lootScroll = AceGUI:Create("ScrollFrame")
  lootScroll:SetLayout("Flow")
  lootListGroup:AddChild(lootScroll)
  lootColumn:AddChild(lootListGroup)

  self.testFrame = frame
  self.sessionStatus = sessionStatus
  self.rosterScroll = rosterScroll
  self.lootScroll = lootScroll
  self.instanceSelect = instanceSelect

  self.encounterSelect = encounterSelect
  self.itemLinkInput = itemLinkInput

  instanceSelect:SetCallback("OnValueChanged", function(_, _, value)
    TestUI:SelectInstance(value)
  end)
  encounterSelect:SetCallback("OnValueChanged", function(_, _, value)
    TestUI:SelectEncounter(value)
  end)
  loadLootBtn:SetCallback("OnClick", function()
    TestUI:LoadEncounterLoot()
  end)
end

function TestUI:RefreshTestPanel()
  if not self.testFrame then
    return
  end

  local sessionActive = GLD.db.session and GLD.db.session.active
  self.sessionStatus:SetText("Session Status: " .. (sessionActive and "|cff00ff00ACTIVE|r" or "|cffff0000INACTIVE|r"))

  self.rosterScroll:ReleaseChildren()

  local list = {}
  for _, player in pairs(GLD.db.players) do
    table.insert(list, player)
  end

  table.sort(list, function(a, b)
    if a.attendance == "PRESENT" and b.attendance ~= "PRESENT" then
      return true
    end
    if a.attendance ~= "PRESENT" and b.attendance == "PRESENT" then
      return false
    end
    return (a.name or "") < (b.name or "")
  end)

  for _, player in ipairs(list) do
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    local nameLabel = AceGUI:Create("Label")
    nameLabel:SetText(player.name or "?")
    nameLabel:SetWidth(150)
    row:AddChild(nameLabel)

    local attendanceLabel = AceGUI:Create("Label")
    attendanceLabel:SetText(NS:ColorAttendance(player.attendance))
    attendanceLabel:SetWidth(100)
    row:AddChild(attendanceLabel)

    local toggleBtn = AceGUI:Create("Button")
    toggleBtn:SetText(player.attendance == "PRESENT" and "Mark Absent" or "Mark Present")
    toggleBtn:SetWidth(120)
    local playerKey = player.name .. "-" .. (player.realm or GetRealmName())
    toggleBtn:SetCallback("OnClick", function()
      if GLD.db.players[playerKey] then
        local newState = GLD.db.players[playerKey].attendance == "PRESENT" and "ABSENT" or "PRESENT"
        GLD:SetAttendance(playerKey, newState)
        TestUI:RefreshTestPanel()
      end
    end)
    row:AddChild(toggleBtn)

    local wonBox = AceGUI:Create("EditBox")
    wonBox:SetLabel("Won")
    wonBox:SetText(tostring(player.numAccepted or 0))
    wonBox:SetWidth(80)
    wonBox:SetCallback("OnEnterPressed", function(_, _, value)
      local num = tonumber(value) or 0
      if GLD.db.players[playerKey] then
        GLD.db.players[playerKey].numAccepted = num
      end
    end)
    row:AddChild(wonBox)

    local raidsBox = AceGUI:Create("EditBox")
    raidsBox:SetLabel("Raids")
    raidsBox:SetText(tostring(player.attendanceCount or 0))
    raidsBox:SetWidth(80)
    raidsBox:SetCallback("OnEnterPressed", function(_, _, value)
      local num = tonumber(value) or 0
      if GLD.db.players[playerKey] then
        GLD.db.players[playerKey].attendanceCount = num
      end
    end)
    row:AddChild(raidsBox)

    self.rosterScroll:AddChild(row)
  end

  self:RefreshInstanceList()
end

function TestUI:RefreshInstanceList()
  if not self.instanceSelect then
    return
  end

  if not EncounterJournal then
    if C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
      LoadAddOn("Blizzard_EncounterJournal")
    end
  end
  if EncounterJournal_LoadUI then
    EncounterJournal_LoadUI()
  end

  if not EncounterJournal or (not (C_EncounterJournal and C_EncounterJournal.GetNumTiers) and not _G.EJ_GetNumTiers) then
    if not self._ejDebugShown then
      self._ejDebugShown = true
      GLD:Print("EJ not ready yet (EncounterJournal or EJ_GetNumTiers missing)")
    end
    C_Timer.After(0.2, function()
      TestUI:RefreshInstanceList()
    end)
    return
  end

  EJ_Call("SetDifficultyID", 14)

  local values = {}
  local order = {}

  local tiers = EJ_Call("GetNumTiers") or 0
  if tiers == 0 then
    if not self._ejDebugShown then
      self._ejDebugShown = true
      GLD:Print("EJ tiers = 0 (no data yet)")
    end
    C_Timer.After(0.2, function()
      TestUI:RefreshInstanceList()
    end)
    return
  end
  for tier = 1, tiers do
    EJ_Call("SelectTier", tier)
    local i = 1
    while true do
      local instanceID, name = EJ_Call("GetInstanceByIndex", i, true)
      if not instanceID then
        break
      end
      values[instanceID] = name
      table.insert(order, instanceID)
      i = i + 1
    end
  end

  self.instanceSelect:SetList(values, order)
  if #order == 0 then
    if not self._ejDebugShown then
      self._ejDebugShown = true
      GLD:Print("EJ instances = 0 (no raids returned)")
    end
    C_Timer.After(0.2, function()
      TestUI:RefreshInstanceList()
    end)
    return
  end

  if not self.selectedInstance and order[1] then
    self.instanceSelect:SetValue(order[1])
    self:SelectInstance(order[1])
  end
end

function TestUI:SelectInstance(instanceID)
  if not instanceID then
    return
  end
  if not EncounterJournal then
    if C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
      LoadAddOn("Blizzard_EncounterJournal")
    end
  end
  if not (C_EncounterJournal and C_EncounterJournal.SelectInstance) and not _G.EJ_SelectInstance then
    return
  end
  self.selectedInstance = instanceID
  EJ_Call("SelectInstance", instanceID)

  local encounters = {}
  local order = {}
  self.encounterNameToId = {}
  self.encounterNameToIndex = {}
  self.encounterIdToIndex = {}
  local i = 1
  while true do
    local a, b, c = EJ_Call("GetEncounterInfoByIndex", i, instanceID)
    if not a then
      break
    end
    local encounterID = nil
    local name = nil
    if type(a) == "number" then
      encounterID = a
      name = b
    elseif type(b) == "number" then
      encounterID = b
      name = a
    elseif type(c) == "number" then
      encounterID = c
      name = a
    end

    if type(encounterID) == "number" then
      local displayName = name or ("Encounter " .. encounterID)
      encounters[i] = displayName
      table.insert(order, i)
      if name then
        self.encounterNameToId[name] = encounterID
        self.encounterNameToIndex[name] = i
      end
      self.encounterIdToIndex[encounterID] = i
    end
    i = i + 1
  end

  self.encounterSelect:SetList(encounters, order)
  if #order == 0 then
    GLD:Print("EJ encounters = 0 for instance " .. tostring(instanceID))
  end
  if order[1] then
    self.encounterSelect:SetValue(order[1])
    self:SelectEncounter(order[1])
  end
end

function TestUI:SelectEncounter(encounterID)
  if type(encounterID) == "string" and self.encounterNameToIndex then
    encounterID = self.encounterNameToIndex[encounterID] or encounterID
  end
  self.selectedEncounterIndex = encounterID
  if type(encounterID) == "number" and self.encounterIdToIndex then
    self.selectedEncounterID = nil
    for id, idx in pairs(self.encounterIdToIndex) do
      if idx == encounterID then
        self.selectedEncounterID = id
        break
      end
    end
  end
end

function TestUI:LoadEncounterLoot()
  if not self.selectedEncounterIndex or not self.lootScroll then
    GLD:Print("LoadLoot: missing encounter or lootScroll")
    return
  end

  local encounterIndex = self.selectedEncounterIndex
  if type(encounterIndex) ~= "number" then
    GLD:Print("LoadLoot: invalid encounterIndex " .. tostring(self.selectedEncounterIndex))
    return
  end

  local encounterID = self.selectedEncounterID
  if type(encounterID) ~= "number" then
    GLD:Print("LoadLoot: missing encounterID for index " .. tostring(encounterIndex))
  end

  if not EncounterJournal then
    if C_AddOns and C_AddOns.LoadAddOn then
      C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    elseif LoadAddOn then
      LoadAddOn("Blizzard_EncounterJournal")
    end
  end
  if not (C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex) and not _G.EJ_GetLootInfoByIndex then
    GLD:Print("LoadLoot: EJ_GetLootInfoByIndex missing")
    return
  end

  self.lootScroll:ReleaseChildren()
    EJ_Call("SetLootFilter", 0)
    EJ_Call("SetDifficultyID", 14)
    if C_EncounterJournal and C_EncounterJournal.SetDifficultyID then
      C_EncounterJournal.SetDifficultyID(14)
    end

  if encounterID then
    EJ_Call("SelectEncounter", encounterID)
  end

  GLD:Print("LoadLoot: encounterIndex=" .. tostring(encounterIndex) .. " encounterID=" .. tostring(encounterID))

  local index = 1
  local added = 0
  while true do
    local itemInfo = { EJ_Call("GetLootInfoByIndex", index, encounterID or encounterIndex) }
    local info = itemInfo[1]
    if type(info) == "table" then
      itemInfo = info
    end
    if not itemInfo[1] and type(info) ~= "table" then
      break
    end

    local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, icon = unpack(itemInfo)
    if type(info) == "table" then
      itemName = info.name or itemName
      itemLink = info.link or info.itemLink or itemLink
      itemLevel = info.itemLevel or itemLevel
      icon = info.icon or info.texture or icon
    end
    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    local iconButton = AceGUI:Create("Icon")
    iconButton:SetImage(icon)
    iconButton:SetImageSize(20, 20)
    iconButton:SetWidth(24)
    iconButton:SetHeight(24)
    iconButton:SetCallback("OnEnter", function()
      if itemLink then
        GameTooltip:SetOwner(iconButton.frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
      end
    end)
    iconButton:SetCallback("OnLeave", function()
      GameTooltip:Hide()
    end)
    iconButton:SetCallback("OnClick", function()
      if itemLink then
        self.itemLinkInput:SetText(itemLink)
      end
    end)
    row:AddChild(iconButton)

    local nameLabel = AceGUI:Create("InteractiveLabel")
    local labelText = tostring(itemLink or itemName or "Unknown Item")
    if itemLevel then
      labelText = string.format("%s |cff999999(ilvl %s)|r", labelText, itemLevel)
    end
    nameLabel:SetText(labelText)
    nameLabel:SetWidth(220)
    nameLabel:SetCallback("OnEnter", function()
      if itemLink then
        GameTooltip:SetOwner(nameLabel.frame, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
      end
    end)
    nameLabel:SetCallback("OnLeave", function()
      GameTooltip:Hide()
    end)
    nameLabel:SetCallback("OnClick", function()
      if itemLink then
        self.itemLinkInput:SetText(itemLink)
      end
    end)
    row:AddChild(nameLabel)

    self.lootScroll:AddChild(row)
    added = added + 1

    index = index + 1
  end

  GLD:Print("LoadLoot: items added=" .. tostring(added))
  if added == 0 and encounterID and encounterID ~= encounterIndex then
    local retryIndex = 1
    while true do
      local itemInfo = { EJ_Call("GetLootInfoByIndex", retryIndex, encounterIndex) }
      local info = itemInfo[1]
      if type(info) == "table" then
        itemInfo = info
      end
      if not itemInfo[1] and type(info) ~= "table" then
        break
      end
      local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, icon = unpack(itemInfo)
      if type(info) == "table" then
        itemName = info.name or itemName
        itemLink = info.link or info.itemLink or itemLink
        itemLevel = info.itemLevel or itemLevel
        icon = info.icon or info.texture or icon
      end
      local row = AceGUI:Create("SimpleGroup")
      row:SetFullWidth(true)
      row:SetLayout("Flow")

      local iconButton = AceGUI:Create("Icon")
      iconButton:SetImage(icon)
      iconButton:SetImageSize(20, 20)
      iconButton:SetWidth(24)
      iconButton:SetHeight(24)
      iconButton:SetCallback("OnEnter", function()
        if itemLink then
          GameTooltip:SetOwner(iconButton.frame, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(itemLink)
          GameTooltip:Show()
        end
      end)
      iconButton:SetCallback("OnLeave", function()
        GameTooltip:Hide()
      end)
      iconButton:SetCallback("OnClick", function()
        if itemLink then
          self.itemLinkInput:SetText(itemLink)
        end
      end)
      row:AddChild(iconButton)

      local nameLabel = AceGUI:Create("InteractiveLabel")
      local labelText = tostring(itemLink or itemName or "Unknown Item")
      if itemLevel then
        labelText = string.format("%s |cff999999(ilvl %s)|r", labelText, itemLevel)
      end
      nameLabel:SetText(labelText)
      nameLabel:SetWidth(220)
      nameLabel:SetCallback("OnEnter", function()
        if itemLink then
          GameTooltip:SetOwner(nameLabel.frame, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(itemLink)
          GameTooltip:Show()
        end
      end)
      nameLabel:SetCallback("OnLeave", function()
        GameTooltip:Hide()
      end)
      nameLabel:SetCallback("OnClick", function()
        if itemLink then
          self.itemLinkInput:SetText(itemLink)
        end
      end)
      row:AddChild(nameLabel)

      self.lootScroll:AddChild(row)
      added = added + 1
      retryIndex = retryIndex + 1
    end

    GLD:Print("LoadLoot: fallback items added=" .. tostring(added))
  end

  if added == 0 and C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
    local idx = 1
    local added2 = 0
    while true do
      local itemInfo = { C_EncounterJournal.GetLootInfoByIndex(idx, encounterID) }
      local info = itemInfo[1]
      if type(info) == "table" then
        itemInfo = info
      end
      if not itemInfo[1] and type(info) ~= "table" then
        break
      end

      local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, icon = unpack(itemInfo)
      if type(info) == "table" then
        itemName = info.name or itemName
        itemLink = info.link or info.itemLink or itemLink
        itemLevel = info.itemLevel or itemLevel
        icon = info.icon or info.texture or icon
      end
      local row = AceGUI:Create("SimpleGroup")
      row:SetFullWidth(true)
      row:SetLayout("Flow")

      local iconButton = AceGUI:Create("Icon")
      iconButton:SetImage(icon)
      iconButton:SetImageSize(20, 20)
      iconButton:SetWidth(24)
      iconButton:SetHeight(24)
      iconButton:SetCallback("OnEnter", function()
        if itemLink then
          GameTooltip:SetOwner(iconButton.frame, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(itemLink)
          GameTooltip:Show()
        end
      end)
      iconButton:SetCallback("OnLeave", function()
        GameTooltip:Hide()
      end)
      iconButton:SetCallback("OnClick", function()
        if itemLink then
          self.itemLinkInput:SetText(itemLink)
        end
      end)
      row:AddChild(iconButton)

      local nameLabel = AceGUI:Create("InteractiveLabel")
      local labelText = tostring(itemLink or itemName or "Unknown Item")
      if itemLevel then
        labelText = string.format("%s |cff999999(ilvl %s)|r", labelText, itemLevel)
      end
      nameLabel:SetText(labelText)
      nameLabel:SetWidth(220)
      nameLabel:SetCallback("OnEnter", function()
        if itemLink then
          GameTooltip:SetOwner(nameLabel.frame, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(itemLink)
          GameTooltip:Show()
        end
      end)
      nameLabel:SetCallback("OnLeave", function()
        GameTooltip:Hide()
      end)
      nameLabel:SetCallback("OnClick", function()
        if itemLink then
          self.itemLinkInput:SetText(itemLink)
        end
      end)
      row:AddChild(nameLabel)

      self.lootScroll:AddChild(row)
      added2 = added2 + 1
      idx = idx + 1
    end

    GLD:Print("LoadLoot: C_EncounterJournal items added=" .. tostring(added2))
  end
end

function TestUI:SimulateLootRoll(itemLink)
  if not itemLink or itemLink == "" then
    GLD:Print("Please enter an item link")
    return
  end

  local normalized = itemLink
  local wowheadId = itemLink:match("item=(%d+)")
  if wowheadId then
    normalized = "item:" .. wowheadId
  end

  if not normalized:find("|Hitem:") and normalized:find("^item:%d+") then
    normalized = "item:" .. normalized:match("item:(%d+)")
  end

  if normalized:find("^item:%d+") then
    GLD:RequestItemData(normalized)
  elseif normalized:find("|Hitem:") then
    GLD:RequestItemData(normalized)
  end

  local name, link, quality = GetItemInfo(normalized)
  local displayLink = link or normalized
  local displayName = name or "Test Item"

  local rollID = math.random(1, 10000)
  local rollTime = 120

  local session = {
    rollID = rollID,
    rollTime = rollTime,
    itemLink = displayLink,
    itemName = displayName,
    quality = quality or 4,
    canNeed = true,
    canGreed = true,
    canTransmog = true,
    votes = {},
  }

  GLD.activeRolls[rollID] = session

  if GLD.UI then
    GLD.UI:ShowRollPopup(session)
  end

  GLD:Print("Simulated loot roll: " .. displayLink)
end

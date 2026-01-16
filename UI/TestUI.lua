local _, NS = ...

local GLD = NS.GLD
local AceGUI = LibStub("AceGUI-3.0", true)

local TestUI = {}
NS.TestUI = TestUI

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
  frame:SetHeight(600)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

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

  frame:AddChild(sessionGroup)

  local playerGroup = AceGUI:Create("SimpleGroup")
  playerGroup:SetFullWidth(true)
  playerGroup:SetLayout("Flow")

  local playerLabel = AceGUI:Create("Heading")
  playerLabel:SetText("Player Management")
  playerLabel:SetFullWidth(true)
  playerGroup:AddChild(playerLabel)

  frame:AddChild(playerGroup)

  local rosterScroll = AceGUI:Create("ScrollFrame")
  rosterScroll:SetFullWidth(true)
  rosterScroll:SetHeight(250)
  rosterScroll:SetLayout("Flow")

  frame:AddChild(rosterScroll)

  local lootGroup = AceGUI:Create("SimpleGroup")
  lootGroup:SetFullWidth(true)
  lootGroup:SetLayout("Flow")

  local lootLabel = AceGUI:Create("Heading")
  lootLabel:SetText("Test Loot Choices")
  lootLabel:SetFullWidth(true)
  lootGroup:AddChild(lootLabel)

  local instanceSelect = AceGUI:Create("Dropdown")
  instanceSelect:SetLabel("Raid")
  instanceSelect:SetWidth(220)
  lootGroup:AddChild(instanceSelect)

  local encounterSelect = AceGUI:Create("Dropdown")
  encounterSelect:SetLabel("Encounter")
  encounterSelect:SetWidth(220)
  lootGroup:AddChild(encounterSelect)

  local loadLootBtn = AceGUI:Create("Button")
  loadLootBtn:SetText("Load Loot")
  loadLootBtn:SetWidth(120)
  lootGroup:AddChild(loadLootBtn)

  local itemLinkInput = AceGUI:Create("EditBox")
  itemLinkInput:SetLabel("Item Link")
  itemLinkInput:SetWidth(400)
  itemLinkInput:SetText("item:19345")
  lootGroup:AddChild(itemLinkInput)

  local dropBtn = AceGUI:Create("Button")
  dropBtn:SetText("Simulate Loot Roll")
  dropBtn:SetWidth(150)
  dropBtn:SetCallback("OnClick", function()
    TestUI:SimulateLootRoll(itemLinkInput:GetText())
  end)
  lootGroup:AddChild(dropBtn)

  frame:AddChild(lootGroup)

  local lootScroll = AceGUI:Create("ScrollFrame")
  lootScroll:SetFullWidth(true)
  lootScroll:SetHeight(140)
  lootScroll:SetLayout("Flow")

  frame:AddChild(lootGroup)
  frame:AddChild(lootScroll)

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

    local wonSpinner = AceGUI:Create("Spinner")
    wonSpinner:SetLabel("Won")
    wonSpinner:SetValue(player.numAccepted or 0)
    wonSpinner:SetWidth(100)
    wonSpinner:SetCallback("OnValueChanged", function(_, _, value)
      if GLD.db.players[playerKey] then
        GLD.db.players[playerKey].numAccepted = value
      end
    end)
    row:AddChild(wonSpinner)

    local raidsSpinner = AceGUI:Create("Spinner")
    raidsSpinner:SetLabel("Raids")
    raidsSpinner:SetValue(player.attendanceCount or 0)
    raidsSpinner:SetWidth(100)
    raidsSpinner:SetCallback("OnValueChanged", function(_, _, value)
      if GLD.db.players[playerKey] then
        GLD.db.players[playerKey].attendanceCount = value
      end
    end)
    row:AddChild(raidsSpinner)

    self.rosterScroll:AddChild(row)
  end

  self:RefreshInstanceList()
end

function TestUI:RefreshInstanceList()
  if not self.instanceSelect then
    return
  end

  local values = {}
  local order = {}

  local i = 1
  while true do
    local instanceID, name = EJ_GetInstanceByIndex(i, true)
    if not instanceID then
      break
    end
    values[instanceID] = name
    table.insert(order, instanceID)
    i = i + 1
  end

  self.instanceSelect:SetList(values, order)

  if not self.selectedInstance and order[1] then
    self.instanceSelect:SetValue(order[1])
    self:SelectInstance(order[1])
  end
end

function TestUI:SelectInstance(instanceID)
  if not instanceID then
    return
  end
  self.selectedInstance = instanceID
  EJ_SelectInstance(instanceID)

  local encounters = {}
  local order = {}
  local i = 1
  while true do
    local encounterID, name = EJ_GetEncounterInfoByIndex(i, instanceID)
    if not encounterID then
      break
    end
    encounters[encounterID] = name
    table.insert(order, encounterID)
    i = i + 1
  end

  self.encounterSelect:SetList(encounters, order)
  if order[1] then
    self.encounterSelect:SetValue(order[1])
    self:SelectEncounter(order[1])
  end
end

function TestUI:SelectEncounter(encounterID)
  self.selectedEncounter = encounterID
end

function TestUI:LoadEncounterLoot()
  if not self.selectedEncounter or not self.lootScroll then
    return
  end

  self.lootScroll:ReleaseChildren()
  EJ_SetLootFilter(0)

  local index = 1
  while true do
    local itemInfo = { EJ_GetLootInfoByIndex(index, self.selectedEncounter) }
    if not itemInfo[1] then
      break
    end

    local itemName, itemLink, itemQuality, itemLevel, _, _, _, _, icon = unpack(itemInfo)
    local iconButton = AceGUI:Create("Icon")
    iconButton:SetImage(icon)
    iconButton:SetImageSize(36, 36)
    iconButton:SetWidth(42)
    iconButton:SetHeight(42)
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
    self.lootScroll:AddChild(iconButton)

    index = index + 1
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

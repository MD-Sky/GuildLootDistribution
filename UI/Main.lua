local _, NS = ...

local GLD = NS.GLD
local AceGUI = LibStub("AceGUI-3.0", true)

local UI = {}
NS.UI = UI
GLD.UI = UI

function GLD:InitUI()
  if not AceGUI then
    return
  end
  UI.mainFrame = nil
  UI.rollFrame = nil
end

function UI:ToggleMain()
  if not self.mainFrame then
    self:CreateMainFrame()
  end
  if self.mainFrame:IsShown() then
    self.mainFrame:Hide()
  else
    self.mainFrame:Show()
    self:RefreshMain()
  end
end

function UI:CreateMainFrame()
  local frame = AceGUI:Create("Frame")
  frame:SetTitle("Guild Loot Distribution")
  frame:SetStatusText("GLD / Disloot")
  frame:SetWidth(800)
  frame:SetHeight(500)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

  local header = AceGUI:Create("Label")
  header:SetFullWidth(true)
  header:SetText("My Position: --")
  frame:AddChild(header)

  local adminButton = AceGUI:Create("Button")
  adminButton:SetText("Admin Panel")
  adminButton:SetWidth(120)
  adminButton:SetCallback("OnClick", function()
    if GLD:IsAdmin() then
      UI:OpenAdmin()
    else
      GLD:Print("you do not have Guild Permission to access this panel")
    end
  end)
  frame:AddChild(adminButton)

  local sessionStart = AceGUI:Create("Button")
  sessionStart:SetText("Start Session")
  sessionStart:SetWidth(120)
  sessionStart:SetCallback("OnClick", function()
    if GLD:IsAdmin() then
      GLD:StartSession()
      UI:RefreshMain()
    else
      GLD:Print("you do not have Guild Permission to access this panel")
    end
  end)
  frame:AddChild(sessionStart)

  local sessionEnd = AceGUI:Create("Button")
  sessionEnd:SetText("End Session")
  sessionEnd:SetWidth(120)
  sessionEnd:SetCallback("OnClick", function()
    if GLD:IsAdmin() then
      GLD:EndSession()
      UI:RefreshMain()
    else
      GLD:Print("you do not have Guild Permission to access this panel")
    end
  end)
  frame:AddChild(sessionEnd)

  local rosterGroup = AceGUI:Create("SimpleGroup")
  rosterGroup:SetFullWidth(true)
  rosterGroup:SetFullHeight(true)
  rosterGroup:SetLayout("Fill")

  local scroll = AceGUI:Create("ScrollFrame")
  scroll:SetLayout("Flow")
  rosterGroup:AddChild(scroll)

  frame:AddChild(rosterGroup)

  self.mainFrame = frame
  self.header = header
  self.scroll = scroll
end

function UI:RefreshMain()
  if not self.mainFrame then
    return
  end

  local isAdmin = GLD:IsAdmin()
  local myPos = "--"
  if isAdmin then
    local key = NS:GetPlayerKeyFromUnit("player")
    local player = key and GLD.db.players[key]
    if player and player.queuePos then
      myPos = tostring(player.queuePos)
    end
  else
    if GLD.shadow and GLD.shadow.my and GLD.shadow.my.queuePos then
      myPos = tostring(GLD.shadow.my.queuePos)
    end
  end

  self.header:SetText("My Position: " .. myPos)

  self.scroll:ReleaseChildren()

  local rows = self:GetRosterRows(isAdmin)
  for _, row in ipairs(rows) do
    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    label:SetText(row)
    self.scroll:AddChild(label)
  end
end

function UI:GetRosterRows(isAdmin)
  local rows = {}
  if isAdmin then
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
      if a.queuePos and b.queuePos then
        return a.queuePos < b.queuePos
      end
      if a.savedPos and b.savedPos then
        return a.savedPos < b.savedPos
      end
      return (a.name or "") < (b.name or "")
    end)

    for _, player in ipairs(list) do
      local role = NS:GetRoleForPlayer(player.name)
      local classIcon = NS:GetClassIcon(player.class)
      local roleIcon = NS:GetRoleIcon(role)
      local attendance = NS:ColorAttendance(player.attendance)
      local row = string.format("%s %s %s | Pos: %s | Prev: %s | Won: %s | Raids: %s | %s",
        classIcon,
        roleIcon,
        player.name or "?",
        player.queuePos or "-",
        player.savedPos or "-",
        player.numAccepted or 0,
        player.attendanceCount or 0,
        attendance
      )
      table.insert(rows, row)
    end
  else
    local roster = GLD.shadow and GLD.shadow.roster or {}
    local list = {}
    for _, entry in pairs(roster) do
      table.insert(list, entry)
    end
    table.sort(list, function(a, b)
      if a.queuePos and b.queuePos then
        return a.queuePos < b.queuePos
      end
      return (a.name or "") < (b.name or "")
    end)

    for _, entry in ipairs(list) do
      local role = entry.role or "NONE"
      local classIcon = NS:GetClassIcon(entry.class)
      local roleIcon = NS:GetRoleIcon(role)
      local attendance = NS:ColorAttendance(entry.attendance)
      local row = string.format("%s %s %s | Pos: %s | %s",
        classIcon,
        roleIcon,
        entry.name or "?",
        entry.queuePos or "-",
        attendance
      )
      table.insert(rows, row)
    end
  end

  if #rows == 0 then
    table.insert(rows, "No roster data")
  end

  return rows
end

function UI:ShowRollPopup(session)
  if not AceGUI then
    return
  end

  if self.rollFrame then
    self.rollFrame:Release()
  end

  local frame = AceGUI:Create("Frame")
  frame:SetTitle("Loot Roll")
  frame:SetStatusText(session.itemName or "Item")
  frame:SetWidth(400)
  frame:SetHeight(240)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

  local itemLabel = AceGUI:Create("Label")
  itemLabel:SetFullWidth(true)
  itemLabel:SetText(session.itemLink or session.itemName or "Unknown Item")
  frame:AddChild(itemLabel)

  local buttons = {
    { label = "Need", vote = "NEED" },
    { label = "Greed", vote = "GREED" },
    { label = "Transmog", vote = "TRANSMOG" },
    { label = "Pass", vote = "PASS" },
  }

  for _, btn in ipairs(buttons) do
    local button = AceGUI:Create("Button")
    button:SetText(btn.label)
    button:SetWidth(90)
    button:SetCallback("OnClick", function()
      session.votes = session.votes or {}
      local key = NS:GetPlayerKeyFromUnit("player")
      session.votes[key] = btn.vote
      GLD:SendCommMessageSafe(NS.MSG.ROLL_VOTE, {
        rollID = session.rollID,
        vote = btn.vote,
      }, "RAID")
      frame:Hide()
    end)
    frame:AddChild(button)
  end

  self.rollFrame = frame
end

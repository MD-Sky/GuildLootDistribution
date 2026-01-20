local _, NS = ...

local GLD = NS.GLD
local AceGUI = LibStub("AceGUI-3.0", true)

local UI = {}
NS.UI = UI
GLD.UI = UI

function GLD:InitUI()
  UI.mainFrame = nil
  UI.rollFrame = nil
  UI.rollFrames = nil
  UI.adminVoteFrame = nil
  UI.lastRollResult = nil
  UI.lastRollResultAt = nil
  UI.historyFrame = nil
  UI.debugFrame = nil
  UI.debugEditBox = nil
  UI.debugLines = {}
  UI.debugMaxLines = 400
  UI.historySelectedId = nil
  UI.filterText = ""
  UI.noteFilterText = ""
  UI.showOffline = true
  UI.showGuests = true
  UI.sortKey = "name"
  UI.sortAscending = true
  UI.guestAnchorsVisible = true
  UI.editRosterEnabled = false
  UI.enableNoteSearch = false
  UI.visibleRows = 18
  if not AceGUI then
    return
  end
end

function UI:ToggleMain()
  if not self.mainFrame then
    self:CreateMainFrame()
    self.mainFrame:Show()
    self:RefreshMain()
    return
  end
  if self.mainFrame:IsShown() then
    self.mainFrame:Hide()
  else
    self.mainFrame:Show()
    self:RefreshMain()
  end
end

function UI:CreateMainFrame()
  GLD:CreateMainFrame()
  self.mainFrame = GLD.UI and GLD.UI.mainFrame or nil
end

function UI:CreateDebugFrame()
  if not AceGUI or self.debugFrame then
    return
  end

  local frame = AceGUI:Create("Frame")
  frame:SetTitle("GuildLoot Debug")
  frame:SetStatusText("Debug output")
  frame:SetWidth(700)
  frame:SetHeight(420)
  frame:SetLayout("Fill")
  frame:EnableResize(true)
  if frame.frame and frame.frame.SetBackdrop then
    frame.frame:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame.frame:SetBackdropColor(0, 0, 0, 1)
  end

  frame:SetCallback("OnClose", function(widget)
    widget:Hide()
  end)

  local editBox = AceGUI:Create("MultiLineEditBox")
  editBox:SetLabel("")
  editBox:DisableButton(true)
  editBox:SetFullWidth(true)
  editBox:SetFullHeight(true)
  frame:AddChild(editBox)

  self.debugFrame = frame
  self.debugEditBox = editBox
  self:RefreshDebugLog()
end

function UI:ShowDebugFrame()
  if not self.debugFrame then
    self:CreateDebugFrame()
  end
  if self.debugFrame and not self.debugFrame:IsShown() then
    self.debugFrame:Show()
  end
  self:RefreshDebugLog()
end

function UI:ToggleDebugFrame()
  if not self.debugFrame then
    self:CreateDebugFrame()
    if self.debugFrame then
      self.debugFrame:Show()
    end
    self:RefreshDebugLog()
    return
  end
  if self.debugFrame:IsShown() then
    self.debugFrame:Hide()
  else
    self.debugFrame:Show()
    self:RefreshDebugLog()
  end
end

function UI:AppendDebugLine(msg)
  if msg == nil then
    return
  end
  self.debugLines = self.debugLines or {}
  table.insert(self.debugLines, tostring(msg))
  local maxLines = self.debugMaxLines or 400
  if #self.debugLines > maxLines then
    local overflow = #self.debugLines - maxLines
    for _ = 1, overflow do
      table.remove(self.debugLines, 1)
    end
  end
  if self.debugEditBox then
    self:RefreshDebugLog()
  end
end

function UI:RefreshDebugLog()
  if not self.debugEditBox then
    return
  end
  local lines = self.debugLines or {}
  local text = table.concat(lines, "\n")
  self.debugEditBox:SetText(text)
  if self.debugEditBox.SetCursorPosition then
    self.debugEditBox:SetCursorPosition(#text)
  end
  if self.debugEditBox.scrollFrame and self.debugEditBox.scrollFrame.GetVerticalScrollRange then
    self.debugEditBox.scrollFrame:SetVerticalScroll(self.debugEditBox.scrollFrame:GetVerticalScrollRange())
  end
  if self.debugFrame and self.debugFrame.SetStatusText then
    self.debugFrame:SetStatusText(string.format("Lines: %d", #lines))
  end
end

function UI:RefreshMain()
  if not self.mainFrame then
    return
  end

  if GLD.UpdateGuestAttendanceFromGroup then
    GLD:UpdateGuestAttendanceFromGroup()
  end

  if GLD.UpdateRosterStatusText then
    GLD:UpdateRosterStatusText()
  end

  if GLD.UpdateBottomBarPermissions then
    GLD:UpdateBottomBarPermissions()
  end

  if GLD.UpdateGuestPanelLayout then
    GLD:UpdateGuestPanelLayout()
  end

  if self.guestAnchorsVisible and GLD.RefreshGuestAnchors then
    GLD:RefreshGuestAnchors()
  end

  if GLD.RefreshTable then
    GLD:RefreshTable()
  end

  if self.RefreshLootWindow then
    self:RefreshLootWindow()
  end
end

function UI:ShowAdminVotePopup(session, pendingKeys, pendingLabels)
  if not AceGUI or not session then
    return
  end
  if not GLD:IsAuthority() then
    GLD:Print("Only the authority can apply admin votes.")
    return
  end

  if self.adminVoteFrame then
    self.adminVoteFrame:Release()
    self.adminVoteFrame = nil
  end

  local frame = AceGUI:Create("Frame")
  frame:SetTitle("Admin Vote Override")
  frame:SetStatusText(session.itemName or "Item")
  frame:SetWidth(360)
  frame:SetHeight(220)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

  local dropdown = AceGUI:Create("Dropdown")
  dropdown:SetLabel("Select Player")
  dropdown:SetFullWidth(true)
  local values = {}
  for i, key in ipairs(pendingKeys or {}) do
    local label = pendingLabels and pendingLabels[i] or tostring(key)
    values[key] = label
  end
  dropdown:SetList(values)
  if pendingKeys and pendingKeys[1] then
    dropdown:SetValue(pendingKeys[1])
  end
  frame:AddChild(dropdown)

  local function sendVote(vote)
    local key = dropdown:GetValue()
    if not key then
      GLD:Print("Select a player first.")
      return
    end
    GLD:HandleRollVote(UnitName("player") or "", {
      rollID = session.rollID,
      vote = vote,
      voterKey = key,
    })
    frame:Release()
  end

  local buttons = {
    { label = "Need", vote = "NEED" },
    { label = "Greed", vote = "GREED" },
    { label = "Transmog", vote = "TRANSMOG" },
    { label = "Pass", vote = "PASS" },
  }

  for _, btn in ipairs(buttons) do
    local b = AceGUI:Create("Button")
    b:SetText(btn.label)
    b:SetWidth(80)
    b:SetCallback("OnClick", function()
      sendVote(btn.vote)
    end)
    frame:AddChild(b)
  end

  self.adminVoteFrame = frame
end

-- Roster Manager-style UI ---------------------------------------------------
local ROSTER_ROW_HEIGHT = 20
local ROSTER_HEADER_HEIGHT = 22
local ROSTER_COLUMN_PADDING = 2
local ROSTER_ICON_SIZE = 16
local ROSTER_HEADER_AREA_HEIGHT = 36
local ROSTER_BOTTOM_BAR_HEIGHT = 78
local ROSTER_GUEST_PANEL_HEIGHT = 90
local GUILD_CREST_SIZE = 40
local GUILD_CREST_RETRY_DELAY = 0.5
local GUILD_CREST_MAX_RETRIES = 6
local GUILD_CREST_BACKGROUND_TEXTURE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local GUILD_CREST_SHOW_TABARD_BORDER = false
local GUILD_CREST_USE_TABARD_FILES = true
local GUILD_CREST_INNER_PADDING = 3
local GUILD_CREST_OFFSET_X = 0
local GUILD_CREST_OFFSET_Y = 0
local GUILD_CREST_EMBLEM_SCALE = 1
local GUILD_CREST_EMBLEM_OFFSET_X = -1
local GUILD_CREST_EMBLEM_OFFSET_Y = 3
local GUILD_CREST_EMBLEM_ZOOM = 0.08
local GUILD_CREST_USE_MASK = true
local MAIN_FRAME_HORIZONTAL_PADDING = 32 -- 16 left + 16 right margins
local HEADER_ROW_HORIZONTAL_PADDING = 30 -- 6 left + 24 right margins inside the inset
local MIN_MAIN_FRAME_WIDTH = 520

local function AddSpecialFrame(name)
  if not name then
    return
  end
  if not UISpecialFrames then
    UISpecialFrames = {}
  end
  for _, existing in ipairs(UISpecialFrames) do
    if existing == name then
      return
    end
  end
  table.insert(UISpecialFrames, name)
end

local function SafeRegisterEvent(frame, event)
  if not frame or not event then
    return false
  end
  local ok = pcall(frame.RegisterEvent, frame, event)
  return ok
end

local function BuildDefaultRosterColumns()
  return {
    { key = "class", label = "Class", width = 32, align = "CENTER", isIcon = true },
    { key = "spec", label = "Spec", width = 32, align = "CENTER", isIcon = true },
    { key = "role", label = "Role", width = 60, align = "CENTER" },
    { key = "name", label = "Name", width = 190, align = "LEFT", sortKey = "name" },
    { key = "queuePos", label = "Queue Pos", width = 72, align = "CENTER", sortKey = "queuePos" },
    { key = "heldPos", label = "Held Pos", width = 72, align = "CENTER", sortKey = "heldPos" },
    { key = "itemsWon", label = "Items Won", width = 80, align = "CENTER", sortKey = "itemsWon" },
    { key = "raidsAttended", label = "Raids Attended", width = 110, align = "CENTER", sortKey = "raidsAttended" },
    { key = "attendance", label = "Attendance", width = 90, align = "CENTER", sortKey = "attendance" },
  }
end

local function CalculateMainFrameWidth(columns)
  if not columns or #columns == 0 then
    return nil
  end
  local x = 4
  local maxRight = 0
  for _, col in ipairs(columns) do
    local width = (col and col.width) or 0
    local right = x + width
    if right > maxRight then
      maxRight = right
    end
    x = x + width + ROSTER_COLUMN_PADDING
  end
  if maxRight <= 0 then
    return nil
  end
  return math.max(MIN_MAIN_FRAME_WIDTH, maxRight + HEADER_ROW_HORIZONTAL_PADDING + MAIN_FRAME_HORIZONTAL_PADDING)
end

local function SetEditBoxEnabled(editBox, enabled)
  if not editBox then
    return
  end
  if editBox.SetEnabled then
    editBox:SetEnabled(enabled)
  else
    editBox:EnableMouse(enabled)
  end
  if editBox.SetTextColor then
    if enabled then
      editBox:SetTextColor(1, 1, 1)
    else
      editBox:SetTextColor(0.6, 0.6, 0.6)
    end
  end
end

local function ParseNonNegativeInt(text)
  local num = tonumber(text)
  if not num or num < 0 then
    return nil
  end
  if math.floor(num) ~= num then
    return nil
  end
  return num
end

local function NormalizeAttendanceInput(text)
  local key = (text or ""):upper()
  if key == "P" then
    return "PRESENT"
  end
  if key == "A" then
    return "ABSENT"
  end
  if key == "PART" then
    return "PARTIAL"
  end
  if key == "PRESENT" or key == "ABSENT" or key == "PARTIAL" or key == "OFFLINE" then
    return key
  end
  return nil
end

local function SetCheckLabel(check, text)
  if check.Text then
    check.Text:SetText(text)
  elseif check.text then
    check.text:SetText(text)
  end
end

local function DebugGuildCrest(frame, msg)
  if not GLD or not GLD.Debug then
    return
  end
  if frame then
    if frame.guildCrestDebugState == msg then
      return
    end
    frame.guildCrestDebugState = msg
  end
  GLD:Debug("Guild crest: " .. msg)
end

local function FormatFrameSize(frame)
  if not frame or not frame.GetSize then
    return "0x0"
  end
  local width, height = frame:GetSize()
  return string.format("%.1fx%.1f", width or 0, height or 0)
end

local function FormatFramePoint(frame)
  if not frame or not frame.GetPoint then
    return "none"
  end
  local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
  if not point then
    return "none"
  end
  local relativeName = relativeTo and relativeTo.GetName and relativeTo:GetName() or tostring(relativeTo)
  return string.format("%s %s %s %.1f %.1f", tostring(point), tostring(relativeName), tostring(relativePoint), x or 0, y or 0)
end

local function NormalizeTexCoordValues(a, b, c, d, e, f, g, h)
  if e == nil then
    local left, right, top, bottom = a, b, c, d
    return left, top, left, bottom, right, top, right, bottom
  end
  return a, b, c, d, e, f, g, h
end

local function FormatTexCoordValues(a, b, c, d, e, f, g, h)
  a, b, c, d, e, f, g, h = NormalizeTexCoordValues(a, b, c, d, e, f, g, h)
  return string.format(
    "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
    a or 0,
    b or 0,
    c or 0,
    d or 0,
    e or 0,
    f or 0,
    g or 0,
    h or 0
  )
end

local function DebugTextureState(label, texture)
  if not texture then
    GLD:Debug(label .. "=nil")
    return
  end
  local width, height = texture:GetSize()
  local a, b, c, d, e, f, g, h = texture:GetTexCoord()
  local point, relativeTo, relativePoint, x, y = texture:GetPoint(1)
  local relativeName = relativeTo and relativeTo.GetName and relativeTo:GetName() or tostring(relativeTo)
  local layer, sublevel = texture:GetDrawLayer()
  local atlas = texture.GetAtlas and texture:GetAtlas() or nil
  GLD:Debug(
    label
      .. " tex="
      .. tostring(texture:GetTexture())
      .. " atlas="
      .. tostring(atlas)
      .. " size="
      .. string.format("%.1fx%.1f", width or 0, height or 0)
      .. " shown="
      .. tostring(texture:IsShown())
      .. " layer="
      .. tostring(layer)
      .. ":"
      .. tostring(sublevel)
      .. " coord="
      .. FormatTexCoordValues(a, b, c, d, e, f, g, h)
      .. " point="
      .. string.format(
        "%s %s %s %.1f %.1f",
        tostring(point),
        tostring(relativeName),
        tostring(relativePoint),
        x or 0,
        y or 0
      )
  )
end

local function IsTexCoordValid(texture)
  if not texture or not texture.GetTexCoord then
    return false
  end
  local left, right, top, bottom = texture:GetTexCoord()
  if not left or not right or not top or not bottom then
    return false
  end
  if right <= left or bottom <= top then
    return false
  end
  return true
end

local function EnsureFullTexCoord(texture, label, crest)
  if not texture then
    return
  end
  local left, right, top, bottom = texture:GetTexCoord()
  if left ~= 0 or right ~= 1 or top ~= 0 or bottom ~= 1 then
    texture:SetTexCoord(0, 1, 0, 1)
    DebugGuildCrest(
      crest and crest.ownerFrame,
      (label or "texture") .. " texcoord reset from " .. FormatTexCoordValues(left, right, top, bottom)
    )
  end
end

local function FindBlizzardEmblemTexture()
  local function TextureHasData(texture)
    if not texture or not texture.GetTexture then
      return false
    end
    local tex = texture:GetTexture()
    local atlas = texture.GetAtlas and texture:GetAtlas() or nil
    return tex ~= nil or atlas ~= nil
  end

  local function FindEmblemInFrame(frame, frameLabel)
    if not frame then
      return nil, nil
    end
    local keys = {
      "Emblem",
      "EmblemTexture",
      "TabardEmblem",
      "TabardEmblemTexture",
    }
    for _, key in ipairs(keys) do
      local tex = frame[key]
      if TextureHasData(tex) then
        return frameLabel .. "." .. key, tex
      end
    end
    if frame.GetRegions then
      local regions = { frame:GetRegions() }
      for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" then
          local name = region.GetName and region:GetName() or nil
          if name and name:find("Emblem") and TextureHasData(region) then
            return name, region
          end
        end
      end
    end
    return nil, nil
  end

  local candidates = {
    { name = "GuildFrameTabardEmblem", texture = _G.GuildFrameTabardEmblem },
    { name = "GuildFrameTabardEmblemTexture", texture = _G.GuildFrameTabardEmblemTexture },
    { name = "GuildFrameTabard.Emblem", texture = _G.GuildFrameTabard and _G.GuildFrameTabard.Emblem },
    { name = "GuildFrameTabard.EmblemTexture", texture = _G.GuildFrameTabard and _G.GuildFrameTabard.EmblemTexture },
    { name = "GuildFrameTabard.TabardEmblem", texture = _G.GuildFrameTabard and _G.GuildFrameTabard.TabardEmblem },
    { name = "TabardFrame.Emblem", texture = _G.TabardFrame and _G.TabardFrame.Emblem },
    { name = "TabardFrame.EmblemTexture", texture = _G.TabardFrame and _G.TabardFrame.EmblemTexture },
    {
      name = "CommunitiesFrame.GuildDetailsFrame.TabardFrame.Emblem",
      texture = _G.CommunitiesFrame
        and _G.CommunitiesFrame.GuildDetailsFrame
        and _G.CommunitiesFrame.GuildDetailsFrame.TabardFrame
        and _G.CommunitiesFrame.GuildDetailsFrame.TabardFrame.Emblem,
    },
    {
      name = "CommunitiesFrame.GuildDetailsFrame.TabardFrame.EmblemTexture",
      texture = _G.CommunitiesFrame
        and _G.CommunitiesFrame.GuildDetailsFrame
        and _G.CommunitiesFrame.GuildDetailsFrame.TabardFrame
        and _G.CommunitiesFrame.GuildDetailsFrame.TabardFrame.EmblemTexture,
    },
  }
  for _, candidate in ipairs(candidates) do
    local texture = candidate.texture
    if TextureHasData(texture) then
      return candidate.name, texture
    end
  end
  local name, texture = FindEmblemInFrame(_G.GuildFrameTabard, "GuildFrameTabard")
  if texture then
    return name, texture
  end
  name, texture = FindEmblemInFrame(_G.TabardFrame, "TabardFrame")
  if texture then
    return name, texture
  end
  if _G.CommunitiesFrame and _G.CommunitiesFrame.GuildDetailsFrame then
    name, texture = FindEmblemInFrame(_G.CommunitiesFrame.GuildDetailsFrame.TabardFrame, "CommunitiesFrame.GuildDetailsFrame.TabardFrame")
    if texture then
      return name, texture
    end
  end
  for name, obj in pairs(_G) do
    if type(name) == "string"
      and name:find("Tabard")
      and name:find("Emblem")
      and not name:find("Top")
      and not name:find("Bottom")
      and not name:find("Left")
      and not name:find("Right")
      and obj
      and obj.GetObjectType
    then
      if obj:GetObjectType() == "Texture" and TextureHasData(obj) then
        return name, obj
      end
    end
  end
  return nil, nil
end

local function DebugEmblemState(crest, tag)
  if not GLD or not GLD.IsDebugEnabled or not GLD:IsDebugEnabled() then
    return
  end
  if not crest then
    return
  end
  local key = tostring(tag)
  if crest.lastEmblemDebugTag == key then
    return
  end
  crest.lastEmblemDebugTag = key
  local ownerName = crest.ownerFrame and crest.ownerFrame.GetName and crest.ownerFrame:GetName() or tostring(crest.ownerFrame)
  GLD:Debug("Guild crest: emblem dump (" .. key .. ") owner=" .. tostring(ownerName))
  GLD:Debug("Guild crest: crest size=" .. FormatFrameSize(crest) .. " point=" .. FormatFramePoint(crest))
  if crest.anchorFrame then
    local anchorName = crest.anchorFrame.GetName and crest.anchorFrame:GetName() or tostring(crest.anchorFrame)
    GLD:Debug(
      "Guild crest: anchor="
        .. tostring(anchorName)
        .. " size="
        .. FormatFrameSize(crest.anchorFrame)
        .. " point="
        .. FormatFramePoint(crest.anchorFrame)
    )
  end
  DebugTextureState("Guild crest: emblem", crest.TabardEmblem)
  DebugTextureState("Guild crest: emblemUpper", crest.TabardEmblemUpper)
  DebugTextureState("Guild crest: emblemLower", crest.TabardEmblemLower)
  DebugTextureState("Guild crest: background", crest.TabardBackground)
  DebugTextureState("Guild crest: mask", crest.Mask)
  local blizzardName, blizzardEmblem = FindBlizzardEmblemTexture()
  if blizzardEmblem then
    DebugTextureState("Guild crest: blizzard emblem (" .. tostring(blizzardName) .. ")", blizzardEmblem)
  else
    GLD:Debug("Guild crest: blizzard emblem not found")
  end
  local emblemTex = crest.TabardEmblem or crest.TabardEmblemUpper or crest.TabardEmblemLower
  if emblemTex and crest.GetSize and crest.GetPoint and emblemTex.GetSize and emblemTex.GetPoint then
    print("CrestHolder", crest:GetSize(), crest:GetPoint(1))
    print("Emblem", emblemTex:GetSize(), emblemTex:GetPoint(1))
  end
end

local function GetGuildTabardColor(color, defaultR, defaultG, defaultB)
  if not color then
    return defaultR, defaultG, defaultB
  end
  if type(color) == "table" then
    if color.GetRGB then
      return color:GetRGB()
    end
    if color.r and color.g and color.b then
      return color.r, color.g, color.b
    end
    if color[1] and color[2] and color[3] then
      return color[1], color[2], color[3]
    end
  end
  return defaultR, defaultG, defaultB
end

local function GetGuildTabardInfoCompat(unit)
  if C_GuildInfo and C_GuildInfo.GetGuildTabardInfo then
    return C_GuildInfo.GetGuildTabardInfo(unit)
  end
  if GetGuildTabardInfo then
    local ok, a, b, c, d, e, f = pcall(GetGuildTabardInfo, unit)
    if not ok then
      return nil
    end
    if type(a) == "table" then
      return a
    end
    if a == nil and b == nil and c == nil and d == nil and e == nil and f == nil then
      return nil
    end
    return {
      backgroundFileID = a,
      borderFileID = b,
      emblemFileID = c,
      backgroundColor = d,
      borderColor = e,
      emblemColor = f,
    }
  end
  return nil
end

local function FormatGuildTabardColor(color)
  if not color then
    return "nil"
  end
  if type(color) == "table" then
    if color.GetRGB then
      local r, g, b = color:GetRGB()
      return string.format("%.2f,%.2f,%.2f", r, g, b)
    end
    if color.r and color.g and color.b then
      return string.format("%.2f,%.2f,%.2f", color.r, color.g, color.b)
    end
    if color[1] and color[2] and color[3] then
      return string.format("%.2f,%.2f,%.2f", color[1], color[2], color[3])
    end
  end
  return tostring(color)
end

local function FormatTabardFiles(results)
  if not results or #results == 0 then
    return "none"
  end
  local parts = {}
  for i = 1, #results do
    parts[i] = tostring(results[i])
  end
  return table.concat(parts, ",")
end

local function ResolvePortraitAnchor(frame)
  if not frame then
    return nil
  end
  if frame.PortraitFrame then
    return frame.PortraitFrame.Portrait or frame.PortraitFrame
  end
  if frame.portrait then
    return frame.portrait
  end
  if frame.Portrait then
    return frame.Portrait
  end
  local name = frame.GetName and frame:GetName()
  if name then
    return _G[name .. "Portrait"] or _G[name .. "PortraitFrame"] or _G[name .. "PortraitFramePortrait"]
  end
  return nil
end

local function ResolvePortraitParent(anchor, frame)
  if not anchor then
    return frame
  end
  if anchor.GetObjectType and anchor:GetObjectType() == "Texture" then
    return anchor:GetParent() or frame
  end
  return anchor
end

local function ApplyCrestMask(crest)
  if not crest or not crest.Mask or not GUILD_CREST_USE_MASK then
    return
  end
  if crest.maskApplied then
    return
  end
  local mask = crest.Mask
  local textures = {
    crest.TabardBackground,
    crest.TabardBorder,
    crest.TabardEmblem,
    crest.TabardBackgroundUpper,
    crest.TabardBackgroundLower,
    crest.TabardEmblemUpper,
    crest.TabardEmblemLower,
    crest.TabardBorderUpper,
    crest.TabardBorderLower,
  }
  for _, tex in ipairs(textures) do
    if tex and tex.AddMaskTexture then
      tex:AddMaskTexture(mask)
    end
  end
  crest.maskApplied = true
end

local function UpdateCrestLayout(crest, anchor)
  if not crest then
    return
  end
  local size = GUILD_CREST_SIZE
  if anchor and anchor.GetWidth and anchor.GetHeight then
    local width = anchor:GetWidth()
    local height = anchor:GetHeight()
    if width and height and width > 0 and height > 0 then
      size = math.min(width, height)
    end
  end
  if GUILD_CREST_INNER_PADDING and GUILD_CREST_INNER_PADDING > 0 then
    size = math.max(1, size - (GUILD_CREST_INNER_PADDING * 2))
  end
  crest:SetSize(size, size)
  local emblemScale = tonumber(GUILD_CREST_EMBLEM_SCALE) or 1
  local emblemOffsetX = tonumber(GUILD_CREST_EMBLEM_OFFSET_X) or 0
  local emblemOffsetY = tonumber(GUILD_CREST_EMBLEM_OFFSET_Y) or 0
  if emblemScale <= 0 then
    emblemScale = 1
  end
  local emblemWidth = math.max(1, size * emblemScale)
  local emblemHeight = math.max(1, size * emblemScale)
  local emblemHalfHeight = emblemHeight / 2
  local emblemQuarterHeight = emblemHeight / 4

  local function SetupFull(tex)
    if not tex then
      return
    end
    tex:ClearAllPoints()
    tex:SetAllPoints(crest)
    tex:SetTexCoord(0, 1, 0, 1)
  end

  local function SetupHalf(tex, position)
    if not tex then
      return
    end
    tex:ClearAllPoints()
    if position == "TOP" then
      tex:SetPoint("TOPLEFT", crest, "TOPLEFT", 0, 0)
      tex:SetPoint("TOPRIGHT", crest, "TOPRIGHT", 0, 0)
      tex:SetHeight(size / 2)
    else
      tex:SetPoint("BOTTOMLEFT", crest, "BOTTOMLEFT", 0, 0)
      tex:SetPoint("BOTTOMRIGHT", crest, "BOTTOMRIGHT", 0, 0)
      tex:SetHeight(size / 2)
    end
    tex:SetTexCoord(0, 1, 0, 1)
  end

  local function SetupEmblemFull(tex)
    if not tex then
      return
    end
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", crest, "CENTER", emblemOffsetX, emblemOffsetY)
    tex:SetSize(emblemWidth, emblemHeight)
  end

  local function SetupEmblemHalf(tex, position)
    if not tex then
      return
    end
    tex:ClearAllPoints()
    if position == "TOP" then
      tex:SetPoint("CENTER", crest, "CENTER", emblemOffsetX, emblemOffsetY + emblemQuarterHeight)
    else
      tex:SetPoint("CENTER", crest, "CENTER", emblemOffsetX, emblemOffsetY - emblemQuarterHeight)
    end
    tex:SetSize(emblemWidth, emblemHalfHeight)
  end

  SetupFull(crest.TabardBackground)
  SetupFull(crest.TabardBorder)
  SetupEmblemFull(crest.TabardEmblem)
  SetupHalf(crest.TabardBackgroundUpper, "TOP")
  SetupHalf(crest.TabardBackgroundLower, "BOTTOM")
  SetupEmblemHalf(crest.TabardEmblemUpper, "TOP")
  SetupEmblemHalf(crest.TabardEmblemLower, "BOTTOM")
  SetupFull(crest.TabardBorderUpper)
  SetupFull(crest.TabardBorderLower)
  if crest.Mask then
    crest.Mask:ClearAllPoints()
    crest.Mask:SetAllPoints(crest)
    crest.Mask:SetTexCoord(0, 1, 0, 1)
  end
  ApplyCrestMask(crest)
end

local function SetTabardTexturePiece(texture, fileID, r, g, b, show)
  if not texture then
    return false
  end
  if not fileID or fileID == 0 then
    texture:Hide()
    return false
  end
  texture:SetTexture(fileID)
  EnsureFullTexCoord(texture, "tabard-piece", texture and texture:GetParent())
  if r and g and b then
    texture:SetVertexColor(r, g, b, 1)
  end
  if show then
    texture:Show()
  else
    texture:Hide()
  end
  return true
end

local function GetEmblemTexCoord(emblemTexture)
  if not emblemTexture or not C_Texture or not C_Texture.GetTextureInfo then
    return 0, 1, 0, 1
  end
  local ok, width, height = pcall(C_Texture.GetTextureInfo, emblemTexture)
  if not ok then
    return 0, 1, 0, 1
  end
  if type(width) == "table" then
    local info = width
    width = info.width or info[1]
    height = info.height or info[2]
  end
  if not width or not height or height <= 0 then
    return 0, 1, 0, 1
  end
  -- Some emblem textures are 2x1 with the emblem art on the right half.
  if (width / height) >= 1.5 then
    return 0.5, 1, 0, 1
  end
  return 0, 1, 0, 1
end

local function TexCoordsEqual(a, b)
  if not a or not b or #a ~= #b then
    return false
  end
  for i = 1, #a do
    if math.abs((a[i] or 0) - (b[i] or 0)) > 0.0001 then
      return false
    end
  end
  return true
end

local function ApplyEmblemZoomToTexture(texture)
  if not texture or not texture.GetTexCoord or not texture.SetTexCoord then
    return
  end
  local zoom = tonumber(GUILD_CREST_EMBLEM_ZOOM) or 0
  if zoom <= 0 then
    return
  end
  if zoom > 0.49 then
    zoom = 0.49
  end
  local a, b, c, d, e, f, g, h = texture:GetTexCoord()
  a, b, c, d, e, f, g, h = NormalizeTexCoordValues(a, b, c, d, e, f, g, h)
  local current = { a, b, c, d, e, f, g, h }
  if texture.gldZoomedTexCoord and TexCoordsEqual(texture.gldZoomedTexCoord, current) then
    return
  end
  local minX = math.min(a, c, e, g)
  local maxX = math.max(a, c, e, g)
  local minY = math.min(b, d, f, h)
  local maxY = math.max(b, d, f, h)
  if minX == maxX or minY == maxY then
    return
  end
  local scale = 1 - (zoom * 2)
  if scale <= 0 then
    return
  end
  local centerX = (minX + maxX) * 0.5
  local centerY = (minY + maxY) * 0.5
  local function scaleX(x)
    return centerX + (x - centerX) * scale
  end
  local function scaleY(y)
    return centerY + (y - centerY) * scale
  end
  local na, nb, nc, nd, ne, nf, ng, nh =
    scaleX(a), scaleY(b), scaleX(c), scaleY(d), scaleX(e), scaleY(f), scaleX(g), scaleY(h)
  texture:SetTexCoord(na, nb, nc, nd, ne, nf, ng, nh)
  texture.gldZoomedTexCoord = { na, nb, nc, nd, ne, nf, ng, nh }
end

local function ApplyEmblemZoom(crest)
  if not crest then
    return
  end
  local hasSingle = crest.TabardEmblem and crest.TabardEmblem:GetTexture()
  local hasPieces = (crest.TabardEmblemUpper and crest.TabardEmblemUpper:GetTexture())
    or (crest.TabardEmblemLower and crest.TabardEmblemLower:GetTexture())
  if hasSingle and not hasPieces then
    ApplyEmblemZoomToTexture(crest.TabardEmblem)
  end
end

local function ApplyGuildEmblemTexture(crest, emblemTexture, r, g, b)
  if not crest or not crest.TabardEmblem then
    return false
  end
  local emblem = crest.TabardEmblem
  emblem:ClearAllPoints()
  emblem:SetAllPoints(crest)
  emblem:SetTexture(emblemTexture)
  local left, right, top, bottom = GetEmblemTexCoord(emblemTexture)
  emblem:SetTexCoord(left, right, top, bottom)
  if r and g and b then
    emblem:SetVertexColor(r, g, b, 1)
  end
  ApplyEmblemZoomToTexture(emblem)
  local a, b, c, d, e, f, g, h = emblem:GetTexCoord()
  print("emblem texcoord", FormatTexCoordValues(a, b, c, d, e, f, g, h))
  emblem:Show()
  return emblem:GetTexture() ~= nil
end

local function HideTabardSingles(crest)
  if not crest then
    return
  end
  if crest.TabardBackground then
    crest.TabardBackground:Hide()
  end
  if crest.TabardEmblem then
    crest.TabardEmblem:Hide()
  end
  if crest.TabardBorder then
    crest.TabardBorder:Hide()
  end
end

local function HideTabardPieces(crest)
  if not crest then
    return
  end
  if crest.TabardBackgroundUpper then
    crest.TabardBackgroundUpper:Hide()
  end
  if crest.TabardBackgroundLower then
    crest.TabardBackgroundLower:Hide()
  end
  if crest.TabardEmblemUpper then
    crest.TabardEmblemUpper:Hide()
  end
  if crest.TabardEmblemLower then
    crest.TabardEmblemLower:Hide()
  end
  if crest.TabardBorderUpper then
    crest.TabardBorderUpper:Hide()
  end
  if crest.TabardBorderLower then
    crest.TabardBorderLower:Hide()
  end
end

local function HideEmblemSingles(crest)
  if not crest then
    return
  end
  if crest.TabardEmblem then
    crest.TabardEmblem:Hide()
  end
end

local function TrySetGuildCrestFromTabardFiles(crest, unit)
  if not GetGuildTabardFiles then
    DebugGuildCrest(crest and crest.ownerFrame, "GetGuildTabardFiles missing")
    return false
  end

  local results = { pcall(GetGuildTabardFiles) }
  local ok = table.remove(results, 1)
  if (not ok or #results == 0) and unit then
    local unitResults = { pcall(GetGuildTabardFiles, unit) }
    local unitOk = table.remove(unitResults, 1)
    if unitOk and #unitResults > 0 then
      results = unitResults
      ok = true
    end
  end
  if not ok then
    DebugGuildCrest(crest and crest.ownerFrame, "GetGuildTabardFiles error")
    return false
  end
  if #results == 0 then
    DebugGuildCrest(crest and crest.ownerFrame, "GetGuildTabardFiles returned no files")
    return false
  end
  DebugGuildCrest(
    crest and crest.ownerFrame,
    "GetGuildTabardFiles count=" .. tostring(#results) .. " files=" .. FormatTabardFiles(results)
  )

  local info = GetGuildTabardInfoCompat("player")
  local bgR, bgG, bgB = GetGuildTabardColor(info and info.backgroundColor, 0, 0, 0)
  local emR, emG, emB = GetGuildTabardColor(info and info.emblemColor, 1, 1, 1)
  local brR, brG, brB = GetGuildTabardColor(info and info.borderColor, 1, 1, 1)

  local appliedEmblem = false
  if #results >= 6 then
    local bgUpper, bgLower, borderUpper, borderLower, emblemUpper, emblemLower =
      results[1], results[2], results[3], results[4], results[5], results[6]
    HideTabardSingles(crest)
    SetTabardTexturePiece(crest.TabardBackgroundUpper, bgUpper, bgR, bgG, bgB, true)
    SetTabardTexturePiece(crest.TabardBackgroundLower, bgLower, bgR, bgG, bgB, true)
    local hasEmblemUpper = SetTabardTexturePiece(crest.TabardEmblemUpper, emblemUpper, emR, emG, emB, true)
    local hasEmblemLower = SetTabardTexturePiece(crest.TabardEmblemLower, emblemLower, emR, emG, emB, true)
    appliedEmblem = hasEmblemUpper and hasEmblemLower
    ApplyEmblemZoom(crest)
    DebugEmblemState(
      crest,
      "tabard-files-upper-lower:" .. tostring(emblemUpper) .. ":" .. tostring(emblemLower)
    )
    SetTabardTexturePiece(crest.TabardBorderUpper, borderUpper, brR, brG, brB, GUILD_CREST_SHOW_TABARD_BORDER)
    SetTabardTexturePiece(crest.TabardBorderLower, borderLower, brR, brG, brB, GUILD_CREST_SHOW_TABARD_BORDER)
  else
    local bgFile, borderFile, emblemFile = results[1], results[2], results[3]
    HideTabardPieces(crest)
    SetTabardTexturePiece(crest.TabardBackground, bgFile, bgR, bgG, bgB, true)
    appliedEmblem = SetTabardTexturePiece(crest.TabardEmblem, emblemFile, emR, emG, emB, true)
    ApplyEmblemZoom(crest)
    DebugEmblemState(crest, "tabard-files-single:" .. tostring(emblemFile))
    SetTabardTexturePiece(crest.TabardBorder, borderFile, brR, brG, brB, GUILD_CREST_SHOW_TABARD_BORDER)
  end

  if appliedEmblem then
    DebugGuildCrest(
      crest and crest.ownerFrame,
      "applied tabard files count=" .. tostring(#results) .. " bg=" .. FormatGuildTabardColor(info and info.backgroundColor)
        .. " em=" .. FormatGuildTabardColor(info and info.emblemColor)
    )
    return true
  end

  DebugGuildCrest(
    crest and crest.ownerFrame,
    "tabard files missing emblem piece count=" .. tostring(#results)
  )
  return false
end

local function TrySetGuildCrestEmblemFromTabardFiles(crest, unit)
  if not GetGuildTabardFiles then
    return false
  end
  local results = { pcall(GetGuildTabardFiles, unit or "player") }
  local ok = table.remove(results, 1)
  if not ok or #results < 6 then
    return false
  end

  local emblemUpper, emblemLower = results[5], results[6]
  local info = GetGuildTabardInfoCompat("player")
  local emR, emG, emB = GetGuildTabardColor(info and info.emblemColor, 1, 1, 1)

  HideTabardPieces(crest)
  HideEmblemSingles(crest)
  local hasUpper = SetTabardTexturePiece(crest.TabardEmblemUpper, emblemUpper, emR, emG, emB, true)
  local hasLower = SetTabardTexturePiece(crest.TabardEmblemLower, emblemLower, emR, emG, emB, true)
  if hasUpper and hasLower then
    ApplyEmblemZoom(crest)
    DebugGuildCrest(
      crest and crest.ownerFrame,
      "applied emblem pieces from tabard files upper=" .. tostring(emblemUpper) .. " lower=" .. tostring(emblemLower)
    )
    DebugEmblemState(crest, "tabard-files-emblem-only:" .. tostring(emblemUpper) .. ":" .. tostring(emblemLower))
    return true
  end
  return false
end

local function TrySetGuildCrestFromTabardInfo(crest, unit)
  if not crest then
    DebugGuildCrest(crest and crest.ownerFrame, "missing crest")
    return false
  end

  local info = GetGuildTabardInfoCompat(unit)
  if not info then
    DebugGuildCrest(crest.ownerFrame, "tabard info nil")
    return false
  end

  local emblemTexture = info.emblemFileID or info.emblemTexture or info.emblemFile
  if not emblemTexture or (type(emblemTexture) == "number" and emblemTexture == 0) then
    DebugGuildCrest(crest.ownerFrame, "tabard info missing emblem file id: " .. tostring(emblemTexture))
    return false
  end

  local bgR, bgG, bgB = GetGuildTabardColor(info.backgroundColor, 0, 0, 0)
  local emR, emG, emB = GetGuildTabardColor(info.emblemColor, 1, 1, 1)

  HideTabardPieces(crest)
  if crest.TabardBackground then
    crest.TabardBackground:SetTexture(GUILD_CREST_BACKGROUND_TEXTURE)
    EnsureFullTexCoord(crest.TabardBackground, "background", crest)
    crest.TabardBackground:SetVertexColor(bgR, bgG, bgB, 1)
    crest.TabardBackground:Show()
  end
  local hasEmblem = ApplyGuildEmblemTexture(crest, emblemTexture, emR, emG, emB)
  if crest.TabardBorder then
    crest.TabardBorder:Hide()
  end
  if hasEmblem then
    ApplyEmblemZoom(crest)
    DebugGuildCrest(
      crest.ownerFrame,
      "applied emblem=" .. tostring(emblemTexture) .. " bg=" .. FormatGuildTabardColor(info.backgroundColor)
        .. " em=" .. FormatGuildTabardColor(info.emblemColor)
    )
    DebugEmblemState(crest, "tabard-info:" .. tostring(emblemTexture))
  else
    DebugGuildCrest(crest.ownerFrame, "emblem texture missing after apply: " .. tostring(emblemTexture))
    DebugEmblemState(crest, "tabard-info-missing:" .. tostring(emblemTexture))
    return false
  end
  return true
end

local function TrySetGuildCrestFromHelpers(crest, unit)
  if SetLargeGuildTabardTextures then
    if crest and crest.TabardEmblem and crest.TabardBackground and crest.TabardBorder then
      if pcall(SetLargeGuildTabardTextures, unit or "player", crest.TabardEmblem, crest.TabardBackground, crest.TabardBorder) then
        local hasEmblem = crest.TabardEmblem and crest.TabardEmblem:GetTexture()
        if hasEmblem then
          HideTabardPieces(crest)
          if not GUILD_CREST_SHOW_TABARD_BORDER and crest.TabardBorder then
            crest.TabardBorder:Hide()
          end
          ApplyEmblemZoom(crest)
          DebugGuildCrest(crest and crest.ownerFrame, "applied SetLargeGuildTabardTextures (textures)")
          DebugEmblemState(crest, "helper-large-textures")
          return true
        end
      end
    end
    if pcall(SetLargeGuildTabardTextures, crest, unit) or pcall(SetLargeGuildTabardTextures, unit, crest) then
      local hasEmblem = (crest.TabardEmblem and crest.TabardEmblem:GetTexture())
        or (crest.TabardEmblemUpper and crest.TabardEmblemUpper:GetTexture())
      if hasEmblem then
        if crest.TabardEmblemUpper and crest.TabardEmblemUpper:GetTexture() then
          HideTabardSingles(crest)
        elseif crest.TabardEmblem and crest.TabardEmblem:GetTexture() then
          HideTabardPieces(crest)
        end
        ApplyEmblemZoom(crest)
        DebugGuildCrest(crest and crest.ownerFrame, "applied SetLargeGuildTabardTextures")
        DebugEmblemState(crest, "helper-large")
        return true
      end
    end
  end
  if SetSmallGuildTabardTextures then
    if pcall(SetSmallGuildTabardTextures, crest, unit) or pcall(SetSmallGuildTabardTextures, unit, crest) then
      local hasEmblem = (crest.TabardEmblem and crest.TabardEmblem:GetTexture())
        or (crest.TabardEmblemUpper and crest.TabardEmblemUpper:GetTexture())
      if hasEmblem then
        if crest.TabardEmblemUpper and crest.TabardEmblemUpper:GetTexture() then
          HideTabardSingles(crest)
        elseif crest.TabardEmblem and crest.TabardEmblem:GetTexture() then
          HideTabardPieces(crest)
        end
        ApplyEmblemZoom(crest)
        DebugGuildCrest(crest and crest.ownerFrame, "applied SetSmallGuildTabardTextures")
        DebugEmblemState(crest, "helper-small")
        return true
      end
    end
  end
  return false
end

local function TrySetGuildCrestTextures(crest, unit)
  if TrySetGuildCrestFromHelpers(crest, unit) then
    return true
  end
  if GUILD_CREST_USE_TABARD_FILES and TrySetGuildCrestEmblemFromTabardFiles(crest, unit) then
    return true
  end
  if TrySetGuildCrestFromTabardInfo(crest, unit) then
    return true
  end
  if GUILD_CREST_USE_TABARD_FILES and TrySetGuildCrestFromTabardFiles(crest, unit) then
    return true
  end
  return false
end

local function UpdateGuildCrest(frame)
  if not frame then
    return
  end
  if frame.PortraitFrame then
    frame.PortraitFrame:Show()
  end
  if frame.portrait then
    frame.portrait:Hide()
  end
  local portraitAnchor = ResolvePortraitAnchor(frame)
  local portraitParent = ResolvePortraitParent(portraitAnchor, frame)
  if not portraitParent then
    return
  end

  if not frame.guildCrest then
    local crest = CreateFrame("Frame", nil, portraitParent)
    crest:SetSize(GUILD_CREST_SIZE, GUILD_CREST_SIZE)
    if portraitParent.GetFrameLevel then
      crest:SetFrameLevel(portraitParent:GetFrameLevel() + 2)
    end
    crest.TabardBackground = crest:CreateTexture(nil, "BACKGROUND")
    crest.TabardBorder = crest:CreateTexture(nil, "BORDER")
    crest.TabardEmblem = crest:CreateTexture(nil, "ARTWORK")
    crest.TabardBackgroundUpper = crest:CreateTexture(nil, "BACKGROUND")
    crest.TabardBackgroundLower = crest:CreateTexture(nil, "BACKGROUND")
    crest.TabardEmblemUpper = crest:CreateTexture(nil, "ARTWORK")
    crest.TabardEmblemLower = crest:CreateTexture(nil, "ARTWORK")
    crest.TabardBorderUpper = crest:CreateTexture(nil, "BORDER")
    crest.TabardBorderLower = crest:CreateTexture(nil, "BORDER")
    crest.Mask = crest:CreateMaskTexture()
    crest.TabardBackground:SetAllPoints(crest)
    crest.TabardBorder:SetAllPoints(crest)
    crest.TabardEmblem:SetAllPoints(crest)
    crest.TabardBackground:SetTexture(GUILD_CREST_BACKGROUND_TEXTURE)
    crest.Mask:SetTexture(GUILD_CREST_BACKGROUND_TEXTURE)
    crest.Mask:SetAllPoints(crest)
    crest.Mask:SetTexCoord(0, 1, 0, 1)
    crest.ownerFrame = frame
    frame.guildCrest = crest
  end
  if portraitParent and frame.guildCrest:GetParent() ~= portraitParent then
    frame.guildCrest:SetParent(portraitParent)
    if portraitParent.GetFrameLevel then
      frame.guildCrest:SetFrameLevel(portraitParent:GetFrameLevel() + 2)
    end
  end
  frame.guildCrest:ClearAllPoints()
  if portraitAnchor then
    frame.guildCrest:SetPoint(
      "CENTER",
      portraitAnchor,
      "CENTER",
      GUILD_CREST_OFFSET_X or 0,
      GUILD_CREST_OFFSET_Y or 0
    )
  else
    frame.guildCrest:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    DebugGuildCrest(frame, "portrait anchor missing; using fallback top-left anchor")
  end
  frame.guildCrest.anchorFrame = portraitAnchor
  UpdateCrestLayout(frame.guildCrest, portraitAnchor)

  if IsInGuild and IsInGuild() then
    if TrySetGuildCrestTextures(frame.guildCrest, "player") then
      frame.guildCrest:Show()
      frame.guildCrestRetries = 0
    else
      frame.guildCrest:Hide()
      DebugGuildCrest(frame, "crest data not ready; requesting guild roster")
      if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
      elseif GuildRoster then
        GuildRoster()
      end
      if C_Timer and C_Timer.After then
        local retries = frame.guildCrestRetries or 0
        if retries < GUILD_CREST_MAX_RETRIES and not frame.guildCrestRetryPending then
          frame.guildCrestRetryPending = true
          frame.guildCrestRetries = retries + 1
          DebugGuildCrest(
            frame,
            "crest retry scheduled " .. tostring(frame.guildCrestRetries) .. "/" .. tostring(GUILD_CREST_MAX_RETRIES)
          )
          C_Timer.After(GUILD_CREST_RETRY_DELAY, function()
            if not frame then
              return
            end
            frame.guildCrestRetryPending = nil
            UpdateGuildCrest(frame)
          end)
        end
      end
    end
  else
    DebugGuildCrest(frame, "not in guild")
    frame.guildCrest:Hide()
    frame.guildCrestRetries = 0
  end
end

function GLD:CreateMainFrame()
  local ui = self.UI
  if ui.mainFrame then
    return ui.mainFrame
  end

  local frame = CreateFrame("Frame", "GLDMainFrame", UIParent, "ButtonFrameTemplate")
  frame:SetSize(1200, 580)
  frame:SetPoint("CENTER")
  if frame.TitleText then
    frame.TitleText:SetText("Guild Loot Distribution")
  end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  UpdateGuildCrest(frame)
  frame:HookScript("OnShow", function()
    UpdateGuildCrest(frame)
  end)
  SafeRegisterEvent(frame, "PLAYER_ENTERING_WORLD")
  SafeRegisterEvent(frame, "PLAYER_GUILD_UPDATE")
  SafeRegisterEvent(frame, "GUILD_ROSTER_UPDATE")
  frame:HookScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "GUILD_ROSTER_UPDATE" then
      if event == "GUILD_ROSTER_UPDATE" and not frame.guildCrestRosterEventLogged then
        frame.guildCrestRosterEventLogged = true
        DebugGuildCrest(frame, "event GUILD_ROSTER_UPDATE fired")
      end
      UpdateGuildCrest(frame)
    end
  end)
  AddSpecialFrame(frame:GetName())

  local statusText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  local closeButton = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
  if closeButton then
    statusText:SetPoint("RIGHT", closeButton, "LEFT", -8, 0)
  else
    statusText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -40, -6)
  end
  statusText:SetText("")
  ui.statusText = statusText

    ui.mainFrame = frame
    ui.headerArea = self:CreateHeaderArea(frame)
    ui.bottomBar = self:CreateBottomBar(frame)
    ui.guestPanel = self:CreateGuestPanel(frame)
    ui.tableInset, ui.headerRow, ui.scrollBox, ui.scrollBar = self:CreateTable(frame)

    self:UpdateGuestPanelLayout()
    local requiredWidth = CalculateMainFrameWidth(ui.rosterColumns)
    if requiredWidth then
      frame:SetWidth(requiredWidth)
    end
    self:UpdateHeaderSortIndicators()
    return frame
  end

function GLD:CreateHeaderArea(frame)
  local ui = self.UI
  local header = CreateFrame("Frame", nil, frame)
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -32)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -32)
  header:SetHeight(ROSTER_HEADER_AREA_HEIGHT)

  local label = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("LEFT", header, "LEFT", 42, 0)
  label:SetText("Player Search")

  local searchBox = CreateFrame("EditBox", nil, header, "SearchBoxTemplate")
  searchBox:SetSize(200, 20)
  searchBox:SetPoint("LEFT", label, "RIGHT", 8, 0)
  searchBox:SetAutoFocus(false)
  searchBox:SetText(ui.filterText or "")
  searchBox:SetScript("OnTextChanged", function(box)
    if SearchBoxTemplate_OnTextChanged then
      SearchBoxTemplate_OnTextChanged(box)
    end
    ui.filterText = box:GetText() or ""
    self:RefreshTable()
  end)
  if SearchBoxTemplate_OnEditFocusGained then
    searchBox:SetScript("OnEditFocusGained", SearchBoxTemplate_OnEditFocusGained)
  end
  if SearchBoxTemplate_OnEditFocusLost then
    searchBox:SetScript("OnEditFocusLost", SearchBoxTemplate_OnEditFocusLost)
  end
  ui.searchBox = searchBox

  if ui.enableNoteSearch then
    local noteBox = CreateFrame("EditBox", nil, header, "SearchBoxTemplate")
    noteBox:SetSize(200, 20)
    noteBox:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    noteBox:SetAutoFocus(false)
    noteBox:SetText(ui.noteFilterText or "")
    noteBox:SetScript("OnTextChanged", function(box)
      if SearchBoxTemplate_OnTextChanged then
        SearchBoxTemplate_OnTextChanged(box)
      end
      ui.noteFilterText = box:GetText() or ""
      self:RefreshTable()
    end)
    if SearchBoxTemplate_OnEditFocusGained then
      noteBox:SetScript("OnEditFocusGained", SearchBoxTemplate_OnEditFocusGained)
    end
    if SearchBoxTemplate_OnEditFocusLost then
      noteBox:SetScript("OnEditFocusLost", SearchBoxTemplate_OnEditFocusLost)
    end

    local noteLabel = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    noteLabel:SetPoint("RIGHT", noteBox, "LEFT", -8, 0)
    noteLabel:SetText("Note Search")
    ui.noteSearchBox = noteBox
  end

  return header
end

function GLD:CreateTable(frame)
  local ui = self.UI
  ui.rosterColumns = ui.rosterColumns or BuildDefaultRosterColumns()
  self.rosterColumns = ui.rosterColumns
  self:UpdateColumnOffsets()

  local tableInset = frame.Inset
  if not tableInset then
    tableInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
  end
  tableInset:ClearAllPoints()
  tableInset:SetPoint("TOPLEFT", ui.headerArea, "BOTTOMLEFT", 0, -6)
  tableInset:SetPoint("BOTTOMRIGHT", ui.bottomBar, "TOPRIGHT", 0, 6)

  local headerRow = CreateFrame("Frame", nil, tableInset)
  headerRow:SetHeight(ROSTER_HEADER_HEIGHT)
  headerRow:SetPoint("TOPLEFT", tableInset, "TOPLEFT", 6, -6)
  headerRow:SetPoint("TOPRIGHT", tableInset, "TOPRIGHT", -24, -6)

  local scrollBox = CreateFrame("Frame", nil, tableInset, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", tableInset, "BOTTOMRIGHT", -24, 6)

  local scrollBar = CreateFrame("EventFrame", nil, tableInset, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", headerRow, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

  local view = CreateScrollBoxListLinearView()
  view:SetElementInitializer("GLDRosterRowTemplate", function(row, elementData)
    self:InitializeRosterRow(row)
    self:PopulateRosterRow(row, elementData)
  end)
  view:SetElementExtent(ROSTER_ROW_HEIGHT)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  ui.headerRow = headerRow
  ui.scrollBox = scrollBox
  ui.scrollBar = scrollBar
  self:CreateHeaderButtons(headerRow)

  return tableInset, headerRow, scrollBox, scrollBar
end

function GLD:CreateBottomBar(frame)
  local ui = self.UI
  local bar = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
  bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
  bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 12)
  bar:SetHeight(ROSTER_BOTTOM_BAR_HEIGHT)

  local showOffline = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
  showOffline:SetPoint("LEFT", bar, "LEFT", 8, 9)
  showOffline:SetChecked(ui.showOffline)
  SetCheckLabel(showOffline, "Show Offline")
  showOffline:SetScript("OnClick", function(btn)
    ui.showOffline = btn:GetChecked()
    self:RefreshTable()
  end)

  local showGuests = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
  showGuests:SetPoint("LEFT", showOffline, "RIGHT", 120, 0)
  showGuests:SetChecked(ui.showGuests)
  SetCheckLabel(showGuests, "Show Guests")
  showGuests:SetScript("OnClick", function(btn)
    ui.showGuests = btn:GetChecked()
    self:RefreshTable()
  end)

  local rowSlider = CreateFrame("Slider", nil, bar, "OptionsSliderTemplate")
  rowSlider:SetWidth(160)
  rowSlider:SetPoint("CENTER", bar, "CENTER", 0, 9)
  rowSlider:SetMinMaxValues(12, 30)
  rowSlider:SetValueStep(1)
  rowSlider:SetObeyStepOnDrag(true)
  rowSlider:SetValue(ui.visibleRows or 18)
  if rowSlider.Text then
    rowSlider.Text:SetText("Rows")
  end
  if rowSlider.Low then
    rowSlider.Low:SetText("12")
  end
  if rowSlider.High then
    rowSlider.High:SetText("30")
  end
  rowSlider:SetScript("OnValueChanged", function(_, value)
    ui.visibleRows = math.floor(value + 0.5)
    -- Integration point: adjust frame height or visible rows if you want this slider to resize the list.
  end)
  ui.rowSlider = rowSlider

  local rowCountText = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rowCountText:SetPoint("LEFT", rowSlider, "RIGHT", 8, 0)
  rowCountText:SetText("")
  ui.rowCountText = rowCountText

  local function RequireAdmin(action)
    if self:IsAdmin() then
      action()
    else
      self:Print("you do not have Guild Permission to access this panel")
    end
  end

  local buttonSpacing = 6
  local buttonRowOffset = 5
  local buttonRow = CreateFrame("Frame", nil, bar)
  buttonRow:SetHeight(20)
  buttonRow:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 8, buttonRowOffset)
  buttonRow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -8, buttonRowOffset)

  local function CreateActionButton(label, width, onClick)
    local button = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
    button:SetSize(width, 20)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
  end

  local buttons = {}
  buttons[#buttons + 1] = CreateActionButton("History", 80, function()
    RequireAdmin(function()
      if ui.ToggleHistory then
        ui:ToggleHistory()
      end
    end)
  end)
  buttons[#buttons + 1] = CreateActionButton("Admin", 70, function()
    RequireAdmin(function()
      if ui.OpenAdmin then
        ui:OpenAdmin()
      end
    end)
  end)
  buttons[#buttons + 1] = CreateActionButton("End Session", 100, function()
    RequireAdmin(function()
      if self.EndSession then
        self:EndSession()
      end
      ui:RefreshMain()
    end)
  end)
  buttons[#buttons + 1] = CreateActionButton("Start Session", 100, function()
    RequireAdmin(function()
      if self.StartSession then
        self:StartSession()
      end
      ui:RefreshMain()
    end)
  end)
  buttons[#buttons + 1] = CreateActionButton("Guest Anchors", 110, function()
    RequireAdmin(function()
      ui.guestAnchorsVisible = not ui.guestAnchorsVisible
      ui:RefreshMain()
    end)
  end)

  local previous = nil
  for _, button in ipairs(buttons) do
    if not previous then
      button:SetPoint("LEFT", buttonRow, "LEFT", 0, 0)
    else
      button:SetPoint("LEFT", previous, "RIGHT", buttonSpacing, 0)
    end
    previous = button
  end

  ui.adminButtons = { buttons[1], buttons[2], buttons[3], buttons[4], buttons[5] }
  ui.toggleGuestsBtn = buttons[5]

  return bar
end

function GLD:CreateGuestPanel(frame)
  local ui = self.UI
  local panel = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
  panel:SetHeight(ROSTER_GUEST_PANEL_HEIGHT)
  panel:SetPoint("BOTTOMLEFT", ui.bottomBar, "TOPLEFT", 0, 6)
  panel:SetPoint("BOTTOMRIGHT", ui.bottomBar, "TOPRIGHT", 0, 6)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
  title:SetText("Guest Anchors (Non-guild Party/Raid)")
  panel.title = title

  local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -22)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetSize(1, 1)
  scrollFrame:SetScrollChild(scrollChild)
  panel.scrollFrame = scrollFrame
  panel.scrollChild = scrollChild
  panel.rows = {}

  return panel
end

function GLD:UpdateGuestPanelLayout()
  local ui = self.UI
  if not ui or not ui.mainFrame or not ui.tableInset or not ui.bottomBar or not ui.guestPanel or not ui.headerArea then
    return
  end

  if ui.guestAnchorsVisible then
    ui.guestPanel:Show()
  else
    ui.guestPanel:Hide()
  end

  ui.tableInset:ClearAllPoints()
  ui.tableInset:SetPoint("TOPLEFT", ui.headerArea, "BOTTOMLEFT", 0, -6)
  if ui.guestAnchorsVisible then
    ui.tableInset:SetPoint("BOTTOMRIGHT", ui.guestPanel, "TOPRIGHT", 0, 6)
  else
    ui.tableInset:SetPoint("BOTTOMRIGHT", ui.bottomBar, "TOPRIGHT", 0, 6)
  end
end

function GLD:UpdateBottomBarPermissions()
  local ui = self.UI
  if not ui or not ui.adminButtons then
    return
  end
  local isAdmin = self:IsAdmin()
  for _, button in ipairs(ui.adminButtons) do
    if button and button.SetEnabled then
      button:SetEnabled(isAdmin)
    end
  end
  if ui.toggleGuestsBtn and ui.toggleGuestsBtn.SetEnabled then
    ui.toggleGuestsBtn:SetEnabled(isAdmin)
  end
end

function GLD:UpdateRosterStatusText()
  local ui = self.UI
  if not ui or not ui.statusText then
    return
  end
  local text = nil
  if self.GetRosterStatusText then
    text = self:GetRosterStatusText()
  end
  if not text or text == "" then
    text = self:GetDefaultRosterStatusText()
  end
  ui.statusText:SetText(text or "")
end

function GLD:IsRosterEditEnabled()
  return self.editRosterEnabled == true and self:IsAdmin()
end

function GLD:SetRosterEditEnabled(enabled)
  self.editRosterEnabled = enabled and true or false
  if self.UI then
    self.UI.editRosterEnabled = self.editRosterEnabled
  end
  if self.UpdateRosterEditState then
    self:UpdateRosterEditState()
  end
end

function GLD:UpdateRosterEditState()
  local ui = self.UI
  if not ui or not ui.headerButtons then
    return
  end
  -- Placeholder for any edit-only header tweaks.
  -- Keep this method to hook in refreshes when Edit Roster is toggled.
end

function GLD:GetDefaultRosterStatusText()
  local myPos = "--"
  local isAdmin = self:IsAdmin()
  if isAdmin then
    local key = NS:GetPlayerKeyFromUnit("player")
    local player = key and self.db and self.db.players and self.db.players[key]
    if player and player.queuePos then
      myPos = tostring(player.queuePos)
    end
  else
    if self.shadow and self.shadow.my and self.shadow.my.queuePos then
      myPos = tostring(self.shadow.my.queuePos)
    end
  end
  return "My Position: " .. myPos
end

function GLD:CreateHeaderButtons(headerRow)
  local ui = self.UI
  ui.headerButtons = {}
  for index, col in ipairs(self.rosterColumns or {}) do
    local button = CreateFrame("Button", nil, headerRow, "BackdropTemplate")
    button:SetSize(col.width, ROSTER_HEADER_HEIGHT)
    button:SetPoint("LEFT", headerRow, "LEFT", col.x, 0)
    button:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    button:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    button:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("CENTER", button, "CENTER", 0, 0)
    text:SetText(col.label)
    button.text = text

    button.sortKey = col.sortKey
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    arrow:Hide()
    button.sortArrow = arrow

    if col.sortKey then
      button:SetScript("OnClick", function()
        self:ToggleSort(col.sortKey)
      end)
    end

    ui.headerButtons[index] = button
  end
end

function GLD:UpdateColumnOffsets()
  local x = 4
  for _, col in ipairs(self.rosterColumns or {}) do
    col.x = x
    x = x + col.width + ROSTER_COLUMN_PADDING
  end
end

function GLD:ToggleSort(sortKey)
  local ui = self.UI
  if ui.sortKey == sortKey then
    ui.sortAscending = not ui.sortAscending
  else
    ui.sortKey = sortKey
    ui.sortAscending = true
  end
  self:UpdateHeaderSortIndicators()
  self:RefreshTable()
end

function GLD:UpdateHeaderSortIndicators()
  local ui = self.UI
  if not ui or not ui.headerButtons then
    return
  end
  for _, button in ipairs(ui.headerButtons) do
    if button.sortKey and button.sortKey == ui.sortKey then
      if button.sortArrow then
        button.sortArrow:Show()
        if ui.sortAscending then
          button.sortArrow:SetTexCoord(0, 1, 0, 1)
        else
          button.sortArrow:SetTexCoord(0, 1, 1, 0)
        end
      end
      if button.text then
        button.text:SetTextColor(1, 0.9, 0.6)
      end
    else
      if button.sortArrow then
        button.sortArrow:Hide()
      end
      if button.text then
        button.text:SetTextColor(1, 1, 1)
      end
    end
  end
end

function GLD:GetRosterMembers()
  -- Integration point: return your current roster list (array or keyed table).
  local members = nil
  if self.GetMembers then
    members = self:GetMembers()
  end
  members = members or self.sessionMembers or (self.db and self.db.players) or {}

  local list = {}
  if type(members) == "table" and #members > 0 then
    for _, member in ipairs(members) do
      if type(member) == "table" and member.member then
        list[#list + 1] = member
      else
        list[#list + 1] = { member = member, key = member and (member.key or member.playerKey) or nil }
      end
    end
  else
    for key, member in pairs(members) do
      if type(member) == "table" and member.member then
        if not member.key then
          member.key = key
        end
        list[#list + 1] = member
      else
        list[#list + 1] = { member = member, key = key }
      end
    end
  end
  return list
end

function GLD:GetMemberName(member)
  if not member then
    return "?"
  end
  local name = member.name or member.fullName or member.displayName
  if name and name ~= "" then
    if type(name) == "string" then
      return (strsplit("-", name))
    end
    return name
  end
  return tostring(member)
end

function GLD:IsGuestMember(member)
  if self.IsGuest then
    return self:IsGuest(member)
  end
  if member and member.isGuest ~= nil then
    return member.isGuest
  end
  return member and member.source == "guest"
end

function GLD:IsMemberOffline(rowData)
  if rowData and rowData.member and rowData.member.online ~= nil then
    return not rowData.member.online
  end
  local status = (rowData and rowData.attendanceStatus or ""):upper()
  if status == "" then
    return false
  end
  return status ~= "PRESENT"
end

function GLD:GetMemberNoteText(member)
  -- Integration point: return the note text you want to filter on for note search.
  return member and (member.note or member.publicNote or member.officerNote) or nil
end

function GLD:GetAttendanceSortValue(status)
  local key = (status or ""):upper()
  if key == "PRESENT" then
    return 1
  end
  if key == "PARTIAL" then
    return 2
  end
  if key == "ABSENT" or key == "OFFLINE" then
    return 3
  end
  return 4
end

function GLD:GetAttendanceTextColor(status, override)
  if type(override) == "table" then
    local r = override.r or override[1]
    local g = override.g or override[2]
    local b = override.b or override[3]
    if r and g and b then
      return r, g, b
    end
  end

  local key = (status or ""):upper()
  if key == "PRESENT" then
    return 0.55, 0.9, 0.55
  end
  if key == "ABSENT" or key == "OFFLINE" then
    return 0.9, 0.45, 0.45
  end
  if key == "PARTIAL" then
    return 0.9, 0.75, 0.4
  end
  return 0.8, 0.8, 0.8
end

function GLD:BuildRosterRowData(entry)
  -- Integration point: wire your existing helper functions here.
  local member = entry
  local playerKey = nil
  if type(entry) == "table" and entry.member then
    member = entry.member
    playerKey = entry.key
  end
  local rawName = self:GetMemberName(member)
  local isGuest = self:IsGuestMember(member)
  local baseName = NS:GetPlayerBaseName(rawName) or rawName or "?"
  local displayName = NS:GetPlayerDisplayName(baseName, isGuest)
  local classFile = member and (member.classFile or member.classFileName or member.class)
  local nameColor = nil
  if classFile then
    local r, g, b = NS:GetClassColor(classFile)
    nameColor = { r = r, g = g, b = b }
  end

  local role = self.GetRole and self:GetRole(member) or (member and member.role)
  local queuePos = self.GetQueuePos and self:GetQueuePos(member) or (member and member.queuePos)
  local heldPos = self.GetHeldPos and self:GetHeldPos(member) or (member and (member.heldPos or member.savedPos))
  local itemsWon = self.GetItemsWon and self:GetItemsWon(member) or (member and (member.itemsWon or member.numAccepted))
  local raidsAttended = self.GetRaidsAttended and self:GetRaidsAttended(member) or (member and (member.raidsAttended or member.attendanceCount))

  local attendanceStatus, attendanceColor = nil, nil
  if self.GetAttendanceStatus then
    attendanceStatus, attendanceColor = self:GetAttendanceStatus(member)
  end
  attendanceStatus = attendanceStatus or (member and member.attendance) or ""
  local r, g, b = self:GetAttendanceTextColor(attendanceStatus, attendanceColor)

  local classTexture, classCoords = nil, nil
  if self.GetClassIconInfo then
    local tex, left, right, top, bottom = self:GetClassIconInfo(member)
    classTexture = tex
    if type(left) == "table" then
      classCoords = left
    elseif left and right and top and bottom then
      classCoords = { left, right, top, bottom }
    end
    if classTexture and not classCoords and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTexture] then
      classCoords = CLASS_ICON_TCOORDS[classTexture]
      classTexture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
    end
  end
  if not classTexture then
    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
      classTexture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
      classCoords = CLASS_ICON_TCOORDS[classFile]
    end
  end

  local specIcon = self.GetSpecIcon and self:GetSpecIcon(member) or (member and member.specIcon)

  if not playerKey and baseName and self.FindPlayerKeyByName then
    playerKey = self:FindPlayerKeyByName(baseName, member and member.realm)
  end

  return {
    member = member,
    playerKey = playerKey,
    name = baseName,
    nameLower = (baseName or ""):lower(),
    displayName = displayName,
    isGuest = isGuest,
    nameColor = nameColor,
    role = role or "",
    queuePos = queuePos,
    heldPos = heldPos,
    itemsWon = itemsWon,
    raidsAttended = raidsAttended,
    attendanceStatus = attendanceStatus,
    attendanceColor = { r = r, g = g, b = b },
    classTexture = classTexture,
    classCoords = classCoords,
    specIcon = specIcon,
    sort = {
      name = (name or ""):lower(),
      queuePos = tonumber(queuePos),
      heldPos = tonumber(heldPos),
      itemsWon = tonumber(itemsWon),
      raidsAttended = tonumber(raidsAttended),
      attendance = self:GetAttendanceSortValue(attendanceStatus),
    },
  }
end

function GLD:InitializeRosterRow(row)
  if row.isInitialized then
    return
  end
  row:SetHeight(ROSTER_ROW_HEIGHT)
  if self.UI and self.UI.headerRow then
    row:SetWidth(self.UI.headerRow:GetWidth())
  end
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetColorTexture(1, 1, 1, 0.08)
  highlight:SetAllPoints(row)
  row.cells = {}
  row.editBoxes = {}

  for _, col in ipairs(self.rosterColumns or {}) do
    if col.isIcon then
      local tex = row:CreateTexture(nil, "ARTWORK")
      tex:SetSize(ROSTER_ICON_SIZE, ROSTER_ICON_SIZE)
      tex:SetPoint("LEFT", row, "LEFT", col.x + (col.width - ROSTER_ICON_SIZE) * 0.5, 0)
      row.cells[col.key] = tex
    else
      local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      fs:SetWidth(col.width)
      fs:SetJustifyH(col.align or "LEFT")
      fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
      row.cells[col.key] = fs

      if col.key == "queuePos" or col.key == "heldPos" or col.key == "itemsWon" or col.key == "raidsAttended" or col.key == "attendance" then
        local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        box:SetSize(col.width - 6, ROSTER_ROW_HEIGHT - 2)
        box:SetPoint("LEFT", row, "LEFT", col.x + 3, 0)
        box:SetAutoFocus(false)
        box:SetJustifyH("CENTER")
        if col.key ~= "attendance" and box.SetNumeric then
          box:SetNumeric(true)
        end
        box:SetScript("OnEscapePressed", function(edit)
          edit:ClearFocus()
        end)
        row.editBoxes[col.key] = box
        if col.key == "queuePos" then
          row.queuePosBox = box
        elseif col.key == "heldPos" then
          row.heldPosBox = box
        elseif col.key == "itemsWon" then
          row.itemsWonBox = box
        elseif col.key == "raidsAttended" then
          row.raidsBox = box
        elseif col.key == "attendance" then
          row.attendanceBox = box
        end
      end
    end
  end

  local function canEditRow(data)
    if not self:IsRosterEditEnabled() then
      return false
    end
    if not data or data.isGuest then
      return false
    end
    if not data.playerKey or not self.db or not self.db.players or not self.db.players[data.playerKey] then
      return false
    end
    return true
  end

  if row.queuePosBox then
    row.queuePosBox:SetScript("OnEnterPressed", function(box)
      local data = row.data
      if not canEditRow(data) then
        box:ClearFocus()
        return
      end
      local pos = ParseNonNegativeInt(box:GetText())
      if pos ~= nil then
        local player = self.db.players[data.playerKey]
        if player.attendance == "ABSENT" then
          player.savedPos = pos
          player.queuePos = nil
        else
          if self.RemoveFromQueue then
            self:RemoveFromQueue(data.playerKey)
          end
          if self.InsertToQueue then
            self:InsertToQueue(data.playerKey, pos)
          else
            player.queuePos = pos
          end
        end
      end
      self:RefreshTable()
      self:UpdateRosterStatusText()
      box:ClearFocus()
    end)
  end

  if row.heldPosBox then
    row.heldPosBox:SetScript("OnEnterPressed", function(box)
      local data = row.data
      if not canEditRow(data) then
        box:ClearFocus()
        return
      end
      local pos = ParseNonNegativeInt(box:GetText())
      if pos ~= nil then
        self.db.players[data.playerKey].savedPos = pos
      end
      self:RefreshTable()
      box:ClearFocus()
    end)
  end

  if row.itemsWonBox then
    row.itemsWonBox:SetScript("OnEnterPressed", function(box)
      local data = row.data
      if not canEditRow(data) then
        box:ClearFocus()
        return
      end
      local num = ParseNonNegativeInt(box:GetText())
      if num ~= nil then
        self.db.players[data.playerKey].numAccepted = num
      end
      self:RefreshTable()
      box:ClearFocus()
    end)
  end

  if row.raidsBox then
    row.raidsBox:SetScript("OnEnterPressed", function(box)
      local data = row.data
      if not canEditRow(data) then
        box:ClearFocus()
        return
      end
      local num = ParseNonNegativeInt(box:GetText())
      if num ~= nil then
        self.db.players[data.playerKey].attendanceCount = num
      end
      self:RefreshTable()
      box:ClearFocus()
    end)
  end

  if row.attendanceBox then
    row.attendanceBox:SetScript("OnEnterPressed", function(box)
      local data = row.data
      if not canEditRow(data) then
        box:ClearFocus()
        return
      end
      local status = NormalizeAttendanceInput(box:GetText())
      if status then
        local player = self.db.players[data.playerKey]
        if status == "PRESENT" or status == "ABSENT" then
          if self.SetAttendance then
            self:SetAttendance(data.playerKey, status)
          else
            player.attendance = status
          end
        elseif status == "OFFLINE" then
          if self.SetAttendance then
            self:SetAttendance(data.playerKey, "ABSENT")
          else
            player.attendance = "ABSENT"
          end
          player.attendance = "OFFLINE"
        else
          player.attendance = status
        end
      end
      self:RefreshTable()
      box:ClearFocus()
    end)
  end

  row.isInitialized = true
end

function GLD:PopulateRosterRow(row, data)
  if not data or not row.cells then
    return
  end
  row.data = data
  local cells = row.cells

  local classIcon = cells.class
  if classIcon then
    if data.classTexture then
      classIcon:SetTexture(data.classTexture)
      if data.classCoords then
        classIcon:SetTexCoord(data.classCoords[1], data.classCoords[2], data.classCoords[3], data.classCoords[4])
      else
        classIcon:SetTexCoord(0, 1, 0, 1)
      end
      classIcon:Show()
    else
      classIcon:Hide()
    end
  end

  local specIcon = cells.spec
  if specIcon then
    if data.specIcon then
      specIcon:SetTexture(data.specIcon)
      specIcon:SetTexCoord(0, 1, 0, 1)
      specIcon:Show()
    else
      specIcon:Hide()
    end
  end

  if cells.role then
    cells.role:SetText(data.role or "")
  end
  if cells.name then
    cells.name:SetText(data.displayName or data.name or "")
    if data.nameColor then
      cells.name:SetTextColor(data.nameColor.r, data.nameColor.g, data.nameColor.b)
    else
      cells.name:SetTextColor(1, 1, 1)
    end
  end
  if cells.queuePos then
    cells.queuePos:SetText(data.queuePos or "-")
  end
  if cells.heldPos then
    cells.heldPos:SetText(data.heldPos or "-")
  end
  if cells.itemsWon then
    cells.itemsWon:SetText(data.itemsWon or "-")
  end
  if cells.raidsAttended then
    cells.raidsAttended:SetText(data.raidsAttended or "-")
  end
  if cells.attendance then
    cells.attendance:SetText(data.attendanceStatus or "")
    if data.attendanceColor then
      cells.attendance:SetTextColor(data.attendanceColor.r, data.attendanceColor.g, data.attendanceColor.b)
    else
      cells.attendance:SetTextColor(0.8, 0.8, 0.8)
    end
  end

  local editEnabled = self:IsRosterEditEnabled()
  local canEdit = editEnabled and not data.isGuest and data.playerKey and self.db and self.db.players and self.db.players[data.playerKey]

  if row.queuePosBox then
    if canEdit then
      row.queuePosBox:Show()
      row.queuePosBox:SetText(tostring(data.queuePos or ""))
      SetEditBoxEnabled(row.queuePosBox, true)
      if cells.queuePos then
        cells.queuePos:Hide()
      end
    else
      row.queuePosBox:Hide()
      if cells.queuePos then
        cells.queuePos:Show()
      end
    end
  end
  if row.heldPosBox then
    if canEdit then
      row.heldPosBox:Show()
      row.heldPosBox:SetText(tostring(data.heldPos or ""))
      SetEditBoxEnabled(row.heldPosBox, true)
      if cells.heldPos then
        cells.heldPos:Hide()
      end
    else
      row.heldPosBox:Hide()
      if cells.heldPos then
        cells.heldPos:Show()
      end
    end
  end
  if row.itemsWonBox then
    if canEdit then
      row.itemsWonBox:Show()
      row.itemsWonBox:SetText(tostring(data.itemsWon or 0))
      SetEditBoxEnabled(row.itemsWonBox, true)
      if cells.itemsWon then
        cells.itemsWon:Hide()
      end
    else
      row.itemsWonBox:Hide()
      if cells.itemsWon then
        cells.itemsWon:Show()
      end
    end
  end
  if row.raidsBox then
    if canEdit then
      row.raidsBox:Show()
      row.raidsBox:SetText(tostring(data.raidsAttended or 0))
      SetEditBoxEnabled(row.raidsBox, true)
      if cells.raidsAttended then
        cells.raidsAttended:Hide()
      end
    else
      row.raidsBox:Hide()
      if cells.raidsAttended then
        cells.raidsAttended:Show()
      end
    end
  end
  if row.attendanceBox then
    if canEdit then
      row.attendanceBox:Show()
      row.attendanceBox:SetText(tostring(data.attendanceStatus or ""))
      SetEditBoxEnabled(row.attendanceBox, true)
      if cells.attendance then
        cells.attendance:Hide()
      end
    else
      row.attendanceBox:Hide()
      if cells.attendance then
        cells.attendance:Show()
      end
    end
  end
end

function GLD:PassRosterFilters(rowData)
  local ui = self.UI
  if not ui then
    return false
  end
  if not ui.showGuests and rowData.isGuest then
    return false
  end
  if not ui.showOffline and self:IsMemberOffline(rowData) then
    return false
  end
  local filterText = (ui.filterText or ""):lower()
  if filterText ~= "" then
    if not rowData.nameLower or not rowData.nameLower:find(filterText, 1, true) then
      return false
    end
  end
  local noteFilter = (ui.noteFilterText or ""):lower()
  if ui.enableNoteSearch and noteFilter ~= "" then
    local noteText = self:GetMemberNoteText(rowData.member)
    noteText = noteText and noteText:lower() or ""
    if noteText == "" or not noteText:find(noteFilter, 1, true) then
      return false
    end
  end
  return true
end

function GLD:SortRosterData(rows)
  local ui = self.UI
  if not ui or not ui.sortKey then
    return
  end
  local key = ui.sortKey
  local ascending = ui.sortAscending

  table.sort(rows, function(a, b)
    local aSort = a.sort and a.sort[key]
    local bSort = b.sort and b.sort[key]
    if aSort == bSort then
      return (a.sort and a.sort.name or "") < (b.sort and b.sort.name or "")
    end
    if aSort == nil then
      return not ascending
    end
    if bSort == nil then
      return ascending
    end
    if type(aSort) == "string" or type(bSort) == "string" then
      aSort = tostring(aSort)
      bSort = tostring(bSort)
    end
    if ascending then
      return aSort < bSort
    end
    return aSort > bSort
  end)
end

function GLD:RefreshTable()
  local ui = self.UI
  if not ui or not ui.scrollBox then
    return
  end

  local members = self:GetRosterMembers()
  local rows = {}
  for _, member in ipairs(members) do
    local rowData = self:BuildRosterRowData(member)
    if self:PassRosterFilters(rowData) then
      rows[#rows + 1] = rowData
    end
  end

  self:SortRosterData(rows)

  if CreateDataProvider then
    local dataProvider = CreateDataProvider()
    for _, rowData in ipairs(rows) do
      dataProvider:Insert(rowData)
    end
    ui.scrollBox:SetDataProvider(dataProvider, true)
  end

  if ui.rowCountText then
    ui.rowCountText:SetText(string.format("%d Rows", #rows))
  end
end

function GLD:RefreshGuestAnchors()
  local ui = self.UI
  local panel = ui and ui.guestPanel
  if not panel or not panel:IsShown() then
    return
  end

  local isAdmin = self:IsAdmin()
  local existingGuests = {}
  for key, player in pairs(self.db and self.db.players or {}) do
    if player and player.source == "guest" then
      existingGuests[key] = true
    end
  end

  local units = {}
  local function addUnit(unit)
    if not UnitExists(unit) or not UnitIsConnected(unit) then
      return
    end
    if UnitIsUnit(unit, "player") then
      return
    end
    if UnitIsInMyGuild and UnitIsInMyGuild(unit) then
      return
    end
    local key = NS:GetPlayerKeyFromUnit(unit)
    if key and existingGuests[key] then
      return
    end
    units[#units + 1] = unit
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      addUnit("raid" .. i)
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      addUnit("party" .. i)
    end
  end

  local rowHeight = 22
  if #units == 0 then
    if not panel.emptyLabel then
      panel.emptyLabel = panel.scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      panel.emptyLabel:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 4, -4)
    end
    panel.emptyLabel:SetText("No non-guild party/raid members found.")
    panel.emptyLabel:Show()
    for _, row in ipairs(panel.rows) do
      row:Hide()
    end
    panel.scrollChild:SetHeight(rowHeight)
    panel.scrollFrame:UpdateScrollChildRect()
    return
  end

  if panel.emptyLabel then
    panel.emptyLabel:Hide()
  end

  for index, unit in ipairs(units) do
    local row = panel.rows[index]
    if not row then
      row = CreateFrame("Frame", nil, panel.scrollChild)
      row:SetHeight(rowHeight)
      row.icon = row:CreateTexture(nil, "ARTWORK")
      row.icon:SetSize(16, 16)
      row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
      row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
      row.name:SetWidth(200)
      row.addButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      row.addButton:SetSize(90, 18)
      row.addButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)
      row.addButton:SetText("Add Guest")
      panel.rows[index] = row
    end

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.scrollChild, "TOPLEFT", 0, -((index - 1) * rowHeight))
    row:SetPoint("RIGHT", panel.scrollChild, "RIGHT", -4, 0)

    local name = UnitName(unit)
    local classFile = select(2, UnitClass(unit))
    local displayName = NS:GetPlayerDisplayName(name, false)
    row.name:SetText(displayName)
    local r, g, b = NS:GetClassColor(classFile)
    row.name:SetTextColor(r, g, b)

    if classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile] then
      local coords = CLASS_ICON_TCOORDS[classFile]
      row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
      row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
      row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      row.icon:SetTexCoord(0, 1, 0, 1)
    end

    if row.addButton and row.addButton.SetEnabled then
      row.addButton:SetEnabled(isAdmin)
    end
    row.addButton:SetScript("OnClick", function()
      if not self:IsAdmin() then
        self:Print("you do not have Guild Permission to access this panel")
        return
      end
      if self.AddGuestFromUnit then
        self:AddGuestFromUnit(unit)
      end
      UI:RefreshMain()
    end)
    row:Show()
  end

  for i = #units + 1, #panel.rows do
    panel.rows[i]:Hide()
  end

  panel.scrollChild:SetHeight(#units * rowHeight + 4)
  panel.scrollFrame:UpdateScrollChildRect()
end

function UI:SubmitRollVote(session, vote, advanceTest)
  if not session or not vote then
    return
  end

  session.votes = session.votes or {}
  local key = NS:GetPlayerKeyFromUnit("player")
  session.votes[key] = vote

  if session.isTest and GLD.CheckRollCompletion then
    GLD:CheckRollCompletion(session)
  end

  if not session.isTest then
    local authority = GLD:GetAuthorityName()
    if authority and not GLD:IsAuthority() then
      GLD:SendCommMessageSafe(NS.MSG.ROLL_VOTE, {
        rollID = session.rollID,
        vote = vote,
        voterKey = key,
      }, "WHISPER", authority)
    else
      local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
      GLD:SendCommMessageSafe(NS.MSG.ROLL_VOTE, {
        rollID = session.rollID,
        vote = vote,
        voterKey = key,
      }, channel)
    end
  else
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY")
    GLD:SendCommMessageSafe(NS.MSG.ROLL_VOTE, {
      rollID = session.rollID,
      vote = vote,
      voterKey = key,
    }, channel)
  end

  if session.locked then
    GLD:Print("Result locked. Your vote was recorded but the outcome is final.")
  end

  if advanceTest and NS.TestUI and session.testVoterName and not IsInGroup() and not IsInRaid() then
    NS.TestUI.testVotes = NS.TestUI.testVotes or {}
    NS.TestUI.testVotes[session.testVoterName] = vote
    NS.TestUI:AdvanceTestVoter()
  end

  if self.RefreshLootWindow then
    local rollKey = session and session.rollID
    self:RefreshLootWindow({ advance = true, activeKey = rollKey })
  end
end

function UI:ShowRollPopup(session)
  if self.mainFrame and self.mainFrame:IsShown() and session and not session.isTest then
    if self.RefreshLootWindow then
      self:RefreshLootWindow()
    end
    return
  end
  if not AceGUI then
    return
  end

  if self.RefreshLootWindow then
    self:RefreshLootWindow({ forceShow = true })
  end

  self.rollFrames = self.rollFrames or {}
  if session.rollID and self.rollFrames[session.rollID] then
    self.rollFrames[session.rollID]:Release()
    self.rollFrames[session.rollID] = nil
  end

  local frame = AceGUI:Create("Frame")
  if session.testVoterName then
    frame:SetTitle("Loot Roll - " .. session.testVoterName)
  else
    frame:SetTitle("Loot Roll")
  end
  frame:SetStatusText(session.itemName or "Item")
  frame:SetWidth(400)
  frame:SetHeight(240)
  frame:SetLayout("Flow")
  frame:EnableResize(false)
  if frame.frame and frame.frame.SetBackdrop then
    frame.frame:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame.frame:SetBackdropColor(0, 0, 0, 1)
  end

  frame:SetCallback("OnClose", function(widget)
    if session.rollID and self.rollFrames then
      self.rollFrames[session.rollID] = nil
    end
    widget:Release()
  end)

  local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
  if session.itemLink then
    local itemIcon = select(10, GetItemInfo(session.itemLink))
    if itemIcon then
      icon = itemIcon
    else
      GLD:RequestItemData(session.itemLink)
    end
  end

  local iconWidget = AceGUI:Create("Icon")
  iconWidget:SetImage(icon)
  iconWidget:SetImageSize(28, 28)
  iconWidget:SetWidth(32)
  iconWidget:SetHeight(32)
  iconWidget:SetCallback("OnEnter", function()
    local link = session.itemLink
    if link and link ~= "" then
      GameTooltip:SetOwner(iconWidget.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end)
  iconWidget:SetCallback("OnLeave", function()
    GameTooltip:Hide()
  end)
  frame:AddChild(iconWidget)

  local itemLabel = AceGUI:Create("InteractiveLabel")
  itemLabel:SetFullWidth(true)
  itemLabel:SetText(session.itemLink or session.itemName or "Unknown Item")
  itemLabel:SetCallback("OnEnter", function()
    local link = session.itemLink
    if link and link ~= "" then
      GameTooltip:SetOwner(frame.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end)
  itemLabel:SetCallback("OnLeave", function()
    GameTooltip:Hide()
  end)
  frame:AddChild(itemLabel)

  local intentLabel = AceGUI:Create("Label")
  intentLabel:SetFullWidth(true)
  intentLabel:SetText("Declare your intent here. Please mirror your choice in the Blizzard roll window.")
  frame:AddChild(intentLabel)

  local waitLabel = AceGUI:Create("Label")
  waitLabel:SetFullWidth(true)
  waitLabel:SetText("")
  frame:AddChild(waitLabel)

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
    if btn.vote == "NEED" and session.canNeed == false then
      button:SetDisabled(true)
    end
    if btn.vote == "GREED" and session.canGreed == false then
      button:SetDisabled(true)
    end
    if btn.vote == "TRANSMOG" and session.canTransmog == false then
      button:SetDisabled(true)
    end
    button:SetCallback("OnClick", function()
      self:SubmitRollVote(session, btn.vote, btn.vote ~= "NEED")
      if btn.vote == "NEED" then
        waitLabel:SetText("WAIT FOR EVERYONE TO VOTE TO FIND THE WINNER")
        for _, child in ipairs(frame.children or {}) do
          if child.type == "Button" then
            child:SetDisabled(true)
          end
        end
        return
      end
      if session.rollID and self.rollFrames then
        self.rollFrames[session.rollID] = nil
      end
      frame:Release()
    end)
    frame:AddChild(button)
  end

  if session.rollID then
    self.rollFrames[session.rollID] = frame
  else
    self.rollFrame = frame
  end
end

function UI:ShowRollResultPopup(result)
  if not result then
    return
  end
  if self.RecordRollResult then
    self:RecordRollResult(result)
  end
  if not AceGUI then
    return
  end

  if self.resultFrame then
    self.resultFrame:Release()
  end

  local frame = AceGUI:Create("Frame")
  frame:SetTitle("Loot Result")
  frame:SetStatusText(result.itemName or "Item")
  frame:SetWidth(420)
  frame:SetHeight(180)
  frame:SetLayout("Flow")
  frame:EnableResize(false)

  local itemLabel = AceGUI:Create("InteractiveLabel")
  itemLabel:SetFullWidth(true)
  itemLabel:SetText(result.itemLink or result.itemName or "Unknown Item")
  itemLabel:SetCallback("OnEnter", function()
    local link = result.itemLink
    if link and link ~= "" then
      GameTooltip:SetOwner(frame.frame, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink(link)
      GameTooltip:Show()
    end
  end)
  itemLabel:SetCallback("OnLeave", function()
    GameTooltip:Hide()
  end)
  frame:AddChild(itemLabel)

  local winnerLabel = AceGUI:Create("Label")
  winnerLabel:SetFullWidth(true)
  winnerLabel:SetText("Winner: " .. tostring(result.winnerName or "None"))
  frame:AddChild(winnerLabel)

  local closeBtn = AceGUI:Create("Button")
  closeBtn:SetText("OK")
  closeBtn:SetWidth(100)
  closeBtn:SetCallback("OnClick", function()
    frame:Hide()
  end)
  frame:AddChild(closeBtn)

  self.resultFrame = frame
end



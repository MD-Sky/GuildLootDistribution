local _, NS = ...

local GLD = NS.GLD
local UI = NS.UI

local FakeLootRoll = {}
UI.FakeLootRoll = FakeLootRoll

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local FRAME_WIDTH = 420
local FRAME_PADDING = 10
local ROW_HEIGHT = 44
local ROW_SPACING = 6
local ICON_SIZE = 32
local BUTTON_SIZE = 26
local BUTTON_GAP = 6

local SAMPLE_ITEMS = {
  { name = "Voidglass Kris", link = "item:237728" },
  { name = "Astral Gladiator's Prestigious Cloak", link = "item:244234" },
}

local BUTTON_TEXTURES = {
  need = "Interface\\Buttons\\UI-GroupLoot-Button-Need-Up",
  greed = "Interface\\Buttons\\UI-GroupLoot-Button-Greed-Up",
  transmog = "Interface\\Buttons\\UI-GroupLoot-Button-Disenchant-Up",
  pass = "Interface\\Buttons\\UI-GroupLoot-Button-Pass-Up",
}

local function GetCovers()
  local rollBlockers = GLD and GLD.RollBlockers or nil
  if not rollBlockers or not rollBlockers.EnsureForRollFrame or not rollBlockers.SetMode then
    return nil
  end
  if not rollBlockers._gldTutorialWrapper then
    rollBlockers._gldTutorialWrapper = {
      EnsureForRollFrame = function(_, frame)
        return rollBlockers.EnsureForRollFrame(frame)
      end,
      SetMode = function(_, frame, mode)
        return rollBlockers.SetMode(frame, mode)
      end,
    }
  end
  return rollBlockers._gldTutorialWrapper
end

local function CreateRollButton(parent, texture)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints()
  icon:SetTexture(texture or DEFAULT_ICON)
  button.icon = icon
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  return button
end

local function UpdateRowDisplay(row)
  if not row then
    return
  end
  local name = row.itemName or "Item"
  local icon = DEFAULT_ICON
  local r, g, b = 1, 1, 1
  if row.itemLink and GetItemInfo then
    local infoName, _, quality, _, _, _, _, _, _, infoIcon = GetItemInfo(row.itemLink)
    if infoName and infoName ~= "" then
      name = infoName
    end
    if infoIcon then
      icon = infoIcon
    end
    if quality then
      local qR, qG, qB = GetItemQualityColor(quality)
      if qR then
        r, g, b = qR, qG, qB
      end
    end
    if GLD and GLD.RequestItemData and (not infoName or not infoIcon) then
      GLD:RequestItemData(row.itemLink)
    end
  end
  row.itemText:SetText(name)
  row.itemText:SetTextColor(r, g, b)
  row.icon:SetTexture(icon)
end

function FakeLootRoll:EnsureFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "GLDTutorialFakeLootRoll", UIParent, "BackdropTemplate")
  local totalHeight = (ROW_HEIGHT * #SAMPLE_ITEMS) + (ROW_SPACING * (#SAMPLE_ITEMS - 1)) + (FRAME_PADDING * 2)
  frame:SetSize(FRAME_WIDTH, totalHeight)
  frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
  frame:SetFrameStrata("FULLSCREEN")
  frame:SetFrameLevel(20)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  frame:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
  frame:SetClampedToScreen(true)
  frame:Hide()

  frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  frame:SetScript("OnEvent", function()
    FakeLootRoll:RefreshItems()
  end)
  frame:SetScript("OnShow", function()
    FakeLootRoll:RefreshItems()
  end)

  self.frame = frame
  self.rows = {}

  for i, sample in ipairs(SAMPLE_ITEMS) do
    local row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_PADDING, -FRAME_PADDING - (i - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -FRAME_PADDING, -FRAME_PADDING - (i - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      tile = true,
      tileSize = 4,
      edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetTexture(DEFAULT_ICON)

    local passButton = CreateRollButton(row, BUTTON_TEXTURES.pass)
    passButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    local transmogButton = CreateRollButton(row, BUTTON_TEXTURES.transmog)
    transmogButton:SetPoint("RIGHT", passButton, "LEFT", -BUTTON_GAP, 0)
    local greedButton = CreateRollButton(row, BUTTON_TEXTURES.greed)
    greedButton:SetPoint("RIGHT", transmogButton, "LEFT", -BUTTON_GAP, 0)
    local needButton = CreateRollButton(row, BUTTON_TEXTURES.need)
    needButton:SetPoint("RIGHT", greedButton, "LEFT", -BUTTON_GAP, 0)

    row.NeedButton = needButton
    row.GreedButton = greedButton
    row.TransmogButton = transmogButton
    row.DisenchantButton = transmogButton
    row.PassButton = passButton
    row.Need = needButton
    row.Greed = greedButton
    row.Disenchant = transmogButton
    row.Pass = passButton

    row.itemText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.itemText:SetJustifyH("LEFT")
    row.itemText:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.itemText:SetPoint("RIGHT", needButton, "LEFT", -8, 0)
    row.itemText:SetText(sample.name or "Item")

    row.itemName = sample.name
    row.itemLink = sample.link

    self.rows[i] = row
  end

  self:RefreshItems()
end

function FakeLootRoll:RefreshItems()
  for _, row in ipairs(self.rows or {}) do
    UpdateRowDisplay(row)
  end
end

function FakeLootRoll:ApplyMode(mode)
  if not mode or mode == "" then
    mode = "UNLOCK_ALL"
  end
  self.mode = mode
  if not self.frame or not self.frame:IsShown() then
    return
  end
  local covers = GetCovers()
  if not covers then
    return
  end
  for _, row in ipairs(self.rows or {}) do
    covers:EnsureForRollFrame(row)
    covers:SetMode(row, mode)
  end
end

function FakeLootRoll:SetMode(mode)
  self.mode = mode or "UNLOCK_ALL"
  if self.frame and self.frame:IsShown() then
    self:ApplyMode(self.mode)
  end
end

function FakeLootRoll:Show()
  self:EnsureFrame()
  if self.frame then
    self.frame:Show()
  end
  self:ApplyMode(self.mode or "LOCK_ALL")
end

function FakeLootRoll:Hide()
  if self.frame and self.frame:IsShown() then
    self:ApplyMode("UNLOCK_ALL")
    self.frame:Hide()
  end
end

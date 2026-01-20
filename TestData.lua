local _, NS = ...

local GLD = NS.GLD

local SAMPLE_PLAYERS = {
  { name = "Aeryn", class = "MAGE", attendance = "PRESENT" },
  { name = "Bram", class = "WARRIOR", attendance = "PRESENT" },
  { name = "Cyra", class = "PRIEST", attendance = "PRESENT" },
  { name = "Dho", class = "HUNTER", attendance = "PRESENT" },
  { name = "Elra", class = "DRUID", attendance = "PRESENT" },
  { name = "Fenn", class = "PALADIN", attendance = "PRESENT" },
  { name = "Gorr", class = "SHAMAN", attendance = "ABSENT" },
  { name = "Hela", class = "ROGUE", attendance = "ABSENT" },
  { name = "Iris", class = "WARLOCK", attendance = "PRESENT" },
  { name = "Jace", class = "DEMONHUNTER", attendance = "PRESENT" },
}

function GLD:SeedTestData()
  local realm = GetRealmName()

  if not self.testDb then
    return
  end

  self.testDb.players = {}
  self.testDb.queue = {}

  for i, data in ipairs(SAMPLE_PLAYERS) do
    local key = data.name .. "-" .. realm
    self.testDb.players[key] = {
      name = data.name,
      realm = realm,
      class = data.class,
      attendance = data.attendance,
      queuePos = nil,
      savedPos = nil,
      numAccepted = math.max(0, i - 5),
      lastWinAt = 0,
      isHonorary = false,
      attendanceCount = math.max(0, i - 3),
      source = "test",
    }
    if data.attendance == "PRESENT" then
      table.insert(self.testDb.queue, key)
    else
      self.testDb.players[key].savedPos = i
    end
  end

  if NS.TestUI and NS.TestUI.RefreshTestPanel then
    NS.TestUI:RefreshTestPanel()
  end
  if NS.TestUI and NS.TestUI.RefreshTestDataPanel then
    NS.TestUI:RefreshTestDataPanel()
  end
  self:Print("Test data seeded")
end

local _, NS = ...

local GLD = NS.GLD
local CLASS_DATA = NS.CLASS_DATA or {}

local DEFAULT_TEST_PLAYERS = {
  { name = "Lily", class = "DRUID", spec = "Restoration" },
  { name = "Rob", class = "SHAMAN", spec = "Enhancement" },
  { name = "Steph", class = "HUNTER", spec = "Marksmanship" },
  { name = "Alex", class = "WARLOCK", spec = "Affliction" },
  { name = "Ryan", class = "DEATHKNIGHT", spec = "Unholy" },
  { name = "Vulthan", class = "WARRIOR", spec = "Arms" },
}

local function NormalizeName(name)
  if not name then
    return nil
  end
  if strtrim then
    return strtrim(name)
  end
  return name:gsub("^%s+", ""):gsub("%s+$", "")
end

local function NormalizeClassToken(classToken)
  if not classToken then
    return nil
  end
  return tostring(classToken):upper()
end

local function FindSpecForClass(classToken, specName)
  if not classToken or not specName then
    return nil
  end
  local classData = CLASS_DATA[classToken]
  if not classData or not classData.specs then
    return nil
  end
  local target = tostring(specName):lower()
  for name in pairs(classData.specs) do
    if name:lower() == target then
      return name
    end
  end
  return nil
end

local function IsNonNegativeInt(value)
  if type(value) ~= "number" then
    return false
  end
  if value < 0 then
    return false
  end
  return value == math.floor(value)
end

local function GetTestPresentCount(players)
  local count = 0
  for _, player in pairs(players or {}) do
    if player and player.attendance ~= "ABSENT" then
      count = count + 1
    end
  end
  return count
end

local function BuildTestQueueEntries(players, excludeKey)
  local entries = {}
  for key, player in pairs(players or {}) do
    if player and player.attendance ~= "ABSENT" and key ~= excludeKey then
      entries[#entries + 1] = {
        key = key,
        player = player,
        pos = tonumber(player.queuePos) or 99999,
        name = player.name or "",
      }
    end
  end
  table.sort(entries, function(a, b)
    if a.pos == b.pos then
      if a.name == b.name then
        return tostring(a.key) < tostring(b.key)
      end
      return a.name < b.name
    end
    return a.pos < b.pos
  end)
  return entries
end

function GLD:GetTestQueueMax()
  if not self.testDb or not self.testDb.players then
    return 0
  end
  return GetTestPresentCount(self.testDb.players)
end

function GLD:NormalizeTestQueuePositions()
  if not self.testDb or not self.testDb.players then
    return
  end
  local entries = BuildTestQueueEntries(self.testDb.players, nil)
  self.testDb.queue = {}
  for i, entry in ipairs(entries) do
    entry.player.queuePos = i
    self.testDb.queue[i] = entry.key
  end
end

function GLD:MoveTestPlayerToQueueBottom(key)
  if not self.testDb or not self.testDb.players or not key then
    return
  end
  local winner = self.testDb.players[key]
  if not winner or winner.attendance == "ABSENT" then
    return
  end
  local entries = BuildTestQueueEntries(self.testDb.players, key)
  self.testDb.queue = {}
  for i, entry in ipairs(entries) do
    entry.player.queuePos = i
    self.testDb.queue[i] = entry.key
  end
  winner.queuePos = #entries + 1
  self.testDb.queue[#entries + 1] = key
end

function GLD:InitTestDB()
  if not GuildLootTestDB or type(GuildLootTestDB) ~= "table" then
    GuildLootTestDB = {}
  end

  GuildLootTestDB.version = GuildLootTestDB.version or 1
  GuildLootTestDB.players = GuildLootTestDB.players or {}
  GuildLootTestDB.queue = GuildLootTestDB.queue or {}
  GuildLootTestDB.testSessions = GuildLootTestDB.testSessions or {}
  GuildLootTestDB.testSession = GuildLootTestDB.testSession or {
    active = false,
    currentId = nil,
  }

  self.testDb = GuildLootTestDB
end

function GLD:GetTestDB()
  return self.testDb
end

function GLD:FindTestPlayerKeyByName(name, realm)
  local clean = NormalizeName(name)
  if not clean then
    return nil
  end
  local target = clean:lower()
  local realmName = realm and realm ~= "" and realm or GetRealmName()
  for key, player in pairs((self.testDb and self.testDb.players) or {}) do
    if player and player.name and player.name:lower() == target then
      if player.realm == nil or player.realm == realmName then
        return key
      end
    end
  end
  return nil
end

function GLD:ValidateTestPlayer(data, ignoreKey)
  if not data then
    return false, "No player data."
  end

  local name = NormalizeName(data.name)
  if not name or name == "" then
    return false, "Name is required."
  end

  local classToken = NormalizeClassToken(data.class)
  if not classToken or not CLASS_DATA[classToken] then
    return false, "Class must be a valid class token."
  end

  local existingKey = self:FindTestPlayerKeyByName(name, data.realm)
  if existingKey and existingKey ~= ignoreKey then
    return false, "Name already exists in Test DB."
  end

  local warn = nil
  if data.spec and data.spec ~= "" then
    local spec = FindSpecForClass(classToken, data.spec)
    if not spec then
      warn = "Spec does not match the class. Stored anyway."
    end
  end

  if data.queuePos ~= nil and not IsNonNegativeInt(data.queuePos) then
    return false, "Queue Pos must be an integer >= 0."
  end

  if data.savedPos ~= nil and not IsNonNegativeInt(data.savedPos) then
    return false, "Held Pos must be an integer >= 0."
  end

  if data.numAccepted ~= nil and not IsNonNegativeInt(data.numAccepted) then
    return false, "Won must be an integer >= 0."
  end

  if data.attendanceCount ~= nil and not IsNonNegativeInt(data.attendanceCount) then
    return false, "Raids must be an integer >= 0."
  end

  return true, nil, warn
end

function GLD:AddTestPlayer(data)
  if not self.testDb then
    return false, "Test DB not initialized."
  end

  local name = NormalizeName(data.name)
  local classToken = NormalizeClassToken(data.class)
  local ok, err, warn = self:ValidateTestPlayer({
    name = name,
    class = classToken,
    spec = data.spec,
    realm = data.realm,
  })
  if not ok then
    return false, err
  end

  local realm = data.realm and data.realm ~= "" and data.realm or GetRealmName()
  local key = name .. "-" .. realm
  local specName = data.spec or nil
  local normalizedSpec = FindSpecForClass(classToken, specName) or specName

  self.testDb.players[key] = {
    name = name,
    realm = realm,
    class = classToken,
    specName = normalizedSpec,
    attendance = "PRESENT",
    queuePos = data.queuePos,
    savedPos = data.savedPos or 0,
    numAccepted = data.numAccepted or 0,
    attendanceCount = data.attendanceCount or 0,
  }

  return true, key, warn
end

function GLD:UpdateTestPlayer(key, updates)
  if not self.testDb or not self.testDb.players or not self.testDb.players[key] then
    return false, "Test player not found."
  end

  local player = self.testDb.players[key]
  local merged = {
    name = player.name,
    realm = player.realm,
    class = updates.class or player.class,
    spec = updates.spec or player.specName,
    attendance = updates.attendance ~= nil and updates.attendance or player.attendance,
    queuePos = updates.queuePos ~= nil and updates.queuePos or player.queuePos,
    savedPos = updates.savedPos ~= nil and updates.savedPos or player.savedPos,
    numAccepted = updates.numAccepted ~= nil and updates.numAccepted or player.numAccepted,
    attendanceCount = updates.attendanceCount ~= nil and updates.attendanceCount or player.attendanceCount,
  }

  local ok, err, warn = self:ValidateTestPlayer(merged, key)
  if not ok then
    return false, err
  end

  local queuePos = updates.queuePos
  if queuePos ~= nil then
    local maxPos = nil
    if self.GetTestQueueMax then
      if updates.attendance ~= nil then
        local count = GetTestPresentCount(self.testDb.players)
        local wasPresent = player.attendance ~= "ABSENT"
        local willBePresent = merged.attendance ~= "ABSENT"
        if wasPresent and not willBePresent then
          count = count - 1
        elseif not wasPresent and willBePresent then
          count = count + 1
        end
        maxPos = count
      else
        maxPos = self:GetTestQueueMax()
      end
    end
    if maxPos ~= nil and queuePos > maxPos then
      queuePos = maxPos
      warn = warn or ("Queue Pos capped at " .. tostring(maxPos) .. ".")
    end
  end

  if updates.class then
    player.class = NormalizeClassToken(updates.class)
  end
  if updates.spec ~= nil then
    player.specName = FindSpecForClass(player.class, updates.spec) or updates.spec
  end
  if updates.attendance ~= nil then
    if updates.attendance == "ABSENT" then
      if player.attendance ~= "ABSENT" then
        player.savedPos = player.queuePos or player.savedPos or 0
        player.queuePos = nil
      end
      player.attendance = "ABSENT"
    else
      if player.attendance ~= "PRESENT" then
        if player.savedPos and player.savedPos > 0 then
          player.queuePos = player.savedPos
        end
      end
      player.attendance = "PRESENT"
    end
  end
  if updates.queuePos ~= nil and player.attendance ~= "ABSENT" then
    player.queuePos = queuePos
  end
  if updates.savedPos ~= nil then
    player.savedPos = updates.savedPos
  end
  if updates.numAccepted ~= nil then
    player.numAccepted = updates.numAccepted
  end
  if updates.attendanceCount ~= nil then
    player.attendanceCount = updates.attendanceCount
  end

  if (updates.queuePos ~= nil or updates.attendance ~= nil) and self.NormalizeTestQueuePositions then
    self:NormalizeTestQueuePositions()
  end

  return true, nil, warn
end

function GLD:RemoveTestPlayer(key)
  if not self.testDb or not self.testDb.players then
    return false, "Test DB not initialized."
  end
  if not self.testDb.players[key] then
    return false, "Test player not found."
  end
  self.testDb.players[key] = nil
  return true
end

function GLD:ResetTestDB()
  if not self.testDb then
    return false, "Test DB not initialized."
  end
  self.testDb.players = {}
  self.testDb.queue = {}
  self.testDb.testSessions = {}
  self.testDb.testSession = {
    active = false,
    currentId = nil,
  }

  for _, entry in ipairs(DEFAULT_TEST_PLAYERS) do
    self:AddTestPlayer(entry)
  end

  return true
end

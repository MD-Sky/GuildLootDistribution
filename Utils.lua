local _, NS = ...

local GLD = NS.GLD

local CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS
local ROLE_ICON_TCOORDS = {
  TANK = {0, 19/64, 22/64, 41/64},
  HEALER = {20/64, 39/64, 1/64, 20/64},
  DAMAGER = {20/64, 39/64, 22/64, 41/64},
  NONE = {0, 0, 0, 0},
}

function NS:SplitNameRealm(name)
  if not name or name == "" then
    return nil, nil
  end
  local base, realm = strsplit("-", name)
  if not realm or realm == "" then
    realm = GetRealmName()
  end
  return base, realm
end

function NS:GetPlayerKeyFromUnit(unit)
  if not unit or not UnitExists(unit) then
    return nil
  end
  local guid = UnitGUID(unit)
  if guid and guid ~= "" then
    return guid
  end
  local name, realm = UnitName(unit)
  if not name then
    return nil
  end
  if not realm or realm == "" then
    realm = GetRealmName()
  end
  return name .. "-" .. realm
end

function GLD:GetUnitFullName(unit)
  if not unit or not UnitExists(unit) then
    return nil
  end
  local name, realm = UnitName(unit)
  if not name or name == "" then
    return nil
  end
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

function GLD:GetOurGuildName()
  local name = GetGuildInfo("player")
  if name and name ~= "" then
    return name
  end
  return nil
end

function GLD:IsGuest(unitOrMember)
  local ourGuild = self:GetOurGuildName()
  if type(unitOrMember) == "table" then
    if unitOrMember.isGuest ~= nil then
      return unitOrMember.isGuest
    end
    if unitOrMember.source ~= nil then
      return unitOrMember.source == "guest"
    end
    if unitOrMember.member then
      return self:IsGuest(unitOrMember.member)
    end
    if unitOrMember.unit then
      local guildName = GetGuildInfo(unitOrMember.unit)
      if not ourGuild then
        return true
      end
      return not guildName or guildName ~= ourGuild
    end
    return false
  end

  if type(unitOrMember) == "string" and UnitExists(unitOrMember) then
    local guildName = GetGuildInfo(unitOrMember)
    if not ourGuild then
      return true
    end
    return not guildName or guildName ~= ourGuild
  end

  return false
end

function GLD:GetGuidForSender(sender)
  if not sender or sender == "" then
    return nil
  end
  local base, realm = NS:SplitNameRealm(sender)
  if not base then
    return nil
  end
  local fullName = (realm and realm ~= "") and (base .. "-" .. realm) or base

  local function matches(unit)
    if not UnitExists(unit) then
      return false
    end
    local name, unitRealm = UnitName(unit)
    if not name then
      return false
    end
    local unitFull = (unitRealm and unitRealm ~= "") and (name .. "-" .. unitRealm) or name
    return unitFull == fullName or name == sender
  end

  if matches("player") then
    return UnitGUID("player")
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if matches(unit) then
        return UnitGUID(unit)
      end
    end
  end

  return nil
end

function GLD:MaybeWelcomeGuest(unit, fullName)
  if not unit or not UnitExists(unit) or not UnitIsConnected(unit) then
    return
  end
  if UnitIsUnit(unit, "player") then
    return
  end
  if not self:GetOurGuildName() then
    return
  end
  if not self:IsGuest(unit) then
    return
  end

  local guid = UnitGUID(unit)
  if not guid or guid == "" then
    return
  end
  fullName = fullName or self:GetUnitFullName(unit)
  if not fullName or fullName == "" then
    return
  end

  local guestDB = self.guestDB or GLT_DB
  if not guestDB then
    return
  end
  guestDB.seenGuests = guestDB.seenGuests or {}
  guestDB.lastGuestWelcomeAt = guestDB.lastGuestWelcomeAt or {}

  if not guestDB.seenGuests[guid] then
    guestDB.seenGuests[guid] = true
    guestDB.lastGuestWelcomeAt[guid] = time()
    local msg = "Welcome to the Incompetents guild raid. This raid uses our loot system. Guests can vote, but cannot edit our loot table/admin settings."
    SendChatMessage(msg, "WHISPER", nil, fullName)
  end
end

function GLD:WelcomeGuestsFromGroup()
  if not IsInRaid() then
    return
  end

  local function visit(unit)
    if not UnitExists(unit) then
      return
    end
    local fullName = self:GetUnitFullName(unit)
    if fullName then
      self:MaybeWelcomeGuest(unit, fullName)
    end
  end

  for i = 1, GetNumGroupMembers() do
    visit("raid" .. i)
  end
end

function GLD:RebuildGroupRoster()
  local roster = {}
  local rosterByKey = {}
  local currentKeys = {}
  local added = {}
  local previousKeys = self.groupRosterKeys or {}
  local ourGuild = self:GetOurGuildName()

  local function addUnit(unit)
    if not unit or not UnitExists(unit) then
      return
    end
    local key = NS:GetPlayerKeyFromUnit(unit)
    local name, realm = UnitName(unit)
    local fullName = self:GetUnitFullName(unit)
    local guildName = GetGuildInfo(unit)
    local isGuildMember = ourGuild and guildName and guildName == ourGuild or false
    local entry = {
      unit = unit,
      key = key,
      name = name,
      realm = realm,
      fullName = fullName,
      isGuildMember = isGuildMember,
    }
    roster[#roster + 1] = entry
    if key then
      rosterByKey[key] = entry
      currentKeys[key] = true
      if not previousKeys[key] and fullName and not UnitIsUnit(unit, "player") then
        added[#added + 1] = fullName
      end
    end
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      addUnit("raid" .. i)
    end
  else
    addUnit("player")
  end

  self.groupRoster = roster
  self.groupRosterByKey = rosterByKey
  self.groupRosterKeys = currentKeys
  return roster, rosterByKey, added
end

function GLD:CanAccessAdminUI()
  if self:IsGuest("player") then
    return false
  end
  return self:IsAdmin()
end

function GLD:CanMutateState()
  if not self:CanAccessAdminUI() then
    return false
  end
  local authorityGUID = self.GetAuthorityGUID and self:GetAuthorityGUID() or nil
  if not authorityGUID or authorityGUID == "" then
    return true
  end
  return self:IsAuthority()
end

local function GetClassColorObject(classFile)
  if not classFile then
    return nil
  end
  if C_ClassColor and C_ClassColor.GetClassColor then
    return C_ClassColor.GetClassColor(classFile)
  end
  if RAID_CLASS_COLORS then
    return RAID_CLASS_COLORS[classFile]
  end
  return nil
end

function NS:GetPlayerBaseName(name)
  if type(name) == "string" and name ~= "" then
    local base = strsplit("-", name)
    if base and base ~= "" then
      return base
    end
    return name
  end
  if name then
    return tostring(name)
  end
  return nil
end

function NS:GetPlayerDisplayName(name, isGuest)
  local base = NS:GetPlayerBaseName(name)
  if not base or base == "" then
    base = name or "?"
  end
  base = tostring(base)
  if isGuest then
    return base .. "-|cffffffffguest|r"
  end
  return base
end

function NS:GetClassColor(classFile)
  local color = GetClassColorObject(classFile)
  if color then
    return color.r or 1, color.g or 1, color.b or 1
  end
  return 1, 1, 1
end

function NS:GetNameRealmFromKey(key)
  if not key then
    return nil
  end
  if key:find("Player%-") then
    return nil
  end
  return NS:SplitNameRealm(key)
end

function NS:GetClassIcon(classFile)
  if not classFile then
    return ""
  end
  local coords = CLASS_ICON_TCOORDS[classFile]
  if not coords then
    return ""
  end
  return string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:16:16:0:0:256:256:%d:%d:%d:%d|t",
    coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256)
end

function NS:GetRoleIcon(role)
  role = role or "NONE"
  local coords = ROLE_ICON_TCOORDS[role] or ROLE_ICON_TCOORDS.NONE
  if role == "NONE" then
    return ""
  end
  return string.format("|TInterface\\LFGFrame\\UI-LFG-ICON-ROLES:16:16:0:0:64:64:%d:%d:%d:%d|t",
    coords[1] * 64, coords[2] * 64, coords[3] * 64, coords[4] * 64)
end

function NS:ColorAttendance(attendance)
  if attendance == "PRESENT" then
    return "|cff00ff00PRESENT|r"
  end
  return "|cffff0000ABSENT|r"
end

function NS:GetRoleForPlayer(name)
  if not name then
    return "NONE"
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      local unitName = UnitName(unit)
      if unitName == name then
        local role = UnitGroupRolesAssigned(unit)
        if role and role ~= "NONE" then
          return role
        end
      end
    end
  end
  return "NONE"
end

function GLD:UpsertPlayerFromUnit(unit)
  local key = NS:GetPlayerKeyFromUnit(unit)
  if not key then
    return nil
  end
  local name, realm = UnitName(unit)
  local classFile = select(2, UnitClass(unit))
  local player = self.db.players[key]
  if not player then
    player = {
      name = name,
      realm = realm or GetRealmName(),
      class = classFile,
      specId = nil,
      specName = nil,
      attendance = "ABSENT",
      queuePos = nil,
      savedPos = nil,
      numAccepted = 0,
      lastWinAt = 0,
      isHonorary = false,
      attendanceCount = 0,
    }
    self.db.players[key] = player
  else
    player.name = name or player.name
    player.realm = realm or player.realm
    player.class = classFile or player.class
  end
  return key
end

function GLD:AddGuestFromUnit(unit)
  if self.CanMutateState and not self:CanMutateState() then
    if self.Print then
      self:Print("you do not have Guild Permission to access this panel")
    end
    return
  end
  if not unit or not UnitExists(unit) then
    return
  end
  local key = NS:GetPlayerKeyFromUnit(unit)
  if not key then
    return
  end

  local name, realm = UnitName(unit)
  if not name then
    return
  end
  local classFile = select(2, UnitClass(unit))
  local player = self.db.players[key]
  if not player then
    player = {
      name = name,
      realm = realm or GetRealmName(),
      class = classFile,
      attendance = "PRESENT",
      queuePos = nil,
      savedPos = nil,
      numAccepted = 0,
      lastWinAt = 0,
      isHonorary = false,
      attendanceCount = 0,
    }
    self.db.players[key] = player
  else
    player.name = name or player.name
    player.realm = realm or player.realm
    player.class = classFile or player.class
    player.attendance = player.attendance or "PRESENT"
  end
  player.source = "guest"

  self:EnsureQueuePositions()
  self:BroadcastSnapshot()
  if self.UI then
    self.UI:RefreshMain()
  end
  self:Print("Added guest: " .. name)
end

function GLD:RefreshFromGuildRoster()
  if not IsInGuild() then
    self:Print("You are not in a guild.")
    return
  end

  if GuildRoster then
    GuildRoster()
  end

  local attempts = 0
  local function rebuild()
    attempts = attempts + 1
    local count = GetNumGuildMembers and GetNumGuildMembers() or 0
    if (not count or count == 0) and attempts < 6 then
      C_Timer.After(0.4, rebuild)
      return
    end

    local keep = {}
    for key, player in pairs(self.db.players or {}) do
      if player and (player.source == "guest" or player.source == "test") then
        keep[key] = player
      end
    end

    self.db.players = {}
    self.db.queue = {}

    local realmName = GetRealmName()
    for i = 1, (count or 0) do
      local name, _, _, _, _, _, _, _, _, _, classFileName, _, _, _, _, _, guid = GetGuildRosterInfo(i)
      if name then
        local base, realm = NS:SplitNameRealm(name)
        local key = (guid and guid ~= "" and guid) or (base .. "-" .. (realm or realmName))
        self.db.players[key] = {
          name = base,
          realm = realm or realmName,
          class = classFileName,
          attendance = "ABSENT",
          queuePos = nil,
          savedPos = nil,
          numAccepted = 0,
          lastWinAt = 0,
          isHonorary = false,
          attendanceCount = 0,
          source = "guild",
        }
      end
    end

    for key, player in pairs(keep) do
      if not self.db.players[key] then
        self.db.players[key] = player
      end
    end

    self.shadow.roster = {}
    self.shadow.my.queuePos = nil
    self.shadow.my.attendance = nil

    self:AutoMarkCurrentGroup()
    self:EnsureQueuePositions()
    self:BroadcastSnapshot()
    if self.UI then
      self.UI:RefreshMain()
    end
    self:Print("Guild roster loaded.")
  end

  C_Timer.After(0.4, rebuild)
end

function GLD:UpdateGuestAttendanceFromGroup()
  if not self.db or not self.db.players then
    return
  end

  local present = {}
  local function addUnit(unit)
    if not UnitExists(unit) or not UnitIsConnected(unit) then
      return
    end
    local key = NS:GetPlayerKeyFromUnit(unit)
    if key then
      present[key] = true
    end
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      addUnit("raid" .. i)
    end
  else
    addUnit("player")
  end

  for key, player in pairs(self.db.players) do
    if player and player.source == "guest" then
      if present[key] then
        self:SetAttendance(key, "PRESENT")
      else
        self:SetAttendance(key, "ABSENT")
      end
    end
  end
end

local function BuildFullName(name, realm)
  if not name or name == "" then
    return nil
  end
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

function GLD:GetLocalRosterEntry(roster)
  if type(roster) ~= "table" then
    return nil
  end

  local localKey = NS.GetPlayerKeyFromUnit and NS:GetPlayerKeyFromUnit("player") or nil
  local name, realm = UnitName("player")
  local fullName = BuildFullName(name, realm)

  if localKey and roster[localKey] then
    return roster[localKey], localKey
  end
  if fullName and roster[fullName] then
    return roster[fullName], fullName
  end
  if name and roster[name] then
    return roster[name], name
  end

  for key, entry in pairs(roster) do
    if type(entry) == "table" then
      local entryKey = entry.key or entry.playerKey or key
      if localKey and entryKey == localKey then
        return entry, entryKey
      end
      local entryName = entry.name or entry.fullName or entry.displayName
      local entryRealm = entry.realm
      if entryName and not entryRealm and NS.SplitNameRealm then
        local base, parsedRealm = NS:SplitNameRealm(entryName)
        if base then
          entryName = base
          entryRealm = parsedRealm or entryRealm
        end
      end
      local entryFull = BuildFullName(entryName, entryRealm)
      if fullName and entryFull and entryFull == fullName then
        return entry, entryKey
      end
      if name and entryName and entryName == name then
        return entry, entryKey
      end
    end
  end

  return nil
end

function GLD:BuildMySnapshotFromRoster(roster)
  local entry = self:GetLocalRosterEntry(roster)
  if not entry then
    return nil
  end
  return {
    queuePos = entry.queuePos,
    savedPos = entry.savedPos or entry.heldPos or entry.holdPos,
    numAccepted = entry.numAccepted,
    attendance = entry.attendance,
    attendanceCount = entry.attendanceCount,
  }
end

function GLD:UpdateShadowMyFromRoster(roster)
  if not self.shadow then
    return nil
  end
  local snapshot = self:BuildMySnapshotFromRoster(roster)
  if not snapshot then
    return nil
  end
  self.shadow.my = self.shadow.my or {}
  for key, value in pairs(snapshot) do
    self.shadow.my[key] = value
  end
  return snapshot
end

function GLD:BuildRollNonce()
  self._rollNonce = (self._rollNonce or 0) + 1
  local now = GetServerTime and GetServerTime() or time()
  return tostring(now) .. "-" .. tostring(math.random(100000, 999999)) .. "-" .. tostring(self._rollNonce)
end

function GLD:MakeRollKey(rollID, nonce)
  if rollID == nil then
    return nil
  end
  local suffix = nonce and tostring(nonce) or "legacy"
  return tostring(rollID) .. "@" .. suffix
end

function GLD:GetLegacyRollKey(rollID)
  return self:MakeRollKey(rollID, "legacy")
end

function GLD:GetRollKeyFromPayload(payload)
  if not payload then
    return nil
  end
  if payload.rollKey and payload.rollKey ~= "" then
    return tostring(payload.rollKey)
  end
  if payload.rollID ~= nil then
    return self:GetLegacyRollKey(payload.rollID)
  end
  return nil
end

function GLD:IsRollSessionExpired(session, now, maxAgeSeconds)
  if not session then
    return true
  end
  local ts = now or (GetServerTime and GetServerTime() or time())
  if session.locked then
    return true
  end
  if session.rollExpiresAt and session.rollExpiresAt > 0 and session.rollExpiresAt < ts then
    return true
  end
  local maxAge = maxAgeSeconds or 1800
  if session.createdAt and session.createdAt > 0 and session.createdAt < (ts - maxAge) then
    return true
  end
  return false
end

function GLD:FindActiveRoll(rollKey, rollID)
  if not self.activeRolls then
    return rollKey, nil
  end
  if rollKey and self.activeRolls[rollKey] then
    return rollKey, self.activeRolls[rollKey]
  end
  if rollID ~= nil then
    local legacyKey = self:GetLegacyRollKey(rollID)
    if self.activeRolls[legacyKey] then
      return legacyKey, self.activeRolls[legacyKey]
    end
    for key, session in pairs(self.activeRolls) do
      if session and session.rollID == rollID then
        return key, session
      end
    end
  end
  return rollKey, nil
end

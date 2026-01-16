local _, NS = ...

local GLD = NS.GLD

function GLD:GetAuthorityName()
  if not IsInGroup() then
    return nil
  end

  local function fullName(unit)
    local name, realm = UnitName(unit)
    if not name then
      return nil
    end
    if realm and realm ~= "" then
      return name .. "-" .. realm
    end
    return name
  end

  local function isGuildMaster(unit)
    local _, _, rankIndex = GetGuildInfo(unit)
    return rankIndex == 0
  end

  local function isOfficer(unit)
    local _, rankName, rankIndex = GetGuildInfo(unit)
    if rankIndex == 0 then
      return true
    end
    return rankName and rankName:lower() == "officer"
  end

  local function isRaidLeaderOrAssistant(unit)
    return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
  end

  local gm = nil
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitIsConnected(unit) and isGuildMaster(unit) then
        gm = fullName(unit)
        break
      end
    end
  else
    if UnitExists("player") and UnitIsConnected("player") and isGuildMaster("player") then
      gm = fullName("player")
    end
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) and UnitIsConnected(unit) and isGuildMaster(unit) then
        gm = fullName(unit)
        break
      end
    end
  end

  if gm then
    return gm
  end

  local officers = {}
  local function consider(unit)
    if UnitExists(unit) and UnitIsConnected(unit) and isOfficer(unit) and isRaidLeaderOrAssistant(unit) then
      local name = fullName(unit)
      if name then
        table.insert(officers, { name = name, leader = UnitIsGroupLeader(unit) })
      end
    end
  end

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      consider("raid" .. i)
    end
  else
    consider("player")
    for i = 1, GetNumSubgroupMembers() do
      consider("party" .. i)
    end
  end

  table.sort(officers, function(a, b)
    if a.leader ~= b.leader then
      return a.leader
    end
    return a.name < b.name
  end)

  return officers[1] and officers[1].name or nil
end

function GLD:IsAuthority()
  local authority = self:GetAuthorityName()
  if not authority then
    return false
  end
  local name, realm = UnitName("player")
  if realm and realm ~= "" then
    return authority == name .. "-" .. realm
  end
  return authority == name
end

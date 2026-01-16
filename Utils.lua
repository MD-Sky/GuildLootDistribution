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

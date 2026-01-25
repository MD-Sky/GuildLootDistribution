local _, NS = ...

local GLD = NS.GLD

function GLD:SetSessionAuthority(guid, name)
  if not self.db or not self.db.session then
    return
  end
  if guid and guid ~= "" then
    self.db.session.authorityGUID = guid
  else
    self.db.session.authorityGUID = nil
  end
  if name and name ~= "" then
    self.db.session.authorityName = name
  else
    self.db.session.authorityName = nil
  end
end

function GLD:ClearSessionAuthority()
  if not self.db or not self.db.session then
    return
  end
  self.db.session.authorityGUID = nil
  self.db.session.authorityName = nil
end

function GLD:GetAuthorityGUID()
  return self.db and self.db.session and self.db.session.authorityGUID or nil
end

function GLD:GetAuthorityName()
  local session = self.db and self.db.session or nil
  if session and session.authorityName and session.authorityName ~= "" then
    return session.authorityName
  end
  local guid = session and session.authorityGUID or nil
  if guid and self.db and self.db.players and self.db.players[guid] then
    local player = self.db.players[guid]
    local name = player.name
    local realm = player.realm
    if name then
      if realm and realm ~= "" then
        return name .. "-" .. realm
      end
      return name
    end
  end
  if guid then
    local function tryUnit(unit)
      if UnitExists(unit) and UnitGUID(unit) == guid then
        return self:GetUnitFullName(unit)
      end
      return nil
    end
    local name = tryUnit("player")
    if name then
      return name
    end
    if IsInRaid() then
      for i = 1, GetNumGroupMembers() do
        name = tryUnit("raid" .. i)
        if name then
          return name
        end
      end
    elseif IsInGroup() then
      for i = 1, GetNumSubgroupMembers() do
        name = tryUnit("party" .. i)
        if name then
          return name
        end
      end
    end
  end
  return nil
end

function GLD:IsAuthority()
  local authorityGUID = self:GetAuthorityGUID()
  if not authorityGUID then
    return false
  end
  local myGuid = UnitGUID("player")
  return myGuid and myGuid == authorityGUID
end

function GLD:IsAuthorizedSender(sender, payloadAuthorityGUID, payloadAuthorityName)
  local senderGuid = self.GetGuidForSender and self:GetGuidForSender(sender) or nil
  if payloadAuthorityGUID and senderGuid and payloadAuthorityGUID ~= senderGuid then
    return false, senderGuid
  end

  local authorityGUID = self:GetAuthorityGUID()
  if (not authorityGUID or authorityGUID == "") and (payloadAuthorityGUID or senderGuid) then
    local name = payloadAuthorityName or sender
    self:SetSessionAuthority(payloadAuthorityGUID or senderGuid, name)
    authorityGUID = self:GetAuthorityGUID()
  end

  if payloadAuthorityGUID and authorityGUID and authorityGUID ~= payloadAuthorityGUID then
    return false, senderGuid
  end

  if not authorityGUID or not senderGuid then
    return false, senderGuid
  end

  if payloadAuthorityName and payloadAuthorityName ~= "" and authorityGUID == senderGuid then
    if self.db and self.db.session and (not self.db.session.authorityName or self.db.session.authorityName == "") then
      self.db.session.authorityName = payloadAuthorityName
    end
  end

  return senderGuid == authorityGUID, senderGuid
end

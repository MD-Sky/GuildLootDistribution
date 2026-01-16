local _, NS = ...

local GLD = NS.GLD

function GLD:GetAuthorityName()
  if not IsInGroup() then
    return nil
  end

  if UnitIsGroupLeader("player") and self:IsAdmin() then
    local name, realm = UnitName("player")
    if realm and realm ~= "" then
      return name .. "-" .. realm
    end
    return name
  end

  local assistants = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitIsGroupAssistant(unit) then
        local name, realm = UnitName(unit)
        if name then
          if realm and realm ~= "" then
            table.insert(assistants, name .. "-" .. realm)
          else
            table.insert(assistants, name)
          end
        end
      end
    end
  end

  table.sort(assistants)
  return assistants[1]
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

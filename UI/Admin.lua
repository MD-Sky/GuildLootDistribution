local _, NS = ...

local GLD = NS.GLD
local UI = NS.UI

function UI:OpenAdmin()
  if not GLD.CanAccessAdminUI or not GLD:CanAccessAdminUI() then
    GLD:ShowPermissionDeniedPopup()
    return
  end
  GLD:OpenConfig()
end

local _, NS = ...

local GLD = NS.GLD
local UI = NS.UI

function UI:OpenAdmin()
  if not GLD.CanMutateState or not GLD:CanMutateState() then
    GLD:Print("you do not have Guild Permission to access this panel")
    return
  end
  GLD:OpenConfig()
end

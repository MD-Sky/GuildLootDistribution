local _, NS = ...

local GLD = NS.GLD

function GLD:InitConfig()
  local AceConfig = LibStub("AceConfig-3.0", true)
  local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
  if not AceConfig or not AceConfigDialog then
    return
  end

  local options = {
    type = "group",
    name = "GuildLoot",
    args = {
      general = {
        type = "group",
        name = "General",
        order = 1,
        args = {
          transmogWinnerMove = {
            type = "select",
            name = "Transmog winner move",
            values = { END = "End", MIDDLE = "Middle" },
            get = function() return GLD.db.config.transmogWinnerMove end,
            set = function(_, val) GLD.db.config.transmogWinnerMove = val end,
            order = 1,
          },
          greedWinnerMove = {
            type = "select",
            name = "Greed winner move",
            values = { NONE = "None", END = "End" },
            get = function() return GLD.db.config.greedWinnerMove end,
            set = function(_, val) GLD.db.config.greedWinnerMove = val end,
            order = 2,
          },
          debugLogs = {
            type = "toggle",
            name = "Enable debug logs",
            desc = "Show debug messages in chat (off by default).",
            get = function() return GLD.db.config.debugLogs == true end,
            set = function(_, val) GLD.db.config.debugLogs = val and true or false end,
            hidden = function() return not GLD:IsAdmin() end,
            order = 99,
          },
        },
      },
    },
  }

  AceConfig:RegisterOptionsTable("GuildLoot", options)
  self.options = options
end

function GLD:OpenConfig()
  local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
  if not AceConfigDialog then
    return
  end
  AceConfigDialog:Open("GuildLoot")
end

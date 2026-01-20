-- Minimal ChatThrottleLib implementation for embedded addons
-- Provides required SendAddonMessage wrapper without throttling.

local MAJOR, MINOR = "ChatThrottleLib", 1
local LibStub = LibStub
if not LibStub then
  return
end

local CTL = LibStub:NewLibrary(MAJOR, MINOR)
if not CTL then
  return
end

-- Ensure full ChatThrottleLib versions can safely replace this stub.
CTL.version = 0
CTL.securelyHooked = true

local SendAddonMessageFunc = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
local SendChatMessageFunc = SendChatMessage

function CTL:SendAddonMessage(prio, prefix, text, distribution, target, queueName, callbackFn, callbackArg)
  if not SendAddonMessageFunc then
    if callbackFn then
      callbackFn(callbackArg or 0, false)
    end
    return false
  end

  local result = SendAddonMessageFunc(prefix, text, distribution, target)
  if callbackFn then
    local sent = callbackArg
    if type(sent) ~= "number" then
      sent = #(text or "")
    end
    callbackFn(sent, result)
  end
  return result
end

function CTL:SendChatMessage(prio, text, chatType, language, target, queueName, callbackFn, callbackArg)
  if not SendChatMessageFunc then
    if callbackFn then
      callbackFn(callbackArg or 0, false)
    end
    return false
  end

  local result = SendChatMessageFunc(text, chatType, language, target)
  if callbackFn then
    local sent = callbackArg
    if type(sent) ~= "number" then
      sent = #(text or "")
    end
    callbackFn(sent, result)
  end
  return result
end

function CTL:Enqueue(prio, prefix, text, distribution, target, queueName, callbackFn, callbackArg)
  if prefix and text and distribution then
    return self:SendAddonMessage(prio, prefix, text, distribution, target, queueName, callbackFn, callbackArg)
  end
  if callbackFn then
    local sent = callbackArg
    if type(sent) ~= "number" then
      sent = #(text or "")
    end
    callbackFn(sent, true)
  end
  return true
end

ChatThrottleLib = CTL

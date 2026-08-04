--------------------------------------------------------
-- logger.lua
-- App-wide logger with backend-controlled remote logging
--------------------------------------------------------

local composer = require("composer")
local network = require("network")

local M = {}

local BACKEND_BASE = "https://infoshagame.com"
local DEBUG_URL = BACKEND_BASE .. "/debug.php"

local isSending = false

local function urlEncode(str)
    str = tostring(str or "")
    str = str:gsub("\n", " ")
    str = str:gsub("\r", " ")
    str = str:gsub("([^%w %-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
    return str
end

local function joinArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    return table.concat(parts, " ")
end

local function remoteEnabled()
    return composer.getVariable("debugLoggingEnabled") == true
end

local function currentUserId()
    return composer.getVariable("userId")
end

function M.isEnabled()
    return remoteEnabled()
end

function M.log(...)
    local msg = joinArgs(...)
    print(msg)

    if not remoteEnabled() then
        return
    end

    if isSending then
        return
    end

    isSending = true

    local userId = currentUserId() or ""
    local url = DEBUG_URL
        .. "?msg=" .. urlEncode(msg)
        .. "&userId=" .. urlEncode(userId)

    network.request(url, "GET", function()
        isSending = false
    end)
end

function M.scene(sceneName, ...)
    local prefix = "[scene:" .. tostring(sceneName or "unknown") .. "]"
    M.log(prefix, ...)
end

function M.error(...)
    M.log("[ERROR]", ...)
end

function M.warn(...)
    M.log("[WARN]", ...)
end

return M
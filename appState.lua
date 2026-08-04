
-- appState.lua
local M = {
    userId = nil,
    userName = nil,
    prefix = nil,
    className = nil,
    classStatus = "Draft",
    apiToken = nil,

    -- Access / subscription state
    hasAccess = false,
    accessStatus = nil,
    accessSource = nil,
    accessEndsAt = nil,
}

function M.set(data)
    if not data then return end

    if data.userId ~= nil then M.userId = data.userId end
    if data.userName ~= nil then M.userName = data.userName end
    if data.prefix ~= nil then M.prefix = data.prefix end
    if data.className ~= nil then M.className = data.className end
    if data.classStatus ~= nil then M.classStatus = data.classStatus end
    if data.apiToken ~= nil then M.apiToken = data.apiToken end

    if data.hasAccess ~= nil then M.hasAccess = data.hasAccess end
    if data.accessStatus ~= nil then M.accessStatus = data.accessStatus end
    if data.accessSource ~= nil then M.accessSource = data.accessSource end
    if data.accessEndsAt ~= nil then M.accessEndsAt = data.accessEndsAt end
end

function M.get()
    return {
        userId = M.userId,
        userName = M.userName,
        prefix = M.prefix,
        className = M.className,
        classStatus = M.classStatus,
        apiToken = M.apiToken,

        hasAccess = M.hasAccess,
        accessStatus = M.accessStatus,
        accessSource = M.accessSource,
        accessEndsAt = M.accessEndsAt,
    }
end

function M.restoreAuthsFromPrefs(state, shared)
    state = state or {}
    shared = shared or {}

    local token = shared.apiToken

    if not token or token == "" then
        token = system.getPreference("app", "apiToken", "string")
    end

    state.apiToken = token

    M.set({
        userId = state.userId,
        userName = state.userName,
        apiToken = token,
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })

    return token
end

function M.clearClass()
    M.prefix = nil
    M.className = nil
    M.classStatus = "Draft"
end

function M.clearAccess()
    M.hasAccess = false
    M.accessStatus = nil
    M.accessSource = nil
    M.accessEndsAt = nil
end

function M.clearAll()
    M.userId = nil
    M.userName = nil
    M.prefix = nil
    M.className = nil
    M.classStatus = "Draft"
    M.apiToken = nil

    M.clearAccess()
end

return M
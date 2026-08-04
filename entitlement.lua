-- entitlement.lua
local M = {}

local billing = require("billing")
local appState = require("appState")

local function applyEntitlementData(data)
    data = data or {}

    appState.set({
        hasAccess = (data.active == true),
        accessStatus = data.status,
        accessSource = data.entitlementSource,
        accessEndsAt = data.currentPeriodEnd or data.freeAccessEndsAt
    })
end

function M.refresh(callback)
    billing.checkEntitlement(function(result)
        if result.success then
            local data = result.data or {}
            applyEntitlementData(data)

            if callback then
                callback({
                    success = true,
                    data = data
                })
            end
        else
            if callback then
                callback({
                    success = false,
                    error = result.error
                })
            end
        end
    end)
end

function M.hasAccess()
    local state = appState.get()
    return (state.hasAccess == true)
end

function M.status()
    local state = appState.get()
    return state.accessStatus
end

function M.source()
    local state = appState.get()
    return state.accessSource
end

function M.endsAt()
    local state = appState.get()
    return state.accessEndsAt
end

return M
-- buttonAccess.lua
local M = {}

function M.hasAccess(appState)
 --   return true  -- for debug - remove before build!
    local s = appState and appState.get and appState.get() or {}
    return s.hasAccess == true
end

function M.applyPrimaryActionAccess(button, hasAccess, colors)
    if not button then return end

    button.alpha = hasAccess and 1.0 or 0.4

    if button.label then
        if hasAccess then
            button.label:setFillColor(unpack(colors.textOnPrimary))
        else
            button.label:setFillColor(0.85, 0.85, 0.85)
        end
    end

    if button.icon then
        button.icon.alpha = hasAccess and 1.0 or 0.5
    end
end

return M
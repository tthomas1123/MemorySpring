-------------------------------------------------------
-- accessibleButton.lua
-- Reusable Accessible Button Component for Solar2D
-------------------------------------------------------
local accessibleButton = {}

function accessibleButton.new(sceneGroup, label, x, y, colorSet, onTap, icon, scale)
    scale = scale or 1.0
    local btnWidth  = display.contentWidth  * 0.50 * scale
    local btnHeight = display.contentHeight * 0.06 * scale
    local cornerRadius = 14
    local fontSize = math.floor(btnHeight * 0.38)

    -- Button container
    local group = display.newGroup()
    group.x, group.y = x, y

    -- Main button shape
    local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, cornerRadius)
    front:setFillColor(unpack(colorSet))
    front.strokeWidth = 4
    front:setStrokeColor(0, 0, 0, 0.3)
    front.alpha = 0.98

    -- Focus outline
    local focusOutline = display.newRoundedRect(group, 0, 0, btnWidth + 8, btnHeight + 8, cornerRadius + 4)
    focusOutline:setFillColor(0, 0, 0, 0)
    focusOutline:setStrokeColor(0.2, 0.6, 1, 0.9)
    focusOutline.strokeWidth = 5
    focusOutline.alpha = 0
    front.focusOutline = focusOutline

    -- Icon + label
    local iconText = icon and (icon .. "  ") or ""
    local labelText = display.newText({
        parent = group,
        text = iconText .. label,
        font = native.systemFontBold,
        fontSize = fontSize,
        align = "center"
    })
    labelText:setFillColor(0, 0, 0)

    ---------------------------------------------------
    -- Touch & focus handlers
    ---------------------------------------------------
    local function onTouch(event)
        if event.phase == "began" then
            transition.to(front, {time = 80, xScale = 0.95, yScale = 0.95})
            labelText.alpha = 0.8
            focusOutline.alpha = 1
        elseif event.phase == "ended" or event.phase == "cancelled" then
            transition.to(front, {time = 80, xScale = 1.0, yScale = 1.0})
            labelText.alpha = 1.0
            transition.to(focusOutline, {time = 150, alpha = 0})
            if onTap then onTap(event) end
        end
        return true
    end

    local function onHover(event)
        if event.isPrimaryMouseButtonDown then return end
        if event.isMouseOver then
            transition.to(front, {time = 120, alpha = 1.0})
            transition.to(focusOutline, {time = 150, alpha = 0.8})
        else
            transition.to(front, {time = 120, alpha = 0.9})
            transition.to(focusOutline, {time = 150, alpha = 0})
        end
    end

    -- Add event listeners
    front:addEventListener("touch", onTouch)
    labelText:addEventListener("touch", onTouch)
    front:addEventListener("mouse", onHover)

    -- Keyboard/gamepad focus outline
    group:addEventListener("key", function(event)
        if event.phase == "down" and (event.keyName == "tab" or event.keyName == "space" or event.keyName == "enter") then
            focusOutline.alpha = 1
        elseif event.phase == "up" then
            focusOutline.alpha = 0
        end
        return false
    end)

    -- Insert into scene group if provided
    if sceneGroup then
        sceneGroup:insert(group)
    end

    return group
end

return accessibleButton

------------------------------------------------------------
-- ui/standardHeader.lua
-- Standard header for SmartSheep + SmartSheepCreator
-- Pattern:
--   • Back arrow (top-left) with LARGE invisible hit target
--   • Title (default centered)
--   • NO underline/divider (use spacing below header)
-- Safe-area aware (display.safe*)
--
-- NEW (auto-fit title):
--   • Title will auto-scale down if it would overlap back hit area (or right reserved area)
--   • Reserve space on BOTH sides so long translations don't collide
--
-- NEW (titlePlacement = "back"):
--   • Title renders next to the back arrow (e.g., "Back")
--   • Title hugs the icon + uses smaller font
--   • Back hit target expands to include the title text
--
-- Usage:
--   local StandardHeader = require("ui.standardHeader")
--   local header = StandardHeader.new(sceneGroup, {
--       titleKey       = "support",
--       fallbackTitle  = "Support",
--       onBack         = function() composer.gotoScene("settings", { effect="slideRight", time=250 }) end,
--       backIconImage  = "icons/back.png",
--       headerH        = display.contentHeight * 0.11,
--       titleFontSize  = 80,
--       titleColor     = colors.textPrimary,
--       hitSize        = 72,
--       iconSize       = 56,
--
--       -- Optional:
--       -- titlePlacement = "center" | "back"
--       -- backLabelFontSize = 42
--       -- backLabelGap = 10
--       -- sideReserveFactor = 1.35,
--       -- minTitleScale     = 0.70,
--   })
------------------------------------------------------------

local M = {}

local languages = require("languages")
local colors    = require("colors")

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- reasonable defaults across phones/tablets
local function defaultSizes()
    local h = display.contentHeight

    -- Large tap area (thumb-friendly)
    local hit = math.floor(h * 0.085)

    -- Slightly smaller icon (cleaner look)
    local icon = math.floor(h * 0.048)

    -- Minimums so small phones still feel good
    hit = math.max(hit, 64)
    icon = math.max(icon, 40)

    return hit, icon
end

function M.new(sceneGroup, opts)
    opts = opts or {}

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth

    local headerH = opts.headerH or opts.height or math.floor(display.contentHeight * 0.11)

    -- Title row center (slightly below exact center tends to look better with large fonts)
    local titleY = safeY + headerH * (opts.titleYFactor or 0.55)

    local hitDefault, iconDefault = defaultSizes()
    local hitSize  = opts.hitSize  or hitDefault
    local iconSize = opts.iconSize or iconDefault

    local group = display.newGroup()
    if sceneGroup then sceneGroup:insert(group) end

    local function resolveTitle()
        if opts.titleKey and opts.titleKey ~= "" then
            return languages.t(opts.titleKey) or opts.fallbackTitle or opts.titleKey
        end
        return opts.fallbackTitle or ""
    end

    --------------------------------------------------------
    -- Back button (icon + large invisible hit rect)
    --------------------------------------------------------
    local backGroup = display.newGroup()
    group:insert(backGroup)

    -- Left padding: align with your existing pattern
    backGroup.x = safeX + hitSize * (opts.leftFactor or 0.70)
    backGroup.y = titleY

    -- invisible hit target (we may resize it later if titlePlacement="back")
    local hitRect = display.newRect(backGroup, 0, 0, hitSize, hitSize)
    hitRect.isVisible = false
    hitRect.isHitTestable = true

    local backIconPath = opts.backIconImage or "icons/back.png"
    local backIcon = nil

    if backIconPath and backIconPath ~= "" then
        backIcon = display.newImageRect(backGroup, backIconPath, iconSize, iconSize)
        if backIcon then
            backIcon.x, backIcon.y = 0, 0
        else
            print("WARNING: back icon failed to load:", backIconPath)
        end
    end

    -- Optional fallback glyph if PNG missing
    local fallbackText = nil
    if (not backIcon) and (opts.fallbackGlyph ~= false) then
        fallbackText = display.newText({
            parent   = backGroup,
            text     = "←",
            x        = 0,
            y        = 0,
            font     = native.systemFontBold,
            fontSize = math.floor(iconSize * 0.95),
            align    = "center"
        })
        fallbackText:setFillColor(unpack(opts.iconColor or colors.textPrimary))
    end

    --------------------------------------------------------
    -- Title placement
    --------------------------------------------------------
    local titlePlacement = opts.titlePlacement or "center" -- "center" (default) or "back"
    local title = nil

    -- Center title (default behavior)
    if titlePlacement ~= "back" then
        title = display.newText({
            parent   = group,
            text     = resolveTitle(),
            x        = safeX + safeW * 0.5,
            y        = titleY,
            font     = opts.titleFont or native.systemFontBold,
            fontSize = opts.titleFontSize or 80,
            align    = "center"
        })
        title:setFillColor(unpack(opts.titleColor or colors.textPrimary))
    else
        -- Back-adjacent label ("Back" hugging arrow)
        local labelText = resolveTitle()
        local gap = opts.backLabelGap or math.floor(iconSize * 0.25)
        local backLabelSize = opts.backLabelFontSize or math.floor((opts.titleFontSize or 80) * 0.55)

        title = display.newText({
            parent   = backGroup,
            text     = labelText,
            x        = 0,
            y        = 0,
            font     = opts.titleFont or native.systemFontBold,
            fontSize = backLabelSize,
            align    = "left"
        })
        title.anchorX = 0
        title:setFillColor(unpack(opts.titleColor or colors.textPrimary))

        local iconW = (backIcon and backIcon.width) or (fallbackText and fallbackText.width) or iconSize
        local iconRight = iconW * 0.5

        title.x = iconRight + gap
        title.y = 0

        -- Expand hitRect to include the label too
        -- Keep generous left space + cover through end of label
        local rightMost = title.x + title.width
        local leftMost  = -hitSize * 0.55
        local neededW = (rightMost - leftMost) + (hitSize * 0.15)
        hitRect.width = math.max(hitSize, neededW)
    end

    --------------------------------------------------------
    -- Back touch feedback
    --------------------------------------------------------
    local function pressVisual(isDown)
        local target = backIcon or fallbackText
        if not target then return end
        if isDown then
            transition.to(target, { time = 80, xScale = 0.92, yScale = 0.92 })
            target.alpha = 0.85
            if titlePlacement == "back" and title then title.alpha = 0.85 end
        else
            transition.to(target, { time = 80, xScale = 1.0, yScale = 1.0 })
            target.alpha = 1.0
            if titlePlacement == "back" and title then title.alpha = 1.0 end
        end
    end

    local function backTouch(event)
        if event.phase == "began" then
            pressVisual(true)
        elseif event.phase == "ended" or event.phase == "cancelled" then
            pressVisual(false)
            if opts.onBack then opts.onBack(event) end
        end
        return true
    end

    hitRect:addEventListener("touch", backTouch)
    if backIcon then backIcon:addEventListener("touch", backTouch) end
    if fallbackText then fallbackText:addEventListener("touch", backTouch) end
    if titlePlacement == "back" and title then title:addEventListener("touch", backTouch) end

    --------------------------------------------------------
    -- Title fitting (center title only)
    --------------------------------------------------------
    local sideReserveFactor = opts.sideReserveFactor or 1.35
    local minTitleScale     = opts.minTitleScale or 0.70

    local function fitTitle()
        if titlePlacement == "back" then return end
        if not title or not title.removeSelf then return end

        title.xScale, title.yScale = 1.0, 1.0

        local sideReserve = hitSize * sideReserveFactor
        local maxTitleW = safeW - (sideReserve * 2)
        maxTitleW = math.max(80, maxTitleW)

        if title.width > maxTitleW then
            local s = maxTitleW / title.width
            s = clamp(s, minTitleScale, 1.0)
            title.xScale, title.yScale = s, s
        end
    end

    fitTitle()

    --------------------------------------------------------
    -- Public API
    --------------------------------------------------------
    local header = {
        group = group,
        title = title,
        headerH = headerH,
        headerBottomY = safeY + headerH,
        refresh = function()
            if title and title.removeSelf then
                title.text = resolveTitle()
                if titlePlacement ~= "back" then
                    fitTitle()
                end
                -- if placement="back" and language changes, hitRect may need resize:
                if titlePlacement == "back" then
                    local gap = opts.backLabelGap or math.floor(iconSize * 0.25)
                    local iconW = (backIcon and backIcon.width) or (fallbackText and fallbackText.width) or iconSize
                    local iconRight = iconW * 0.5
                    title.anchorX = 0
                    title.x = iconRight + gap

                    local rightMost = title.x + title.width
                    local leftMost  = -hitSize * 0.55
                    local neededW = (rightMost - leftMost) + (hitSize * 0.15)
                    hitRect.width = math.max(hitSize, neededW)
                end
            end
        end,
        destroy = function()
            if group and group.removeSelf then group:removeSelf() end
        end
    }

    return header
end

return M

------------------------------------------------------------
-- support.lua (SmartSheep / Creator)
-- UPDATED:
--   • Background now uses aspect-fill to extend to true screen edges
--   • Full responsive layout on resize/orientation changes
--   • Uses ui/standardHeader.lua (no underline / divider)
--   • Header title auto-fits for long translations
--   • Buttons:
--       - Icons line up (fixed left inset)
--       - Text truly centered
--       - Auto-fit label so long translations never overflow
------------------------------------------------------------
local composer = require("composer")
local scene    = composer.newScene()

local colors         = require("colors")
local languages      = require("languages")
local StandardHeader = require("ui.standardHeader")

local buttons = {}
local background

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function fitTextToWidth(txt, maxW, minScale)
    if not txt or not txt.removeSelf then return end
    minScale = minScale or 0.70

    txt.xScale, txt.yScale = 1.0, 1.0
    if txt.width <= maxW then return end

    local s = maxW / txt.width
    s = clamp(s, minScale, 1.0)
    txt.xScale, txt.yScale = s, s
end

local function newAspectFillImage(parent, filename)
    local img = display.newImage(parent, filename)
    if not img then
        print("ERROR: failed to load background:", filename)
        return nil
    end

    local iw, ih = img.width, img.height
    local sw = display.actualContentWidth
    local sh = display.actualContentHeight

    local scale = math.max(sw / iw, sh / ih)
    img.xScale = scale
    img.yScale = scale

    img.x = display.contentCenterX
    img.y = display.contentCenterY

    return img
end

------------------------------------------------------------
-- Helper: Button (menu-style) + optional icon
-- Layout rules:
--   1) icon anchored to a FIXED left inset (consistent across buttons)
--   2) label is always centered (x=0)
--   3) label auto-scales down if it would overflow
------------------------------------------------------------
local function makeButton(sceneGroup, label, y, colorSet, onTap, scale, strokeColor, textColor, fontScale, iconImage, iconSize, fallbackEmoji)
    scale = scale or 1.0
    fontScale = fontScale or 1.0

    local btnHeight = display.contentHeight * 0.08
    local fontSize  = math.floor(btnHeight * 0.35) * fontScale
    local btnWidth  = display.contentWidth * 0.78 * scale

    local group = display.newGroup()
    group.x, group.y = display.contentCenterX, y
    sceneGroup:insert(group)

    local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, 14)
    front:setFillColor(unpack(colorSet))
    front.strokeWidth = 5
    front:setStrokeColor(unpack(strokeColor or colors.primaryActionPressed))
    front.alpha = 0.95

    --------------------------------------------------------
    -- Icon (fixed left inset)
    --------------------------------------------------------
    local iconDisplay = nil
    local iconW = iconSize or math.floor(btnHeight * 0.75)
    local iconLeftInset = math.floor(btnWidth * 0.16)

    if iconImage and iconImage ~= "" then
        iconDisplay = display.newImageRect(group, iconImage, iconW, iconW)
        if not iconDisplay then
            print("WARNING: icon image not found/failed to load:", iconImage)
        end
    end

    if (not iconDisplay) and fallbackEmoji and fallbackEmoji ~= "" then
        iconDisplay = display.newText({
            parent = group,
            text = fallbackEmoji,
            font = native.systemFontBold,
            fontSize = math.floor(fontSize * 1.1),
            align = "center"
        })
        iconDisplay:setFillColor(unpack(textColor or colors.textOnPrimary))
    end

    if iconDisplay then
        iconDisplay.x = -btnWidth * 0.5 + iconLeftInset
        iconDisplay.y = 0
    end

    --------------------------------------------------------
    -- Centered label (independent of icon width)
    --------------------------------------------------------
    local labelText = display.newText({
        parent = group,
        text = label,
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = fontSize,
        align = "center"
    })
    labelText:setFillColor(unpack(textColor or colors.textOnPrimary))

    local function fitLabel()
        if not labelText or not labelText.removeSelf then return end
        labelText.xScale, labelText.yScale = 1.0, 1.0

        local maxW = btnWidth * 0.86
        if labelText.width > maxW then
            local s = maxW / labelText.width
            s = clamp(s, 0.75, 1.0)
            labelText.xScale, labelText.yScale = s, s
        end
    end
    fitLabel()

    --------------------------------------------------------
    -- Touch behavior
    --------------------------------------------------------
    local function onTouch(event)
        if event.phase == "began" then
            transition.to(front, { time = 80, xScale = 0.95, yScale = 0.95 })
            labelText.alpha = 0.8
            if iconDisplay then iconDisplay.alpha = 0.8 end
        elseif event.phase == "ended" or event.phase == "cancelled" then
            transition.to(front, { time = 80, xScale = 1.0, yScale = 1.0 })
            labelText.alpha = 1.0
            if iconDisplay then iconDisplay.alpha = 1.0 end
            if onTap then onTap(event) end
        end
        return true
    end

    front:addEventListener("touch", onTouch)
    labelText:addEventListener("touch", onTouch)
    if iconDisplay then iconDisplay:addEventListener("touch", onTouch) end

    group.label      = labelText
    group.icon       = iconDisplay
    group.iconImage  = iconImage
    group.fitLabel   = fitLabel
    group._btnWidth  = btnWidth
    group._btnHeight = btnHeight

    return group
end

------------------------------------------------------------
-- URL helpers
------------------------------------------------------------
local function openURL(url)
    if url and url ~= "" then
        system.openURL(url)
    end
end

local function openMailTo(email, subject)
    email = email or "admin@infoshagame.com"
    subject = subject or "InfoSha Game Support"
    local mailto = "mailto:" .. email .. "?subject=" .. string.gsub(subject, " ", "%%20")
    system.openURL(mailto)
end

------------------------------------------------------------
-- Scene Create
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    background = newAspectFillImage(sceneGroup, "settings-background.png")
    if background then
        background:toBack()
    end

    --------------------------------------------------------
    -- Header (StandardHeader; auto-fits title; NO underline)
    --------------------------------------------------------
    local hitSize  = math.max(math.floor(display.contentHeight * 0.085), 64)
    local iconSize = math.max(math.floor(display.contentHeight * 0.048), 40)
    local baseTitleSize = clamp(math.floor(display.contentHeight * 0.050), 44, 72)

    local header = StandardHeader.new(sceneGroup, {
        titleKey      = "support",
        fallbackTitle = "Support",
        backIconImage = "icons/back.png",
        hitSize       = hitSize,
        iconSize      = iconSize,
        titleFontSize = baseTitleSize,
        onBack = function()
            composer.gotoScene("settings", { effect = "slideRight", time = 250 })
        end
    })
    self._header = header

    local function fitHeaderTitle()
        if not header or not header.title then return end
        local safeW = display.safeActualContentWidth or display.contentWidth
        local pad = 16
        local maxTitleW = safeW - (hitSize * 2) - (pad * 2)
        fitTextToWidth(header.title, maxTitleW, 0.70)
    end
    self._fitHeaderTitle = fitHeaderTitle
    fitHeaderTitle()

    --------------------------------------------------------
    -- Buttons (start below header)
    --------------------------------------------------------
    local topPadding = display.contentHeight * 0.06
    local y = header.headerBottomY + topPadding
    local spacing = display.contentHeight * 0.10

    buttons.contact = makeButton(
        sceneGroup,
        languages.t("contact_support") or "Contact Support",
        y,
        colors.primaryAction,
        function()
            openMailTo("admin@infoshagame.com", "InfoSha Game Support")
        end,
        1,
        colors.primaryActionPressed,
        colors.textOnPrimary,
        1,
        "icons/support2.png",
        nil,
        "✉️"
    )

    buttons.privacyKids = makeButton(
        sceneGroup,
        languages.t("kids_privacy") or "Privacy Policy",
        y + spacing,
        colors.primaryAction,
        function()
            openURL("https://infoshagame.com/creator-privacy/index.html")
        end,
        1,
        colors.primaryActionPressed,
        colors.textOnPrimary,
        1,
        "icons/privacy.png",
        nil,
        "🔒"
    )

    buttons.website = makeButton(
        sceneGroup,
        languages.t("visit_website") or "Visit Website",
        y + spacing * 2.0,
        colors.primaryAction,
        function()
            openURL("https://infoshagame.com/creator-terms")
        end,
        1,
        colors.primaryActionPressed,
        colors.textOnPrimary,
        1,
        "icons/web.png",
        nil,
        "🌐"
    )

    --------------------------------------------------------
    -- Layout
    --------------------------------------------------------
    local function layoutScene()
        local safeY = display.safeScreenOriginY or 0

        if background and background.removeSelf then
            local iw, ih = background.width, background.height
            local sw = display.actualContentWidth
            local sh = display.actualContentHeight
            local scale = math.max(sw / iw, sh / ih)

            background.xScale = scale
            background.yScale = scale
            background.x = display.contentCenterX
            background.y = display.contentCenterY
        end

        if self._fitHeaderTitle then
            self._fitHeaderTitle()
        end

        local headerBottomY = 0
        if self._header and self._header.headerBottomY then
            headerBottomY = self._header.headerBottomY
        else
            headerBottomY = safeY + math.floor(display.contentHeight * 0.11)
        end

        local topPadding = display.contentHeight * 0.06
        local startY = headerBottomY + topPadding
        local spacing = display.contentHeight * 0.10

        if buttons.contact then
            buttons.contact.x = display.contentCenterX
            buttons.contact.y = startY
            if buttons.contact.fitLabel then buttons.contact.fitLabel() end
        end

        if buttons.privacyKids then
            buttons.privacyKids.x = display.contentCenterX
            buttons.privacyKids.y = startY + spacing
            if buttons.privacyKids.fitLabel then buttons.privacyKids.fitLabel() end
        end

        if buttons.website then
            buttons.website.x = display.contentCenterX
            buttons.website.y = startY + spacing * 2.0
            if buttons.website.fitLabel then buttons.website.fitLabel() end
        end

        if background then background:toBack() end
        if self._header and self._header.group then self._header.group:toFront() end
        if buttons.contact then buttons.contact:toFront() end
        if buttons.privacyKids then buttons.privacyKids:toFront() end
        if buttons.website then buttons.website:toFront() end
    end

    self._layoutScene = layoutScene

    --------------------------------------------------------
    -- Language Refresh Hook
    --------------------------------------------------------
    function scene.refreshLanguage()
        if scene._header and scene._header.refresh then
            scene._header.refresh()
            if scene._fitHeaderTitle then
                scene._fitHeaderTitle()
            end
        end

        if buttons.contact and buttons.contact.label then
            buttons.contact.label.text = languages.t("contact_support") or "Contact Support"
            if buttons.contact.fitLabel then buttons.contact.fitLabel() end
        end

        if buttons.privacyKids and buttons.privacyKids.label then
            buttons.privacyKids.label.text = languages.t("kids_privacy") or "Privacy Policy"
            if buttons.privacyKids.fitLabel then buttons.privacyKids.fitLabel() end
        end

        if buttons.website and buttons.website.label then
            buttons.website.label.text = languages.t("visit_website") or "Visit Website"
            if buttons.website.fitLabel then buttons.website.fitLabel() end
        end

        if scene._layoutScene then
            scene._layoutScene()
        end
    end

    layoutScene()
end

scene:addEventListener("create", scene)

------------------------------------------------------------
-- Refresh on return + resize handling
------------------------------------------------------------
function scene:show(event)
    if event.phase == "did" then
        if self.refreshLanguage then
            self.refreshLanguage()
        end

        if not self._onResize then
            self._onResize = function()
                if self._layoutScene then
                    self._layoutScene()
                end
            end
            Runtime:addEventListener("resize", self._onResize)
        end

        if self._layoutScene then
            self._layoutScene()
        end
    end
end
scene:addEventListener("show", scene)

function scene:hide(event)
    if event.phase == "will" then
        if self._onResize then
            Runtime:removeEventListener("resize", self._onResize)
            self._onResize = nil
        end
    end
end
scene:addEventListener("hide", scene)

function scene:destroy(event)
    if self._onResize then
        Runtime:removeEventListener("resize", self._onResize)
        self._onResize = nil
    end

    if background and background.removeSelf then
        background:removeSelf()
        background = nil
    end
end
scene:addEventListener("destroy", scene)

return scene
------------------------------------------------------------
-- settings.lua
-- SmartSheep Creator
--
-- Updated:
--   • Uses StandardHeader back arrow like languageSettings.lua
--   • Returns to whichever scene opened it
--   • Keeps mock layout
--   • Buttons: Language / About / Support / Log Out
--   • Green Subscribe button at bottom
------------------------------------------------------------
local composer = require("composer")
local scene    = composer.newScene()

local colors         = require("colors")
local languages      = require("languages")
local StandardHeader = require("ui.standardHeader")
local billing = require("billing")
local appState = require("appState")

local buttons = {}
local background
local sheep
local titleLabel
local returnSceneName = "menu"

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
    minScale = minScale or 0.72

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
-- Return navigation
------------------------------------------------------------
local function goBack()
    composer.gotoScene(returnSceneName or "menu", {
        effect = "slideRight",
        time = 220
    })
end

local function gotoPaywall()
    composer.gotoScene("paywall", {
        effect = "slideLeft",
        time = 220,
        params = {
            returnTo = "settings"
        }
    })
end

------------------------------------------------------------
-- Button helper
------------------------------------------------------------
local function makeButton(sceneGroup, label, y, fillColor, onTap, opts)
    opts = opts or {}

    local scale       = opts.scale or 1.0
    local strokeColor = opts.strokeColor or colors.primaryActionPressed
    local textColor   = opts.textColor or colors.textOnPrimary
    local iconImage   = opts.iconImage
    local fallback    = opts.fallbackEmoji or ""
    local fontScale   = opts.fontScale or 1.0

    local btnHeight = display.contentHeight * 0.072 * scale
    local fontSize  = math.floor(btnHeight * 0.34) * fontScale
    local btnWidth  = display.contentWidth * 0.78 * scale

    local group = display.newGroup()
    group.x, group.y = display.contentCenterX, y
    sceneGroup:insert(group)

    local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, 14)
    front:setFillColor(unpack(fillColor))
    front.strokeWidth = 4
    front:setStrokeColor(unpack(strokeColor))
    front.alpha = 0.96

    local iconDisplay = nil
    local iconW = math.floor(btnHeight * 0.62)
    local iconInset = btnWidth * 0.16

    if iconImage and iconImage ~= "" then
        iconDisplay = display.newImageRect(group, iconImage, iconW, iconW)
    end

    if (not iconDisplay) and fallback ~= "" then
        iconDisplay = display.newText({
            parent = group,
            text = fallback,
            x = 0,
            y = 0,
            font = native.systemFontBold,
            fontSize = math.floor(fontSize * 1.05)
        })
        iconDisplay:setFillColor(unpack(textColor))
    end

    if iconDisplay then
        iconDisplay.x = -btnWidth * 0.5 + iconInset
        iconDisplay.y = 0
    end

    local labelText = display.newText({
        parent = group,
        text = label,
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = fontSize,
        align = "center"
    })
    labelText:setFillColor(unpack(textColor))

    local function fitLabel()
        local maxW = btnWidth * 0.84
        fitTextToWidth(labelText, maxW, 0.75)
    end
    fitLabel()

    local function onTouch(event)
        if event.phase == "began" then
            transition.to(front, { time = 80, xScale = 0.96, yScale = 0.96 })
            labelText.alpha = 0.85
            if iconDisplay then iconDisplay.alpha = 0.85 end
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

    group.front = front
    group.label = labelText
    group.icon = iconDisplay
    group.fitLabel = fitLabel
    group._btnHeight = btnHeight
    group._btnWidth = btnWidth

    return group
end

------------------------------------------------------------
-- Scene Create
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    if event and event.params and event.params.returnTo then
        returnSceneName = event.params.returnTo
    else
        returnSceneName = composer.getSceneName("previous") or "menu"
    end

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    background = newAspectFillImage(sceneGroup, "settings-background.png")
    if background then background:toBack() end

    --------------------------------------------------------
    -- Header (same style as languageSettings)
    --------------------------------------------------------
    local hitSize  = math.max(math.floor(display.contentHeight * 0.085), 64)
    local iconSize = math.max(math.floor(display.contentHeight * 0.048), 40)
    local baseTitleSize = clamp(math.floor(display.contentHeight * 0.050), 44, 72)

    local header = StandardHeader.new(sceneGroup, {
        titleKey      = "settings",
        fallbackTitle = "Settings",
        backIconImage = "icons/back.png",
        hitSize       = hitSize,
        iconSize      = iconSize,
        titleFontSize = baseTitleSize,
        onBack = function()
            goBack()
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
    -- Buttons
    --------------------------------------------------------
    buttons.language = makeButton(
        sceneGroup,
        languages.t("language") or "Language",
        0,
        colors.primaryAction,
        function()
            composer.gotoScene("languageSettings", {
                effect = "slideLeft",
                time = 220,
                params = {
                    returnTo = "settings"
                }
            })
        end,
        {
            strokeColor = colors.primaryActionPressed,
            textColor = colors.textOnPrimary,
            iconImage = "icons/lang.png",
            fallbackEmoji = "🌐"
        }
    )

    buttons.about = makeButton(
        sceneGroup,
        languages.t("about") or "About",
        0,
        colors.primaryAction,
        function()
            composer.gotoScene("about", { effect = "slideLeft", time = 220 })
        end,
        {
            strokeColor = colors.primaryActionPressed,
            textColor = colors.textOnPrimary,
            iconImage = "icons/about.png",
            fallbackEmoji = "📘"
        }
    )

    buttons.support = makeButton(
        sceneGroup,
        languages.t("support") or "Support",
        0,
        colors.primaryAction,
        function()
            composer.gotoScene("support", { effect = "slideLeft", time = 220 })
        end,
        {
            strokeColor = colors.primaryActionPressed,
            textColor = colors.textOnPrimary,
            iconImage = "icons/support.png",
            fallbackEmoji = "🛟"
        }
    )

    buttons.logout = makeButton(
        sceneGroup,
        languages.t("log_out") or "Log Out",
        0,
        colors.primaryAction,
        function()
            billing.clearUserId()

            appState.clearAll()

            system.deletePreferences("app", { "userId", "userName" })

            composer.setVariable("userId", nil)
            composer.setVariable("userName", nil)
            composer.setVariable("subscriptionPlan", nil)
            composer.setVariable("subscriptionStatus", nil)
            composer.setVariable("debugLoggingEnabled", false)

            composer.removeScene("addClass")
            composer.removeScene("selectLevels")
            composer.removeScene("customize")

            composer.gotoScene("menu", { effect = "fade", time = 220 })
        end,
        {
            strokeColor = colors.primaryActionPressed,
            textColor = colors.textOnPrimary,
            iconImage = "icons/logout.png",
            fallbackEmoji = "↪"
        }
    )

    buttons.subscribe = makeButton(
        sceneGroup,
        languages.t("subscribe") or "Subscribe",
        0,
        colors.subscribeAction,
        gotoPaywall,
        {
            scale = 0.88,
            strokeColor = colors.subscribeActionBorder,
            textColor = colors.textOnPrimary or { 1, 1, 1 },
            iconImage = "icons/star.png",
            fallbackEmoji = "⭐"
        }
    )

    --------------------------------------------------------
    -- Sheep trio
    --------------------------------------------------------
    sheep = display.newImage(sceneGroup, "sheep-trio.png")
    if sheep then
        local targetW = display.contentWidth * 0.52
        local scale = targetW / sheep.width
        sheep.xScale, sheep.yScale = scale, scale
        sheep.alpha = 0.96
        sheep.anchorY = 0
    end

    --------------------------------------------------------
    -- Layout
    --------------------------------------------------------
    local function layoutScene()
        local top    = display.safeScreenOriginY or 0
        local swSafe = display.safeActualContentWidth or display.contentWidth
        local shSafe = display.safeActualContentHeight or display.contentHeight

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
            headerBottomY = top + math.floor(display.contentHeight * 0.11)
        end

        local startY = headerBottomY + (display.contentHeight * 0.06)
        local spacing = display.contentHeight * 0.10

        if buttons.language then
            buttons.language.x = display.contentCenterX
            buttons.language.y = startY
            if buttons.language.fitLabel then buttons.language.fitLabel() end
        end

        if buttons.about then
            buttons.about.x = display.contentCenterX
            buttons.about.y = startY + spacing
            if buttons.about.fitLabel then buttons.about.fitLabel() end
        end

        if buttons.support then
            buttons.support.x = display.contentCenterX
            buttons.support.y = startY + spacing * 2
            if buttons.support.fitLabel then buttons.support.fitLabel() end
        end

        if buttons.logout then
            buttons.logout.x = display.contentCenterX
            buttons.logout.y = startY + spacing * 3
            if buttons.logout.fitLabel then buttons.logout.fitLabel() end
        end

        if sheep and sheep.removeSelf and buttons.logout then
            local targetW = swSafe * 0.52
            local scale = targetW / sheep.width
            sheep.xScale, sheep.yScale = scale, scale
            sheep.x = display.contentCenterX
            sheep.y = buttons.logout.y + (buttons.logout._btnHeight * 0.5) + 18
        end

        if buttons.subscribe and sheep then
            buttons.subscribe.x = display.contentCenterX
            buttons.subscribe.y = sheep.y + sheep.height * sheep.yScale + 28
            if buttons.subscribe.fitLabel then buttons.subscribe.fitLabel() end
        end

        if background then background:toBack() end
        if sheep then sheep:toFront() end
        if self._header and self._header.group then self._header.group:toFront() end
        if buttons.language then buttons.language:toFront() end
        if buttons.about then buttons.about:toFront() end
        if buttons.support then buttons.support:toFront() end
        if buttons.logout then buttons.logout:toFront() end
        if buttons.subscribe then buttons.subscribe:toFront() end
    end

    self._layoutScene = layoutScene

    --------------------------------------------------------
    -- Language refresh
    --------------------------------------------------------
    function scene.refreshLanguage()
        if scene._header and scene._header.refresh then
            scene._header.refresh()
            if scene._fitHeaderTitle then
                scene._fitHeaderTitle()
            end
        end

        if buttons.language and buttons.language.label then
            buttons.language.label.text = languages.t("language") or "Language"
            if buttons.language.fitLabel then buttons.language.fitLabel() end
        end

        if buttons.about and buttons.about.label then
            buttons.about.label.text = languages.t("about") or "About"
            if buttons.about.fitLabel then buttons.about.fitLabel() end
        end

        if buttons.support and buttons.support.label then
            buttons.support.label.text = languages.t("support") or "Support"
            if buttons.support.fitLabel then buttons.support.fitLabel() end
        end

        if buttons.logout and buttons.logout.label then
            buttons.logout.label.text = languages.t("log_out") or "Log Out"
            if buttons.logout.fitLabel then buttons.logout.fitLabel() end
        end

        if buttons.subscribe and buttons.subscribe.label then
            buttons.subscribe.label.text = languages.t("subscribe") or "Subscribe"
            if buttons.subscribe.fitLabel then buttons.subscribe.fitLabel() end
        end

        if scene._layoutScene then
            scene._layoutScene()
        end
    end

    layoutScene()
end

scene:addEventListener("create", scene)

------------------------------------------------------------
-- Show / Hide / Destroy
------------------------------------------------------------
function scene:show(event)
    if event.phase == "did" then
        if event and event.params and event.params.returnTo then
            returnSceneName = event.params.returnTo
        end

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

    if sheep and sheep.removeSelf then
        sheep:removeSelf()
        sheep = nil
    end

    if background and background.removeSelf then
        background:removeSelf()
        background = nil
    end
end
scene:addEventListener("destroy", scene)

return scene
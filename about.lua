------------------------------------------------------------
-- about.lua
-- UPDATED:
--   • Background now uses aspect-fill to extend to true screen edges
--   • Full responsive layout on resize/orientation changes
--   • Uses ui/standardHeader.lua (Back icon only: icons/back.png)
--   • NO underline/divider
--   • Header title auto-fits for long translations
--   • Version label anchored with bottom padding so it stays visible
------------------------------------------------------------
local composer = require("composer")
local scene    = composer.newScene()

local colors         = require("colors")
local languages      = require("languages")
local StandardHeader = require("ui.standardHeader")

local background
local body
local version

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Shrink-to-fit (single line) using xScale/yScale
local function fitTextToWidth(txt, maxW, minScale)
    if not txt or not txt.removeSelf then return end
    minScale = minScale or 0.70

    txt.xScale, txt.yScale = 1.0, 1.0
    if txt.width <= maxW then return end

    local s = maxW / txt.width
    s = clamp(s, minScale, 1.0)
    txt.xScale, txt.yScale = s, s
end

-- Match menu/settings background behavior so image reaches true edges
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
-- Scene creation
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    local userId     = composer.getVariable("userId")
    local userName   = composer.getVariable("userName")

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    background = newAspectFillImage(sceneGroup, "settings-background.png")
    if background then
        background:toBack()
    else
        print("ERROR: Failed to load background image 'settings-background.png'")
    end

    --------------------------------------------------------
    -- Header (Standard back arrow -> settings)
    --------------------------------------------------------
    local hitSize  = math.max(math.floor(display.contentHeight * 0.085), 64)
    local iconSize = math.max(math.floor(display.contentHeight * 0.048), 40)
    local baseTitleSize = clamp(math.floor(display.contentHeight * 0.050), 44, 72)

    local header = StandardHeader.new(sceneGroup, {
        titleKey      = "about_smartsheep",
        fallbackTitle = "About SmartSheep",
        backIconImage = "icons/back.png",
        hitSize       = hitSize,
        iconSize      = iconSize,
        titleFontSize = baseTitleSize,
        onBack = function()
            local menuScene = composer.getScene("menu")
            if menuScene and menuScene.refreshLanguage then
                menuScene.refreshLanguage()
            end

            composer.gotoScene("settings", {
                effect = "slideRight",
                time = 250,
                params = {
                    user = userId,
                    name = userName
                }
            })
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
    -- Content helpers
    --------------------------------------------------------
    local function getAboutBody()
        return languages.t("about_body") or
            ("SmartSheep turns Scripture memory into a fun game.\n\n" ..
             "Catch one word at a time until the verse is completed exactly.\n\n" ..
             "Built for families, classes, and ministries.")
    end

    local versionString = system.getInfo("appVersionString") or "1.0.0"

    local function getVersionLine()
        return (languages.t("version") or "Version") .. " " .. versionString
    end

    --------------------------------------------------------
    -- Content area
    --------------------------------------------------------
    body = display.newText({
        parent   = sceneGroup,
        text     = getAboutBody(),
        x        = display.contentCenterX,
        y        = 0,
        width    = (display.safeActualContentWidth or display.contentWidth) * 0.86,
        font     = native.systemFontBold,
        fontSize = 60,
        align    = "left"
    })
    body.anchorY = 0
    body:setFillColor(unpack(colors.textPrimary))

    version = display.newText({
        parent   = sceneGroup,
        text     = getVersionLine(),
        x        = display.contentCenterX,
        y        = 0,
        font     = native.systemFont,
        fontSize = 60,
        align    = "center"
    })
    version.anchorY = 1
    version:setFillColor(unpack(colors.textOnPrimary))

    --------------------------------------------------------
    -- Layout
    --------------------------------------------------------
    local function layoutScene()
        local safeX = display.safeScreenOriginX or 0
        local safeY = display.safeScreenOriginY or 0
        local safeW = display.safeActualContentWidth or display.contentWidth
        local safeH = display.safeActualContentHeight or display.contentHeight

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

        local contentTop = headerBottomY + (display.contentHeight * 0.06)

        if body and body.removeSelf then
            body.width = safeW * 0.86
            body.x = safeX + safeW * 0.5
            body.y = contentTop
        end

        if version and version.removeSelf then
            local bottomPadding = math.max(display.contentHeight * 0.05, 30)
            version.x = safeX + safeW * 0.5
            version.y = safeY + safeH - bottomPadding
        end

        if background then background:toBack() end
        if self._header and self._header.group then self._header.group:toFront() end
        if body then body:toFront() end
        if version then version:toFront() end
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

        if body then
            body.text = getAboutBody()
        end

        if version then
            version.text = getVersionLine()
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

    if body and body.removeSelf then
        body:removeSelf()
        body = nil
    end

    if version and version.removeSelf then
        version:removeSelf()
        version = nil
    end

    if background and background.removeSelf then
        background:removeSelf()
        background = nil
    end
end
scene:addEventListener("destroy", scene)

return scene
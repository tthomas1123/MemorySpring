------------------------------------------------------------
-- languageSettings.lua (SmartSheep Creator)
-- UPDATED:
--   • Background now uses aspect-fill to extend to true screen edges
--   • Full responsive layout on resize/orientation changes
--   • Uses ui/standardHeader.lua (Back icon only: icons/back.png)
--   • NO underline/divider
--   • Header title auto-fits for long translations
--   • Language buttons slightly larger + consistent spacing
------------------------------------------------------------
local composer = require("composer")
local scene    = composer.newScene()

local colors           = require("colors")
local accessibleButton = require("accessibleButton")
local languages        = require("languages")
local StandardHeader   = require("ui.standardHeader")

local background
local languageButtons = {}

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
        titleKey      = "select_language",
        fallbackTitle = "Select Language",
        backIconImage = "icons/back.png",
        hitSize       = hitSize,
        iconSize      = iconSize,
        titleFontSize = baseTitleSize,
        onBack = function()
            local menuScene = composer.getScene("menu")
            if menuScene and menuScene.refreshLanguage then
                menuScene.refreshLanguage()
            end

            local aboutScene = composer.getScene("about")
            if aboutScene and aboutScene.refreshLanguage then
                aboutScene.refreshLanguage()
            end

            local settingsScene = composer.getScene("settings")
            if settingsScene and settingsScene.refreshLanguage then
                settingsScene.refreshLanguage()
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
    -- Language List
    --------------------------------------------------------
    local langList = languages.supported or { "en" }
    local buttonScale = 0.85

    local function onLanguageSelect(lang)
        languages.setLanguage(lang)
        system.setPreferences("app", { language = lang })

        native.showAlert(
            languages.t("language_updated") or "Language updated",
            languages.t("restart_notice") or "The change will apply immediately.",
            { languages.t("ok") or "OK" }
        )

        if self._header and self._header.refresh then
            self._header.refresh()
            fitHeaderTitle()
        end
    end

    for i, lang in ipairs(langList) do
        local displayName = string.upper(lang)

        local btn = accessibleButton.new(
            sceneGroup,
            displayName,
            display.contentCenterX,
            0,
            colors.secondaryAction,
            function()
                onLanguageSelect(lang)
            end,
            nil,
            buttonScale
        )

        languageButtons[#languageButtons + 1] = btn
    end

    --------------------------------------------------------
    -- Layout
    --------------------------------------------------------
    local function layoutScene()
        local top = display.safeScreenOriginY or 0

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

        local buttonY = headerBottomY + (display.contentHeight * 0.07)
        local spacing = math.floor(display.contentHeight * 0.085)

        for i, btn in ipairs(languageButtons) do
            if btn and btn.removeSelf then
                btn.x = display.contentCenterX
                btn.y = buttonY + (i - 1) * spacing
            end
        end

        if background then background:toBack() end
        if self._header and self._header.group then self._header.group:toFront() end
        for _, btn in ipairs(languageButtons) do
            if btn and btn.toFront then
                btn:toFront()
            end
        end
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

    for i = 1, #languageButtons do
        languageButtons[i] = nil
    end

    if background and background.removeSelf then
        background:removeSelf()
        background = nil
    end
end
scene:addEventListener("destroy", scene)

return scene
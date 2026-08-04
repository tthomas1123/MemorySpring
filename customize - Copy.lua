-- customize.lua (LEVEL EDITOR ONLY)
-- Solar2D / Composer Scene

local composer  = require("composer")
local widget    = require("widget")
local scene     = composer.newScene()

local languages = require("languages")
local colors    = require("colors")
local json      = require("json")
local accessibleButton = require("accessibleButton")
local StandardHeader   = require("ui.standardHeader")
local logger           = require("logger")
local appState         = require("appState")
local buttonAccess     = require("buttonAccess")

local destroyThemeOverlay
local setNativeInputsVisible
local layoutUI
local relayoutTitleField
local getLayoutSafeRect
local setKeyboardState
local goBack = false
local levelReqHandle = nil
local successLoadHandles = {}
local successSaveHandle = nil
local loadToken = 0

local UI = nil
local TITLE_FONT_NAME = native.systemFontBold

local S = {
    userId   = nil,
    userName = nil,
    prefix   = nil,
    classStatus = "Draft",

    mode       = "edit",
    levelId    = "NEW",
    levelTitle = "",
    className  = "",
    lastThemeValue = "Original",

    background = nil,
    fullBleedBg = nil,
    persistentDim = nil,

    header = nil,
    headerBand = nil,
    headerBandDivider = nil,
    gearGroup = nil,

    topCard = nil,
    classIdText = nil,
    classHelperText = nil,

    levelNameField = nil,
    titleInputCardGroup = nil,
    _titleMeasureText = nil,

    themeLabel = nil,
    themeToggleBtn = nil,
    themeBtnLabel = nil,

    recordStatus = nil,
    recordStatusBg = nil,

    themeOverlay    = nil,
    themeOverlayDim = nil,
    themeListCard   = nil,
    themeTable      = nil,
    themeListHint   = nil,
    themeDoneBtn    = nil,

    Level = nil,

    saveBtn = nil,

    wordsCard = nil,

    activeSection = "words",
    tabsGroup = nil,
    tabWords = nil,
    tabSuccess = nil,
    tabsBaseline = nil,

    wordsHeaderText = nil,
    previewLevelPill = nil,
    wordsInputCardGroup = nil,
    wordsTextBox = nil,

    successHeaderText = nil,
    previewSuccessPill = nil,
    successInputCardGroup = nil,
    successTextBox = nil,

    titleDirty = false,
    wordsDirty = false,
    successDirty = false,

    keyboardInset = 0,
    editingField = nil,

    _onResize = nil,
    L = { safeX=0, safeY=0, safeW=0, safeH=0, _baseSafe=nil },

    _themeCommitted = nil,
    _themePending   = nil,

    _isActive = false,
    _initialized = false,
    wordsCache = "",
    successCache = ""
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function isiOS()
    return system.getInfo("platformName") == "iPhone OS"
end

local function isAndroid()
    return system.getInfo("platformName") == "Android"
end

local function buildUI(safeW, safeH)
    local shortSide = math.min(safeW, safeH)
    local scale = shortSide / 375

    local ui = {
        fontBold = native.systemFontBold,
        fontBody = native.systemFont,

        fsHero     = math.floor(clamp(40 * scale, 30, 46)),
        fsSubhero  = math.floor(clamp(22 * scale, 17, 24)),
        fsLabel    = math.floor(clamp(20 * scale, 17, 22)),
        fsSection  = math.floor(clamp(22 * scale, 18, 24)),
        fsButton   = math.floor(clamp(18 * scale, 16, 20)),
        fsInput    = math.floor(clamp(20 * scale, 17, 22)),
        fsBody     = math.floor(clamp(18 * scale, 16, 20)),
        fsStatus   = math.floor(clamp(18 * scale, 15, 20)),
        fsTab      = math.floor(clamp(20 * scale, 16, 22)),
        fsPill     = math.floor(clamp(18 * scale, 15, 20)),

        titleMax   = math.floor(clamp(26 * scale, 20, 28)),
        titleMin   = math.floor(clamp(18 * scale, 16, 20)),

        inputH     = math.floor(clamp(44 * scale, 40, 50)),
        pickerH    = math.floor(clamp(40 * scale, 36, 46)),
        buttonH    = math.floor(clamp(46 * scale, 42, 52)),
        pillH      = math.floor(clamp(34 * scale, 30, 38)),
        tabH       = math.floor(clamp(44 * scale, 40, 50)),

        radiusCard   = math.floor(clamp(24 * scale, 18, 26)),
        radiusInput  = math.floor(clamp(14 * scale, 12, 16)),
        radiusPicker = math.floor(clamp(14 * scale, 12, 16)),
        radiusButton = math.floor(clamp(16 * scale, 14, 18)),
        radiusPill   = math.floor(clamp(12 * scale, 10, 14)),
        radiusTab    = math.floor(clamp(16 * scale, 14, 18)),

        strokeWCard  = 3,
        strokeWInput = 2,
        strokeWThin  = 2,

        gapXS = math.floor(clamp(8 * scale, 6, 10)),
        gapSM = math.floor(clamp(12 * scale, 10, 14)),
        gapMD = math.floor(clamp(16 * scale, 12, 18)),
        gapLG = math.floor(clamp(20 * scale, 16, 24)),

        nativeFieldInset = 6,
        nativeBodyInset  = 6,
    }

    if isiOS() then
        ui.inputH = ui.inputH + 2
        ui.pickerH = ui.pickerH + 2
        ui.nativeFieldInset = 4
        ui.nativeBodyInset = 4
    elseif isAndroid() then
        ui.fsInput = math.max(16, ui.fsInput - 1)
        ui.fsBody = math.max(15, ui.fsBody - 1)
        ui.nativeFieldInset = 6
        ui.nativeBodyInset = 6
    end

    return ui
end

local function urlencode(str)
    if str then
        str = tostring(str)
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

local function safeRect()
    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight
    return safeX, safeY, safeW, safeH
end

local function stableSafeRect()
    local safeX, safeY, safeW, safeH = safeRect()

    if not S.L._baseSafe then
        S.L._baseSafe = { x = safeX, y = safeY, w = safeW, h = safeH }
    end

    -- Freeze the baseline while the keyboard is active / a field is being edited.
    -- This prevents Android from getting "double adjusted" when the OS already
    -- shrinks the viewport.
    if (S.keyboardInset or 0) > 0 or S.editingField then
        local b = S.L._baseSafe
        return b.x, b.y, b.w, b.h
    end

    -- Refresh baseline only when keyboard is closed and the change is real.
    local b = S.L._baseSafe
    if math.abs(safeW - b.w) > 2 or math.abs(safeH - b.h) > 2 then
        S.L._baseSafe = { x = safeX, y = safeY, w = safeW, h = safeH }
        b = S.L._baseSafe
    end

    return b.x, b.y, b.w, b.h
end

getLayoutSafeRect = function()
    local rawX, rawY, rawW, rawH = safeRect()
    local baseX, baseY, baseW, baseH = stableSafeRect()

    if isiOS() then
        -- iOS should use the stable safe area only.
        -- Do not subtract a keyboard inset.
        return baseX, baseY, baseW, baseH, 0
    end

    local viewportReduced = 0
    if rawH and baseH then
        viewportReduced = math.max(0, baseH - rawH)
    end

    local effectiveInset = S.keyboardInset or 0

    -- If Android already shrank the viewport, do not double-adjust.
    if viewportReduced > 20 then
        effectiveInset = 0
    end

    return baseX, baseY, baseW, baseH, effectiveInset
end

local function fitTextToWidth(textObj, maxSize, minSize, maxWidth)
    if not textObj then return end
    maxSize = maxSize or 60
    minSize = minSize or 18
    maxWidth = maxWidth or (display.contentWidth * 0.9)

    local fs = maxSize
    textObj.size = fs
    local guard = 0
    while textObj.contentWidth > maxWidth and fs > minSize and guard < 80 do
        fs = fs - 1
        textObj.size = fs
        guard = guard + 1
    end
end

local function computeNativeBoxFontSize(safeW, safeH)
    return (UI and UI.fsBody) or 18
end

local function refreshLayoutSoon()
    if not S or not S._onResize then return end

    S._onResize()

    timer.performWithDelay(30, function()
        if S and S._isActive and S._onResize then
            S._onResize()
        end
    end)
end

local function computeTitleFontSize(safeW, safeH)
    if UI then
        return UI.titleMax
    end
    local base = math.floor(safeH * 0.022)
    return clamp(base, 16, 26)
end

local function fitNativeFieldFont(field, measureTextObj, text, maxSize, minSize, maxWidth, fontName)
    if not field then return end

    local chosenFont = fontName or TITLE_FONT_NAME
    local content = tostring(text or "")

    if content == "" then
        field.font = native.newFont(chosenFont, maxSize)
        return
    end

    if not measureTextObj then
        field.font = native.newFont(chosenFont, maxSize)
        return
    end

    local fs = maxSize
    measureTextObj.text = content
    measureTextObj.size = fs

    local guard = 0
    while measureTextObj.contentWidth > maxWidth and fs > minSize and guard < 80 do
        fs = fs - 1
        measureTextObj.size = fs
        guard = guard + 1
    end

    field.font = native.newFont(chosenFont, fs)
end

relayoutTitleField = function()
    if not S.levelNameField then return end

    local safeW = S.L.safeW or display.contentWidth
    local safeH = S.L.safeH or display.contentHeight
    local maxSize = computeTitleFontSize(safeW, safeH)
    local minSize = UI and UI.titleMin or 12
    local usableWidth = math.max(80, (S.levelNameField.width or 0) - 28)

    fitNativeFieldFont(
        S.levelNameField,
        S._titleMeasureText,
        S.levelNameField.text,
        maxSize,
        minSize,
        usableWidth,
        TITLE_FONT_NAME
    )
end

local function hasUnsavedChanges()
    return S.titleDirty or S.wordsDirty or S.successDirty
end

local function setButtonEnabled(btn, enabled)
    if not btn then return end
    btn._isEnabled = enabled
    btn.alpha = enabled and 1.0 or 0.45
end

local function updatePreviewAvailability()
    local hasSavedLevel = (S.Level and S.Level.text and S.Level.text ~= "NEW")
    local canPreview = hasSavedLevel and (not hasUnsavedChanges())
    setButtonEnabled(S.previewLevelPill, canPreview)
    setButtonEnabled(S.previewSuccessPill, canPreview)
end

local function setRecordStatus(msg)
    if not S.recordStatus then return end

    msg = msg or ""
    S.recordStatus.text = msg

    local has = (tostring(msg):gsub("%s+", "") ~= "")
    S.recordStatus.isVisible = has

    if S.recordStatusBg then
        S.recordStatusBg.isVisible = has
        if has then
            local padW = 28
            local padH = 14
            S.recordStatusBg.width = math.min(display.contentWidth * 0.88, S.recordStatus.contentWidth + padW)
            S.recordStatusBg.height = S.recordStatus.contentHeight + padH
            S.recordStatusBg.x = S.recordStatus.x
            S.recordStatusBg.y = S.recordStatus.y
        end
    end
end

local function cancelNetwork()
    if levelReqHandle then
        pcall(function() network.cancel(levelReqHandle) end)
        levelReqHandle = nil
    end

    if successLoadHandles and type(successLoadHandles) == "table" then
        for i = #successLoadHandles, 1, -1 do
            local h = successLoadHandles[i]
            if h then pcall(function() network.cancel(h) end) end
            successLoadHandles[i] = nil
        end
    end

    if successSaveHandle then
        pcall(function() network.cancel(successSaveHandle) end)
        successSaveHandle = nil
    end
end

local function refreshSharedState(params)
    local shared = appState.get()
    params = params or {}

    S.userId = shared.userId
    S.userName = shared.userName
    S.prefix = shared.prefix
    S.classStatus = shared.classStatus or "Draft"

    S.mode = params.mode or S.mode or "edit"
    S.levelId = tostring(params.levelId or S.levelId or "NEW")
    S.levelTitle = tostring(params.levelTitle or S.levelTitle or "")
    S.className = tostring(params.className or shared.className or S.className or "")
    S.lastThemeValue = tostring(params.theme or S.lastThemeValue or "Original")

    if not S.userName or S.userName == "" then
        S.userName = languages.t("player")
    end
end

setNativeInputsVisible = function(isVisible)
    local function parkNative(obj, visible)
        if not obj then return end

        if visible then
            obj.isVisible = true
            
        else
            obj.isVisible = false
            
            obj.x = -10000
            obj.y = -10000
        end
    end

    parkNative(S.Level, false)

    if isVisible then
        parkNative(S.levelNameField, true)

        local showWords   = (S.activeSection == "words")
        local showSuccess = (S.activeSection == "success")

        parkNative(S.wordsTextBox, showWords)
        parkNative(S.successTextBox, showSuccess)
    else
        parkNative(S.levelNameField, false)
        parkNative(S.wordsTextBox, false)
        parkNative(S.successTextBox, false)
    end
end

local function newAspectFillImage(parent, filename)
    local img = display.newImage(parent, filename)
    if not img then return nil end

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

local function applySaveButtonAccessState()
    if not S.saveBtn then return end
    local hasAccess = buttonAccess.hasAccess(appState)
    buttonAccess.applyPrimaryActionAccess(S.saveBtn, hasAccess, colors)
end

local function updateBackground(theme)
    local themeBackgrounds = {
        Mountain = "themes/Mountain-bg.png",
        Maple    = "themes/Maple-bg.png",
        Undersea = "themes/Undersea-bg.png",
        Jungle   = "themes/Jungle-bg.png",
        Sunshine = "themes/sunshine-bg.png",
        Beach    = "themes/Beach-bg.png",
        Original = "themes/Original-bg.png"
    }

    local newImage = themeBackgrounds[theme] or themeBackgrounds["Original"]

    if S.background then
        display.remove(S.background)
        S.background = nil
    end

    S.background = newAspectFillImage(scene.view, newImage)

    if S.persistentDim then S.persistentDim:toBack() end
    if S.background then S.background:toBack() end
    if S.fullBleedBg then S.fullBleedBg:toBack() end
end

local function newReadabilityPanel(parent, x, y, w, h, radius, alpha)
    local panel = display.newRoundedRect(parent, x, y, w, h, radius or (UI and UI.radiusCard) or 18)
    local a = alpha or 0.78
    panel:setFillColor(colors.appBackgroundSoft[1], colors.appBackgroundSoft[2], colors.appBackgroundSoft[3], a)
    panel.strokeWidth = (UI and UI.strokeWCard) or 3
    panel:setStrokeColor(
        colors.secondaryActionBorder[1],
        colors.secondaryActionBorder[2],
        colors.secondaryActionBorder[3],
        0.90
    )
    panel:toBack()
    return panel
end

local function newInputCard(parent, x, y, w, h, radius)
    local g = display.newGroup()
    parent:insert(g)

    local r = radius or (UI and UI.radiusInput) or 14

    local shadow = display.newRoundedRect(g, x + 2, y + 4, w, h, r)
    shadow:setFillColor(0, 0, 0, 0.14)

    local card = display.newRoundedRect(g, x, y, w, h, r)
  --  card:setFillColor(colors.appBackgroundSoft[1], colors.appBackgroundSoft[2], colors.appBackgroundSoft[3], 0.88)
    card:setFillColor(1, 1, 1, 1) -- solid white
    card.strokeWidth = (UI and UI.strokeWInput) or 2
    card:setStrokeColor(
        colors.secondaryActionBorder[1],
        colors.secondaryActionBorder[2],
        colors.secondaryActionBorder[3],
        0.90
    )

    g[1] = shadow
    g[2] = card
    return g
end

local function newWidePrimaryButton(parent, labelText, x, y, w, h, onTap)
    local g = display.newGroup()
    parent:insert(g)

    local bg = display.newRoundedRect(g, 0, 0, w, h, (UI and UI.radiusButton) or 16)
    bg:setFillColor(unpack(colors.primaryAction))
    bg.strokeWidth = (UI and UI.strokeWInput) or 2
    bg:setStrokeColor(unpack(colors.primaryActionPressed or colors.secondaryActionBorder))

    local icon = display.newText({
        parent = g,
        text   = "✅",
        x      = 0, y = 0,
        font   = TITLE_FONT_NAME,
        fontSize = (UI and UI.fsButton) or 18
    })
    icon:setFillColor(1, 1, 1)

    local t = display.newText({
        parent = g,
        text   = labelText,
        x      = 0, y = 0,
        font   = TITLE_FONT_NAME,
        fontSize = (UI and UI.fsButton) or 18
    })
    t:setFillColor(1, 1, 1)

    local function relayout(newW, newH)
        bg.width, bg.height = newW, newH
        local gap = (UI and UI.gapXS) or 8
        local totalW = icon.width + gap + t.width

        icon.x = -totalW * 0.5 + icon.width * 0.5
        t.x    = icon.x + icon.width * 0.5 + gap + t.width * 0.5
    end

    relayout(w, h)

    g.x, g.y = x, y
    g._bg = bg
    g._icon = icon
    g._label = t
    g._relayout = relayout

    g:addEventListener("tap", function()
        if onTap then onTap() end
        return true
    end)

    return g
end

local function newPill(parent, x, y, text, fontSize)
    local g = display.newGroup()
    parent:insert(g)

    local t = display.newText({
        parent = g,
        text   = text,
        x      = 0, y = 0,
        font   = TITLE_FONT_NAME,
        fontSize = fontSize or ((UI and UI.fsPill) or 18),
        align  = "center"
    })
    t:setFillColor(unpack(colors.textPrimary))

    local pill = display.newRoundedRect(g, 0, 0, t.width + 24, (UI and UI.pillH) or 34, (UI and UI.radiusPill) or 12)
    pill:setFillColor(1, 1, 1, 0.55)
    pill.strokeWidth = (UI and UI.strokeWThin) or 2
    pill:setStrokeColor(unpack(colors.secondaryActionBorder))
    pill:toBack()

    g.x, g.y = x, y
    g._pill = pill
    g._text = t
    g._isEnabled = true
    return g
end

local function newTabButton(parent, labelText, onTap)
    local g = display.newGroup()
    parent:insert(g)

    local bg = display.newRoundedRect(g, 0, 0, 10, 10, (UI and UI.radiusTab) or 16)
    bg.strokeWidth = (UI and UI.strokeWThin) or 2
    bg:setStrokeColor(unpack(colors.secondaryActionBorder))
    bg:setFillColor(1, 1, 1, 0.25)

    local bottomCover = display.newRect(g, 0, 0, 10, 10)
    bottomCover:setFillColor(1, 1, 1, 0.25)

    local t = display.newText({
        parent = g,
        text   = labelText,
        x      = 0, y = 0,
        font   = TITLE_FONT_NAME,
        fontSize = (UI and UI.fsTab) or 20,
        align  = "center"
    })
    t:setFillColor(unpack(colors.textPrimary))

    g._bg = bg
    g._cover = bottomCover
    g._label = t

    g._relayout = function(w, h)
        bg.width, bg.height = w, h
        bottomCover.width  = w
        bottomCover.height = math.floor(h * 0.42)
        bottomCover.y = (h * 0.5) - (bottomCover.height * 0.5)
        t.y = -1
        fitTextToWidth(t, (UI and UI.fsTab) or 20, 16, w * 0.90)
    end

    g:addEventListener("tap", function()
        if onTap then onTap() end
        return true
    end)

    return g
end

local function styleTab(which)
    local isWords = (which == "words")

    local function apply(tab, active)
        if not tab or not tab._bg or not tab._cover then return end
        tab.alpha = active and 1.0 or 0.75
        if active then
            tab._bg:setFillColor(1, 1, 1, 0.78)
            tab._cover:setFillColor(1, 1, 1, 0.78)
            tab._bg.strokeWidth = 2
        else
            tab._bg:setFillColor(1, 1, 1, 0.18)
            tab._cover:setFillColor(1, 1, 1, 0.18)
            tab._bg.strokeWidth = 1
        end
    end

    apply(S.tabWords, isWords)
    apply(S.tabSuccess, not isWords)
end

local function setActiveSection(which)
    if which ~= "words" and which ~= "success" then return end
    if S.activeSection == which then return end

    native.setKeyboardFocus(nil)
    S.activeSection = which

    local showWords   = (which == "words")
    local showSuccess = (which == "success")

    if S.wordsHeaderText then S.wordsHeaderText.isVisible = showWords end
    if S.previewLevelPill then S.previewLevelPill.isVisible = showWords end
    if S.wordsInputCardGroup then S.wordsInputCardGroup.isVisible = showWords end
    if S.wordsTextBox then S.wordsTextBox.isVisible = showWords end

    if S.successHeaderText then S.successHeaderText.isVisible = showSuccess end
    if S.previewSuccessPill then S.previewSuccessPill.isVisible = showSuccess end
    if S.successInputCardGroup then S.successInputCardGroup.isVisible = showSuccess end
    if S.successTextBox then S.successTextBox.isVisible = showSuccess end

    styleTab(which)
    updatePreviewAvailability()
end

local function gotoSelectLevels()
    goBack = true
    S._isActive = false
    cancelNetwork()

    native.setKeyboardFocus(nil)
    setRecordStatus("")
    setNativeInputsVisible(false)
    if destroyThemeOverlay then destroyThemeOverlay() end

    appState.set({
        prefix = S.prefix,
        className = S.className,
        classStatus = S.classStatus
    })

    composer.gotoScene("selectLevels", {
        effect="slideRight",
        time=250,
        params = {
            prefix = S.prefix,
            className = S.className,
            classStatus = S.classStatus
        }
    })

    composer.removeScene("customize")
end

local function gotoSettings()
    native.setKeyboardFocus(nil)
    setRecordStatus("")
    setNativeInputsVisible(false)
    if destroyThemeOverlay then destroyThemeOverlay() end

    appState.set({
        prefix = S.prefix,
        className = S.className,
        classStatus = S.classStatus
    })

    composer.gotoScene("settings", {
        effect = "slideLeft",
        time = 220,
        params = {
            returnTo = "customize"
        }
    })
end

local function gotoGamePreview()
    if hasUnsavedChanges() then
        native.showAlert(
            languages.t("save_first") or "Save First",
            languages.t("save_to_preview_edits") or "Please save your edits before previewing.",
            { languages.t("ok") or "OK" }
        )
        return
    end

    if not (S.previewLevelPill and S.previewLevelPill._isEnabled) then return end

    S._isActive = false
    cancelNetwork()
    setRecordStatus("")

    composer.gotoScene("game", {
        effect = "slideLeft",
        time = 250,
        params = {
            user   = S.userId,
            name   = S.userName,
            prefix = S.prefix,
            level  = (S.Level and S.Level.text) or "",
            theme  = S.lastThemeValue or "Original"
        }
    })
    composer.removeScene("customize")
end

local function gotoSuccessPreview()
    if hasUnsavedChanges() then
        native.showAlert(
            languages.t("save_first") or "Save First",
            languages.t("save_to_preview_edits") or "Please save your edits before previewing.",
            { languages.t("ok") or "OK" }
        )
        return
    end

    if not (S.previewSuccessPill and S.previewSuccessPill._isEnabled) then return end

    S._isActive = false
    cancelNetwork()
    setRecordStatus("")

    composer.gotoScene("success", {
        effect = "slideLeft",
        time = 250,
        params = {
            user   = S.userId,
            name   = S.userName,
            prefix = S.prefix,
            level  = (S.Level and S.Level.text) or "",
            title  = (S.levelNameField and S.levelNameField.text) or S.levelTitle or "",
            theme  = S.lastThemeValue or "Original"
        }
    })
end

local function saveLevelAndSuccess(isUpdate)
    native.setKeyboardFocus(nil)

    loadToken = loadToken + 1

    if successLoadHandles and type(successLoadHandles) == "table" then
        for i = #successLoadHandles, 1, -1 do
            local h = successLoadHandles[i]
            if h then pcall(function() network.cancel(h) end) end
            successLoadHandles[i] = nil
        end
    end

    if not S.userId or not S.prefix then
        setRecordStatus(languages.t("missing_user_class") or "Missing user or class.")
        return
    end

    local title = tostring((S.levelNameField and S.levelNameField.text) or "")
    if title:gsub("%s+", "") == "" then
        setRecordStatus(languages.t("please_enter_level_name") or "Please enter a level name.")
        return
    end

    local levelId = (S.Level and S.Level.text) or "NEW"
    local theme = S.lastThemeValue or "Original"
    local target = tostring((S.wordsTextBox and S.wordsTextBox.text) or "")
    local success = tostring((S.successTextBox and S.successTextBox.text) or "")

    if #target > 1000 then
        native.showAlert(
            languages.t("too_long") or "Too Long",
            (languages.t("verse_too_long") or "Words to Remember must be 1000 characters or fewer.") ..
            "\n\n(" .. tostring(#target) .. "/1000)",
            { languages.t("ok") or "OK" }
        )
        return
    end

    if #success > 1000 then
        native.showAlert(
            languages.t("too_long") or "Too Long",
            (languages.t("success_too_long") or "Success Message must be 1000 characters or fewer.") ..
            "\n\n(" .. tostring(#success) .. "/1000)",
            { languages.t("ok") or "OK" }
        )
        return
    end

    local function doSetRequests(realLevelId)
        if S.Level then S.Level.text = tostring(realLevelId or levelId) end

        local base = "https://infoshagame.com/user/list/"
        local lvlEndpoint = isUpdate and "updateLevel.php?type=update" or "setLevel.php?type=set"
        local sucEndpoint = isUpdate and "updateSuccess.php?type=updates" or "setSuccess.php?type=sets"

        local levelReq = base .. lvlEndpoint ..
            "&level=" .. urlencode(tostring(realLevelId)) ..
            "&title=" .. urlencode(title) ..
            "&verse=" .. urlencode(target) ..
            "&theme=" .. urlencode(theme) ..
            "&user=" .. urlencode(S.userId) ..
            "&prefix=" .. urlencode(S.prefix) ..
            "&status=draft"

        local successReq = base .. sucEndpoint ..
            "&level=" .. urlencode(tostring(realLevelId)) ..
            "&success=" .. urlencode(success) ..
            "&countr=1" ..
            "&user=" .. urlencode(S.userId)

        setRecordStatus((languages.t("saving") or "Saving") .. "...")

        network.request(levelReq, "GET", function(e1)
            if not S._isActive or goBack then return end
            if e1.isError then
                setRecordStatus(languages.t("save_failed") or "Save failed")
                return
            end

            successSaveHandle = network.request(successReq, "GET", function(e2)
                successSaveHandle = nil
                if not S._isActive or goBack then return end
                if e2.isError then
                    setRecordStatus(languages.t("save_failed") or "Save failed")
                    return
                end

                S.titleDirty = false
                S.wordsDirty = false
                S.successDirty = false
                setRecordStatus(languages.t("updated") or "Saved")
                updatePreviewAvailability()
            end)
        end)
    end

    if tostring(levelId) == "NEW" then
        local seedRequest = "https://infoshagame.com/user/list/seedLevel.php?type=seed"
        setRecordStatus(languages.t("creating_new_level") or "Creating new level...")

        network.request(seedRequest, "GET", function(ev)
            if not S._isActive or goBack then return end
            if ev.isError then
                setRecordStatus(languages.t("seed_error") or "Seed error")
                return
            end

            local resp = json.decode(ev.response)
            local nextId = (resp and resp[1] and resp[1].NextLevel) and tostring(resp[1].NextLevel) or nil
            if not nextId or nextId == "" then
                setRecordStatus(languages.t("seed_error") or "Seed error")
                return
            end

            doSetRequests(nextId)
        end)
    else
        doSetRequests(levelId)
    end
end

local function loadSuccessText(levelId)
    if not levelId or not S.successTextBox then return end
    if not S._isActive or goBack then return end

    if successLoadHandles and type(successLoadHandles) == "table" then
        for i = #successLoadHandles, 1, -1 do
            local h = successLoadHandles[i]
            if h then pcall(function() network.cancel(h) end) end
            successLoadHandles[i] = nil
        end
    end

    local successCombined = ""
    local pending = 1
    local myToken = loadToken

    local function onResponse(event)
        if not S._isActive or goBack then return end
        if myToken ~= loadToken then return end

        pending = pending - 1

        if not event.isError and event.response and event.response ~= "" then
            local response = json.decode(event.response)
            if response and #response > 0 then
                for _, row in ipairs(response) do
                    if row.SuccessText then
                        successCombined = successCombined .. row.SuccessText .. "\n"
                    end
                end
            end
        end

        if pending == 0 and not S.successDirty then
            local finalSuccess = (successCombined ~= "" and successCombined) or ""
            S.successCache = finalSuccess
            if S.successTextBox then
                S.successTextBox.text = finalSuccess
            end
        end
    end

    local url = "https://infoshagame.com/user/list/getSuccess.php?type=gets" ..
        "&level=" .. urlencode(levelId) ..
        "&countr=1"
    local h = network.request(url, "GET", onResponse)
    successLoadHandles[#successLoadHandles + 1] = h
end

local function loadLevelData(callback)
    if not S.userId or not S.prefix then
        if callback then callback(false) end
        return
    end

    if goBack or not S._isActive then
        if callback then callback(false) end
        return
    end

    if levelReqHandle then
        pcall(function() network.cancel(levelReqHandle) end)
        levelReqHandle = nil
    end

    loadToken = loadToken + 1
    local myToken = loadToken

    local req = "https://infoshagame.com/user/list/getLevelP.php?type=getp" ..
        "&user=" .. urlencode(S.userId) ..
        "&prefix=" .. urlencode(S.prefix)

    setRecordStatus(languages.t("loading") or "Loading...")

    levelReqHandle = network.request(req, "GET", function(event)
        if goBack or not S._isActive then return end
        if myToken ~= loadToken then return end

        levelReqHandle = nil

        if event.isError then
            setRecordStatus(languages.t("load_failed") or "Load failed")
            if callback then callback(false) end
            return
        end

        local response = json.decode(event.response)
        local found = nil

        if response and type(response) == "table" then
            for _, row in ipairs(response) do
                if row and row.Status ~= "deleted" then
                    local rid = tostring(row.LevelID or "")
                    local rtitle = tostring(row.Title or "")
                    if (S.levelId and S.levelId ~= "" and S.levelId ~= "NEW" and rid == tostring(S.levelId))
                        or (S.levelTitle and S.levelTitle ~= "" and rtitle == tostring(S.levelTitle)) then
                        found = row
                        break
                    end
                end
            end
        end

        if not found then
            setRecordStatus("")
            if callback then callback(false) end
            return
        end

        local rid    = tostring(found.LevelID or "")
        local rtitle = tostring(found.Title or "")
        local rtext  = tostring(found.Text or "")
        local rtheme = tostring(found.ThemeID or "Original")

        if S.Level then S.Level.text = (rid ~= "" and rid) or "NEW" end
        if S.levelNameField then
            S.levelNameField.text = rtitle
            relayoutTitleField()
        end
        if S.wordsTextBox then
            S.wordsTextBox.text = rtext
        end
        S.wordsCache = rtext

        S.lastThemeValue = (rtheme ~= "" and rtheme) or "Original"
        if S.themeBtnLabel then S.themeBtnLabel.text = S.lastThemeValue end
        updateBackground(S.lastThemeValue)

        setRecordStatus("")

        if rid ~= "" then
            S.titleDirty = false
            S.wordsDirty = false
            S.successDirty = false
            S._initialized = true
            loadSuccessText(rid)
        end

        updatePreviewAvailability()

        if callback then callback(true) end
    end)
end

function scene:paramsInit(event)
    local params = event.params or {}
    refreshSharedState(params)
end

local themeOptions = { "Mountain", "Maple", "Undersea", "Jungle", "Beach", "Original" }

destroyThemeOverlay = function()
    if S.themeTable then display.remove(S.themeTable); S.themeTable = nil end
    if S.themeDoneBtn then display.remove(S.themeDoneBtn); S.themeDoneBtn = nil end
    if S.themeListHint then display.remove(S.themeListHint); S.themeListHint = nil end
    if S.themeListCard then display.remove(S.themeListCard); S.themeListCard = nil end
    if S.themeOverlayDim then display.remove(S.themeOverlayDim); S.themeOverlayDim = nil end
    if S.themeOverlay then display.remove(S.themeOverlay); S.themeOverlay = nil end
end

local function commitThemePending()
    local v = S._themePending or S.lastThemeValue or "Original"
    S.lastThemeValue = v
    if S.themeBtnLabel then S.themeBtnLabel.text = v end
    updateBackground(v)
end

local function cancelThemePending()
    local v = S._themeCommitted or S.lastThemeValue or "Original"
    updateBackground(v)
end

local function hideThemePicker()
    native.setKeyboardFocus(nil)
    setKeyboardState(false, nil, 0)
    cancelThemePending()
    setNativeInputsVisible(true)
    destroyThemeOverlay()

    if S.wordsTextBox then
        S.wordsTextBox.text = tostring(S.wordsCache or "")
    end
    if S.successTextBox then
        S.successTextBox.text = tostring(S.successCache or "")
    end
end

local function showThemePicker()
    if S.wordsTextBox then
        S.wordsCache = tostring(S.wordsTextBox.text or "")
    end
    if S.successTextBox then
        S.successCache = tostring(S.successTextBox.text or "")
    end

    native.setKeyboardFocus(nil)
    setKeyboardState(false, nil, 0)
    setNativeInputsVisible(false)

    S._themeCommitted = S.lastThemeValue or "Original"
    S._themePending   = S._themeCommitted

    S.themeOverlay = display.newGroup()
    scene.view:insert(S.themeOverlay)

    S.themeOverlayDim = display.newRect(
        S.themeOverlay,
        display.contentCenterX,
        display.contentCenterY,
        display.actualContentWidth,
        display.actualContentHeight
    )
    S.themeOverlayDim:setFillColor(0, 0, 0, 0.35)
    S.themeOverlayDim.isHitTestable = true

    S.themeOverlayDim:addEventListener("tap", function(e)
        if S.themeListCard then
            local b = S.themeListCard.contentBounds
            local x, y = e.x, e.y
            local inside = (x >= b.xMin and x <= b.xMax and y >= b.yMin and y <= b.yMax)
            if inside then return true end
        end
        hideThemePicker()
        return true
    end)

    local safeX, safeY, safeW, safeH = stableSafeRect()
    UI = buildUI(safeW, safeH)

    local cardW = math.floor(safeW * 0.88)
    local cardH = math.min(math.floor(safeH * 0.55), 520)
    local centerX = safeX + safeW * 0.5
    local centerY = safeY + safeH * 0.52

    S.themeListCard = display.newRoundedRect(S.themeOverlay, centerX, centerY, cardW, cardH, UI.radiusCard)
    S.themeListCard:setFillColor(colors.appBackgroundSoft[1], colors.appBackgroundSoft[2], colors.appBackgroundSoft[3], 0.92)
    S.themeListCard.strokeWidth = UI.strokeWCard
    S.themeListCard:setStrokeColor(unpack(colors.secondaryActionBorder))
    S.themeListCard.isHitTestable = true
    S.themeListCard:addEventListener("touch", function() return true end)

    S.themeListHint = display.newText({
        parent = S.themeOverlay,
        text   = languages.t("tap_theme_then_done"),
        x      = centerX,
        y      = centerY - cardH * 0.5 + 34,
        font   = TITLE_FONT_NAME,
        fontSize = UI.fsSection,
        align  = "center",
        width  = cardW * 0.92
    })
    S.themeListHint:setFillColor(unpack(colors.textPrimary))

    local rowH = math.max(54, UI.buttonH)
    local tableTop = (centerY - cardH * 0.5) + 70
    local tableH   = cardH - 70 - 110

    local function onRowRender(event)
        local row = event.row
        local label = row.params and row.params.label or ""

        local bg = row._bg
        if not bg then
            bg = display.newRoundedRect(
                row,
                row.contentWidth * 0.5,
                row.contentHeight * 0.5,
                row.contentWidth,
                row.contentHeight - 4,
                UI.radiusInput
            )
            bg:toBack()
            row._bg = bg
        end

        if tostring(label) == tostring(S._themePending) then
            bg:setFillColor(1, 1, 1, 0.70)
        else
            bg:setFillColor(1, 1, 1, 0.22)
        end

        local txt = row._labelText
        if not txt then
            txt = display.newText({
                parent = row,
                text   = label,
                x      = row.contentWidth * 0.5,
                y      = row.contentHeight * 0.5,
                font   = TITLE_FONT_NAME,
                fontSize = UI.fsLabel,
                align  = "center",
                width  = row.contentWidth * 0.92
            })
            txt:setFillColor(unpack(colors.textPrimary))
            row._labelText = txt
        else
            txt.text = label
            txt.size = UI.fsLabel
        end
    end

    local function onRowTouch(event)
        if event.phase ~= "release" then return true end
        local row = event.row
        local label = row.params and row.params.label or ""
        if label == "" then return true end

        S._themePending = label
        updateBackground(label)

        if S.themeListHint then
            S.themeListHint.text = (languages.t("selected_theme") or "Selected Theme") .. ": " .. tostring(label)
        end

        if S.themeTable and S.themeTable.reloadData then
            S.themeTable:reloadData()
        end

        return true
    end

    S.themeTable = widget.newTableView({
        x = centerX,
        y = tableTop + tableH * 0.5,
        width = cardW * 0.92,
        height = tableH,
        hideBackground = true,
        rowHeight = rowH,
        onRowRender = onRowRender,
        onRowTouch  = onRowTouch,
        noLines = true,
    })
    S.themeOverlay:insert(S.themeTable)

    for i = 1, #themeOptions do
        S.themeTable:insertRow({ rowHeight = rowH, params = { label = themeOptions[i] } })
    end

    S.themeDoneBtn = newWidePrimaryButton(
        S.themeOverlay,
        languages.t("done") or "Done",
        centerX,
        centerY + cardH * 0.5 - 54,
        math.min(320, math.floor(cardW * 0.55)),
        UI.buttonH,
        function()
            native.setKeyboardFocus(nil)
            setKeyboardState(false, nil, 0)
            commitThemePending()
            setNativeInputsVisible(true)
            destroyThemeOverlay()

            if S.wordsTextBox then
                S.wordsTextBox.text = tostring(S.wordsCache or "")
            end
            if S.successTextBox then
                S.successTextBox.text = tostring(S.successCache or "")
            end

            if S._onResize then S._onResize() end
        end
    )

    S.themeOverlay:toFront()
end

layoutUI = function()
    local safeX, safeY, safeW, safeH, keyboardInset = getLayoutSafeRect()
    S.L.safeX, S.L.safeY, S.L.safeW, S.L.safeH = safeX, safeY, safeW, safeH
    UI = buildUI(safeW, safeH)

    local centerX = safeX + safeW * 0.5
    local margin  = math.floor(safeW * 0.05)
    local pad     = math.floor(safeW * 0.04)
    local gap     = math.floor(safeH * 0.014)
    local cardW   = safeW - margin * 2
    local leftX   = centerX - cardW * 0.5 + pad
    local rightX  = centerX + cardW * 0.5 - pad
    local fieldW  = cardW - pad * 2

    if S.fullBleedBg then
        S.fullBleedBg.width  = display.actualContentWidth
        S.fullBleedBg.height = display.actualContentHeight
        S.fullBleedBg.x = display.contentCenterX
        S.fullBleedBg.y = display.contentCenterY
    end

    if S.background then
        S.background.x = display.contentCenterX
        S.background.y = display.contentCenterY
    end

    if S.persistentDim then
        S.persistentDim.width  = display.actualContentWidth
        S.persistentDim.height = display.actualContentHeight
        S.persistentDim.x = display.contentCenterX
        S.persistentDim.y = display.contentCenterY
    end

    local headerH = math.floor(display.contentHeight * 0.11)
    local headerCenterY = safeY + headerH * 0.5
    local keyboardInset = math.max(0, S.keyboardInset or 0)

    if S.headerBand then
        S.headerBand.x = centerX
        S.headerBand.y = headerCenterY
        S.headerBand.width = safeW
        S.headerBand.height = headerH
    end

    if S.headerBandDivider then
        S.headerBandDivider.x = centerX
        S.headerBandDivider.y = safeY + headerH
        S.headerBandDivider.width = safeW
    end

    local topY = (S.header and S.header.headerBottomY) or (safeY + safeH * 0.10)
    local y = topY + math.floor(safeH * 0.006)

    local topCardH = math.max(160, math.floor(safeH * 0.19))
    local titleFieldH = UI.inputH
    local themeRowH = UI.pickerH
    local saveRowH = UI.buttonH

    if S.topCard then
        S.topCard.x = centerX
        S.topCard.y = y + topCardH * 0.5
        S.topCard.width = cardW
        S.topCard.height = topCardH
    end

    local innerTop = y + UI.gapMD

    if S.classIdText then
        S.classIdText.x = centerX
        S.classIdText.y = innerTop + math.floor(UI.fsHero * 0.55)
        S.classIdText.width = cardW * 0.92
        fitTextToWidth(S.classIdText, UI.fsHero, 28, cardW * 0.92)
    end

    if S.classHelperText then
        S.classHelperText.x = centerX
        S.classHelperText.y = innerTop + UI.fsHero + UI.gapMD
        S.classHelperText.width = cardW * 0.88
        fitTextToWidth(S.classHelperText, UI.fsLabel, 18, cardW * 0.88)
    end

    local helperBottom = S.classHelperText.y + (S.classHelperText.contentHeight * 0.5)

local titleY = helperBottom 
             + UI.gapMD - 5 -- space below helper
             + math.floor(titleFieldH * 0.5)
    local titleFieldInset = 10

    if S.titleInputCardGroup and S.titleInputCardGroup[2] then
        S.titleInputCardGroup[1].x, S.titleInputCardGroup[1].y = centerX + 2, titleY + 4
        S.titleInputCardGroup[1].width, S.titleInputCardGroup[1].height = fieldW, titleFieldH
        S.titleInputCardGroup[2].x, S.titleInputCardGroup[2].y = centerX, titleY
        S.titleInputCardGroup[2].width, S.titleInputCardGroup[2].height = fieldW, titleFieldH
    end

    if S.levelNameField then
        S.levelNameField.x = centerX
        S.levelNameField.y = titleY
        S.levelNameField.width = fieldW - (titleFieldInset * 2)
        S.levelNameField.height = titleFieldH - UI.nativeFieldInset
        relayoutTitleField()
    end

local themeRowY = titleY + math.floor(titleFieldH * 0.5) + UI.gapMD + math.floor(themeRowH * 0.5)
local themeBtnH = UI.pickerH
local labelGap = UI.gapSM
local saveBtnW = math.floor(cardW * 0.34)

local themeBtnW = 120
if S.themeBtnLabel then
    themeBtnW = math.min(math.floor(fieldW * 0.28), math.max(110, S.themeBtnLabel.contentWidth + 32))
end

local labelW = S.themeLabel and S.themeLabel.contentWidth or 0
local themeGroupW = labelW + labelGap + themeBtnW

if S.themeLabel then
    S.themeLabel.anchorX = 0
    S.themeLabel.anchorY = 0.5
    S.themeLabel.x = leftX
    S.themeLabel.y = themeRowY
    S.themeLabel.size = UI.fsLabel
end

if S.themeToggleBtn then
    S.themeToggleBtn.x = leftX + labelW + labelGap + (themeBtnW * 0.5)
    S.themeToggleBtn.y = themeRowY
    S.themeToggleBtn.width = themeBtnW
    S.themeToggleBtn.height = themeBtnH
end

if S.themeBtnLabel and S.themeToggleBtn then
    S.themeBtnLabel.x = S.themeToggleBtn.x
    S.themeBtnLabel.y = S.themeToggleBtn.y
    fitTextToWidth(S.themeBtnLabel, UI.fsLabel, 15, S.themeToggleBtn.width * 0.80)
end

if S.saveBtn then
    S.saveBtn.x = rightX - (saveBtnW * 0.5)
    S.saveBtn.y = themeRowY
    if S.saveBtn._relayout then
        S.saveBtn._relayout(saveBtnW, saveRowH)
    end
end

local statusY = themeRowY + math.floor(math.max(themeRowH, saveRowH) * 0.5) + UI.gapMD + math.floor(UI.fsStatus * 0.5)
if S.recordStatus then
    S.recordStatus.x = centerX
    S.recordStatus.y = statusY
    S.recordStatus.width = safeW * 0.88
    fitTextToWidth(S.recordStatus, UI.fsStatus, 14, safeW * 0.88)

    if S.recordStatusBg and S.recordStatus.isVisible then
        local padW = 28
        local padH = 14
        S.recordStatusBg.x = S.recordStatus.x
        S.recordStatusBg.y = S.recordStatus.y
        S.recordStatusBg.width = math.min(safeW * 0.88, S.recordStatus.contentWidth + padW)
        S.recordStatusBg.height = S.recordStatus.contentHeight + padH
    end
end
    local wordsCardTop = y + topCardH + gap
    local visibleBottom = safeY + safeH - keyboardInset - gap
local wordsCardH

if isiOS() then
    -- Keep the editor area more stable on iPhone
    wordsCardH = math.max(220, (safeY + safeH) - wordsCardTop - 8)
else
    wordsCardH = math.max(220, visibleBottom - wordsCardTop - 8)
end

    if S.wordsCard then
        S.wordsCard.x = centerX
        S.wordsCard.y = wordsCardTop + wordsCardH * 0.5
        S.wordsCard.width = cardW
        S.wordsCard.height = wordsCardH
    end

    local cardInnerTop = wordsCardTop + UI.gapMD
    local cardInnerBottom = wordsCardTop + wordsCardH - UI.gapMD

    local tabRowH = UI.tabH
    local tabGap  = UI.gapSM
    local headerRowH = math.floor(UI.fsSection + 10)
    local boxGap = UI.gapSM
    local nativeFS = clamp(computeTitleFontSize(safeW, safeH), 18, 26)
    local boxW = fieldW

    local tabsY = cardInnerTop + tabRowH * 0.5 - 2
    local tabsW = cardW - pad * 2
    local eachW = math.floor((tabsW - tabGap) * 0.5)
    local tabsLeftX  = centerX - tabsW * 0.5
    local wordsTabX  = tabsLeftX + eachW * 0.5
    local succTabX   = tabsLeftX + eachW + tabGap + eachW * 0.5

    if S.tabsBaseline then
        S.tabsBaseline.x = centerX
        S.tabsBaseline.y = tabsY + tabRowH * 0.5 - 2
        S.tabsBaseline.width = tabsW
        S.tabsBaseline.height = 2
    end

    if S.tabWords then
        S.tabWords.x, S.tabWords.y = wordsTabX, tabsY
        if S.tabWords._relayout then S.tabWords._relayout(eachW, tabRowH) end
    end

    if S.tabSuccess then
        S.tabSuccess.x, S.tabSuccess.y = succTabX, tabsY
        if S.tabSuccess._relayout then S.tabSuccess._relayout(eachW, tabRowH) end
    end

    local contentTop = cardInnerTop + tabRowH + UI.gapSM
    local contentBottom2 = cardInnerBottom
    local available = contentBottom2 - contentTop
    local fixed = headerRowH + boxGap + 6
    local boxH = clamp(math.floor(available - fixed), 100, math.floor(wordsCardH * 0.72))

    local function pillWidth(p)
        if not p then return 0 end
        if p._pill and p._pill.width then return p._pill.width end
        return p.width or 0
    end

    local cy = contentTop

    if S.activeSection == "words" then
        local wordsHeaderY = cy + headerRowH * 0.5

        if S.wordsHeaderText then
            S.wordsHeaderText.x = leftX
            S.wordsHeaderText.y = wordsHeaderY
            fitTextToWidth(S.wordsHeaderText, UI.fsSection, 18, cardW * 0.60)
        end

        if S.previewLevelPill then
            S.previewLevelPill.isVisible = true
            S.previewLevelPill.x = rightX - pillWidth(S.previewLevelPill) * 0.5
            S.previewLevelPill.y = wordsHeaderY
        end

        cy = cy + headerRowH + boxGap
        local wordsBoxY = cy + boxH * 0.5

        if S.wordsInputCardGroup and S.wordsInputCardGroup[2] then
            S.wordsInputCardGroup[1].x, S.wordsInputCardGroup[1].y = centerX + 2, wordsBoxY + 4
            S.wordsInputCardGroup[1].width, S.wordsInputCardGroup[1].height = boxW, boxH
            S.wordsInputCardGroup[2].x, S.wordsInputCardGroup[2].y = centerX, wordsBoxY
            S.wordsInputCardGroup[2].width, S.wordsInputCardGroup[2].height = boxW, boxH
        end

        if S.wordsTextBox then
            S.wordsTextBox.x, S.wordsTextBox.y = centerX, wordsBoxY
            S.wordsTextBox.width, S.wordsTextBox.height = boxW
            S.wordsTextBox.height = boxH - UI.nativeBodyInset
            S.wordsTextBox.font = native.newFont(native.systemFont, nativeFS + 2)
        end
    else
        local successHeaderY = cy + headerRowH * 0.5

        if S.successHeaderText then
            S.successHeaderText.x = leftX
            S.successHeaderText.y = successHeaderY
            fitTextToWidth(S.successHeaderText, UI.fsSection, 18, cardW * 0.60)
        end

        if S.previewSuccessPill then
            S.previewSuccessPill.isVisible = true
            S.previewSuccessPill.x = rightX - pillWidth(S.previewSuccessPill) * 0.5
            S.previewSuccessPill.y = successHeaderY
        end

        cy = cy + headerRowH + boxGap
        local successBoxY = cy + boxH * 0.5

        if S.successInputCardGroup and S.successInputCardGroup[2] then
            S.successInputCardGroup[1].x, S.successInputCardGroup[1].y = centerX + 2, successBoxY + 4
            S.successInputCardGroup[1].width, S.successInputCardGroup[1].height = boxW, boxH
            S.successInputCardGroup[2].x, S.successInputCardGroup[2].y = centerX, successBoxY
            S.successInputCardGroup[2].width, S.successInputCardGroup[2].height = boxW, boxH
        end

        if S.successTextBox then
            S.successTextBox.x, S.successTextBox.y = centerX, successBoxY
            S.successTextBox.width, S.successTextBox.height = boxW
            S.successTextBox.height = boxH - UI.nativeBodyInset
            S.successTextBox.font = native.newFont(native.systemFont, nativeFS + 2)
        end
    end

    if S.recordStatusBg and S.recordStatusBg.isVisible then S.recordStatusBg:toFront() end
    if S.recordStatus then S.recordStatus:toFront() end
    if S.headerBand then S.headerBand:toFront() end
    if S.headerBandDivider then S.headerBandDivider:toFront() end
    if S.header and S.header.group and S.header.group.toFront then S.header.group:toFront() end

    if S.gearGroup and S.topCard then
        local edgeInset = 12 -- tweak this to move it "in a little"

        local headerRowY = safeY + math.floor(headerH * 0.52)

        local rightEdge = S.topCard.x + (S.topCard.width * 0.5)

        S.gearGroup.x = rightEdge - edgeInset
        S.gearGroup.y = headerRowY
        S.gearGroup:toFront()
    end

    setNativeInputsVisible(not S.themeOverlay)
end

setKeyboardState = function(isOpen, fieldName, keyboardHeight)
    if isiOS() then
        -- Let iOS manage the keyboard. Do not apply a manual inset.
        if isOpen then
            S.editingField = fieldName or S.editingField or "unknown"
        else
            S.editingField = nil
        end

        S.keyboardInset = 0

        if S._onResize then
            S._onResize()
        end
        return
    end

    -- Android: keep manual inset support
    if isOpen then
        local fallback = math.floor(display.contentHeight * 0.34)
        local inset = tonumber(keyboardHeight) or 0

        if inset <= 0 then
            inset = tonumber(S.keyboardInset) or 0
        end
        if inset <= 0 then
            inset = fallback
        end

        S.keyboardInset = inset
        S.editingField = fieldName or S.editingField or "unknown"
    else
        S.keyboardInset = 0
        S.editingField = nil
    end

    if S._onResize then
        S._onResize()
    end
end

local function onKeyboardEvent(event)
    local phase = event and event.phase
    local keyboardHeight = 0

    if event and event.endCoordinates and event.endCoordinates.height then
        keyboardHeight = tonumber(event.endCoordinates.height) or 0
    end

    if phase == "began" or phase == "willShow" or phase == "didShow" then
        setKeyboardState(true, S.editingField, keyboardHeight)
    elseif phase == "ended" or phase == "willHide" or phase == "didHide" then
        setKeyboardState(false, nil, 0)
    end

    return false
end
local function onTitleInput(event)
    if event.phase == "began" then
        setKeyboardState(true, "title")
        relayoutTitleField()
        if not isiOS() then
        refreshLayoutSoon()
        end
    elseif event.phase == "editing" then
        S.titleDirty = true
        if (S.keyboardInset or 0) <= 0 then
            setKeyboardState(true, "title")
        end
        relayoutTitleField()
        updatePreviewAvailability()
    elseif event.phase == "ended" or event.phase == "submitted" then
        relayoutTitleField()
        setKeyboardState(false, nil)
    end
end
local function onWordsInput(event)
    if event.phase == "began" then
        S.wordsCache = tostring((event.target and event.target.text) or S.wordsCache or "")
        setKeyboardState(true, "words")
        if not isiOS() then
        refreshLayoutSoon()
        end
    elseif event.phase == "editing" then
        S.wordsDirty = true
        S.wordsCache = tostring((event.target and event.target.text) or "")
        if (S.keyboardInset or 0) <= 0 then
            setKeyboardState(true, "words")
        end
        updatePreviewAvailability()
    elseif event.phase == "ended" or event.phase == "submitted" then
        S.wordsCache = tostring((event.target and event.target.text) or S.wordsCache or "")
        setKeyboardState(false, nil)
    end
end

local function onSuccessInput(event)
    if event.phase == "began" then
        S.successDirty = true
        S.successCache = tostring((event.target and event.target.text) or S.successCache or "")
        setKeyboardState(true, "success")
        updatePreviewAvailability()
        if not isiOS() then
        refreshLayoutSoon()
        end
    elseif event.phase == "editing" then
        S.successDirty = true
        S.successCache = tostring((event.target and event.target.text) or "")
        if (S.keyboardInset or 0) <= 0 then
            setKeyboardState(true, "success")
        end
        updatePreviewAvailability()
    elseif event.phase == "ended" or event.phase == "submitted" then
        S.successCache = tostring((event.target and event.target.text) or S.successCache or "")
        setKeyboardState(false, nil)
    end
end

function scene:create(event)
    self:paramsInit(event)
    local sceneGroup = self.view

    local safeX, safeY, safeW, safeH = stableSafeRect()
    UI = buildUI(safeW, safeH)

    S.fullBleedBg = display.newRect(
        sceneGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.actualContentWidth,
        display.actualContentHeight
    )
    S.fullBleedBg:setFillColor(
        colors.appBackgroundSoft[1],
        colors.appBackgroundSoft[2],
        colors.appBackgroundSoft[3]
    )
    S.fullBleedBg:toBack()

    updateBackground(S.lastThemeValue)

    local headerH = math.floor(display.contentHeight * 0.11)
    local headerCenterY = safeY + headerH * 0.5
    local bg = colors.appBackgroundSoft or {1,1,1}

    S.headerBand = display.newRect(sceneGroup, display.contentCenterX, headerCenterY, safeW, headerH)
    S.headerBand:setFillColor(bg[1], bg[2], bg[3], 0.28)

    S.headerBandDivider = display.newRect(sceneGroup, display.contentCenterX, safeY + headerH, safeW, 1)
    S.headerBandDivider:setFillColor(0, 0, 0, 0.10)

    S.persistentDim = display.newRect(
        sceneGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.actualContentWidth,
        display.actualContentHeight
    )
    S.persistentDim:setFillColor(0, 0, 0, 0.10)
    S.persistentDim:toBack()

    S.topCard = newReadabilityPanel(sceneGroup, display.contentCenterX, display.contentCenterY, display.contentWidth * 0.92, 300, UI.radiusCard, 0.78)

    S.classIdText = display.newText({
        parent = sceneGroup,
        text   = (languages.t("class_id") or "Class ID") .. ": " .. tostring(S.prefix or ""),
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 40,
        align  = "center",
        width  = display.contentWidth * 0.88
    })
    S.classIdText:setFillColor(unpack(colors.textPrimary))

    S.classHelperText = display.newText({
        parent = sceneGroup,
        text   = languages.t("share_with_students") or "Share this with your students.",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = native.systemFont,
        fontSize = 18,
        align  = "center",
        width  = display.contentWidth * 0.88
    })
    S.classHelperText:setFillColor(unpack(colors.textPrimary))
    S.classHelperText.alpha = 0.92

    S.titleInputCardGroup = newInputCard(
        sceneGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.contentWidth * 0.90,
        44,
        14
    )

    S._titleMeasureText = display.newText({
        parent = sceneGroup,
        text = "",
        x = -10000,
        y = -10000,
        font = TITLE_FONT_NAME,
        fontSize = 22
    })
    S._titleMeasureText.isVisible = false

    S.levelNameField = native.newTextField(1, 1, 10, 10)
    S.levelNameField.placeholder = languages.t("enter_level_name") or "Enter a level name"
    S.levelNameField.text = S.levelTitle or ""
    S.levelNameField:setTextColor(0,0,0)
    if S.levelNameField.hasBackground ~= nil then
        S.levelNameField.hasBackground = true
    end
    S.levelNameField.font = native.newFont(TITLE_FONT_NAME, UI.fsInput)
    S.levelNameField.align = "left"
    S.levelNameField:addEventListener("userInput", onTitleInput)
    sceneGroup:insert(S.levelNameField)

    S.themeLabel = display.newText({
        parent = sceneGroup,
        text   = languages.t("theme") or "Theme",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 20
    })
    S.themeLabel:setFillColor(unpack(colors.textPrimary))

    S.themeToggleBtn = display.newRoundedRect(sceneGroup, display.contentCenterX, display.contentCenterY, 160, 40, 14)
    S.themeToggleBtn:setFillColor(1, 1, 1, 0.55)
    S.themeToggleBtn.strokeWidth = 2
    S.themeToggleBtn:setStrokeColor(unpack(colors.secondaryActionBorder))

    S.themeBtnLabel = display.newText({
        parent = sceneGroup,
        text   = S.lastThemeValue or "Original",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 20
    })
    S.themeBtnLabel:setFillColor(unpack(colors.textPrimary))

    S.recordStatus = display.newText({
        parent = sceneGroup,
        text   = "",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 18,
        align  = "center",
        width  = display.contentWidth * 0.88
    })
    S.recordStatus:setFillColor(unpack(colors.error))
    S.recordStatus.isVisible = false

    S.recordStatusBg = display.newRoundedRect(
        sceneGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.contentWidth * 0.44,
        42,
        14
    )
    S.recordStatusBg:setFillColor(
        colors.appBackgroundSoft[1],
        colors.appBackgroundSoft[2],
        colors.appBackgroundSoft[3],
        0.82
    )
    S.recordStatusBg.strokeWidth = 2
    S.recordStatusBg:setStrokeColor(
        colors.secondaryActionBorder[1],
        colors.secondaryActionBorder[2],
        colors.secondaryActionBorder[3],
        0.55
    )
    S.recordStatusBg.isVisible = false

    S.themeToggleBtn:addEventListener("tap", function()
        if S.themeOverlay then hideThemePicker() else showThemePicker() end
        return true
    end)
    S.themeBtnLabel:addEventListener("tap", function()
        if S.themeToggleBtn then
            S.themeToggleBtn:dispatchEvent({ name="tap" })
        end
        return true
    end)

    S.saveBtn = newWidePrimaryButton(
        sceneGroup,
        (languages.t("save") or "Save"),
        display.contentCenterX, display.contentCenterY,
        300, UI.buttonH,
        function()
            local hasAccess = buttonAccess.hasAccess(appState)
            if not hasAccess then
                native.showAlert("Subscription Required", "Please subscribe to save this level.", { "OK" })
                return
            end
            local isUpdate = (S.Level and S.Level.text and S.Level.text ~= "NEW")
            saveLevelAndSuccess(isUpdate)
        end
    )

    S.wordsCard = newReadabilityPanel(sceneGroup, display.contentCenterX, display.contentCenterY, display.contentWidth * 0.92, display.contentHeight * 0.46, UI.radiusCard, 0.78)

    S.tabsGroup = display.newGroup()
    sceneGroup:insert(S.tabsGroup)

    S.tabsBaseline = display.newRect(S.tabsGroup, display.contentCenterX, display.contentCenterY, display.contentWidth * 0.80, 2)
    S.tabsBaseline:setFillColor(0, 0, 0, 0.10)
    S.tabsBaseline:toBack()

    S.tabWords = newTabButton(S.tabsGroup, (languages.t("words_to_remember") or "Words to Remember"), function()
        setActiveSection("words")
        styleTab("words")
        layoutUI()
        setNativeInputsVisible(true)
        return true
    end)

    S.tabSuccess = newTabButton(S.tabsGroup, (languages.t("success_message") or "Success Message"), function()
        setActiveSection("success")
        styleTab("success")
        layoutUI()
        setNativeInputsVisible(true)
        return true
    end)

    S.activeSection = "words"
    styleTab("words")

    S.wordsHeaderText = display.newText({
        parent = sceneGroup,
        text   = languages.t("words_to_remember") or "Words to Remember",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 22,
        align  = "left"
    })
    S.wordsHeaderText.anchorX = 0
    S.wordsHeaderText.anchorY = 0.5
    S.wordsHeaderText:setFillColor(unpack(colors.textPrimary))

    S.previewLevelPill = newPill(sceneGroup, display.contentCenterX, display.contentCenterY, languages.t("preview_game") or "Preview Game", UI.fsPill)
    S.previewLevelPill:addEventListener("tap", function()
        if not S.previewLevelPill._isEnabled then return true end
        gotoGamePreview()
        return true
    end)

    S.wordsInputCardGroup = newInputCard(sceneGroup, display.contentCenterX, display.contentCenterY, display.contentWidth * 0.90, display.contentHeight * 0.16, UI.radiusInput)
    S.wordsTextBox = native.newTextBox(display.contentCenterX, display.contentCenterY, display.contentWidth * 0.90, display.contentHeight * 0.16)
    S.wordsTextBox.isEditable = true
    S.wordsTextBox:setTextColor(0,0,0)
    if S.wordsTextBox.hasBackground ~= nil then S.wordsTextBox.hasBackground = true end
    S.wordsTextBox:addEventListener("userInput", onWordsInput)
    sceneGroup:insert(S.wordsTextBox)

    S.successHeaderText = display.newText({
        parent = sceneGroup,
        text   = languages.t("success_message") or "Success Message",
        x      = display.contentCenterX,
        y      = display.contentCenterY,
        font   = TITLE_FONT_NAME,
        fontSize = 22,
        align  = "left"
    })
    S.successHeaderText.anchorX = 0
    S.successHeaderText.anchorY = 0.5
    S.successHeaderText:setFillColor(unpack(colors.textPrimary))

    S.previewSuccessPill = newPill(sceneGroup, display.contentCenterX, display.contentCenterY, languages.t("preview_success") or "Preview Success", UI.fsPill)
    S.previewSuccessPill:addEventListener("tap", function()
        if not S.previewSuccessPill._isEnabled then return true end
        gotoSuccessPreview()
        return true
    end)

    S.successInputCardGroup = newInputCard(sceneGroup, display.contentCenterX, display.contentCenterY, display.contentWidth * 0.90, display.contentHeight * 0.13, UI.radiusInput)
    S.successTextBox = native.newTextBox(display.contentCenterX, display.contentCenterY, display.contentWidth * 0.90, display.contentHeight * 0.13)
    S.successTextBox.isEditable = true
    S.successTextBox:setTextColor(0,0,0)
    if S.successTextBox.hasBackground ~= nil then S.successTextBox.hasBackground = true end
    S.successTextBox:addEventListener("userInput", onSuccessInput)
    sceneGroup:insert(S.successTextBox)

    S.Level = native.newTextField(1, 1, 10, 10)
    S.Level.text = S.levelId or "NEW"
    S.Level.isVisible = false
    sceneGroup:insert(S.Level)

    S._onResize = function()
        layoutUI()
    end
    Runtime:addEventListener("resize", S._onResize)
    Runtime:addEventListener("keyboard", onKeyboardEvent)

    updatePreviewAvailability()
    applySaveButtonAccessState()
    layoutUI()

    S.activeSection = "words"
    styleTab("words")
    if S.successHeaderText then S.successHeaderText.isVisible = false end
    if S.previewSuccessPill then S.previewSuccessPill.isVisible = false end
    if S.successInputCardGroup then S.successInputCardGroup.isVisible = false end
    if S.successTextBox then S.successTextBox.isVisible = false end

    setNativeInputsVisible(true)
end

function scene:show(event)
    if event.phase == "will" then
        refreshSharedState(event.params or {})
        goBack = false
        S._isActive = true
        setRecordStatus("")
        cancelNetwork()
    end

    applySaveButtonAccessState()

    if event.phase == "did" then
        local sceneGroup = self.view

        if not S.header then
            S.header = StandardHeader.new(sceneGroup, {
                titlePlacement    = "back",
                fallbackTitle     = "",
                onBack            = gotoSelectLevels,
                backIconImage     = "icons/back.png",
                titleColor        = colors.textPrimary,
                backLabelFontSize = 44,
                backLabelGap      = 8,
            })
        end

        if not S.gearGroup then
            S.gearGroup = display.newGroup()
            sceneGroup:insert(S.gearGroup)

            local gearIcon = display.newImageRect(S.gearGroup, "icons/gear6-blue.png", 62, 62)
            gearIcon.x, gearIcon.y = 0, 0

            local gearHit = display.newRect(S.gearGroup, 0, 0, 110, 110)
            gearHit.isVisible = false
            gearHit.isHitTestable = true
            gearHit:addEventListener("tap", function()
                gotoSettings()
                return true
            end)
        end

        if S.classIdText then
            S.classIdText.text = (languages.t("class_id") or "Class ID") .. ": " .. tostring(S.prefix or "")
        end

        if S.levelNameField and S.mode == "create" then
            S.levelNameField.text = S.levelTitle or ""
            relayoutTitleField()
        end

        if S.themeBtnLabel then
            S.themeBtnLabel.text = S.lastThemeValue or "Original"
        end

        setNativeInputsVisible(true)
        layoutUI()

        if S.mode == "create" or tostring(S.levelId) == "NEW" then
            if not S._initialized then
                if S.Level then S.Level.text = "NEW" end
                if S.levelNameField then
                    S.levelNameField.text = (S.levelTitle or "")
                    relayoutTitleField()
                end

                S.wordsCache = S.wordsCache or ""
                S.successCache = S.successCache or ""

                if S.wordsTextBox then S.wordsTextBox.text = tostring(S.wordsCache) end
                if S.successTextBox then S.successTextBox.text = tostring(S.successCache) end

                S.titleDirty = false
                S.wordsDirty = false
                S.successDirty = false
                S._initialized = true
            else
                if S.wordsTextBox then S.wordsTextBox.text = tostring(S.wordsCache or "") end
                if S.successTextBox then S.successTextBox.text = tostring(S.successCache or "") end
            end

            S.keyboardInset = 0
            S.editingField = nil

            setRecordStatus("")

            S.activeSection = "words"
            styleTab("words")
            if S.wordsHeaderText then S.wordsHeaderText.isVisible = true end
            if S.previewLevelPill then S.previewLevelPill.isVisible = true end
            if S.wordsInputCardGroup then S.wordsInputCardGroup.isVisible = true end
            if S.wordsTextBox then S.wordsTextBox.isVisible = true end

            if S.successHeaderText then S.successHeaderText.isVisible = false end
            if S.previewSuccessPill then S.previewSuccessPill.isVisible = false end
            if S.successInputCardGroup then S.successInputCardGroup.isVisible = false end
            if S.successTextBox then S.successTextBox.isVisible = false end

            updatePreviewAvailability()
            layoutUI()
            setNativeInputsVisible(true)
        else
            loadLevelData(function(ok)
                if not S._isActive or goBack then return end
                updatePreviewAvailability()
                layoutUI()
                setNativeInputsVisible(true)
            end)
        end
    end
end

function scene:hide(event)
    if event.phase == "will" then
        S._isActive = false
        cancelNetwork()
        
        setRecordStatus("")
        S.keyboardInset = 0
        S.editingField = nil

        appState.set({
            prefix = S.prefix,
            className = S.className,
            classStatus = S.classStatus
        })

        native.setKeyboardFocus(nil)
        setNativeInputsVisible(false)
        if destroyThemeOverlay then destroyThemeOverlay() end
    end
end

function scene:destroy(event)
    S._isActive = false
    cancelNetwork()
    S._initialized = false
    S.wordsCache = ""
    S.successCache = ""
    if S._onResize then
        Runtime:removeEventListener("resize", S._onResize)
        S._onResize = nil
    end

    Runtime:removeEventListener("keyboard", onKeyboardEvent)

    if destroyThemeOverlay then destroyThemeOverlay() end

    if S.levelNameField then S.levelNameField:removeSelf(); S.levelNameField = nil end
    if S.wordsTextBox then S.wordsTextBox:removeSelf(); S.wordsTextBox = nil end
    if S.successTextBox then S.successTextBox:removeSelf(); S.successTextBox = nil end
    if S.Level then S.Level:removeSelf(); S.Level = nil end
    if S.saveBtn then display.remove(S.saveBtn); S.saveBtn = nil end

    if S.titleInputCardGroup then display.remove(S.titleInputCardGroup); S.titleInputCardGroup = nil end
    if S._titleMeasureText then display.remove(S._titleMeasureText); S._titleMeasureText = nil end

    if S.wordsInputCardGroup then display.remove(S.wordsInputCardGroup); S.wordsInputCardGroup = nil end
    if S.successInputCardGroup then display.remove(S.successInputCardGroup); S.successInputCardGroup = nil end

    if S.previewLevelPill then display.remove(S.previewLevelPill); S.previewLevelPill = nil end
    if S.previewSuccessPill then display.remove(S.previewSuccessPill); S.previewSuccessPill = nil end

    if S.tabWords then display.remove(S.tabWords); S.tabWords = nil end
    if S.tabSuccess then display.remove(S.tabSuccess); S.tabSuccess = nil end
    if S.tabsBaseline then display.remove(S.tabsBaseline); S.tabsBaseline = nil end
    if S.tabsGroup then display.remove(S.tabsGroup); S.tabsGroup = nil end

    if S.themeLabel then display.remove(S.themeLabel); S.themeLabel = nil end
    if S.themeToggleBtn then display.remove(S.themeToggleBtn); S.themeToggleBtn = nil end
    if S.themeBtnLabel then display.remove(S.themeBtnLabel); S.themeBtnLabel = nil end

    if S.topCard then display.remove(S.topCard); S.topCard = nil end
    if S.wordsCard then display.remove(S.wordsCard); S.wordsCard = nil end

    if S.recordStatusBg then display.remove(S.recordStatusBg); S.recordStatusBg = nil end
    if S.recordStatus then display.remove(S.recordStatus); S.recordStatus = nil end

    if S.classIdText then display.remove(S.classIdText); S.classIdText = nil end
    if S.classHelperText then display.remove(S.classHelperText); S.classHelperText = nil end

    if S.headerBand then display.remove(S.headerBand); S.headerBand = nil end
    if S.headerBandDivider then display.remove(S.headerBandDivider); S.headerBandDivider = nil end

    if S.gearGroup then display.remove(S.gearGroup); S.gearGroup = nil end

    if S.fullBleedBg then display.remove(S.fullBleedBg); S.fullBleedBg = nil end
    if S.persistentDim then display.remove(S.persistentDim); S.persistentDim = nil end
    if S.background then display.remove(S.background); S.background = nil end

    if S.header and S.header.destroy then
        S.header:destroy()
        S.header = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
------------------------------------------------------------
-- success.lua  (Level Complete Screen)
------------------------------------------------------------
local composer         = require("composer")
local scene            = composer.newScene()

local colors           = require("colors")
local languages        = require("languages")
local accessibleButton = require("accessibleButton")
local json             = require("json")
local StandardHeader   = require("ui.standardHeader")
local logger           = require("logger")

------------------------------------------------------------
-- Locals / State
------------------------------------------------------------
local user, name, classCode, className, level, title, text, theme
local successTextDisplay
local panelW, panelH
local headerObj
local headerBand
local headerBandDivider
local headerTextDisplay
------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function safeColor(c, fallback)
    if type(c) == "table" and #c >= 3 then return c end
    return fallback or { 1, 1, 1 }
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function applyParams(params)
    params = params or {}

    user      = params.user or user
    name      = params.name or name
    classCode =
          params.prefix
       or params.classCode
       or params.class_code
       or classCode
       or composer.getVariable("prefix")
    className = params.className or className or composer.getVariable("className")
    level     = params.level or level
    title     = params.title or title
    text      = params.text or text
    theme     = params.theme or theme
end

local function getUiScale()
    local baseW, baseH = 720, 1280
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight
    local s = math.min(safeW / baseW, safeH / baseH)
    return clamp(s, 1.0, 3.0)
end

local function urlencode(str)
    if (str) then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
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
-- Auto-fit the success text inside the cream panel
------------------------------------------------------------
local function fitTextToPanel(displayObj, maxW, maxH, startSize, minSize, padding)
    if not displayObj then return end

    padding   = padding or 16
    startSize = startSize or displayObj.size or 72
    minSize   = minSize or 26

    displayObj.width = maxW - padding * 2

    local size = startSize
    displayObj.size = size

    local function fits()
        return (displayObj.contentWidth <= (maxW - padding * 2) + 1)
           and (displayObj.contentHeight <= (maxH - padding * 2) + 1)
    end

    while size > minSize and not fits() do
        size = size - 2
        displayObj.size = size
    end

    while displayObj.contentHeight > (maxH - padding * 2) + 1 and size > 18 do
        size = size - 1
        displayObj.size = size
    end
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function gotoMenu()
    logger.scene("success", "gotoMenu user=", tostring(user), " name=", tostring(name))
    composer.removeScene("game")
    composer.gotoScene("menu")
end

local function gotoNextLevel()
    local prefix         = classCode or composer.getVariable("prefix")
    local currentLevelId = tonumber(level)

    if not user or not prefix or not currentLevelId then
        logger.error(
            "[scene:success] gotoNextLevel missing user/prefix/currentLevelId",
            " user=", tostring(user),
            " prefix=", tostring(prefix),
            " level=", tostring(level)
        )
        print("NextLevel error: missing user/prefix/currentLevelId",
              "user=", user, "prefix=", prefix, "level=", level)
        return
    end

    local url = "https://www.infoshagame.com/user/list/getLevelP.php"
        .. "?type=getp"
        .. "&user="   .. tostring(user)
        .. "&prefix=" .. tostring(prefix)

    logger.scene("success", "gotoNextLevel request start currentLevelId=", tostring(currentLevelId), " prefix=", tostring(prefix))

    network.request(url, "GET", function(event)
        if event.isError then
            logger.error("[scene:success] gotoNextLevel network error currentLevelId=", tostring(currentLevelId))
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("error_connection") or "Could not connect to server.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        local list = json.decode(event.response)
        if not list or #list == 0 then
            logger.error("[scene:success] gotoNextLevel empty or invalid level list currentLevelId=", tostring(currentLevelId))
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("no_passages_found") or "No passages found.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        local nextLevelId = nil
        for i, row in ipairs(list) do
            local rowId = tonumber(row.LevelID)
            if rowId == currentLevelId then
                for j = i + 1, #list do
                    local r = list[j]
                    if r.Text and r.Text ~= "" then
                        nextLevelId = tonumber(r.LevelID)
                        break
                    end
                end
                break
            end
        end

        if not nextLevelId then
            logger.scene("success", "gotoNextLevel no next level found, going to selectLevel")
            composer.removeScene("success")
            composer.gotoScene("selectLevel", { params = { user = user, prefix = classCode } })
            return
        end

        logger.scene("success", "gotoNextLevel success nextLevelId=", tostring(nextLevelId))
        composer.removeScene("success")
        composer.gotoScene("game", {
            params = {
                user              = user,
                name              = name,
                classCode         = classCode,
                className         = className,
                desiredLevel      = nextLevelId,
                useFirstAvailable = false
            }
        })
    end)
end

local function gotoCustomize()
    if not classCode or classCode == ""  then
        logger.warn("[scene:success] gotoCustomize blocked missing classCode")
        native.showAlert(languages.t("no_class_selected"), languages.t("please_select_class"), { languages.t("ok") })
        return
    end

    logger.scene("success", "gotoCustomize user=", tostring(user), " name=", tostring(name), " classCode=", tostring(classCode), " level=", tostring(level))
    composer.removeScene("game")
    composer.gotoScene("customize", {
    effect = "slideRight",
    time = 250,
    params = {
        user       = user,
        name       = name,
        prefix     = classCode,
        className  = className,
        levelId    = level,
        levelTitle = title,
        theme      = theme,
        mode       = "edit",
    }
})
end

------------------------------------------------------------
-- Load Success Text
------------------------------------------------------------
local function loadSuccessText(levelId, fallbackText)
    if not levelId then
        logger.warn("[scene:success] loadSuccessText missing levelId, using fallback")
        if successTextDisplay then
            successTextDisplay.text = fallbackText or ""
            fitTextToPanel(successTextDisplay, panelW, panelH, 78, 26, 18)
        end
        return
    end

    logger.scene("success", "loadSuccessText start levelId=", tostring(levelId), " fallbackLen=", tostring(#tostring(fallbackText or "")))

    local combined = ""
    local pendingRequests = 1
    local countrs = { 1 }

    local function finish()
        if not successTextDisplay then
            logger.warn("[scene:success] loadSuccessText finish skipped successTextDisplay=nil")
            return
        end

        if combined ~= "" then
            logger.scene("success", "loadSuccessText finish using remote text textLen=", tostring(#combined))
            successTextDisplay.text = combined
        else
            logger.warn("[scene:success] loadSuccessText finish using fallback text")
            successTextDisplay.text = fallbackText or languages.t("no_success_messages_found") or "No success messages found"
        end
        fitTextToPanel(successTextDisplay, panelW, panelH, 78, 26, 18)
    end

    local function onResponse(event)
        pendingRequests = pendingRequests - 1

        if not event.isError and event.response and event.response ~= "" then
            local response = json.decode(event.response)
            if response and type(response) == "table" and #response > 0 then
                for _, row in ipairs(response) do
                    if row.SuccessText and row.SuccessText ~= "" then
                        combined = combined .. row.SuccessText .. "\n"
                    end
                end
            end
        else
            logger.warn("[scene:success] loadSuccessText one request failed or empty, pendingRequests=", tostring(pendingRequests))
        end

        if pendingRequests == 0 then
            combined = combined:gsub("%s+$", "")
            finish()
        end
    end

    if successTextDisplay then
        successTextDisplay.text = languages.t("loading_success_message") or "Loading success message"
        fitTextToPanel(successTextDisplay, panelW, panelH, 60, 26, 18)
    end

    for _, c in ipairs(countrs) do
        local url = "https://infoshagame.com/user/list/getSuccess.php?type=gets"
            .. "&level=" .. urlencode(tostring(levelId))
            .. "&countr=" .. tostring(c)
        network.request(url, "GET", onResponse)
    end
end

------------------------------------------------------------
-- Scene: create
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    local params     = event.params or {}
    local uiScale    = getUiScale()

    user      = params.user
    name      = params.name
    classCode =
      params.prefix
   or params.classCode
   or params.class_code
   or composer.getVariable("prefix")
    className = params.className or composer.getVariable("className")
    level     = params.level
    title     = params.title
    text      = params.text
    theme     = params.theme

    local fallbackSuccess = params.successText or params.success or params.success_message or text or ""

    logger.scene(
        "success",
        "create start user=", tostring(user),
        " name=", tostring(name),
        " classCode=", tostring(classCode),
        " className=", tostring(className),
        " level=", tostring(level),
        " title=", tostring(title),
        " theme=", tostring(theme),
        " fallbackSuccessLen=", tostring(#tostring(fallbackSuccess))
    )

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    local bgFile = (theme and theme ~= "") and ("themes/" .. theme .. "-bg.png") or "themes/Original-bg.png"

    local background = newAspectFillImage(sceneGroup, bgFile)
    if background then
        background:toBack()
        logger.scene("success", "background loaded bgFile=", tostring(bgFile))
    else
        logger.warn("[scene:success] background load failed, using fallback rect bgFile=", tostring(bgFile))
        background = display.newRect(
            sceneGroup,
            display.contentCenterX,
            display.contentCenterY,
            display.actualContentWidth,
            display.actualContentHeight
        )
        background:setFillColor(unpack(safeColor(colors.appBackgroundSoft, { 0.90, 0.97, 1.00 })))
        background:toBack()
    end

    --------------------------------------------------------
    -- Header
    --------------------------------------------------------
    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth

    local headerH = math.floor(display.contentHeight * 0.11)
    local headerCenterY = safeY + headerH * 0.5

    local bg = colors.appBackgroundSoft or { 1, 1, 1 }
    headerBand = display.newRect(sceneGroup, safeX + safeW * 0.5, headerCenterY, safeW, headerH)
    headerBand:setFillColor(bg[1], bg[2], bg[3], 0.28)
    headerBand:toFront()

    headerBandDivider = display.newRect(sceneGroup, safeX + safeW * 0.5, safeY + headerH, safeW, 1)
    headerBandDivider:setFillColor(0, 0, 0, 0.10)
    headerBandDivider:toFront()

    headerObj = StandardHeader.new(sceneGroup, {
        titlePlacement    = "back",
        fallbackTitle     = "",
        onBack            = gotoCustomize,
        backIconImage     = "icons/back.png",
        titleColor        = colors.textPrimary,
        backLabelFontSize = 44,
        backLabelGap      = 8,
    })
    logger.scene("success", "header created")

    local blue = colors.primaryAction or { 0.10, 0.45, 0.85 }
    if headerObj then
        if headerObj.backIcon and headerObj.backIcon.setFillColor then
            headerObj.backIcon:setFillColor(unpack(blue))
        elseif headerObj.backArrow and headerObj.backArrow.setFillColor then
            headerObj.backArrow:setFillColor(unpack(blue))
        elseif headerObj.backIconImage and headerObj.backIconImage.setFillColor then
            headerObj.backIconImage:setFillColor(unpack(blue))
        end
    end

    if headerObj and headerObj.group and headerObj.group.toFront then
        headerObj.group:toFront()
    end

    local headerLine = (languages.t("you_completed") or "You completed") .. " " .. tostring(title or "")
        headerTextDisplay = display.newText({
            parent   = sceneGroup,
            text     = headerLine,
            x        = display.contentCenterX,
            y        = display.contentHeight * 0.14,
            width    = display.contentWidth * 0.92,
            font     = native.systemFontBold,
            fontSize = 52,
            align    = "center"
        })
        headerTextDisplay:setFillColor(unpack(safeColor(colors.textPrimary, { 0.18, 0.18, 0.18 })))
    --------------------------------------------------------
    -- Cream panel + bordered
    --------------------------------------------------------
    panelW = display.contentWidth * 0.90
    panelH = display.contentHeight * 0.68
    local panelY = display.contentHeight * 0.55

    local panel = display.newRoundedRect(sceneGroup, display.contentCenterX, panelY, panelW, panelH, 18)
    panel:setFillColor(unpack(safeColor(colors.secondaryAction, { 1.00, 0.95, 0.85 })))
    panel.alpha = 0.80

    panel.strokeWidth = 4
    panel:setStrokeColor(unpack(safeColor(colors.secondaryActionBorder, { 0.78, 0.31, 0.00 })))

    successTextDisplay = display.newText({
        parent   = sceneGroup,
        text     = fallbackSuccess or "",
        x        = display.contentCenterX,
        y        = panelY,
        width    = panelW * 0.92,
        font     = native.systemFontBold,
        fontSize = 78,
        align    = "center"
    })
    successTextDisplay:setFillColor(unpack(safeColor(colors.textPrimary, { 0.18, 0.18, 0.18 })))

    fitTextToPanel(successTextDisplay, panelW, panelH, 78, 26, 18)

    --------------------------------------------------------
    -- Fetch from server
    --------------------------------------------------------
    loadSuccessText(level, fallbackSuccess)
end

------------------------------------------------------------
-- Standard scene events
------------------------------------------------------------
function scene:show(event)
    logger.scene("success", "show phase=", event.phase or "nil")

    if event.phase == "will" then
        applyParams(event.params)

        if headerTextDisplay then
            headerTextDisplay.text = (languages.t("you_completed") or "You completed") .. " " .. tostring(title or "")
        end
        local bgFile = (theme and theme ~= "") and ("themes/" .. theme .. "-bg.png") or "themes/Original-bg.png"
        logger.scene(
            "success",
            "show will refreshed params user=", tostring(user),
            " classCode=", tostring(classCode),
            " level=", tostring(level),
            " title=", tostring(title),
            " theme=", tostring(theme),
            " bgFile=", tostring(bgFile)
        )
    end

    if event.phase == "did" then
        local params = event.params or {}
        local fallbackSuccess = params.successText or params.success or params.success_message or text or ""

        loadSuccessText(level, fallbackSuccess)
    end
end

function scene:hide(event)
    logger.scene("success", "hide phase=", event.phase or "nil")
end

function scene:destroy(event)
    logger.scene("success", "destroy start")
    headerTextDisplay = nil
    level = nil
    classCode = nil
    successTextDisplay = nil
    panelW, panelH = nil, nil

    if headerObj and headerObj.destroy then
        headerObj:destroy()
        headerObj = nil
    end

    if headerBandDivider then display.remove(headerBandDivider); headerBandDivider = nil end
    if headerBand then display.remove(headerBand); headerBand = nil end

    logger.scene("success", "destroy complete")
end

scene:addEventListener("create",  scene)
scene:addEventListener("show",    scene)
scene:addEventListener("hide",    scene)
scene:addEventListener("destroy", scene)

return scene
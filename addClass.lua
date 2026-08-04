-- addClass.lua
-- Card List Select Screen + Popup Add Class
------------------------------------------------------------

local composer = require("composer")
local widget   = require("widget")
local scene    = composer.newScene()
local tutorialGroup
------------------------------------------------------------
-- Globals and Imports
------------------------------------------------------------
local recordStatus

local colors           = require("colors")
local accessibleButton = require("accessibleButton")
local json             = require("json")
local languages        = require("languages")
local logger           = require("logger")
local appState         = require("appState")
local buttonAccess     = require("buttonAccess")
local tutorial = require("tutorial")
local userId   = nil
local userName = nil
local apiToken = nil
local appId    = nil

local gearGroup
local titleLabel
local greetingLabel
local helperText
local newClassButton

local selectedClassId
local selectedLabel
local selectedClassName
local selectedClassStatus
local classListTable
local classRows = {}

local listViewportH = 0
local rowHeightPx = 180
local listH
local listPadPx

local background

local isScrolling = false
local scrollTouchCount = 0
local SV_RIGHT_GUTTER = 0

local popup = {
    group = nil,
    dim = nil,
    card = nil,
    title = nil,
    codeLabel = nil,
    codeValue = nil,
    nameLabel = nil,
    nameField = nil,
    cancelBtn = nil,
    saveBtn = nil,
    regenBtn = nil,

    keyboardInset = 0,
    fieldHasFocus = false,
    cardW = 0,
    cardH = 0,
    centerX = 0,
    baseCenterY = 0,
}
local generatedPrefix = nil

------------------------------------------------------------
-- Utility: clamp
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

------------------------------------------------------------
-- Utility: URL Encode
------------------------------------------------------------
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

------------------------------------------------------------
-- Background helper
------------------------------------------------------------
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
-- Safe remove native fields
------------------------------------------------------------
local function removeNativeFields()
    if popup and popup.nameField then
        logger.scene("addClass", "removeNativeFields removing popup.nameField")
        popup.nameField:removeSelf()
        popup.nameField = nil
    end
end

------------------------------------------------------------
-- Layout helpers
------------------------------------------------------------
local function bottomY(obj)
    if not obj then return 0 end
    local h = obj.height or 0
    return obj.y + (h * 0.5)
end

local function userHasClasses()
    for i = 1, #classRows do
        if classRows[i].id and classRows[i].id ~= "" then
            return true
        end
    end
    return false
end

------------------------------------------------------------
-- Scroll gating helpers
------------------------------------------------------------
local function markScrolling()
    isScrolling = true
    scrollTouchCount = scrollTouchCount + 1
end

local function clearScrollingSoon()
    local token = scrollTouchCount
    timer.performWithDelay(160, function()
        if token == scrollTouchCount then
            isScrolling = false
        end
    end)
end

------------------------------------------------------------
-- Teacher-friendly status
------------------------------------------------------------
local function setRecordStatus(msg)
    if not recordStatus then return end
    msg = msg or ""
    recordStatus.text = msg
    local has = (tostring(msg):gsub("%s+", "") ~= "")
    recordStatus.isVisible = has
end

------------------------------------------------------------
-- Access state for Add Class button
------------------------------------------------------------
local function applyNewClassAccessState()
    if not newClassButton then return end

    local state = appState.get() or {}
    print("addClass state.hasAccess =", tostring(state.hasAccess),
          " type =", type(state.hasAccess),
          " accessStatus =", tostring(state.accessStatus))

    local hasAccess = buttonAccess.hasAccess(appState)

    print("applyNewClassAccessState resolved hasAccess:", tostring(hasAccess))

    buttonAccess.applyPrimaryActionAccess(newClassButton, hasAccess, colors)
end

------------------------------------------------------------
-- Check whether a class ID already exists
------------------------------------------------------------
local function checkPrefixExists(prefix, callback)
    if not prefix or prefix == "" then
        callback(false, "Missing prefix")
        return
    end

    local req = "https://infoshagame.com/user/list/checkClassId.php" ..
        "?type=cclass" ..
        "&prefix=" .. urlencode(prefix)

    logger.scene("addClass", "checkPrefixExists start prefix=", prefix, " request=", req)

    network.request(req, "GET", function(event)
        if event.isError then
            logger.error("[scene:addClass] checkPrefixExists network error prefix=", prefix)
            callback(false, "network")
            return
        end

        local response = nil
        if event.response and event.response ~= "" then
            response = json.decode(event.response)
        end

        if response and response.duplicate == true then
            logger.scene("addClass", "checkPrefixExists duplicate prefix=", prefix)
            callback(true, nil, response)
            return
        end

        if response and response.success == true then
            logger.scene("addClass", "checkPrefixExists available prefix=", prefix)
            callback(false, nil, response)
            return
        end

        logger.warn("[scene:addClass] checkPrefixExists unexpected response prefix=", prefix, " response=", tostring(event.response))
        callback(false, "invalid_response", response)
    end)
end

------------------------------------------------------------
-- Kid-friendly ClassID generator
------------------------------------------------------------
local function generateClassId(len)
    len = len or 6
    local alphabet = "23456789ABCDEFGHJKMNPQRSTUVWYZ"
    local chars = {}
    for i = 1, #alphabet do
        chars[#chars + 1] = alphabet:sub(i, i)
    end

    local out = {}
    for i = 1, len do
        out[#out + 1] = chars[math.random(1, #chars)]
    end
    return table.concat(out)
end

------------------------------------------------------------
-- Shared state sync
------------------------------------------------------------
local function refreshSharedState()
    local shared = appState.get() or {}
    userId   = shared.userId
    userName = shared.userName
    apiToken = shared.apiToken or system.getPreference("app", "apiToken", "string")
    appId    = shared.appId or composer.getVariable("appId") or "SMART_SHEEP"

    if not userName or userName == "" then
        userName = languages.t("player")
    end
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function gotoSettings()
    logger.scene("addClass", "gotoSettings")
    removeNativeFields()
    composer.gotoScene("settings", {
        effect = "slideLeft",
        time = 220,
        params = {
            returnTo = "addClass"
        }
    })
end

local function gotoCustomize()
    if not selectedClassId or selectedClassId == "" or selectedLabel == languages.t("no_classes_available") then
        logger.warn("[scene:addClass] gotoCustomize blocked selectedClassId=", tostring(selectedClassId), " selectedLabel=", tostring(selectedLabel))
        native.showAlert(languages.t("no_class_selected"), languages.t("please_select_class"), { languages.t("ok") })
        return
    end

    logger.scene(
        "addClass",
        "gotoCustomize selectedClassId=", selectedClassId,
        " selectedLabel=", selectedLabel,
        " className=", selectedClassName or "",
        " classStatus=", selectedClassStatus or ""
    )

    appState.set({
        prefix = selectedClassId,
        className = selectedClassName or "",
        classStatus = selectedClassStatus or "Draft"
    })

    removeNativeFields()
    composer.removeScene("addClass")
    composer.gotoScene("selectLevels", {
        params = {
            prefix = selectedClassId,
            className = selectedClassName,
            classStatus = selectedClassStatus or "Draft"
        }
    })
end

------------------------------------------------------------
-- Layout list + below content
------------------------------------------------------------
local function layoutBelowList()
    if not classListTable then return end

    if helperText then
        helperText.y = (classListTable.y + classListTable.height * 0.5) + 22
    end

    if newClassButton and helperText then
        newClassButton.y = helperText.y + 78
    end
end

local function layoutList()
    if not titleLabel or not classListTable or not listH then return end

    local anchor = bottomY(titleLabel)
    if recordStatus and recordStatus.isVisible then
        anchor = bottomY(recordStatus)
    end

    local pad = listPadPx or math.floor(display.contentHeight * 0.006)
    local listTop = anchor + pad
    local listCenterY = listTop + (listH * 0.5)
    classListTable.y = listCenterY

    listViewportH = listH
    layoutBelowList()
end

------------------------------------------------------------
-- Popup layout
------------------------------------------------------------
local function layoutPopup()
    if not popup or not popup.card then return end

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight

    local centerX = popup.centerX or (safeX + safeW * 0.5)
    local cardW = popup.cardW or (safeW * 0.90)
    local cardH = popup.cardH or math.max(420, safeH * 0.34)

    local baseCenterY = popup.baseCenterY or (safeY + safeH * 0.45)
    local keyboardInset = popup.keyboardInset or 0

    local visibleBottom = safeY + safeH - keyboardInset - 12
    local desiredCenterY = baseCenterY
    local popupBottom = desiredCenterY + cardH * 0.5

    if popupBottom > visibleBottom then
        desiredCenterY = desiredCenterY - (popupBottom - visibleBottom)
    end

    local minCenterY = safeY + 20 + cardH * 0.5
    if desiredCenterY < minCenterY then
        desiredCenterY = minCenterY
    end

    popup.card.x = centerX
    popup.card.y = desiredCenterY
    popup.card.width = cardW
    popup.card.height = cardH

    if popup.title then
        popup.title.x = centerX
        popup.title.y = desiredCenterY - cardH * 0.40
    end

    if popup.codeLabel then
        popup.codeLabel.x = centerX - cardW * 0.35
        popup.codeLabel.y = desiredCenterY - cardH * 0.26
        popup.codeLabel.anchorX = 0
    end

    if popup.codeValue then
        popup.codeValue.x = centerX - cardW * 0.35
        popup.codeValue.y = popup.codeLabel.y + 40
        popup.codeValue.anchorX = 0
    end

    if popup.regenBtn then
        popup.regenBtn.x = centerX + cardW * 0.22
        popup.regenBtn.y = popup.codeValue.y
    end

    if popup.nameLabel then
        popup.nameLabel.x = centerX - cardW * 0.35
        popup.nameLabel.y = popup.codeValue.y + 64
        popup.nameLabel.anchorX = 0
    end

    local fieldW = cardW * 0.86
    local fieldH = 64
    local fieldY = popup.nameLabel.y + 50

    if popup.nameField then
        popup.nameField.x = centerX
        popup.nameField.y = fieldY
        popup.nameField.width = fieldW
        popup.nameField.height = fieldH
    end

    local btnY = fieldY + fieldH + 100

    if popup.cancelBtn then
        popup.cancelBtn.x = centerX - cardW * 0.22
        popup.cancelBtn.y = btnY
    end

    if popup.saveBtn then
        popup.saveBtn.x = centerX + cardW * 0.22
        popup.saveBtn.y = btnY
    end
end

local function onPopupKeyboardEvent(event)
    if not popup or not popup.card then
        return false
    end

    local phase = event and event.phase
    local h = 0

    if event and event.endCoordinates and event.endCoordinates.height then
        h = tonumber(event.endCoordinates.height) or 0
    end

    logger.scene(
        "addClass",
        "popup keyboard event phase=", tostring(phase),
        " height=", tostring(h),
        " focus=", tostring(popup.fieldHasFocus)
    )

    if phase == "began" or phase == "willShow" or phase == "didShow" then
        popup.keyboardInset = h
        layoutPopup()
    elseif phase == "ended" or phase == "willHide" or phase == "didHide" then
        popup.keyboardInset = 0
        layoutPopup()
    end

    return false
end

------------------------------------------------------------
-- Safe refresh rows
------------------------------------------------------------
local function refreshClassListRows()
    if not classListTable then
        logger.warn("[scene:addClass] refreshClassListRows skipped classListTable=nil")
        return
    end
    if classListTable._isRefreshing then
        logger.warn("[scene:addClass] refreshClassListRows skipped already refreshing")
        return
    end

    logger.scene("addClass", "refreshClassListRows start rowCount=", #classRows)
    classListTable._isRefreshing = true

    local ok = pcall(function()
        if classListTable.deleteAllRows then
            classListTable:deleteAllRows()
            return
        end

        if classListTable.getNumRows and classListTable.deleteRow then
            local n = classListTable:getNumRows() or 0
            for i = n, 1, -1 do
                classListTable:deleteRow(i)
            end
            return
        end
    end)

    if not ok then
        logger.error("[scene:addClass] refreshClassListRows failed, recreating scene")
        classListTable._isRefreshing = false
        composer.removeScene("addClass")
        composer.gotoScene("addClass", { effect = "crossFade", time = 120 })
        return
    end

    for i = 1, #classRows do
        classListTable:insertRow({ rowHeight = rowHeightPx })
    end

    classListTable._isRefreshing = false
    logger.scene("addClass", "refreshClassListRows complete inserted=", #classRows)

    timer.performWithDelay(1, function()
        layoutList()
    end)

    
end

------------------------------------------------------------
-- Data: Load class list
------------------------------------------------------------
local function loadPrefixes(callback)
    if not userId then
        logger.warn("[scene:addClass] loadPrefixes missing userId")
        classRows = {
            { id = "", name = "", status = "", label = languages.t("no_classes_available") }
        }
        setRecordStatus("")
        callback()
        return
    end

    local request = "https://www.infoshagame.com/user/list/getPrefix.php?type=getP&user=" .. urlencode(userId)
    logger.scene("addClass", "loadPrefixes start userId=", userId, " request=", request)
    setRecordStatus((languages.t("loading_classes") or "Loading classes") .. "...")

    network.request(request, "GET", function(event)
        if event.isError then
            logger.error("[scene:addClass] loadPrefixes network error userId=", userId)
            setRecordStatus(languages.t("load_failed") or "Could not load classes.")
            classRows = {
                { id = "", name = "", status = "", label = languages.t("load_error") or "Load error" }
            }
            callback()
            return
        end

        print("loadPrefixes raw response:", event.response)

        local response = nil
        if event.response and event.response ~= "" then
            response = json.decode(event.response)
        end

        classRows = {}

        if response and type(response) == "table" and response.classes and type(response.classes) == "table" and #response.classes > 0 then
            logger.scene("addClass", "loadPrefixes success classes=", #response.classes)
            for _, entry in ipairs(response.classes) do
                local id   = entry.prefix or ""
                local name = entry.classname or ""
                local label = name .. " - " .. (languages.t("class_id") or "Class ID") .. ": " .. id
                local status = entry.status or "Published"

                table.insert(classRows, {
                    id = id,
                    name = name,
                    status = status,
                    label = label
                })
            end
        else
            logger.warn("[scene:addClass] loadPrefixes returned empty or invalid class list")
            table.insert(classRows, {
                id = "",
                name = "",
                status = "",
                label = languages.t("no_classes_available")
            })
        end

        setRecordStatus("")
        callback()
    end)

end

------------------------------------------------------------
-- Popup: show / hide
------------------------------------------------------------
local function destroyPopup()
    logger.scene("addClass", "destroyPopup")

    native.setKeyboardFocus(nil)

    if popup and popup.nameField then
        if popup.nameField.userInput then
            popup.nameField:removeEventListener("userInput", popup.nameField.userInput)
            popup.nameField.userInput = nil
        end
    end

    Runtime:removeEventListener("keyboard", onPopupKeyboardEvent)

    popup.keyboardInset = 0
    popup.fieldHasFocus = false
    popup.cardW = 0
    popup.cardH = 0
    popup.centerX = 0
    popup.baseCenterY = 0

    removeNativeFields()

    if popup and popup.group and popup.group.removeSelf then
        transition.cancel(popup.group)
        popup.group:removeSelf()
    end

    popup.group = nil
    popup.dim = nil
    popup.card = nil
    popup.title = nil
    popup.codeLabel = nil
    popup.codeValue = nil
    popup.nameLabel = nil
    popup.cancelBtn = nil
    popup.saveBtn = nil
    popup.regenBtn = nil
end

local function updatePopupCode(attempt)
    attempt = attempt or 1

    if attempt > 8 then
        logger.error("[scene:addClass] updatePopupCode exceeded attempts")
        generatedPrefix = generateClassId(6)
        if popup and popup.codeValue then
            popup.codeValue.text = generatedPrefix
        end
        return
    end

    local candidate = generateClassId(6)
    logger.scene("addClass", "updatePopupCode candidate=", candidate, " attempt=", attempt)

    checkPrefixExists(candidate, function(exists, err)
        if err == "network" then
            logger.warn("[scene:addClass] updatePopupCode network issue, keeping candidate=", candidate)
            generatedPrefix = candidate
            if popup and popup.codeValue then
                popup.codeValue.text = generatedPrefix
            end
            return
        end

        if exists then
            updatePopupCode(attempt + 1)
            return
        end

        generatedPrefix = candidate
        logger.scene("addClass", "updatePopupCode accepted generatedPrefix=", generatedPrefix)
        if popup and popup.codeValue then
            popup.codeValue.text = generatedPrefix
        end
    end)
end

local function showAddClassPopup(sceneGroup)
    if popup.group then
        logger.warn("[scene:addClass] showAddClassPopup ignored popup already open")
        return
    end

    logger.scene("addClass", "showAddClassPopup")
    popup.group = display.newGroup()
    sceneGroup:insert(popup.group)

    popup.dim = display.newRect(
        popup.group,
        display.contentCenterX,
        display.contentCenterY,
        display.contentWidth * 1.3,
        display.contentHeight * 1.3
    )
    popup.dim:setFillColor(0, 0, 0, 0.35)
    popup.dim.isHitTestable = true

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight

    local cardW = safeW * 0.90
    local cardH = math.max(520, safeH * 0.42)
    local centerX = safeX + safeW * 0.5
    local baseCenterY = safeY + safeH * 0.20

    popup.keyboardInset = 0
    popup.fieldHasFocus = false
    popup.cardW = cardW
    popup.cardH = cardH
    popup.centerX = centerX
    popup.baseCenterY = baseCenterY

    popup.card = display.newRoundedRect(
        popup.group,
        centerX,
        baseCenterY,
        cardW,
        cardH,
        24
    )
    popup.card:setFillColor(1, 1, 1, 0.96)
    popup.card.strokeWidth = 2
    popup.card:setStrokeColor(unpack(colors.appBackgroundDepth))

    popup.title = display.newText({
        parent = popup.group,
        text   = languages.t("add_class") or "Add Class",
        x      = centerX,
        y      = baseCenterY - cardH * 0.40,
        font   = native.systemFontBold,
        fontSize = 44,
        align  = "center"
    })
    popup.title:setFillColor(unpack(colors.textPrimary))

    popup.codeLabel = display.newText({
        parent = popup.group,
        text   = (languages.t("class_id") or "Class ID") .. ":",
        x      = centerX - cardW * 0.35,
        y      = baseCenterY - cardH * 0.18,
        font   = native.systemFontBold,
        fontSize = 30,
        align  = "left"
    })
    popup.codeLabel.anchorX = 0
    popup.codeLabel:setFillColor(unpack(colors.textSecondary))

    popup.codeValue = display.newText({
        parent = popup.group,
        text   = "------",
        x      = centerX - cardW * 0.35,
        y      = popup.codeLabel.y + 48,
        font   = native.systemFontBold,
        fontSize = 46,
        align  = "left"
    })
    popup.codeValue.anchorX = 0
    popup.codeValue:setFillColor(unpack(colors.textPrimary))

    popup.regenBtn = accessibleButton.new(
        popup.group,
        languages.t("new_code") or "New Code",
        centerX + cardW * 0.22,
        popup.codeValue.y,
        colors.secondaryAction,
        function()
            logger.scene("addClass", "regenBtn tapped")
            updatePopupCode()
        end,
        "↻",
        0.55
    )
    if popup.regenBtn and popup.regenBtn.label then
        popup.regenBtn.label:setFillColor(unpack(colors.textOnLight))
    end

    popup.nameLabel = display.newText({
        parent = popup.group,
        text   = (languages.t("class_name_label") or "Class Name"),
        x      = centerX - cardW * 0.35,
        y      = popup.codeValue.y + 72,
        font   = native.systemFontBold,
        fontSize = 30,
        align  = "left"
    })
    popup.nameLabel.anchorX = 0
    popup.nameLabel:setFillColor(unpack(colors.textSecondary))

    local fieldW = cardW * 0.86
    local fieldH = 64
    popup.nameField = native.newTextField(centerX, popup.nameLabel.y + 58, fieldW, fieldH)
    popup.nameField.placeholder = languages.t("class_name") or "Class Name"
    popup.nameField.font = native.newFont("Arial", 30)
    popup.nameField:setTextColor(unpack(colors.textPrimary))
    if popup.nameField.hasBackground ~= nil then
        popup.nameField.hasBackground = true
    end

    popup.nameField.userInput = function(event)
        if event.phase == "began" then
            popup.fieldHasFocus = true
        elseif event.phase == "ended" or event.phase == "submitted" then
            popup.fieldHasFocus = false
        end
        return false
    end
    popup.nameField:addEventListener("userInput", popup.nameField.userInput)

    local btnY = baseCenterY + cardH * 0.36

    popup.cancelBtn = accessibleButton.new(
        popup.group,
        languages.t("cancel") or "Cancel",
        centerX - cardW * 0.22,
        btnY,
        colors.secondaryAction,
        function()
            logger.scene("addClass", "cancel add class popup")
            native.setKeyboardFocus(nil)
            destroyPopup()
        end,
        "✕",
        0.65
    )
    if popup.cancelBtn and popup.cancelBtn.label then
        popup.cancelBtn.label:setFillColor(unpack(colors.textOnLight))
    end

    local function doSave()
        native.setKeyboardFocus(nil)
        popup.keyboardInset = 0
        layoutPopup()
        refreshSharedState()

        if not userId then
            logger.error("[scene:addClass] doSave missing userId")
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("error_connection") or "Missing user.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        if not apiToken or apiToken == "" then
            logger.error("[scene:addClass] doSave missing apiToken")
            native.showAlert(
                languages.t("error") or "Error",
                "Missing login token. Please log in again.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        local classname = (popup.nameField and popup.nameField.text) or ""
        classname = tostring(classname)

        if classname:gsub("%s+", "") == "" then
            logger.warn("[scene:addClass] doSave blocked empty classname")
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("error_missing") or "Please enter a class name.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        local prefix = generatedPrefix or (popup.codeValue and popup.codeValue.text) or ""

        if not prefix or prefix == "" or prefix == "------" then
            logger.warn("[scene:addClass] doSave blocked invalid prefix")
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("load_failed") or "Please try again.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        local request = "https://www.infoshagame.com/user/list/addClass.php"

        local body =
            "type=aclass" ..
            "&user=" .. urlencode(userId) ..
            "&prefix=" .. urlencode(prefix) ..
            "&class=" .. urlencode(classname) ..
            "&appId=" .. urlencode(appId or "")

        local params = {
            headers = {
                ["Content-Type"] = "application/x-www-form-urlencoded",
                ["Authorization"] = "Bearer " .. tostring(apiToken)
            },
            body = body
        }

        logger.scene(
            "addClass",
            "doSave POST request=", request,
            " userId=", tostring(userId),
            " prefix=", tostring(prefix),
            " appId=", tostring(appId or "")
        )

        network.request(request, "POST", function(event)
            if event.isError then
                logger.error("[scene:addClass] doSave network error prefix=", tostring(prefix))
                native.showAlert("Error", "Could not save class.", { "OK" })
                return
            end

            print("SAVE RESPONSE:", event.response)

            local response = nil
            if event.response and event.response ~= "" then
                response = json.decode(event.response)
            end

            if not response or response.success ~= true then
                logger.error("[scene:addClass] doSave backend rejected save response=", tostring(event.response))
                native.showAlert("Error", "Class was not saved.", { "OK" })
                return
            end

            logger.scene("addClass", "doSave confirmed success prefix=", tostring(prefix))

            destroyPopup()

            loadPrefixes(function()
                refreshClassListRows()
                timer.performWithDelay(250, function()
                if not userHasClasses() then
                        tutorial.start()
                    else
                        tutorial.stop()
                    end
                end)
            end)
        end, params)
    end

    popup.saveBtn = accessibleButton.new(
        popup.group,
        languages.t("save_class") or "Save Class",
        centerX + cardW * 0.22,
        btnY,
        colors.primaryAction,
        doSave,
        "✅",
        0.65
    )

    local function swallowTap(event)
        return true
    end

    local function dimTouch(event)
        if event.phase == "ended" then
            logger.scene("addClass", "popup dim tapped close")
            native.setKeyboardFocus(nil)
            destroyPopup()
        end
        return true
    end

    popup.dim:addEventListener("touch", dimTouch)
    popup.dim:addEventListener("tap", swallowTap)

    popup.card.isHitTestable = true
    popup.card:addEventListener("touch", function(event) return true end)
    popup.card:addEventListener("tap", swallowTap)

    Runtime:addEventListener("keyboard", onPopupKeyboardEvent)

    layoutPopup()
    updatePopupCode()
end

------------------------------------------------------------
-- Scene Creation
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    refreshSharedState()

    logger.scene("addClass", "create start userId=", userId or "nil", " userName=", userName or "nil")
    math.randomseed(os.time() + math.floor(system.getTimer()))

    background = newAspectFillImage(sceneGroup, "settings-background.png")
    if background then background:toBack() end

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight

    gearGroup = display.newGroup()
    sceneGroup:insert(gearGroup)

    local gearIcon = display.newImageRect(gearGroup, "icons/gear6-blue.png", 64, 64)
    gearIcon.x, gearIcon.y = 0, 0

    local gearHit = display.newRect(gearGroup, 0, 0, 110, 110)
    gearHit.isVisible = false
    gearHit.isHitTestable = true

    gearHit:addEventListener("tap", function()
        gotoSettings()
        return true
    end)

    tutorialGroup = display.newGroup()
    sceneGroup:insert(tutorialGroup)

    local tutorialIcon = display.newCircle(tutorialGroup, 0, 0, 24)
    tutorialIcon:setFillColor(1, 1, 1, 0.75)
    tutorialIcon.strokeWidth = 2
    tutorialIcon:setStrokeColor(unpack(colors.primaryAction))

    local tutorialText = display.newText({
        parent = tutorialGroup,
        text = "?",
        x = 0,
        y = -1,
        font = native.systemFontBold,
        fontSize = 32
    })
    tutorialText:setFillColor(unpack(colors.primaryAction))

    local tutorialHit = display.newRect(tutorialGroup, 0, 0, 90, 90)
    tutorialHit.isVisible = false
    tutorialHit.isHitTestable = true

    tutorialHit:addEventListener("tap", function()
        tutorial.start()
        return true
    end)

    tutorialGroup.x = safeX + safeW - 115
    tutorialGroup.y = safeY + 77
    greetingLabel = display.newText({
        parent = sceneGroup,
        text   = (languages.t("greeting") or "Hello") .. ", " .. userName,
        x      = display.contentCenterX,
        y      = safeY + safeH * 0.09,
        font   = native.systemFontBold,
        fontSize = 42,
        align  = "center",
        width  = safeW * 0.76
    })
    greetingLabel:setFillColor(unpack(colors.textPrimary))

    titleLabel = display.newText({
        parent = sceneGroup,
        text   = (languages.t("select_your_class") or "Add or Select Class"),
        x      = display.contentCenterX,
        y      = greetingLabel.contentBounds.yMax + 26,
        font   = native.systemFontBold,
        fontSize = 46,
        align  = "center",
        width  = safeW * 0.86
    })
    titleLabel:setFillColor(unpack(colors.textPrimary))

    recordStatus = display.newText({
        parent = sceneGroup,
        text   = "",
        x      = display.contentCenterX,
        y      = bottomY(titleLabel) + 22,
        font   = native.systemFont,
        fontSize = 30,
        align  = "center",
        width  = safeW * 0.92
    })
    recordStatus:setFillColor(unpack(colors.textSecondary))
    recordStatus.alpha = 0.95
    recordStatus.isVisible = false

    listH = safeH * 0.56
    listPadPx = math.floor(display.contentHeight * 0.005)
    listViewportH = listH

    rowHeightPx = math.floor(listH / 7.0)
    rowHeightPx = math.max(110, math.min(rowHeightPx, 150))

    classListTable = widget.newTableView({
        x = display.contentCenterX,
        y = display.contentCenterY,
        width  = safeW * 0.94,
        height = listH,
        hideBackground = true,
        noLines = true,
        rowHeight = rowHeightPx,
        hideScrollBar = true,

        listener = function(e)
            if e.phase == "moved" then
                markScrolling()
            end
            if e.phase == "ended" then
                clearScrollingSoon()
            end
            return false
        end,

        onRowRender = function(e)
            local row = e.row
            local data = classRows[row.index]
            if not data then return end

            local cardH = row.contentHeight * 0.92
            local rightInset = SV_RIGHT_GUTTER or 0

            local cardW = (row.contentWidth * 0.98) - rightInset
            local cardX = (row.contentWidth * 0.5) - (rightInset * 0.5)

            local cardLeft  = cardX - (cardW * 0.5)
            local cardRight = cardX + (cardW * 0.5)

            local card = display.newRoundedRect(
                row,
                cardX,
                row.contentHeight * 0.5,
                cardW,
                cardH,
                18
            )
            card:setFillColor(1, 1, 1, 0.78)
            card.strokeWidth = 2
            card:setStrokeColor(unpack(colors.appBackgroundDepth))

            local chevronX = cardRight - 32
            local titleX = cardLeft + 20
            local titleMaxW = math.max(80, (chevronX - 16) - titleX)

            local title = display.newText({
                parent = row,
                text   = data.label,
                x      = titleX,
                y      = row.contentHeight * 0.40,
                font   = native.systemFontBold,
                fontSize = 24,
                align  = "left",
                width  = titleMaxW
            })
            title.anchorX = 0
            title:setFillColor(unpack(colors.textPrimary))

            local status = data.status or ""
            if status ~= "" and data.id ~= "" then
                local pillW = 120
                local pillX = cardLeft + 20 + (pillW * 0.5)
                local pillY = row.contentHeight * 0.72

                local pill = display.newRoundedRect(row, pillX, pillY, pillW, 38, 18)

                local statusKey = "published"
                if status == "Draft" then
                    statusKey = "draft"
                    pill:setFillColor(0.65, 0.78, 0.92, 0.95)
                else
                    pill:setFillColor(0.38, 0.75, 0.62, 0.95)
                end

                local pillText = display.newText({
                    parent = row,
                    text = languages.t(statusKey) or status,
                    x = pillX,
                    y = pillY,
                    font = native.systemFontBold,
                    fontSize = 20
                })
                pillText:setFillColor(1, 1, 1)
            end

            local chevron = display.newText({
                parent = row,
                text = "›",
                x = chevronX,
                y = row.contentHeight * 0.52,
                font = native.systemFontBold,
                fontSize = 48
            })
            chevron:setFillColor(unpack(colors.primaryAction))

            local hit = display.newRect(
                row,
                row.contentWidth * 0.5,
                row.contentHeight * 0.5,
                row.contentWidth,
                row.contentHeight
            )
            hit.isVisible = false
            hit.isHitTestable = true

            hit:addEventListener("tap", function()
                local d = classRows[row.index]

                if isScrolling then
                    logger.warn("[scene:addClass] row tap ignored while scrolling rowIndex=", row.index)
                    return true
                end

                if d and d.id and d.id ~= "" and d.label ~= languages.t("no_classes_available") then
                    logger.scene("addClass", "row tap rowIndex=", row.index, " classId=", d.id, " label=", d.label)
                    selectedClassId = d.id
                    selectedLabel = d.label
                    selectedClassName = d.name or ""
                    selectedClassStatus = d.status or "Draft"
                    gotoCustomize()
                else
                    logger.warn("[scene:addClass] row tap ignored invalid row rowIndex=", row.index, " label=", d and d.label or "nil")
                end
                return true
            end)
        end,

        onRowTouch = function(e)
            return false
        end
    })
    sceneGroup:insert(classListTable)

    helperText = display.newText({
        parent = sceneGroup,
        text = (languages.t("dont_see_class") or "Don’t see your class? Add one below."),
        x = display.contentCenterX,
        y = 0,
        font = native.systemFont,
        fontSize = 30,
        align = "center",
        width = safeW * 0.88
    })
    helperText:setFillColor(unpack(colors.textSecondary))
    helperText.alpha = 0.95

    newClassButton = accessibleButton.new(
        sceneGroup,
        languages.t("add_class") or "Add Class",
        display.contentCenterX,
        0,
        colors.primaryAction,
        function()
            local hasAccess = buttonAccess.hasAccess(appState)

            if not hasAccess then
                native.showAlert(
                    "Subscription Required",
                    "Please subscribe to create a new class.",
                    { "OK" }
                )
                return
            end

            logger.scene("addClass", "newClassButton tapped")
            showAddClassPopup(sceneGroup)
        end,
        "➕",
        0.92
    )

    if newClassButton and newClassButton.label then
        newClassButton.label:setFillColor(unpack(colors.textOnPrimary))
    end

    applyNewClassAccessState()

    gearGroup.x = safeX + safeW - 50
    gearGroup.y = safeY + 77

    layoutList()

    loadPrefixes(function()
        logger.scene("addClass", "initial loadPrefixes callback")
        refreshClassListRows()

        timer.performWithDelay(250, function()
            if not userHasClasses() then
                tutorial.start()
            else
                tutorial.stop()
            end
        end)
    end)
end

function scene:show(event)
    logger.scene("addClass", "show phase=", event.phase or "nil")

    if event.phase == "will" then
        refreshSharedState()

        if greetingLabel then
            greetingLabel.text = (languages.t("greeting") or "Hello") .. ", " .. userName
        end

        if titleLabel then
            titleLabel.text = (languages.t("select_your_class") or "Add or Select Class")
        end

        if helperText then
            helperText.text = (languages.t("dont_see_class") or "Don’t see your class? Add one below.")
        end

        if newClassButton and newClassButton.label then
            newClassButton.label.text = languages.t("add_class") or "Add Class"
        end

        applyNewClassAccessState()

        loadPrefixes(function()
            refreshClassListRows()
        end)

        timer.performWithDelay(1, function()
            if classListTable then
                layoutList()
            end
        end)
    elseif event.phase == "did" then
        
    end
end

function scene:hide(event)
    logger.scene("addClass", "hide phase=", event.phase or "nil")

    if event.phase == "will" then
        tutorial.stop()
        destroyPopup()
        removeNativeFields()
    end
end

function scene:destroy(event)
    logger.scene("addClass", "destroy")

    destroyPopup()
    removeNativeFields()

    if classListTable then classListTable:removeSelf(); classListTable = nil end
    if newClassButton then newClassButton:removeSelf(); newClassButton = nil end
    if helperText then helperText:removeSelf(); helperText = nil end
    if titleLabel then titleLabel:removeSelf(); titleLabel = nil end
    if greetingLabel then greetingLabel:removeSelf(); greetingLabel = nil end
    if recordStatus then recordStatus:removeSelf(); recordStatus = nil end
    if gearGroup then gearGroup:removeSelf(); gearGroup = nil end
    if tutorialGroup then tutorialGroup:removeSelf(); tutorialGroup = nil end
    if background then background:removeSelf(); background = nil end
end

scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)
scene:addEventListener("create", scene)
scene:addEventListener("show", scene)

return scene
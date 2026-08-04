------------------------------------------------------------
-- selectLevels.lua
-- Refactored to avoid Lua upvalue limit
--
-- UI updates included:
--  • Class editor card at top (Class Name + Class ID + Draft/Published + Save)
--  • Inline status feedback: Updating... / Saved
--  • "Levels" header + Manage pill
--  • Removed status pill from each level row
--  • Manage mode shows delete ✕ per row + Done pill
--  • Settings gear remains upper-right
------------------------------------------------------------

local composer = require("composer")
local widget   = require("widget")
local selectLevelsTutorial = require("selectLevelsTutorial")
local scene    = composer.newScene()
local StandardHeader = require("ui.standardHeader")
local colors           = require("colors")
local json             = require("json")
local languages        = require("languages")
local accessibleButton = require("accessibleButton")
local logger           = require("logger")
local appState         = require("appState")
local buttonAccess = require("buttonAccess")
------------------------------------------------------------
-- Grouped state/UI to avoid excessive upvalues
------------------------------------------------------------
local state = {
    userId = nil,
    userName = nil,
    apiToken = nil,
    prefix = nil,
    classNameValue = "",
    classPublishValue = "Draft",
    manageMode = false,
    isScrolling = false,
    scrollTouchCount = 0,
    listH = 0,
    listPadPx = 0,
    listViewportH = 0,
    rowHeightPx = 120,
    levelRows = {},
}

local ui = {
    background = nil,
    backGroup = nil,
    gearGroup = nil,
    titleLabel = nil,
    greetingLabel = nil,
    recordStatus = nil,

    classCardGroup = nil,
    classCard = nil,
    classNameLabel = nil,
    classNameField = nil,
    classIdLabel = nil,

    draftPill = nil,
    publishedPill = nil,
    draftText = nil,
    publishedText = nil,
    saveClassButton = nil,
    classUpdateStatus = nil,

    listTopBar = nil,
    levelsHeaderLabel = nil,
    levelListTable = nil,

    manageGroup = nil,
    managePill = nil,
    manageToggleText = nil,

    helperText = nil,
    addLevelButton = nil,
}

local LIST_TOPBAR_H = 64
local SV_RIGHT_GUTTER = 0

------------------------------------------------------------
-- Shared state sync
------------------------------------------------------------
local function refreshSharedState(params)
   params = params or {}

    appState.restoreAuthsFromPrefs(state, {})

    local shared = appState.get()

    state.userId = shared.userId
    state.userName = shared.userName
    state.apiToken = shared.apiToken or system.getPreference("app", "apiToken", "string")
    state.prefix = params.prefix or shared.prefix or state.prefix
    state.classPublishValue = params.classStatus or shared.classStatus or state.classPublishValue or "Draft"

    if params.className ~= nil then
        state.classNameValue = params.className
    else
        state.classNameValue = shared.className or state.classNameValue or (state.prefix or "")
    end

    appState.set({
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })

    if not state.userName or state.userName == "" then
        state.userName = languages.t("player")
    end
end

------------------------------------------------------------
-- Utils
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

local function bottomY(obj)
    if not obj then return 0 end
    local h = obj.height or 0
    return obj.y + (h * 0.5)
end

local function markScrolling()
    state.isScrolling = true
    state.scrollTouchCount = state.scrollTouchCount + 1
end

local function clearScrollingSoon()
    local token = state.scrollTouchCount
    timer.performWithDelay(160, function()
        if token == state.scrollTouchCount then
            state.isScrolling = false
        end
    end)
end

local function setRecordStatus(msg)
    if not ui.recordStatus then return end
    msg = msg or ""
    ui.recordStatus.text = msg
    ui.recordStatus.isVisible = (tostring(msg):gsub("%s+", "") ~= "")
end

local function setClassUpdateStatus(msg)
    if not ui.classUpdateStatus then return end
    msg = msg or ""
    ui.classUpdateStatus.text = msg
    ui.classUpdateStatus.isVisible = (tostring(msg):gsub("%s+", "") ~= "")
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
-- Navigation
------------------------------------------------------------
local function gotoAddClass()
    logger.scene("selectLevels", "gotoAddClass userId=", state.userId or "nil", " prefix=", state.prefix or "nil")
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
    end
    appState.set({
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
        ui.classNameField.isVisible = false
    end
    native.setKeyboardFocus(nil)
    composer.removeScene("selectLevels")
    composer.gotoScene("addClass", { effect = "slideRight", time = 250 })
end

local function gotoSettings()
    logger.scene("selectLevels", "gotoSettings")
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
    end
    appState.set({
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })
    
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
        ui.classNameField.isVisible = false
    end
    native.setKeyboardFocus(nil)
    composer.gotoScene("settings", {
        effect = "slideLeft",
        time = 220,
        params = { returnTo = "selectLevels" }
    })
end

local function gotoCustomizeWithLevel(row)
    if not row then
        logger.warn("[scene:selectLevels] gotoCustomizeWithLevel blocked row=nil")
        return
    end

    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
    end

    appState.set({
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
        ui.classNameField.isVisible = false
    end
    native.setKeyboardFocus(nil)
    composer.gotoScene("customize", {
        effect = "slideLeft",
        time   = 250,
        params = {
            className   = state.classNameValue,
            levelTitle  = row.title,
            levelId     = row.levelId,
            theme       = row.theme,
            mode        = "edit"
        }
    })
end

local function gotoCustomizeCreate()
    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
    end

    appState.set({
        prefix = state.prefix,
        className = state.classNameValue,
        classStatus = state.classPublishValue
    })

    if ui.classNameField then
        state.classNameValue = ui.classNameField.text or state.classNameValue
        ui.classNameField.isVisible = false
    end
    native.setKeyboardFocus(nil)

    composer.gotoScene("customize", {
        effect = "slideLeft",
        time   = 250,
        params = {
            className   = state.classNameValue,
            mode        = "create",
            levelId     = "NEW"
        }
    })
end

------------------------------------------------------------
-- UI helpers
------------------------------------------------------------
local function updateStatusPillsUI()
    if not ui.draftPill or not ui.publishedPill then return end

    if state.classPublishValue == "Published" then
        -- Draft inactive
        ui.draftPill:setFillColor(1, 1, 1, 0.92)
        ui.draftPill:setStrokeColor(unpack(colors.secondaryActionBorder))
        ui.draftPill.strokeWidth = 2
        ui.draftText:setFillColor(unpack(colors.textPrimary))

        -- Published active (same green as addClass)
        ui.publishedPill:setFillColor(0.38, 0.75, 0.62, 0.95)
        ui.publishedPill:setStrokeColor(0.38, 0.75, 0.62, 0.95)
        ui.publishedPill.strokeWidth = 0
        ui.publishedText:setFillColor(1, 1, 1)
    else
        -- Draft active (same blue as addClass)
        ui.draftPill:setFillColor(0.65, 0.78, 0.92, 0.95)
        ui.draftPill:setStrokeColor(0.65, 0.78, 0.92, 0.95)
        ui.draftPill.strokeWidth = 0
        ui.draftText:setFillColor(1, 1, 1)

        -- Published inactive
        ui.publishedPill:setFillColor(1, 1, 1, 0.92)
        ui.publishedPill:setStrokeColor(unpack(colors.primaryAction))
        ui.publishedPill.strokeWidth = 2
        ui.publishedText:setFillColor(unpack(colors.primaryAction))
    end
end

local function applyAddLevelAccessState()
    if not ui.addLevelButton then return end

    local stateData = appState.get() or {}
    print("selectLevels state.hasAccess =", tostring(stateData.hasAccess),
          " type =", type(stateData.hasAccess),
          " accessStatus =", tostring(stateData.accessStatus))

    local hasAccess = buttonAccess.hasAccess(appState)

    print("applyAddLevelAccessState resolved hasAccess:", tostring(hasAccess))

    buttonAccess.applyPrimaryActionAccess(ui.addLevelButton, hasAccess, colors)
end

local function saveClassSettings()
    local className = (ui.classNameField and ui.classNameField.text) or state.classNameValue or ""
    className = tostring(className or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if className == "" then
        setClassUpdateStatus(languages.t("class_name_required") or "Class name required")
        return
    end

    if not state.userId or tostring(state.userId) == "" then
        setClassUpdateStatus(languages.t("missing_user") or "Missing user")
        return
    end

    if not state.prefix or tostring(state.prefix) == "" then
        setClassUpdateStatus(languages.t("missing_prefix") or "Missing prefix")
        return
    end

    refreshSharedState()

    if not state.apiToken or tostring(state.apiToken) == "" then
        setClassUpdateStatus("Missing login token. Please log in again.")
        return
    end

    state.classNameValue = className
    setClassUpdateStatus((languages.t("updating") or "Updating") .. "...")

    local url = "https://www.infoshagame.com/user/list/updateClass.php"

    local body =
        "type=updatec" ..
        "&user=" .. urlencode(tostring(state.userId)) ..
        "&prefix=" .. urlencode(tostring(state.prefix)) ..
        "&class=" .. urlencode(className) ..
        "&status=" .. urlencode(state.classPublishValue or "Draft") ..
        "&update_who=" .. urlencode(tostring(state.userId))

    local params = {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Bearer " .. tostring(state.apiToken)
        },
        body = body
    }

    print("SAVE POST URL:", url)

    network.request(url, "POST", function(event)
        print("SAVE isError:", tostring(event.isError))
        print("SAVE status:", tostring(event.status))
        print("SAVE response:", tostring(event.response))

        if event.isError then
            setClassUpdateStatus(languages.t("save_failed") or "Save failed")
            return
        end

        if event.status ~= 200 then
            setClassUpdateStatus("Save failed (" .. tostring(event.status) .. ")")
            return
        end

        local raw = tostring(event.response or "")
        local response = nil
        pcall(function()
            response = json.decode(raw)
        end)

        if response then
            if response.error then
                setClassUpdateStatus(tostring(response.error))
                return
            end

            if response.success == false then
                setClassUpdateStatus("Save failed")
                return
            end

            if response.rowsAffected and tonumber(response.rowsAffected) == 0 then
                setClassUpdateStatus("No DB row updated")
                return
            end
        else
            local lowerRaw = raw:lower()
            if raw == "" or lowerRaw:find("error", 1, true) or lowerRaw:find("warning", 1, true) then
                setClassUpdateStatus("Save failed")
                return
            end
        end

        if ui.titleLabel then
            ui.titleLabel.text = className
        end

        appState.set({
            prefix = state.prefix,
            className = className,
            classStatus = state.classPublishValue
        })

        setClassUpdateStatus(languages.t("saved") or "Saved")
        timer.performWithDelay(1200, function()
            setClassUpdateStatus("")
        end)
    end, params)
end

local function updateManagePillLayout()
    if not ui.manageToggleText or not ui.managePill then return end
    local padW, padH = 26, 12
    ui.managePill.width = ui.manageToggleText.width + padW
    ui.managePill.height = ui.manageToggleText.height + padH
end

local function refreshLevelRows()
    if not ui.levelListTable then return end
    if ui.levelListTable._isRefreshing then return end

    ui.levelListTable._isRefreshing = true

    local ok = pcall(function()
        if ui.levelListTable.deleteAllRows then
            ui.levelListTable:deleteAllRows()
            return
        end
        if ui.levelListTable.getNumRows and ui.levelListTable.deleteRow then
            local n = ui.levelListTable:getNumRows() or 0
            for i = n, 1, -1 do
                ui.levelListTable:deleteRow(i)
            end
        end
    end)

    if not ok then
        ui.levelListTable._isRefreshing = false
        composer.removeScene("selectLevels")
        composer.gotoScene("selectLevels", { effect = "crossFade", time = 120 })
        return
    end

    for _ = 1, #state.levelRows do
        ui.levelListTable:insertRow({ rowHeight = state.rowHeightPx })
    end

    ui.levelListTable._isRefreshing = false
    timer.performWithDelay(1, function()
        if scene.layoutList then scene.layoutList() end
    end)
end

local function updateManageUI()
    if not ui.manageToggleText then return end
    ui.manageToggleText.text = state.manageMode and (languages.t("done") or "Done") or (languages.t("manage") or "Manage")
    updateManagePillLayout()
    if ui.levelListTable and ui.levelListTable.reloadData then
        ui.levelListTable:reloadData()
    end
end

local function layoutClassCard(safeW)
    if not ui.classCard then return end

    local cardW = safeW * 0.92
    local cardX = display.contentCenterX
    local fieldW = cardW * 0.80

    local pillsLeft = cardX - cardW * 0.37
    local buttonGap = 8
    local draftW = 88
    local publishedW = 112

    ui.classCard.width = cardW
    ui.classCard.x = cardX

    ui.classNameLabel.x = cardX - cardW * 0.37
    if ui.classIdLabel then
        ui.classIdLabel.x = cardX - cardW * 0.37
    end
    ui.classNameField.x = cardX
    ui.classNameField.width = fieldW

    local firstCenter = pillsLeft + draftW * 0.5
    local secondCenter = firstCenter + (draftW * 0.5) + buttonGap + (publishedW * 0.5)

    ui.draftPill.width = draftW
    ui.publishedPill.width = publishedW
    ui.draftPill.x = firstCenter
    ui.publishedPill.x = secondCenter
    ui.draftText.x = ui.draftPill.x
    ui.publishedText.x = ui.publishedPill.x

    if ui.saveClassButton then
        ui.saveClassButton.x = cardX + cardW * 0.27
    end

    ui.classUpdateStatus.x = cardX
end

function scene.layoutList()
    if not ui.titleLabel or not ui.levelListTable or not state.listH then return end

    local anchor = bottomY(ui.titleLabel)
    if ui.recordStatus and ui.recordStatus.isVisible then
        anchor = bottomY(ui.recordStatus)
    end

    local pad = state.listPadPx or math.floor(display.contentHeight * 0.010)
    local cardTop = anchor + pad

    if ui.classCard then
        ui.classCardGroup.x = 0
        ui.classCardGroup.y = 0
        ui.classCard.y = cardTop + (ui.classCard.height * 0.5)

        local topY = ui.classCard.y - (ui.classCard.height * 0.5)
        ui.classNameLabel.y = topY + 36
        ui.classNameField.y = ui.classNameLabel.y + 56
        if ui.classNameFieldBg then
            ui.classNameFieldBg.x = ui.classNameField.x
            ui.classNameFieldBg.y = ui.classNameField.y
        end
        if ui.classIdLabel then
            ui.classIdLabel.y = ui.classNameField.y + 44
        end
        ui.draftPill.y = ui.classNameField.y + 96
        ui.publishedPill.y = ui.classNameField.y + 96
        
        ui.draftText.y = ui.draftPill.y
        ui.publishedText.y = ui.publishedPill.y
        if ui.saveClassButton then ui.saveClassButton.y = ui.draftPill.y end
        ui.classUpdateStatus.y = ui.draftPill.y + 52
    end

    local listTop = cardTop + (ui.classCard and ui.classCard.height or 0) + 14

    if ui.listTopBar then
        ui.listTopBar.x = display.contentCenterX
        ui.listTopBar.width = ui.levelListTable.width
        ui.listTopBar.height = LIST_TOPBAR_H
        ui.listTopBar.y = listTop + (LIST_TOPBAR_H * 0.5)
    end

    if ui.levelsHeaderLabel then
        ui.levelsHeaderLabel.x = ui.levelListTable.x - ui.levelListTable.width * 0.5 + 22
        ui.levelsHeaderLabel.y = ui.listTopBar.y
    end

    local tableTop = listTop + LIST_TOPBAR_H
    ui.levelListTable.y = tableTop + (state.listH * 0.5)
    state.listViewportH = state.listH

    if ui.manageGroup then
        updateManagePillLayout()
        local listRight = ui.levelListTable.x + (ui.levelListTable.width * 0.5)
        ui.manageGroup.x = listRight - 18 - (ui.managePill.width * 0.5)
        ui.manageGroup.y = ui.listTopBar and ui.listTopBar.y or (ui.levelListTable.y - (ui.levelListTable.height * 0.5) + 30)
        ui.manageGroup:toFront()
    end

    if ui.helperText then
        ui.helperText.y = (ui.levelListTable.y + ui.levelListTable.height * 0.5) + 34
    end

    if ui.addLevelButton and ui.helperText then
        ui.addLevelButton.y = ui.helperText.y + 82
    end
end

------------------------------------------------------------
-- Data
------------------------------------------------------------
local function loadLevels(callback)
    if not state.userId or not state.prefix or state.prefix == "" then
        state.levelRows = {
            { title = languages.t("no_levels_found") or "No levels found.", levelId = "", theme = "Original", status = "", hasText = false }
        }
        setRecordStatus("")
        callback()
        return
    end

    local request = "https://www.infoshagame.com/user/list/getLevelP.php?type=getp" ..
        "&user=" .. urlencode(state.userId) ..
        "&prefix=" .. urlencode(state.prefix)

    setRecordStatus((languages.t("loading") or "Loading") .. "...")

    network.request(request, "GET", function(event)
        if event.isError then
            setRecordStatus(languages.t("load_failed") or "Load failed.")
            state.levelRows = {
                { title = languages.t("load_error") or "Load error", levelId = "", theme = "Original", status = "", hasText = false }
            }
            callback()
            return
        end

        local response = json.decode(event.response)
        state.levelRows = {}

        if response and type(response) == "table" and #response > 0 then
            for _, row in ipairs(response) do
                local t = row.Title or ""
                local status = row.Status or "Draft"
                if t ~= "" and status ~= "deleted" then
                    table.insert(state.levelRows, {
                        title   = t,
                        levelId = tostring(row.LevelID or ""),
                        theme   = row.ThemeID or "Original",
                        status  = status,
                        hasText = ((row.Text or "") ~= "")
                    })
                end
            end
        end

        if #state.levelRows == 0 then
            table.insert(state.levelRows, {
                title = languages.t("no_levels_found") or "No levels found.",
                levelId = "",
                theme = "Original",
                status = "",
                hasText = false
            })
        end

        setRecordStatus("")
        callback()
    end)
end

local function reloadLevels()
    loadLevels(function()
        refreshLevelRows()
        if ui.levelListTable and ui.levelListTable.reloadData then
            ui.levelListTable:reloadData()
        end
    end)
end

local function deleteLevelById(levelId)
    if not levelId or tostring(levelId) == "" then return end
    if not state.userId then return end

    refreshSharedState()

    if not state.apiToken or tostring(state.apiToken) == "" then
        setRecordStatus("Missing login token. Please log in again.")
        return
    end

    local url = "https://infoshagame.com/user/list/setStatus.php"

    local body =
        "type=status" ..
        "&level=" .. urlencode(levelId) ..
        "&user="  .. urlencode(state.userId) ..
        "&status=deleted"

    local params = {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Authorization"] = "Bearer " .. tostring(state.apiToken)
        },
        body = body
    }

    setRecordStatus((languages.t("deleting") or "Deleting") .. "...")

    network.request(url, "POST", function(event)
        if event.isError then
            setRecordStatus(languages.t("delete_failed") or "Delete failed.")
            return
        end

        if event.status ~= 200 then
            setRecordStatus("Delete failed (" .. tostring(event.status) .. ")")
            return
        end

        setRecordStatus("")
        reloadLevels()
    end, params)
end

------------------------------------------------------------
-- Event handlers moved to top-level locals
------------------------------------------------------------
local function onDraftTap()
    state.classPublishValue = "Draft"
    appState.set({
        classStatus = "Draft",
        prefix = state.prefix,
        className = state.classNameValue
    })
    updateStatusPillsUI()
    return true
end

local function onPublishedTap()
    state.classPublishValue = "Published"
    appState.set({
        classStatus = "Published",
        prefix = state.prefix,
        className = state.classNameValue
    })
    updateStatusPillsUI()
    return true
end

local function toggleManageMode()
    state.manageMode = not state.manageMode
    updateManageUI()
    return true
end

local function onManageTouch(e)
    if e.phase == "began" then
        display.getCurrentStage():setFocus(e.target)
        e.target.isFocus = true
        return true
    elseif e.target.isFocus and (e.phase == "ended" or e.phase == "cancelled") then
        display.getCurrentStage():setFocus(nil)
        e.target.isFocus = false
        if e.phase == "ended" then
            toggleManageMode()
        end
        return true
    end
    return true
end

local function renderLevelRow(e)
    local row = e.row
    local data = state.levelRows[row.index]
    if not data then return end

    local isNoLevelsRow = (data.title == (languages.t("no_levels_found") or "No levels found."))

    local cardH = row.contentHeight * 0.92
    local rightInset = SV_RIGHT_GUTTER or 0
    local cardW = (row.contentWidth * 0.98) - rightInset
    local cardX = (row.contentWidth * 0.5) - (rightInset * 0.5)
    local cardLeft = cardX - (cardW * 0.5)
    local cardRight = cardX + (cardW * 0.5)

    local card = display.newRoundedRect(row, cardX, row.contentHeight * 0.5, cardW, cardH, 18)
    card:setFillColor(1, 1, 1, 0.76)
    card.strokeWidth = 2
    card:setStrokeColor(unpack(colors.appBackgroundDepth))

    local chevronX = cardRight - 34
    local deleteX = cardRight - 56
    local titleX = cardLeft + 26
    local titleRight = state.manageMode and (deleteX - 26) or (chevronX - 26)
    local titleMaxW = math.max(80, titleRight - titleX)

    local titleText = display.newText({
        parent = row,
        text = data.title,
        x = titleX,
        y = row.contentHeight * 0.50,
        font = native.systemFontBold,
        fontSize = 32,
        align = "left",
        width = titleMaxW
    })
    titleText.anchorX = 0
    titleText:setFillColor(unpack(colors.textPrimary))

    if not state.manageMode and not isNoLevelsRow then
        local chevron = display.newText({
            parent = row,
            text = "›",
            x = chevronX,
            y = row.contentHeight * 0.52,
            font = native.systemFontBold,
            fontSize = 64
        })
        chevron:setFillColor(unpack(colors.primaryAction))
    end

    local tapHit = display.newRect(row, row.contentWidth * 0.5, row.contentHeight * 0.5, row.contentWidth, row.contentHeight)
    tapHit.isVisible = false
    tapHit.isHitTestable = true
    tapHit:toBack()

    tapHit:addEventListener("tap", function()
        if state.isScrolling or state.manageMode then return true end
        if not data or not data.levelId or data.levelId == "" then return true end
        if isNoLevelsRow then return true end
        gotoCustomizeWithLevel(data)
        return true
    end)

    if state.manageMode and (not isNoLevelsRow) and data.levelId ~= "" then
        local hitR = math.max(20, math.floor(row.contentHeight * 0.18))
        local hit = display.newCircle(row, deleteX, row.contentHeight * 0.52, hitR)
        hit:setFillColor(1, 1, 1, 0.001)
        hit.isHitTestable = true

        local xText = display.newText({
            parent = row,
            text = "✕",
            x = deleteX,
            y = row.contentHeight * 0.52,
            font = native.systemFontBold,
            fontSize = 44
        })
        xText:setFillColor(unpack(colors.error))

        local function confirmDelete()
            native.showAlert(
                languages.t("delete_level") or "Delete Level?",
                languages.t("delete_level_msg") or "This will delete this level.",
                { languages.t("cancel") or "Cancel", languages.t("delete") or "Delete" },
                function(evt)
                    if evt and evt.action == "clicked" and evt.index == 2 then
                        deleteLevelById(data.levelId)
                    end
                end
            )
        end

        hit:addEventListener("tap", function() confirmDelete(); return true end)
        xText:addEventListener("tap", function() confirmDelete(); return true end)
    end
end

------------------------------------------------------------
-- Scene Create
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    local params = event.params or {}

    refreshSharedState(params)

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight

    ui.background = newAspectFillImage(sceneGroup, "settings-background.png")
    if ui.background then ui.background:toBack() end

    

    ui.gearGroup = display.newGroup()
    sceneGroup:insert(ui.gearGroup)
    local gearIcon = display.newImageRect(ui.gearGroup, "icons/gear6-blue.png", 64, 64)
    gearIcon.x, gearIcon.y = 0, 0
    local gearHit = display.newRect(ui.gearGroup, 0, 0, 110, 110)
    gearHit.isVisible = false
    gearHit.isHitTestable = true
    gearHit:addEventListener("tap", function() gotoSettings(); return true end)

    local hitSize  = math.max(math.floor(display.contentHeight * 0.085), 64)
    local iconSize = math.max(math.floor(display.contentHeight * 0.048), 40)

    local header = StandardHeader.new(sceneGroup, {
        titleKey       = nil,
        fallbackTitle  = "",
        backIconImage  = "icons/back.png",
        hitSize        = hitSize,
        iconSize       = iconSize,
        onBack = function()
            gotoAddClass()
        end
    })

    self._header = header
    ui.backGroup = header.group
    ui.gearGroup.x = safeX + safeW - 50
    ui.gearGroup.y = safeY + 77

    local tutorialGroup = display.newGroup()
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
        selectLevelsTutorial.start()
        return true
    end)

    tutorialGroup.x = safeX + safeW - 115
    tutorialGroup.y = safeY + 77

    ui.greetingLabel = display.newText({
        parent = sceneGroup,
        text   = (languages.t("greeting") or "Hello") .. ", " .. state.userName,
        x      = display.contentCenterX,
        y      = safeY + safeH * 0.09,
        font   = native.systemFontBold,
        fontSize = 42,
        align  = "center",
        width  = safeW * 0.76
    })
    ui.greetingLabel:setFillColor(unpack(colors.textPrimary))

    ui.titleLabel = display.newText({
        parent = sceneGroup,
        text   = state.classNameValue ~= "" and state.classNameValue or (languages.t("choose_level") or "Choose Level"),
        x      = display.contentCenterX,
        y      = ui.greetingLabel.contentBounds.yMax + 26,
        font   = native.systemFontBold,
        fontSize = 46,
        align  = "center",
        width  = safeW * 0.86
    })
    ui.titleLabel:setFillColor(unpack(colors.textPrimary))

    ui.recordStatus = display.newText({
        parent = sceneGroup,
        text   = "",
        x      = display.contentCenterX,
        y      = bottomY(ui.titleLabel) + 22,
        font   = native.systemFont,
        fontSize = 30,
        align  = "center",
        width  = safeW * 0.92
    })
    ui.recordStatus:setFillColor(unpack(colors.textSecondary))
    ui.recordStatus.alpha = 0.95
    ui.recordStatus.isVisible = false

    ui.classCardGroup = display.newGroup()
    sceneGroup:insert(ui.classCardGroup)

    ui.classCard = display.newRoundedRect(ui.classCardGroup, display.contentCenterX, 0, safeW * 0.92, 236, 20)
    ui.classCard:setFillColor(1, 1, 1, 0.80)
    ui.classCard.strokeWidth = 2
    ui.classCard:setStrokeColor(unpack(colors.appBackgroundDepth))

    ui.classNameLabel = display.newText({
        parent = ui.classCardGroup,
        text = (languages.t("class_name_label") or "Class Name") .. ":",
        x = 0,
        y = 0,
        font = native.systemFont,
        fontSize = 28,
        align = "left"
    })
    ui.classNameLabel.anchorX = 0
    ui.classNameLabel:setFillColor(unpack(colors.textSecondary))

    -- White background behind native field (consistent cross-platform look)
    ui.classNameFieldBg = display.newRoundedRect(
        ui.classCardGroup,
        display.contentCenterX,
        0,
        safeW * 0.74,
        56,
        10
    )
    ui.classNameFieldBg:setFillColor(1, 1, 1)
    ui.classNameFieldBg.strokeWidth = 2
    ui.classNameFieldBg:setStrokeColor(0.85, 0.85, 0.85)

    -- Native text field (transparent so background shows)
    ui.classNameField = native.newTextField(
        display.contentCenterX,
        0,
        safeW * 0.74,
        52
    )

    ui.classNameField.hasBackground = false
    ui.classNameField.text = state.classNameValue ~= "" and state.classNameValue or ""
    ui.classNameField.placeholder = languages.t("class_name") or "Class Name"
    ui.classNameField.font = native.newFont(native.systemFontBold, 26)

    -- Force black text (consistent on both platforms)
    ui.classNameField:setTextColor(0, 0, 0)

    ui.classIdLabel = display.newText({
        parent = ui.classCardGroup,
        text = (languages.t("class_id") or "Class ID") .. ": " .. (state.prefix or ""),
        x = 0,
        y = 0,
        font = native.systemFont,
        fontSize = 24,
        align = "left"
    })
    ui.classIdLabel.anchorX = 0
    ui.classIdLabel:setFillColor(unpack(colors.textSecondary))
    ui.classIdLabel.alpha = 0.95

    ui.draftPill = display.newRoundedRect(ui.classCardGroup, 0, 0, 88, 44, 14)
    ui.draftText = display.newText({
        parent = ui.classCardGroup,
        text = languages.t("draft") or "Draft",
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = 22
    })

    ui.publishedPill = display.newRoundedRect(ui.classCardGroup, 0, 0, 112, 44, 14)
    ui.publishedText = display.newText({
        parent = ui.classCardGroup,
        text = languages.t("published") or "Published",
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = 22
    })

    ui.saveClassButton = accessibleButton.new(
        ui.classCardGroup,
        languages.t("save") or "Save",
        display.contentCenterX,
        0,
        colors.primaryAction,
        function() saveClassSettings() end,
        nil,
        0.72
    )
    if ui.saveClassButton and ui.saveClassButton.label then
        ui.saveClassButton.label:setFillColor(unpack(colors.textOnPrimary))
    end

    ui.classUpdateStatus = display.newText({
        parent = ui.classCardGroup,
        text = "",
        x = display.contentCenterX,
        y = 0,
        font = native.systemFont,
        fontSize = 22,
        align = "center",
        width = safeW * 0.70
    })
    ui.classUpdateStatus:setFillColor(unpack(colors.textSecondary))
    ui.classUpdateStatus.isVisible = false

    ui.draftPill:addEventListener("tap", onDraftTap)
    ui.draftText:addEventListener("tap", onDraftTap)
    ui.publishedPill:addEventListener("tap", onPublishedTap)
    ui.publishedText:addEventListener("tap", onPublishedTap)
    updateStatusPillsUI()
    layoutClassCard(safeW)

    state.listH = display.contentHeight * 0.40
    state.listPadPx = math.floor(display.contentHeight * 0.010)
    state.listViewportH = state.listH
    state.rowHeightPx = math.floor(state.listH / 4.1)
    state.rowHeightPx = math.max(130, math.min(state.rowHeightPx, 180))

    ui.levelListTable = widget.newTableView({
        x = display.contentCenterX,
        y = display.contentCenterY,
        width  = display.contentWidth * 0.92,
        height = state.listH,
        hideBackground = true,
        noLines = true,
        rowHeight = state.rowHeightPx,
        hideScrollBar = true,
        listener = function(e)
            if e.phase == "moved" then markScrolling() end
            if e.phase == "ended" then clearScrollingSoon() end
            return false
        end,
        onRowRender = renderLevelRow,
        onRowTouch = function() return false end
    })
    sceneGroup:insert(ui.levelListTable)

    ui.listTopBar = display.newRoundedRect(sceneGroup, 0, 0, 10, LIST_TOPBAR_H, 16)
    ui.listTopBar:setFillColor(1, 1, 1, 0.55)
    ui.listTopBar.strokeWidth = 2
    ui.listTopBar:setStrokeColor(unpack(colors.secondaryActionBorder))
    ui.listTopBar:toBack()

    ui.levelsHeaderLabel = display.newText({
        parent = sceneGroup,
        text = languages.t("levels") or "Levels",
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = 30,
        align = "left"
    })
    ui.levelsHeaderLabel.anchorX = 0
    ui.levelsHeaderLabel:setFillColor(unpack(colors.textSecondary))

    ui.manageGroup = display.newGroup()
    sceneGroup:insert(ui.manageGroup)

    ui.manageToggleText = display.newText({
        parent = ui.manageGroup,
        text = languages.t("manage") or "Manage",
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = 28,
        align = "center"
    })
    ui.manageToggleText:setFillColor(unpack(colors.textPrimary))
    ui.manageToggleText.alpha = 0.92

    ui.managePill = display.newRoundedRect(ui.manageGroup, 0, 0, 10, 10, 14)
    ui.managePill:setFillColor(1, 1, 1, 0.45)
    ui.managePill.strokeWidth = 2
    ui.managePill:setStrokeColor(unpack(colors.secondaryActionBorder))
    ui.managePill:toBack()
    updateManagePillLayout()

    ui.managePill:addEventListener("touch", onManageTouch)
    ui.manageToggleText:addEventListener("touch", onManageTouch)

    ui.helperText = display.newText({
        parent = sceneGroup,
        text = (languages.t("dont_see_level") or "Don’t see the level you want? Add one below."),
        x = display.contentCenterX,
        y = 0,
        font = native.systemFont,
        fontSize = 30,
        align = "center",
        width = display.contentWidth * 0.88
    })
    ui.helperText:setFillColor(unpack(colors.textSecondary))
    ui.helperText.alpha = 0.95

    ui.addLevelButton = accessibleButton.new(
        sceneGroup,
        languages.t("add_level") or "Add Level",
        display.contentCenterX,
        0,
        colors.primaryAction,
        function()
            local hasAccess = buttonAccess.hasAccess(appState)

            if not hasAccess then
                native.showAlert(
                    "Subscription Required",
                    "Please subscribe to create a new level.",
                    { "OK" }
                )
                return
            end

            gotoCustomizeCreate()
        end,
        "➕",
        0.86
    )
    if ui.addLevelButton and ui.addLevelButton.label then
        ui.addLevelButton.label:setFillColor(unpack(colors.textOnPrimary))
    end

    applyAddLevelAccessState()

    scene.layoutList()
    loadLevels(function() refreshLevelRows() end)

    if ui.listTopBar then ui.listTopBar:toBack() end
    if ui.manageGroup then ui.manageGroup:toFront() end
    if ui.backGroup then ui.backGroup:toFront() end
    if self._header and self._header.group then
        self._header.group:toFront()
    end
end

------------------------------------------------------------
-- Scene Show / Hide / Destroy
------------------------------------------------------------
function scene:show(event)
    if event.phase == "will" then
        refreshSharedState(event.params or {})

        if ui.classNameField then
            ui.classNameField.isVisible = true
            ui.classNameField.text = state.classNameValue or ""
        end

        if ui.classIdLabel then
            ui.classIdLabel.text = (languages.t("class_id") or "Class ID") .. ": " .. (state.prefix or "")
        end

        if ui.greetingLabel then
            ui.greetingLabel.text = (languages.t("greeting") or "Hello") .. ", " .. state.userName
        end

        if ui.titleLabel then
            ui.titleLabel.text = (state.classNameValue ~= "" and state.classNameValue) or (languages.t("choose_level") or "Choose Level")
        end

        refreshSharedState()

        updateStatusPillsUI()

        applyAddLevelAccessState()
        
        timer.performWithDelay(1, function()
            if scene.layoutList then
                scene.layoutList()
            end
        end)
    elseif event.phase == "did" then
        reloadLevels()
    end
end

function scene:hide(event)
    if event.phase == "will" then
        if ui.classNameField then
            state.classNameValue = ui.classNameField.text or state.classNameValue
            ui.classNameField.isVisible = false
            native.setKeyboardFocus(nil)
        end

        appState.set({
            prefix = state.prefix,
            className = state.classNameValue,
            classStatus = state.classPublishValue
        })
    end

    selectLevelsTutorial.stop()
end

function scene:destroy(event)
    if ui.classNameField then ui.classNameField:removeSelf(); ui.classNameField = nil end
    if ui.classNameFieldBg then ui.classNameFieldBg:removeSelf(); ui.classNameFieldBg = nil end
    if ui.classIdLabel then ui.classIdLabel:removeSelf(); ui.classIdLabel = nil end
    if ui.levelListTable then ui.levelListTable:removeSelf(); ui.levelListTable = nil end
    if ui.listTopBar then ui.listTopBar:removeSelf(); ui.listTopBar = nil end
    if ui.levelsHeaderLabel then ui.levelsHeaderLabel:removeSelf(); ui.levelsHeaderLabel = nil end
    if ui.classCardGroup then ui.classCardGroup:removeSelf(); ui.classCardGroup = nil end
    if ui.manageGroup then ui.manageGroup:removeSelf(); ui.manageGroup = nil end
    if ui.addLevelButton then ui.addLevelButton:removeSelf(); ui.addLevelButton = nil end
    if ui.helperText then ui.helperText:removeSelf(); ui.helperText = nil end
    if ui.titleLabel then ui.titleLabel:removeSelf(); ui.titleLabel = nil end
    if ui.greetingLabel then ui.greetingLabel:removeSelf(); ui.greetingLabel = nil end
    if ui.recordStatus then ui.recordStatus:removeSelf(); ui.recordStatus = nil end
    if ui.backGroup then ui.backGroup:removeSelf(); ui.backGroup = nil end
    if ui.gearGroup then ui.gearGroup:removeSelf(); ui.gearGroup = nil end
    if ui.background then ui.background:removeSelf(); ui.background = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
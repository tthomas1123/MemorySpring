local composer = require("composer")
local widget   = require("widget")
local json     = require("json")

local scene = composer.newScene()

-- Fallback debug values if appState is empty
local userId = 216
local userName = "Debug User"
local apiToken = ""
local appId = "SMART_SHEEP"

local classRows = {}
local classListTable
local statusText
local debugText
local popup = {
    group = nil,
    nameField = nil,
    codeValue = nil
}

local generatedPrefix = nil

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

local function setStatus(msg)
    if statusText then
        statusText.text = msg or ""
    end
    print("STATUS:", msg or "")
end

local function setDebug(msg)
    if debugText then
        debugText.text = tostring(msg or "")
    end
    print("DEBUG:", tostring(msg or ""))
end

local function refreshSharedState()
    local ok, appState = pcall(require, "appState")
    if ok and appState and appState.get then
        local shared = appState.get() or {}
        userId = shared.userId or userId
        userName = shared.userName or userName
        apiToken = shared.apiToken or apiToken
        appId = shared.appId or composer.getVariable("appId") or appId
    end

    print("DEBUG refreshSharedState userId:", tostring(userId))
    print("DEBUG refreshSharedState userName:", tostring(userName))
    print("DEBUG refreshSharedState apiToken:", tostring(apiToken))
    print("DEBUG refreshSharedState appId:", tostring(appId))
end

local function gotoSettings()
    composer.gotoScene("settings", {
        effect = "slideLeft",
        time = 220,
        params = {
            returnTo = "addClassDebug"
        }
    })
end

local function gotoLogin()
    composer.gotoScene("menu", {
        effect = "slideRight",
        time = 220
    })
end

local function generateClassId(len)
    len = len or 6
    local alphabet = "23456789ABCDEFGHJKMNPQRSTUVWYZ"
    local out = {}
    for i = 1, len do
        local n = math.random(1, #alphabet)
        out[#out + 1] = alphabet:sub(n, n)
    end
    return table.concat(out)
end

local function refreshRows()
    if not classListTable then
        return
    end

    if classListTable.deleteAllRows then
        classListTable:deleteAllRows()
    end

    for i = 1, #classRows do
        classListTable:insertRow({ rowHeight = 60 })
    end
end

local function checkPrefixExists(prefix, callback)
    if not prefix or prefix == "" then
        callback(false, "missing_prefix")
        return
    end

    local req = "https://www.infoshagame.com/user/list/checkClassId.php" ..
        "?type=cclass" ..
        "&prefix=" .. urlencode(prefix)

    setDebug("CHECK URL:\n" .. req)

    network.request(req, "GET", function(event)
        print("CHECK CALLBACK HIT")
        print("CHECK isError:", tostring(event.isError))
        print("CHECK status:", tostring(event.status))
        print("CHECK response:", tostring(event.response))

        if event.isError then
            callback(false, "network")
            return
        end

        local response = nil
        if event.response and event.response ~= "" then
            response = json.decode(event.response)
        end

        if not response then
            callback(false, "bad_json")
            return
        end

        if response.duplicate == true then
            callback(true, nil, response)
            return
        end

        if response.success == true then
            callback(false, nil, response)
            return
        end

        callback(false, "unexpected", response)
    end)
end

local function updatePopupCode(attempt)
    attempt = attempt or 1

    if attempt > 8 then
        generatedPrefix = generateClassId(6)
        if popup.codeValue then
            popup.codeValue.text = generatedPrefix
        end
        setDebug("Could not verify uniqueness after 8 tries.\nUsing: " .. generatedPrefix)
        return
    end

    local candidate = generateClassId(6)

    checkPrefixExists(candidate, function(exists, err)
        if err then
            generatedPrefix = candidate
            if popup.codeValue then
                popup.codeValue.text = generatedPrefix
            end
            setDebug("Prefix check error: " .. tostring(err) .. "\nUsing: " .. candidate)
            return
        end

        if exists then
            setDebug("Duplicate generated, retrying: " .. candidate)
            updatePopupCode(attempt + 1)
            return
        end

        generatedPrefix = candidate
        if popup.codeValue then
            popup.codeValue.text = generatedPrefix
        end
        setDebug("Generated prefix: " .. candidate)
    end)
end

local function loadPrefixes()
    refreshSharedState()

    local request = "https://www.infoshagame.com/user/list/getPrefix.php?type=getP&user=" .. urlencode(userId)
    setStatus("Loading classes...")
    setDebug("LOAD URL:\n" .. request .. "\n\nuserId=" .. tostring(userId))

    network.request(request, "GET", function(event)
        print("LOAD CALLBACK HIT")
        print("LOAD isError:", tostring(event.isError))
        print("LOAD status:", tostring(event.status))
        print("LOAD response:", tostring(event.response))

        if event.isError then
            setStatus("Load failed")
            setDebug("Load network error")
            classRows = {
                { label = "LOAD ERROR" }
            }
            refreshRows()
            return
        end

        local response = nil
        if event.response and event.response ~= "" then
            response = json.decode(event.response)
        end

        classRows = {}

        if response and response.classes and #response.classes > 0 then
            for _, entry in ipairs(response.classes) do
                classRows[#classRows + 1] = {
                    label = (entry.classname or "") ..
                        " - " .. (entry.prefix or "") ..
                        " [" .. (entry.status or "") .. "]"
                }
            end
            setStatus("Loaded " .. tostring(#classRows) .. " classes")
        else
            classRows[#classRows + 1] = { label = "NO CLASSES RETURNED" }
            setStatus("No classes returned")
            setDebug("RAW LOAD RESPONSE:\n" .. tostring(event.response))
        end

        refreshRows()
    end)
end

local function destroyPopup()
    if popup.nameField then
        popup.nameField:removeSelf()
        popup.nameField = nil
    end

    if popup.group then
        popup.group:removeSelf()
        popup.group = nil
    end

    popup.codeValue = nil
end

local function doSave()
    refreshSharedState()

    local classname = popup.nameField and popup.nameField.text or ""
    classname = tostring(classname)

    if classname:gsub("%s+", "") == "" then
        native.showAlert("Debug", "Enter a class name.", { "OK" })
        return
    end

    local prefix = generatedPrefix or (popup.codeValue and popup.codeValue.text) or ""
    if prefix == "" then
        native.showAlert("Debug", "Missing prefix.", { "OK" })
        return
    end

    if not apiToken or apiToken == "" then
        native.showAlert("Debug", "Missing apiToken. Login first or hardcode apiToken in addClassDebug.lua.", { "OK" })
        return
    end

    local request = "https://www.infoshagame.com/user/list/addClass.php" ..
        "?type=aclass" ..
        "&user=" .. urlencode(userId) ..
        "&prefix=" .. urlencode(prefix) ..
        "&class=" .. urlencode(classname) ..
        "&token=" .. urlencode(apiToken) ..
        "&appId=" .. urlencode(appId or "")

    setDebug("SAVE URL:\n" .. request)

    network.request(request, "GET", function(event)
        print("SAVE CALLBACK HIT")
        print("SAVE isError:", tostring(event.isError))
        print("SAVE status:", tostring(event.status))
        print("SAVE response:", tostring(event.response))

        if event.isError then
            setStatus("Save network error")
            setDebug("SAVE NETWORK ERROR")
            native.showAlert("Save Error", "Network error while saving.", { "OK" })
            return
        end

        local response = nil
        if event.response and event.response ~= "" then
            response = json.decode(event.response)
        end

        if not response then
            setStatus("Save returned non-JSON")
            setDebug("RAW SAVE RESPONSE:\n" .. tostring(event.response))
            native.showAlert("Save Error", tostring(event.response), { "OK" })
            return
        end

        if response.success ~= true then
            setStatus("Save rejected")
            setDebug("SAVE RESPONSE:\n" .. tostring(event.response))
            native.showAlert("Save Rejected", tostring(response.error or response.message or "Unknown error"), { "OK" })
            return
        end

        setStatus("Save success")
        setDebug("SAVE RESPONSE:\n" .. tostring(event.response))
        destroyPopup()
        loadPrefixes()
    end)
end

local function showPopup(sceneGroup)
    destroyPopup()

    popup.group = display.newGroup()
    sceneGroup:insert(popup.group)

    local dim = display.newRect(
        popup.group,
        display.contentCenterX,
        display.contentCenterY,
        display.contentWidth * 1.2,
        display.contentHeight * 1.2
    )
    dim:setFillColor(0, 0, 0, 0.35)

    local bg = display.newRoundedRect(
        popup.group,
        display.contentCenterX,
        display.contentCenterY,
        display.contentWidth * 0.85,
        240,
        16
    )
    bg:setFillColor(1, 1, 1)

    local title = display.newText({
        parent = popup.group,
        text = "Debug Add Class",
        x = display.contentCenterX,
        y = display.contentCenterY - 90,
        font = native.systemFontBold,
        fontSize = 24
    })
    title:setFillColor(0, 0, 0)

    popup.codeValue = display.newText({
        parent = popup.group,
        text = "------",
        x = display.contentCenterX,
        y = display.contentCenterY - 40,
        font = native.systemFontBold,
        fontSize = 28
    })
    popup.codeValue:setFillColor(0, 0, 0)

    popup.nameField = native.newTextField(display.contentCenterX, display.contentCenterY + 10, 220, 36)
    popup.nameField.placeholder = "Class name"

    local saveBtn = widget.newButton({
        label = "Save",
        x = display.contentCenterX + 60,
        y = display.contentCenterY + 70,
        shape = "roundedRect",
        width = 100,
        height = 36,
        cornerRadius = 8,
        onRelease = doSave
    })
    popup.group:insert(saveBtn)

    local cancelBtn = widget.newButton({
        label = "Cancel",
        x = display.contentCenterX - 60,
        y = display.contentCenterY + 70,
        shape = "roundedRect",
        width = 100,
        height = 36,
        cornerRadius = 8,
        onRelease = function()
            destroyPopup()
        end
    })
    popup.group:insert(cancelBtn)

    updatePopupCode()
end

function scene:create(event)
    local sceneGroup = self.view
    math.randomseed(os.time())

    refreshSharedState()

    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth

    local title = display.newText({
        parent = sceneGroup,
        text = "Add Class Debug",
        x = display.contentCenterX,
        y = 40,
        font = native.systemFontBold,
        fontSize = 26
    })
    title:setFillColor(1, 1, 1)

    statusText = display.newText({
        parent = sceneGroup,
        text = "Ready",
        x = display.contentCenterX,
        y = 75,
        width = display.contentWidth - 20,
        font = native.systemFont,
        fontSize = 16,
        align = "center"
    })
    statusText:setFillColor(1, 1, 0)

    debugText = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX,
        y = 105,
        width = display.contentWidth - 20,
        font = native.systemFont,
        fontSize = 12,
        align = "left"
    })
    debugText.anchorY = 0
    debugText:setFillColor(1, 1, 1)

    local settingsBtn = widget.newButton({
        label = "Settings",
        x = safeX + safeW - 70,
        y = safeY + 35,
        shape = "roundedRect",
        width = 110,
        height = 34,
        cornerRadius = 8,
        onRelease = gotoSettings
    })
    sceneGroup:insert(settingsBtn)

    local loginBtn = widget.newButton({
        label = "Login",
        x = 65,
        y = safeY + 35,
        shape = "roundedRect",
        width = 90,
        height = 34,
        cornerRadius = 8,
        onRelease = gotoLogin
    })
    sceneGroup:insert(loginBtn)

    local addBtn = widget.newButton({
        label = "Open Debug Add Class",
        x = display.contentCenterX,
        y = display.contentHeight - 50,
        shape = "roundedRect",
        width = 220,
        height = 40,
        cornerRadius = 8,
        onRelease = function()
            showPopup(sceneGroup)
        end
    })
    sceneGroup:insert(addBtn)

    classListTable = widget.newTableView({
        x = display.contentCenterX,
        y = display.contentCenterY + 60,
        width = display.contentWidth - 20,
        height = 230,
        onRowRender = function(e)
            local row = e.row
            local data = classRows[row.index]
            if not data then
                return
            end

            local t = display.newText({
                parent = row,
                text = data.label or "",
                x = 10,
                y = row.contentHeight * 0.5,
                width = row.contentWidth - 20,
                font = native.systemFont,
                fontSize = 16,
                align = "left"
            })
            t.anchorX = 0
            t:setFillColor(0, 0, 0)
        end
    })
    sceneGroup:insert(classListTable)

    setStatus("User: " .. tostring(userId) .. " / " .. tostring(userName))
    loadPrefixes()
end

function scene:show(event)
    if event.phase == "will" then
        refreshSharedState()
        setStatus("User: " .. tostring(userId) .. " / " .. tostring(userName))
    end
end

function scene:hide(event)
    if event.phase == "will" then
        destroyPopup()
    end
end

function scene:destroy(event)
    destroyPopup()
    if classListTable then
        classListTable:removeSelf()
        classListTable = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
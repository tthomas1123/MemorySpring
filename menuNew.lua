------------------------------------------------------------
-- menu.lua  (Main Menu Screen with Header Border + Animation)
------------------------------------------------------------
local composer = require("composer")
local json = require("json")
local widget = require("widget")
local scene = composer.newScene()

local colors = require("colors")
local languages = require("languages")
local languageLoader = require("languageLoader")

local desiredLevel = 1
local useFirstAvailableLevel = false   -- NEW

------------------------------------------------------------
-- Globals
------------------------------------------------------------
local sheeppos = 0
local LevelLabel, Class, webView
local closeButton, closeCircle, closeXText
local buttons = {}  -- store button references

-- Next level we want to play for the current class
local desiredLevel = 1

------------------------------------------------------------
-- Forward declarations
------------------------------------------------------------
local setOwner  -- defined later
local restoreLastClass

------------------------------------------------------------
-- Owner Lookup + Class Persistence + Next Level Setup
------------------------------------------------------------
function setOwner()
    if not Class or not Class.text or Class.text == "" then
        LevelLabel.text = languages.t("please_enter_class_code")
        LevelLabel:setFillColor(colors.textPrimary)
        return
    end

    local oRequest = "https://www.infoshagame.com/user/list/getOwner.php?type=getO&prefix=" .. Class.text

    local function networkListener(event)
        if event.isError then
            print("Network error in setOwner:", event.response)
            LevelLabel.text = languages.t("error_connection")
            LevelLabel:setFillColor(colors.textPrimary)
            return
        end

        local data = json.decode(event.response)

        -- No data → class invalid / unavailable
        if not data or #data == 0 then
            LevelLabel.text = languages.t("please_enter_class_code")
            LevelLabel:setFillColor(colors.textPrimary)

            -- Clear composer vars
            composer.setVariable("userId", nil)
            composer.setVariable("className", nil)
            composer.setVariable("prefix", nil)

            -- Clear saved preferences for class
            system.setPreferences("app", {
                lastClassCode     = "",
                lastClassName     = "",
                lastClassOwnerId  = "",
            })

            desiredLevel = 1
            Class.text = ""
            Class.hasCleared = false
            return
        end

        -- Class is valid
        local ownerId   = data[1].OwnerID
        local className = data[1].ClassName
        local prefix    = Class.text

        composer.setVariable("userId", ownerId)
        composer.setVariable("className", className)
        composer.setVariable("prefix", prefix)

        -- Persist class info so it’s restored on next launch
        system.setPreferences("app", {
            lastClassCode     = prefix,
            lastClassName     = className,
            lastClassOwnerId  = ownerId,
            userId            = ownerId,   -- ties into main.lua's savedUserId
        })

        -- Compute next desired level for THIS class from per-class preference
        local lastLevelKey = "lastLevel_" .. tostring(prefix)
        local lastLevelNum = system.getPreference("app", lastLevelKey, "number")

        if type(lastLevelNum) ~= "number" or lastLevelNum <= 0 then
        -- First time for this class: let game.lua pick the first available level
            desiredLevel = nil
            useFirstAvailableLevel = true
        else
        -- Returning: go to last level + 1 as before
             desiredLevel = lastLevelNum + 1
            useFirstAvailableLevel = false
        end

        LevelLabel:setFillColor(colors.textPrimary)
        LevelLabel.text = languages.t("welcome_to") .. " " .. className
    end

    network.request(oRequest, "GET", networkListener)
end

------------------------------------------------------------
-- Restore last class (if any) when menu loads
------------------------------------------------------------
function restoreLastClass()
    if not Class or not LevelLabel then return end

    local savedClassCode = system.getPreference("app", "lastClassCode", "string")
    local savedClassName = system.getPreference("app", "lastClassName", "string")

    if savedClassCode and savedClassCode ~= "" then
        Class.text = savedClassCode
        Class.hasCleared = true

        -- Show a friendly message while we re-validate with server
        LevelLabel.text = languages.t("welcome_to") .. " " .. (savedClassName or "")
        LevelLabel:setFillColor(colors.textPrimary)

        -- This will:
        -- - Re-check that the class still exists
        -- - Reset composer vars
        -- - Recompute desiredLevel
        setOwner()
    else
        LevelLabel.text = languages.t("welcome")
        LevelLabel:setFillColor(colors.textPrimary)
    end
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function gotoGame()
    local userId    = composer.getVariable("userId")
    local classCode = composer.getVariable("prefix")
    local className = composer.getVariable("className")

    if not classCode or classCode == "" then
        LevelLabel.text = languages.t("please_enter_class_code")
        LevelLabel:setFillColor(colors.textPrimary)
        return
    end

    if not userId then
        LevelLabel.text = languages.t("please_login_or_enter_class_code")
        LevelLabel:setFillColor(colors.textPrimary)
        return
    end

    --------------------------------------------------------
    -- 1) Figure out the last completed level for this class
    --------------------------------------------------------
    local prefix       = classCode
    local lastLevelKey = "lastLevel_" .. tostring(prefix)
    local lastLevelNum = system.getPreference("app", lastLevelKey, "number")
    local currentLevelId = tonumber(lastLevelNum or 0)   -- 0 means "no previous level"

    --------------------------------------------------------
    -- 2) Ask server what levels exist for this class
    --    (same endpoint style as success.lua)
    --------------------------------------------------------
    local url = "https://www.infoshagame.com/user/list/getLevelP.php"
        .. "?type=getp"
        .. "&user="   .. tostring(userId)
        .. "&prefix=" .. tostring(prefix)

    print("Menu: fetching level list from", url,
          "currentLevelId (last completed) =", currentLevelId)

    network.request(url, "GET", function(event)
        if event.isError then
            print("Menu gotoGame network error:", event.response)

            -- Fallback behavior: if we can't reach server,
            -- just default to lastLevel + 1 or 1
            local fallbackLevel
            if currentLevelId > 0 then
                fallbackLevel = currentLevelId + 1
            else
                fallbackLevel = 1
            end

            composer.gotoScene("game", {
                params = {
                    user              = userId,
                    classCode         = classCode,
                    className         = className,
                    desiredLevel      = fallbackLevel,
                    useFirstAvailable = false
                }
            })
            return
        end

        local list = json.decode(event.response)
        if not list or #list == 0 then
            print("Menu gotoGame: no levels found for prefix", prefix)
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("no_passages_found") or "No passages found.",
                { languages.t("ok") or "OK" }
            )
            return
        end

        ------------------------------------------------
        -- 3) Choose next level just like success.lua:
        --    - If no last level: first row with Text
        --    - Else: row after currentLevelId with Text
        ------------------------------------------------
        local levelToPlay = nil

        if currentLevelId == 0 then
            -- First time playing this class:
            -- pick the first level that actually has Text
            for _, row in ipairs(list) do
                if row.Text and row.Text ~= "" then
                    levelToPlay = tonumber(row.LevelID)
                    break
                end
            end
        else
            -- We have a last completed level → find it,
            -- then pick next with non-empty Text
            for i, row in ipairs(list) do
                local rowId = tonumber(row.LevelID)
                if rowId == currentLevelId then
                    for j = i + 1, #list do
                        local r = list[j]
                        if r.Text and r.Text ~= "" then
                            levelToPlay = tonumber(r.LevelID)
                            break
                        end
                    end
                    break
                end
            end
        end

        -- If we still didn't find anything, maybe class is complete
        if not levelToPlay then
            print("Menu gotoGame: no next level with text; go to select class.")
            
             composer.gotoScene("selectLevel", {
            params = {
                user              = userId,
                prefix         = classCode
            }
        })
        return
        end

        print("Menu gotoGame: going to LevelID", levelToPlay)

        ------------------------------------------------
        -- 4) Finally go to game.lua with desiredLevel
        ------------------------------------------------
        composer.gotoScene("game", {
            params = {
                user              = userId,
                classCode         = classCode,
                className         = className,
                desiredLevel      = levelToPlay,
                useFirstAvailable = false
            }
        })
    end)
end


------------------------------------------------------------
-- Input Handler
------------------------------------------------------------
local function onClassField(event)
    if (event.phase == "began") then
        if not Class.hasCleared then
            Class.text = ""
            Class.hasCleared = true
        end
    end
end

------------------------------------------------------------
-- Scene Creation
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    local background = display.newImageRect(sceneGroup, "menu-background.png",
        display.contentWidth, display.contentHeight)
    background.x, background.y = display.contentCenterX, display.contentCenterY
    display.setDefault("background", colors.bg)

    --------------------------------------------------------
    -- Helper: Measure widest text across given keys
    --------------------------------------------------------
    local function getMaxTextWidth(keys, icon, font, fontSize)
        local maxWidth = 0
        for _, key in ipairs(keys) do
            local temp = display.newText({
                text = (icon or "") .. " " .. languages.t(key),
                font = font,
                fontSize = fontSize
            })
            if temp.width > maxWidth then maxWidth = temp.width end
            temp:removeSelf()
        end
        return maxWidth
    end

    --------------------------------------------------------
    -- Helper: Make Button (auto-width within group type)
    --------------------------------------------------------
    local function makeButton(label, x, y, colorSet, onTap, icon, scale, widthType)
        scale = scale or 1.0
        widthType = widthType or "main" -- default style

        local btnHeight = display.contentHeight * (widthType == "header" and 0.06 or 0.08) * scale
        local fontSize  = math.floor(btnHeight * 0.35)

        -- define per-group translation lists
        local headerKeys = { "log_in", "language", "exit" }
        local mainKeys   = { "find_class", "play_game", "create" }

        local keysToCheck = (widthType == "header") and headerKeys or mainKeys
        local maxWidth = getMaxTextWidth(keysToCheck, icon, native.systemFontBold, fontSize)

        -- smaller padding for headers, larger for main
        local padding = (widthType == "header") and 40 or 100
        local minWidthFactor = (widthType == "header") and 0.22 or 0.45

        local btnWidth = math.max(maxWidth + padding, display.contentWidth * minWidthFactor)

        local group = display.newGroup()
        group.x, group.y = x, y

        local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, 14)
        front:setFillColor(unpack(colorSet))
        front.strokeWidth = 5
        front:setStrokeColor(unpack(colors.borderPurple))
        front.alpha = 0.95

        local labelText = display.newText({
            parent = group,
            text = (icon or "") .. " " .. label,
            font = native.systemFontBold,
            fontSize = fontSize,
            align = "center"
        })
        labelText:setFillColor(unpack(colors.textPrimary))
        labelText.x, labelText.y = 0, 0

        -- Touch handler
        local function onTouch(event)
            if event.phase == "began" then
                transition.to(front, { time = 80, xScale = 0.95, yScale = 0.95 })
                labelText.alpha = 0.8
            elseif event.phase == "ended" or event.phase == "cancelled" then
                transition.to(front, { time = 80, xScale = 1.0, yScale = 1.0 })
                labelText.alpha = 1.0
                if onTap then onTap(event) end
            end
            return true
        end

        if front and onTouch then front:addEventListener("touch", onTouch) end
        if labelText and onTouch then labelText:addEventListener("touch", onTouch) end

        sceneGroup:insert(group)
        group.label = labelText
        return group
    end

    --------------------------------------------------------
    -- Create Buttons (header + main groups)
    --------------------------------------------------------
    local margin = display.contentWidth * 0.01
    local buttonSpacing = display.contentHeight * 0.10
    local centerY = display.contentCenterY * 0.95

    buttons.language = makeButton(languages.t("language"),
        margin + (display.contentWidth * 0.20),
        display.contentHeight * 0.05, colors.creamBtn,
        function() composer.gotoScene("languageSettings") end, "🌐", 0.7, "header")

    buttons.exit = makeButton(languages.t("exit"),
        display.contentWidth - margin - (display.contentWidth * 0.20),
        display.contentHeight * 0.05, colors.creamBtn,
        function() native.requestExit() end, "", 0.7, "header")

    local headerUnderline = display.newRect(sceneGroup,
        display.contentCenterX,
        display.contentHeight * 0.10,
        display.contentWidth * 0.9, 3)
    headerUnderline:setFillColor(unpack(colors.orangeBtn))

    -- Main buttons use widthType = "main"
    buttons.findClass = makeButton(languages.t("find_class"),
        display.contentCenterX, centerY - buttonSpacing,
        colors.lavenderBtn, setOwner, "🔍", 1, "main")

    buttons.playGame = makeButton(languages.t("play_game"),
        display.contentCenterX, centerY,
        colors.orangeBtn, gotoGame, "▶️", 1, "main")

    --------------------------------------------------------
    -- Class Field
    --------------------------------------------------------
    local fieldWidth  = display.contentWidth * 0.68
    local fieldHeight = display.contentHeight * 0.06
    local fieldX, fieldY = display.contentCenterX, display.contentCenterY * 0.55

    local border = display.newRoundedRect(sceneGroup, fieldX, fieldY,
        fieldWidth + 5, fieldHeight + 5, 12)
    border:setStrokeColor(unpack(colors.borderPurple))
    border.strokeWidth = 8

    Class = native.newTextField(fieldX, fieldY, fieldWidth, fieldHeight)
    Class.placeholder = languages.t("enter_code")
    Class.align = "center"
    Class:setTextColor(unpack(colors.textPrimary))
    Class.hasCleared = false
    Class:addEventListener("userInput", onClassField)

    LevelLabel = display.newText({
        parent = sceneGroup,
        text = "",
        x = fieldX,
        y = fieldY * 0.58,
        font = native.systemFontBold,
        fontSize = 48,
        align = "center"
    })
    LevelLabel:setFillColor(unpack(colors.textPrimary))

    --------------------------------------------------------
    -- Restore last class (if any)
    --------------------------------------------------------
    restoreLastClass()
end

scene:addEventListener("create", scene)

------------------------------------------------------------
-- Language Refresh Function
------------------------------------------------------------
local function refreshLanguage()
    if buttons.language and buttons.language.label then
        buttons.language.label.text = "🌐 " .. languages.t("language")
    end
    if buttons.exit and buttons.exit.label then
        buttons.exit.label.text = languages.t("exit")
    end
    if buttons.findClass and buttons.findClass.label then
        buttons.findClass.label.text = "🔍 " .. languages.t("find_class")
    end    if buttons.playGame and buttons.playGame.label then
        buttons.playGame.label.text = "▶️ " .. languages.t("play_game")
    end
    
    if Class then
        Class.placeholder = languages.t("enter_code")
    end
end
scene.refreshLanguage = refreshLanguage

------------------------------------------------------------
-- Scene Hide / Destroy / Show
------------------------------------------------------------
function scene:hide(event)
    if (event.phase == "will") then
        if Class and Class.removeSelf then Class:removeSelf(); Class = nil end
    end
end

function scene:destroy(event)
    if Class then Class:removeSelf(); Class = nil end
end

scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

function scene:show(event)
    local phase = event.phase

    if phase == "did" and not Class then
        -- Re-create the text field after coming back from another scene
        local fieldWidth  = display.contentWidth * 0.68
        local fieldHeight = display.contentHeight * 0.06
        local fieldX, fieldY = display.contentCenterX, display.contentCenterY * 0.55

        Class = native.newTextField(fieldX, fieldY, fieldWidth, fieldHeight)
        Class.placeholder = languages.t("enter_code")
        Class.align = "center"
        Class:setTextColor(unpack(colors.textPrimary))
        Class.hasCleared = false
        Class:addEventListener("userInput", onClassField)

        -- Restore last class when returning to menu
        restoreLastClass()
    end
end
scene:addEventListener("show", scene)

return scene

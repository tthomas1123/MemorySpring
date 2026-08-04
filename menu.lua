------------------------------------------------------------
-- menu.lua
-- SmartSheep Creator - Welcome Menu
--
-- Updated:
--  • Uses appState for shared user/class flow state
--  • Menu sets userId + userName after auth
--  • Clears class-specific state before going to addClass
--  • Reworked layout to match new welcome mock
--  • Removed gear/settings from this screen
--  • Added subtitle under Welcome
--  • Log In opens login webview
--  • Sign Up opens register webview
--  • Successful auth goes directly to addClass
--  • Subscribe button stays at bottom
--  • Added a little more space between Log In and Sign Up
--  • Save login locally so user stays signed in
------------------------------------------------------------
local composer = require("composer")
local json = require("json")
local billing = require("billing")
local tutorial = require("tutorial")
local scene = composer.newScene()

local colors = require("colors")
local languages = require("languages")
local appState = require("appState")

------------------------------------------------------------
-- Globals
------------------------------------------------------------
local titleLabel, subtitleLabel, webView
local closeCircle, closeXText
local buttons = {}

local background
local sheep

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

local function urlDecode(str)
    if not str then return nil end
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
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

local function newImageByWidth(parent, filename, targetW)
    local img = display.newImage(parent, filename)
    if not img then
        print("ERROR: failed to load image:", filename)
        return nil
    end
    local scale = targetW / img.width
    img.xScale, img.yScale = scale, scale
    return img
end

------------------------------------------------------------
-- Class/User Lookup
------------------------------------------------------------
local function setClass(userId)
    local classRequest = "https://www.infoshagame.com/user/list/getPrefix.php?type=getP&user=" .. userId

    local function networkListener(event)
        if event.isError then
            print("setClass network error")
            return
        end

        print("setClass raw response:", tostring(event.response))

        local data = json.decode(event.response)
        if not data or not data.classes or #data.classes == 0 then
            print("setClass no classes returned for user:", tostring(userId))
            return
        end

        local firstClass = data.classes[1]

        appState.set({
            prefix = firstClass.prefix,
            className = firstClass.classname or "",
            classStatus = firstClass.status or "Draft"
        })
    end

    network.request(classRequest, "GET", networkListener)
end

local function setUser(userId, onDone)
    local userRequest = "https://www.infoshagame.com/user/list/getUser.php?type=get&user=" .. userId

    local function networkListener(event)
        if event.isError then
            print("setUser network error")
            if onDone then onDone(false) end
            return
        end

        print("setUser raw response:", tostring(event.response))

        local data = json.decode(event.response)
        if not data or not data.username then
            print("setUser invalid response")
            if onDone then onDone(false) end
            return
        end

        local userName = data.username
        local shared = appState.get()

        appState.set({
            userId = tostring(userId),
            userName = tostring(userName),
            apiToken = shared.apiToken
        })
local shared = appState.get()
print("AFTER LOGIN appState.userId:", tostring(shared.userId))
print("AFTER LOGIN appState.userName:", tostring(shared.userName))
print("AFTER LOGIN appState.apiToken:", tostring(shared.apiToken))
        setClass(userId)

        if onDone then onDone(true) end
    end

    network.request(userRequest, "GET", networkListener)
end

------------------------------------------------------------
-- Shared Auth WebView (Login / Sign Up)
------------------------------------------------------------
local function openAuthWebView(authUrl)
    if webView then webView:removeSelf(); webView = nil end
    if closeCircle then closeCircle:removeSelf(); closeCircle = nil end
    if closeXText then closeXText:removeSelf(); closeXText = nil end

    local function layoutWebView()
        if not webView then return end

        local left = display.safeScreenOriginX
        local top = display.safeScreenOriginY
        local sw = display.safeActualContentWidth
        local sh = display.safeActualContentHeight

        local w = math.floor(sw * 0.98)
        local h = math.floor(sh * 0.90)

        webView.width = w
        webView.height = h
        webView.x = left + sw * 0.5
        webView.y = top + sh * 0.50

        local buttonSize = 58
        local cx = webView.x + (webView.width / 2) - (buttonSize / 2)
        local cy = webView.y - (webView.height / 2) - (buttonSize / 2)

        if closeCircle then
            closeCircle.x, closeCircle.y = cx, cy
        end
        if closeXText then
            closeXText.x, closeXText.y = cx, cy - 2
        end
    end

    local left = display.safeScreenOriginX
    local top = display.safeScreenOriginY
    local sw = display.safeActualContentWidth
    local sh = display.safeActualContentHeight

    webView = native.newWebView(
        left + sw * 0.5,
        top + sh * 0.5,
        math.floor(sw * 0.92),
        math.floor(sh * 0.72)
    )
    webView:request(authUrl)

    local buttonSize = 58
    closeCircle = display.newCircle(0, 0, buttonSize / 2)
    closeCircle:setFillColor(unpack(colors.secondaryAction))
    closeCircle.strokeWidth = 4
    closeCircle:setStrokeColor(unpack(colors.secondaryActionBorder))

    closeXText = display.newText({
        text = "✕",
        x = 0,
        y = 0,
        font = native.systemFontBold,
        fontSize = 34
    })
    closeXText:setFillColor(unpack(colors.error))

    local function closeAuthWebView()
        if webView then webView:removeSelf(); webView = nil end
        if closeCircle then closeCircle:removeSelf(); closeCircle = nil end
        if closeXText then closeXText:removeSelf(); closeXText = nil end
        Runtime:removeEventListener("resize", layoutWebView)
    end

    closeCircle:addEventListener("tap", closeAuthWebView)
    closeXText:addEventListener("tap", closeAuthWebView)

    layoutWebView()
    Runtime:addEventListener("resize", layoutWebView)
    timer.performWithDelay(50, layoutWebView)
    timer.performWithDelay(250, layoutWebView)

    local function onLoaded(event)
        if not webView then return end
        if event.type == "loaded" or event.type == "finished" then
            local jsCode = [[
                (function () {
                    var style = document.createElement('style');
                    style.innerHTML = `
                        html, body {
                            width: 100% !important;
                            max-width: 100% !important;
                            overflow-x: hidden !important;
                            -webkit-text-size-adjust: 100% !important;
                            touch-action: manipulation;
                        }
                        * { box-sizing: border-box !important; }
                        ::-webkit-scrollbar { width: 0 !important; height: 0 !important; display: none !important; }
                    `;
                    document.head.appendChild(style);
                })();
            ]]
            webView:execute(jsCode)
        end
    end
    webView:addEventListener("load", onLoaded)

    local function onURLRequest(event)
    if not event.url then
        return false
    end

    if not string.find(event.url, "status=success") then
        return false
    end

    local url = event.url

    local id        = url:match("id=(%d+)")
    local rawName   = url:match("username=([^&]+)")
    local rawPlan   = url:match("plan=([^&]+)")
    local rawStatus = url:match("sub_status=([^&]+)")
    local rawToken  = url:match("token=([^&]+)")
print("LOGIN REDIRECT URL:", tostring(event.url))
print("rawToken:", tostring(rawToken))

    local username  = urlDecode(rawName)
    local plan      = urlDecode(rawPlan)
    local subStatus = urlDecode(rawStatus)
    local token     = urlDecode(rawToken)
    print("decoded token:", tostring(token))
    print("LOGIN success id:", tostring(id))
    print("LOGIN success username:", tostring(username))
    print("LOGIN success token:", tostring(token))
    print("LOGIN success plan:", tostring(plan))
    print("LOGIN success sub_status:", tostring(subStatus))

    if not id or not username then
        print("LOGIN success missing id or username")
        return false
    end

    appState.set({
        userId = tostring(id),
        userName = tostring(username),
        apiToken = tostring(token or "")
    })

    appState.clearClass()

    composer.setVariable("debugLoggingEnabled", false)

    system.setPreferences("app", {
        userId = tostring(id),
        userName = tostring(username),
        apiToken = tostring(token or "")
    })

    if plan then
        composer.setVariable("subscriptionPlan", plan)
    end

    if subStatus then
        composer.setVariable("subscriptionStatus", subStatus)
    end

    billing.setUserId(tonumber(id))
    billing.init()

    billing.refreshDebugSettings(function(debugResult)
        if debugResult and debugResult.data then
            local enabled = (debugResult.data.remoteLoggingEnabled == true)
            composer.setVariable("debugLoggingEnabled", enabled)
        else
            composer.setVariable("debugLoggingEnabled", false)
        end

        billing.checkEntitlement(function(result)
            if result and result.success then
                appState.set({
                    hasAccess = (result.active == true),
                    accessStatus = result.data and result.data.status or ""
                })

                print("ENTITLEMENT active:", tostring(result.active))
                print("ENTITLEMENT status:", tostring(result.data and result.data.status))
            else
                appState.set({
                    hasAccess = false,
                    accessStatus = "ERROR"
                })

                print("ENTITLEMENT failed:", tostring(result and result.error))
            end

            setUser(id, function(success)
                local shared = appState.get()
                print("POST setUser success:", tostring(success))
                print("POST setUser appState.userId:", tostring(shared.userId))
                print("POST setUser appState.userName:", tostring(shared.userName))
                print("POST setUser appState.apiToken:", tostring(shared.apiToken))

                closeAuthWebView()

                composer.removeScene("addClass")
                composer.removeScene("selectLevels")
                composer.removeScene("customize")

                timer.performWithDelay(120, function()
                    composer.gotoScene("addClass", { effect = "fade", time = 250 })
                end)
            end)
        end)
    end)

    return false
end

    webView:addEventListener("urlRequest", onURLRequest)
end

local function gotoLogin()
    openAuthWebView("https://www.infoshagame.com/user/list/login.html?lang=" .. languages.current .. "&v=" .. os.time())
end

local function gotoRegister()
    openAuthWebView("https://www.infoshagame.com/user/list/register.html?lang=" .. languages.current .. "&v=" .. os.time())
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function gotoPaywall()
    composer.gotoScene("paywall")
end

------------------------------------------------------------
-- Restore Title
------------------------------------------------------------
local function restoreWelcome()
    if not titleLabel then return end
    titleLabel.text = languages.t("welcome") or "Welcome"
    titleLabel:setFillColor(unpack(colors.textPrimary))
    fitTextToWidth(titleLabel, (display.safeActualContentWidth or display.contentWidth) * 0.90, 0.72)
end

------------------------------------------------------------
-- Scene Creation
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    composer.setVariable("debugLoggingEnabled", false)
    display.setDefault("background", unpack(colors.appBackground))

    background = newAspectFillImage(sceneGroup, "menu-background.png")
    if background then background:toBack() end

    sheep = newImageByWidth(sceneGroup, "sheep.png", display.safeActualContentWidth * 0.23)
    sheep.anchorX, sheep.anchorY = 0.5, 1.0

    local function getMaxTextWidth(buttonDefs, font, fontSize)
        local maxWidth = 0
        for i = 1, #buttonDefs do
            local temp = display.newText({
                text = buttonDefs[i],
                font = font,
                fontSize = fontSize
            })
            if temp.width > maxWidth then
                maxWidth = temp.width
            end
            temp:removeSelf()
        end
        return maxWidth
    end

    local function makeButton(label, x, y, fillColor, onTap, icon, scale, strokeColor, textColor)
        scale = scale or 1.0

        local btnHeight = display.contentHeight * 0.075 * scale
        local fontSize = math.floor(btnHeight * 0.34)

        local maxWidth = getMaxTextWidth({
            "🔐 " .. (languages.t("log_in") or "Log In"),
            "👥 " .. (languages.t("sign_up") or "Sign Up"),
            
        }, native.systemFontBold, fontSize)

        local padding = 86
        local minWidth = display.contentWidth * 0.40
        local btnWidth = math.max(maxWidth + padding, minWidth)

        local group = display.newGroup()
        group.x, group.y = x, y

        local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, 12)
        front:setFillColor(unpack(fillColor))
        front.strokeWidth = 4
        front:setStrokeColor(unpack(strokeColor or colors.primaryActionPressed))
        front.alpha = 0.96

        local labelText = display.newText({
            parent = group,
            text = ((icon and icon ~= "") and (icon .. " ") or "") .. label,
            font = native.systemFontBold,
            fontSize = fontSize,
            align = "center"
        })
        labelText:setFillColor(unpack(textColor or colors.textOnPrimary))
        labelText.x, labelText.y = 0, 0

        local function fitLabel()
            fitTextToWidth(labelText, btnWidth * 0.84, 0.72)
        end
        fitLabel()

        local function onTouch(e)
            if e.phase == "began" then
                transition.to(front, { time = 80, xScale = 0.96, yScale = 0.96 })
                labelText.alpha = 0.85
            elseif e.phase == "ended" or e.phase == "cancelled" then
                transition.to(front, { time = 80, xScale = 1.0, yScale = 1.0 })
                labelText.alpha = 1.0
                if onTap then onTap(e) end
            end
            return true
        end

        front:addEventListener("touch", onTouch)
        labelText:addEventListener("touch", onTouch)

        sceneGroup:insert(group)
        group.label = labelText
        group.fitLabel = fitLabel
        return group
    end

    titleLabel = display.newText({
        parent = sceneGroup,
        text = languages.t("welcome") or "Welcome",
        x = display.contentCenterX,
        y = display.contentHeight * 0.15,
        font = native.systemFontBold,
        fontSize = 56,
        align = "center"
    })
    titleLabel:setFillColor(unpack(colors.textPrimary))

    subtitleLabel = display.newText({
        parent = sceneGroup,
        text = languages.t("create_classes") or "Create classes and fun levels for\nyour students",
        x = display.contentCenterX,
        y = titleLabel.contentBounds.yMax + 28,
        width = display.contentWidth * 0.78,
        font = native.systemFont,
        fontSize = 22,
        align = "center"
    })
    subtitleLabel:setFillColor(0.38, 0.44, 0.52)

    local loginY = subtitleLabel.y + 88
    local signUpY = loginY + 86
  

    buttons.login = makeButton(
        languages.t("log_in") or "Log In",
        display.contentCenterX, loginY,
        colors.primaryAction,
        gotoLogin,
        "🔐",
        1.0,
        colors.primaryActionPressed,
        colors.textOnPrimary
    )

    buttons.signup = makeButton(
        languages.t("sign_up") or "Sign Up",
        display.contentCenterX, signUpY,
        colors.secondaryAction,
        gotoRegister,
        "👥",
        1.0,
        colors.secondaryActionBorder,
        colors.textOnLight
    )

    

    local function layoutScene()
        local top = display.safeScreenOriginY
        local swSafe = display.safeActualContentWidth
        local shSafe = display.safeActualContentHeight

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

        if titleLabel then
            titleLabel.x = display.contentCenterX
            titleLabel.y = top + shSafe * 0.13
            fitTextToWidth(titleLabel, swSafe * 0.82, 0.72)
        end

        if subtitleLabel then
            subtitleLabel.x = display.contentCenterX
            subtitleLabel.y = titleLabel.y + 54
            subtitleLabel.width = swSafe * 0.78
        end

        local loginY2 = subtitleLabel.y + 86
        local signUpY2 = loginY2 + 86
        local sheepY = top + shSafe * 0.70
      

        if buttons.login then
            buttons.login.x = display.contentCenterX
            buttons.login.y = loginY2 + 70
            if buttons.login.fitLabel then buttons.login.fitLabel() end
            buttons.login:toFront()
        end

        if buttons.signup then
            buttons.signup.x = display.contentCenterX
            buttons.signup.y = signUpY2 + 100
            if buttons.signup.fitLabel then buttons.signup.fitLabel() end
            buttons.signup:toFront()
        end

        if sheep and sheep.removeSelf then
            sheep.x = display.contentCenterX
            sheep.y = sheepY
            sheep:toFront()
        end

       

        if background then background:toBack() end
        if titleLabel then titleLabel:toFront() end
        if subtitleLabel then subtitleLabel:toFront() end
    end

    scene._layoutScene = layoutScene
    restoreWelcome()
    layoutScene()
end

scene:addEventListener("create", scene)

------------------------------------------------------------
-- Language Refresh Function
------------------------------------------------------------
local function refreshLanguage()
    if titleLabel then
        titleLabel.text = languages.t("welcome") or "Welcome"
        fitTextToWidth(titleLabel, (display.safeActualContentWidth or display.contentWidth) * 0.90, 0.72)
    end

    if subtitleLabel then
        subtitleLabel.text = languages.t("create_classes") or "Create classes and fun levels for\nyour students"
    end

    if buttons.login and buttons.login.label then
        buttons.login.label.text = "🔐 " .. (languages.t("log_in") or "Log In")
        if buttons.login.fitLabel then buttons.login.fitLabel() end
    end

    if buttons.signup and buttons.signup.label then
        buttons.signup.label.text = "👥 Sign Up"
        if buttons.signup.fitLabel then buttons.signup.fitLabel() end
    end

   
end
scene.refreshLanguage = refreshLanguage

------------------------------------------------------------
-- Scene Hide / Destroy / Show
------------------------------------------------------------
function scene:hide(event)
    if event.phase == "will" then
        if self._onResize then
            Runtime:removeEventListener("resize", self._onResize)
            self._onResize = nil
        end
    end
end

function scene:destroy(event)
    if webView then webView:removeSelf(); webView = nil end
    if closeCircle then closeCircle:removeSelf(); closeCircle = nil end
    if closeXText then closeXText:removeSelf(); closeXText = nil end

    if sheep and sheep.removeSelf then sheep:removeSelf(); sheep = nil end
    if background and background.removeSelf then background:removeSelf(); background = nil end

    if self._onResize then
        Runtime:removeEventListener("resize", self._onResize)
        self._onResize = nil
    end
end

scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

function scene:show(event)
    if event.phase == "did" then
        if not self._onResize then
            self._onResize = function()
                if scene._layoutScene then scene._layoutScene() end
            end
            Runtime:addEventListener("resize", self._onResize)
        end

        local shared = appState.get() or {}
        local existingUserId = shared.userId
        local existingUserName = shared.userName
        local existingApiToken = shared.apiToken

        local savedUserId = system.getPreference("app", "userId", "string")
        local savedUserName = system.getPreference("app", "userName", "string")
        local savedApiToken = system.getPreference("app", "apiToken", "string")

        -- Restore any missing auth fields from saved prefs
        if savedUserId and savedUserId ~= "" then
            local resolvedUserId = existingUserId or savedUserId
            local resolvedUserName = existingUserName or savedUserName or ""
            local resolvedApiToken = existingApiToken or savedApiToken or ""

            appState.set({
                userId = tostring(resolvedUserId),
                userName = tostring(resolvedUserName),
                apiToken = tostring(resolvedApiToken)
            })

            existingUserId = resolvedUserId
            existingUserName = resolvedUserName
            existingApiToken = resolvedApiToken
        end
        -- Restore saved login if appState is empty
        if not existingUserId then
            local savedUserId = system.getPreference("app", "userId", "string")
            local savedUserName = system.getPreference("app", "userName", "string")

            if savedUserId and savedUserId ~= "" then
                appState.set({
                    userId = tostring(savedUserId),
                    userName = tostring(savedUserName or ""),
                    apiToken = savedApiToken or ""
                })

                existingUserId = savedUserId
                existingUserName = savedUserName
            end
        end

        if existingUserId then
            billing.setUserId(tonumber(existingUserId))
            billing.init()

            billing.refreshDebugSettings(function(debugResult)
                print("DEBUG SETTINGS refresh on show:", tostring(debugResult and debugResult.success))
                if debugResult and debugResult.data then
                    local enabled = (debugResult.data.remoteLoggingEnabled == true)
                    composer.setVariable("debugLoggingEnabled", enabled)
                else
                    composer.setVariable("debugLoggingEnabled", false)
                end
            end)

          --  setUser(existingUserId)

            timer.performWithDelay(120, function()
                composer.gotoScene("addClass", { effect = "fade", time = 250 })
            end)

            return
        else
            composer.setVariable("debugLoggingEnabled", false)
        end

        restoreWelcome()

        if scene._layoutScene then scene._layoutScene() end
        timer.performWithDelay(50, function()
            if scene._layoutScene then scene._layoutScene() end
        end)
    end
end

scene:addEventListener("show", scene)

return scene
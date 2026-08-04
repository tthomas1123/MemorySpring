-- paywall.lua
-- Production-oriented paywall with platform-aware store messaging
-- and billing facade support for Apple / Google
------------------------------------------------------------
local composer = require("composer")
local scene    = composer.newScene()

local billing        = require("billing")
local colors         = require("colors")
local languages      = require("languages")
local StandardHeader = require("ui.standardHeader")
local appState       = require("appState")

local background
local sheep

local titleText
local titleShadow

local priceText
local priceShadow

local cancelText
local cancelShadow

local benefitText
local benefitShadow

local statusText
local statusShadow

local subscribeButton
local restoreButton
local refreshTimer

------------------------------------------------------------
-- Platform helpers
------------------------------------------------------------
local platformName = system.getInfo("platformName") or ""

local function isApplePlatform()
    return platformName == "iPhone OS"
end

local function isGooglePlatform()
    return platformName == "Android"
end

local function storeName()
    if isGooglePlatform() then
        return "Google Play"
    elseif isApplePlatform() then
        return "App Store"
    end
    return "store"
end

local function cancelSourceName()
    if isGooglePlatform() then
        return "Google Play"
    elseif isApplePlatform() then
        return "Apple subscriptions"
    end
    return "your account settings"
end

------------------------------------------------------------
-- Debug helper
------------------------------------------------------------
local function paywallLog(...)
    if billing and billing.logDebug then
        billing.logDebug(...)
        return
    end

    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print("[paywall] " .. table.concat(parts, " "))
end

------------------------------------------------------------
-- User helpers
------------------------------------------------------------
local function getResolvedUserId()
    local composerUserId = composer.getVariable("userId")
    if composerUserId and tostring(composerUserId) ~= "" then
        return tonumber(composerUserId)
    end

    local shared = appState.get()
    local sharedUserId = shared and shared.userId or nil
    if sharedUserId and tostring(sharedUserId) ~= "" then
        return tonumber(sharedUserId)
    end

    return nil
end

local function syncComposerUserIdIfNeeded(userId)
    if userId then
        composer.setVariable("userId", tostring(userId))
    end
end

------------------------------------------------------------
-- Local palette
------------------------------------------------------------
local NAVY_TEXT           = { 0.14, 0.18, 0.25 }
local SUBTEXT             = { 0.24, 0.29, 0.36 }
local SHADOW              = { 0.00, 0.00, 0.00, 0.20 }

local BLUE_BUTTON         = { 0.80, 0.89, 1.00 }
local BLUE_BUTTON_STROKE  = { 0.48, 0.67, 0.90 }
local BLUE_BUTTON_TEXT    = { 0.16, 0.32, 0.58 }

------------------------------------------------------------
-- Localization helpers
------------------------------------------------------------
local function tr(key, fallback)
    local value = languages.t(key)
    if value == key and fallback ~= nil then
        return fallback
    end
    return value
end

local function trf(key, fallback, ...)
    local template = tr(key, fallback)
    return string.format(template, ...)
end

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

local function syncShadow(shadow, target, dx, dy)
    if not shadow or not target then return end
    shadow.text = target.text
    shadow.x = target.x + (dx or 2)
    shadow.y = target.y + (dy or 2)
    shadow.xScale = target.xScale
    shadow.yScale = target.yScale
    shadow.width = target.width
    shadow.rotation = target.rotation
end

local function effectiveHeight(txt)
    if not txt then return 0 end
    return (txt.height or 0) * (txt.yScale or 1.0)
end

------------------------------------------------------------
-- Button helper
------------------------------------------------------------
local function makeButton(sceneGroup, opts)
    local label        = opts.label or ""
    local y            = opts.y or 0
    local fillColor    = opts.fillColor or colors.primaryAction
    local strokeColor  = opts.strokeColor or colors.primaryActionPressed
    local textColor    = opts.textColor or colors.textOnPrimary
    local onTap        = opts.onTap
    local scale        = opts.scale or 1.0
    local fontScale    = opts.fontScale or 1.0
    local iconText     = opts.iconText or ""
    local cornerRadius = opts.cornerRadius or 18

    local btnHeight = (opts.height or (display.contentHeight * 0.082))
    local btnWidth  = (opts.width or (display.contentWidth * 0.80)) * scale
    local fontSize  = math.floor(btnHeight * 0.34 * fontScale)

    local group = display.newGroup()
    group.x, group.y = display.contentCenterX, y
    sceneGroup:insert(group)

    local front = display.newRoundedRect(group, 0, 0, btnWidth, btnHeight, cornerRadius)
    front:setFillColor(unpack(fillColor))
    front.strokeWidth = opts.strokeWidth or 5
    front:setStrokeColor(unpack(strokeColor))
    front.alpha = opts.alpha or 0.98

    local iconDisplay
    local iconInset = btnWidth * 0.18

    if iconText ~= "" then
        iconDisplay = display.newText({
            parent = group,
            text = iconText,
            x = -btnWidth * 0.5 + iconInset,
            y = 0,
            font = native.systemFontBold,
            fontSize = math.floor(fontSize * 1.05),
            align = "center"
        })
        iconDisplay:setFillColor(unpack(textColor))
    end

    local labelText = display.newText({
        parent = group,
        text = label,
        x = 0,
        y = 0,
        width = btnWidth * (iconText ~= "" and 0.62 or 0.78),
        font = native.systemFontBold,
        fontSize = fontSize,
        align = "center"
    })
    labelText:setFillColor(unpack(textColor))

    local function fitLabel()
        if not labelText or not labelText.removeSelf then return end
        labelText.xScale, labelText.yScale = 1.0, 1.0

        local maxW = btnWidth * (iconText ~= "" and 0.62 or 0.78)
        labelText.width = maxW

        if labelText.height > btnHeight * 0.62 then
            local s = (btnHeight * 0.62) / labelText.height
            s = clamp(s, 0.72, 1.0)
            labelText.xScale, labelText.yScale = s, s
        end
    end
    fitLabel()

    local enabled = true

    local function setEnabled(value)
        enabled = value and true or false

        if enabled then
            front.alpha = opts.alpha or 0.98
            labelText.alpha = 1.0
            if iconDisplay then iconDisplay.alpha = 1.0 end
        else
            front.alpha = 0.45
            labelText.alpha = 0.82
            if iconDisplay then iconDisplay.alpha = 0.82 end
        end
    end

    local function setLabel(newLabel)
        if not labelText then return end
        labelText.text = newLabel or ""
        fitLabel()
    end

    local function onTouch(event)
        if not enabled then
            return true
        end

        if event.phase == "began" then
            display.getCurrentStage():setFocus(front)
            front.isFocus = true
            transition.to(group, { time = 80, xScale = 0.98, yScale = 0.98 })
            labelText.alpha = 0.88
            if iconDisplay then iconDisplay.alpha = 0.88 end
        elseif front.isFocus then
            if event.phase == "ended" or event.phase == "cancelled" then
                display.getCurrentStage():setFocus(nil)
                front.isFocus = false
                transition.to(group, { time = 80, xScale = 1.0, yScale = 1.0 })
                labelText.alpha = enabled and 1.0 or 0.82
                if iconDisplay then
                    iconDisplay.alpha = enabled and 1.0 or 0.82
                end

                if event.phase == "ended" and onTap then
                    onTap(event)
                end
            end
        end

        return true
    end

    front:addEventListener("touch", onTouch)
    labelText:addEventListener("touch", onTouch)
    if iconDisplay then iconDisplay:addEventListener("touch", onTouch) end

    group.front      = front
    group.label      = labelText
    group.icon       = iconDisplay
    group.fitLabel   = fitLabel
    group.setEnabled = setEnabled
    group.setLabel   = setLabel
    group._btnWidth  = btnWidth
    group._btnHeight = btnHeight

    setEnabled(true)
    return group
end

------------------------------------------------------------
-- Text helpers
------------------------------------------------------------
local function setPriceLine(message)
    if priceText then
        priceText.text = message or ""
        fitTextToWidth(priceText, display.contentWidth * 0.88, 0.78)
        syncShadow(priceShadow, priceText, 2, 2)
    end
end

local function setCancelLine(message)
    if cancelText then
        cancelText.text = message or ""
        fitTextToWidth(cancelText, display.contentWidth * 0.88, 0.80)
        syncShadow(cancelShadow, cancelText, 2, 2)
    end
end

local function setStatus(message)
    if statusText then
        statusText.text = message or ""
        statusText.isVisible = (message and message ~= "") and true or false
        if statusShadow then
            statusShadow.isVisible = statusText.isVisible
        end

        if statusText.isVisible then
            fitTextToWidth(statusText, display.contentWidth * 0.88, 0.78)
            syncShadow(statusShadow, statusText, 2, 2)
        end
    end
end

local function setButtonsEnabled(enabled)
    if subscribeButton and subscribeButton.setEnabled then
        subscribeButton:setEnabled(enabled)
    end
    if restoreButton and restoreButton.setEnabled then
        restoreButton:setEnabled(enabled)
    end
end

------------------------------------------------------------
-- Billing helpers
------------------------------------------------------------
local function updateProductUI()
    local product = billing.getProduct()

    paywallLog("updateProductUI called", "hasProduct=", tostring(product ~= nil))

    if product then
        local price = product.localizedPrice or product.price or "$9.99/month"
        paywallLog("updateProductUI productIdentifier=", tostring(product.productIdentifier))
        paywallLog("updateProductUI localizedPrice=", tostring(product.localizedPrice))
        paywallLog("updateProductUI fallback price=", tostring(product.price))

        setPriceLine(trf("paywall_price_template", "1 month free, then %s", tostring(price)))
        setButtonsEnabled(true)
        setStatus("")
    else
        paywallLog("updateProductUI no product yet")
        setPriceLine("Loading subscription from " .. storeName() .. "...")
        setButtonsEnabled(false)
        setStatus("")
    end
end

local function unlockPremiumLocally(result)
    if not result then
        paywallLog("unlockPremiumLocally skipped because result=nil")
        return
    end

    local data = result.data or result.backendData or {}

    paywallLog(
        "unlockPremiumLocally",
        "active=", tostring(result.active),
        "status=", tostring(data.status),
        "planCode=", tostring(data.planCode),
        "currentPeriodEnd=", tostring(data.currentPeriodEnd)
    )

    composer.setVariable("subscriptionActive", true)

    if data.status then
        composer.setVariable("subscriptionStatus", data.status)
    end

    if data.planCode then
        composer.setVariable("subscriptionPlan", data.planCode)
    end

    if data.currentPeriodEnd then
        composer.setVariable("subscriptionCurrentPeriodEnd", data.currentPeriodEnd)
    end
end

local function refreshEntitlementUI()
    paywallLog("refreshEntitlementUI start")

    billing.checkEntitlement(function(result)
        if not scene.view or not priceText then
            paywallLog("refreshEntitlementUI aborted because scene/view missing")
            return
        end

        paywallLog(
            "refreshEntitlementUI result",
            "success=", tostring(result and result.success),
            "active=", tostring(result and result.active),
            "error=", tostring(result and result.error),
            "status=", tostring(result and result.data and result.data.status)
        )

        if result.success and result.active then
            unlockPremiumLocally(result)
            setStatus(tr("paywall_status_active", "Premium active."))
            setButtonsEnabled(true)
        elseif result.success then
            setStatus("")
            updateProductUI()
        else
            setStatus(tr("paywall_status_verify_failed", "Could not verify subscription status."))
            updateProductUI()
        end

        if scene._layoutScene then
            scene._layoutScene()
        end
    end)
end

local function startPurchase()
    local userId = getResolvedUserId()
    paywallLog("startPurchase tapped", "userId=", tostring(userId), "store=", storeName())

    if not userId then
        paywallLog("startPurchase blocked: no userId")
        setStatus(tr("paywall_status_login_first", "Please log in first."))
        if scene._layoutScene then scene._layoutScene() end
        return
    end

    syncComposerUserIdIfNeeded(userId)
    billing.setUserId(tonumber(userId))

    if not billing.isReady() then
        paywallLog("startPurchase blocked: billing not ready")
        setStatus("Subscription is still loading from " .. storeName() .. "...")
        if scene._layoutScene then scene._layoutScene() end
        return
    end

    local product = billing.getProduct()
    if not product then
        paywallLog("startPurchase blocked: no product returned from billing")
        setStatus("Subscription product not found in " .. storeName() .. ".")
        if scene._layoutScene then scene._layoutScene() end
        return
    end

    paywallLog(
        "startPurchase proceeding",
        "productIdentifier=", tostring(product.productIdentifier),
        "localizedPrice=", tostring(product.localizedPrice)
    )

    setButtonsEnabled(false)
    setStatus("Opening secure " .. storeName() .. " checkout...")
    if scene._layoutScene then scene._layoutScene() end

    billing.purchase(function(result)
        if not scene.view or not statusText then
            paywallLog("purchase callback aborted because scene/view missing")
            return
        end

        paywallLog(
            "purchase callback",
            "success=", tostring(result and result.success),
            "active=", tostring(result and result.active),
            "cancelled=", tostring(result and result.cancelled),
            "error=", tostring(result and result.error)
        )

        local function showFailure()
            setButtonsEnabled(true)

            if result and result.cancelled then
                paywallLog("purchase result: cancelled")
                setStatus(tr("paywall_status_purchase_cancelled", "Purchase cancelled."))
            elseif result and result.error then
                paywallLog("purchase result: failed with error", tostring(result.error))
                setStatus(trf("paywall_status_purchase_failed_with_error", "Purchase failed: %s", tostring(result.error)))
            else
                paywallLog("purchase result: failed without explicit error")
                setStatus(tr("paywall_status_purchase_failed", "Purchase failed."))
            end

            if scene._layoutScene then scene._layoutScene() end
        end

        if result and result.success then
            paywallLog("purchase result: success, unlocking locally")
            setButtonsEnabled(true)
            unlockPremiumLocally(result)
            setStatus(tr("paywall_status_verified", "Premium active. Subscription verified."))
            if scene._layoutScene then scene._layoutScene() end
            return
        end

        paywallLog("purchase failed, doing fallback entitlement check")

        billing.checkEntitlement(function(checkResult)
            if not scene.view or not statusText then
                paywallLog("fallback entitlement check aborted because scene/view missing")
                return
            end

            paywallLog(
                "fallback entitlement check result",
                "success=", tostring(checkResult and checkResult.success),
                "active=", tostring(checkResult and checkResult.active),
                "error=", tostring(checkResult and checkResult.error),
                "status=", tostring(checkResult and checkResult.data and checkResult.data.status)
            )

            if checkResult.success and checkResult.active then
                setButtonsEnabled(true)
                unlockPremiumLocally(checkResult)
                setStatus(tr("paywall_status_verified", "Premium active. Subscription verified."))
            else
                showFailure()
                return
            end

            if scene._layoutScene then scene._layoutScene() end
        end)
    end)
end

local function restorePurchases()
    local userId = getResolvedUserId()
    paywallLog("restorePurchases tapped", "userId=", tostring(userId), "store=", storeName())

    if not userId then
        paywallLog("restorePurchases blocked: no userId")
        setStatus(tr("paywall_status_login_first", "Please log in first."))
        if scene._layoutScene then scene._layoutScene() end
        return
    end

    syncComposerUserIdIfNeeded(userId)
    billing.setUserId(tonumber(userId))

    setButtonsEnabled(false)
    setStatus("Restoring purchases from " .. storeName() .. "...")
    if scene._layoutScene then scene._layoutScene() end

    if billing.restorePurchases then
        paywallLog("restorePurchases using billing.restorePurchases")

        billing.restorePurchases(function(result)
            if not scene.view or not statusText then
                paywallLog("restore callback aborted because scene/view missing")
                return
            end

            paywallLog(
                "restore callback",
                "success=", tostring(result and result.success),
                "active=", tostring(result and result.active),
                "cancelled=", tostring(result and result.cancelled),
                "error=", tostring(result and result.error)
            )

            setButtonsEnabled(true)

            if result and result.success then
                paywallLog("restore result: success, unlocking locally")
                unlockPremiumLocally(result)
                setStatus(tr("paywall_status_restored", "Premium active. Subscription restored."))
                if scene._layoutScene then scene._layoutScene() end
                return
            end

            paywallLog("restore not immediately successful, doing fallback entitlement check")

            billing.checkEntitlement(function(checkResult)
                if not scene.view or not statusText then
                    paywallLog("restore fallback entitlement check aborted because scene/view missing")
                    return
                end

                paywallLog(
                    "restore fallback entitlement check result",
                    "success=", tostring(checkResult and checkResult.success),
                    "active=", tostring(checkResult and checkResult.active),
                    "error=", tostring(checkResult and checkResult.error),
                    "status=", tostring(checkResult and checkResult.data and checkResult.data.status)
                )

                if checkResult.success and checkResult.active then
                    unlockPremiumLocally(checkResult)
                    setStatus(tr("paywall_status_restored", "Premium active. Subscription restored."))
                elseif checkResult.success then
                    setStatus(tr("paywall_status_not_found", "No active subscription found."))
                else
                    setStatus(trf("paywall_status_restore_failed_with_error", "Could not restore subscription: %s", tostring(checkResult.error or "unknown error")))
                end

                setButtonsEnabled(true)
                if scene._layoutScene then scene._layoutScene() end
            end)
        end)
    else
        paywallLog("restorePurchases falling back to billing.checkEntitlement only")

        billing.checkEntitlement(function(result)
            if not scene.view or not statusText then
                paywallLog("restore fallback-only entitlement check aborted because scene/view missing")
                return
            end

            paywallLog(
                "restore fallback-only entitlement result",
                "success=", tostring(result and result.success),
                "active=", tostring(result and result.active),
                "error=", tostring(result and result.error),
                "status=", tostring(result and result.data and result.data.status)
            )

            setButtonsEnabled(true)

            if result.success and result.active then
                unlockPremiumLocally(result)
                setStatus(tr("paywall_status_restored", "Premium active. Subscription restored."))
            elseif result.success then
                setStatus(tr("paywall_status_not_found", "No active subscription found."))
            else
                setStatus(trf("paywall_status_restore_failed_with_error", "Could not restore subscription: %s", tostring(result.error or "unknown error")))
            end

            if scene._layoutScene then scene._layoutScene() end
        end)
    end
end

------------------------------------------------------------
-- Scene Create
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view

    paywallLog("scene:create", "platform=", tostring(platformName), "store=", storeName())

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    background = newAspectFillImage(sceneGroup, "settings-background.png")
    if background then background:toBack() end

    --------------------------------------------------------
    -- Header
    --------------------------------------------------------
    local hitSize       = math.max(math.floor(display.contentHeight * 0.085), 64)
    local iconSize      = math.max(math.floor(display.contentHeight * 0.048), 40)
    local baseTitleSize = clamp(math.floor(display.contentHeight * 0.050), 44, 72)

    local header = StandardHeader.new(sceneGroup, {
        titleKey      = "subscribe",
        fallbackTitle = "Subscribe",
        backIconImage = "icons/back.png",
        hitSize       = hitSize,
        iconSize      = iconSize,
        titleFontSize = baseTitleSize,
        onBack = function()
            paywallLog("paywall back tapped")
            local userId = getResolvedUserId()
            if not userId then
                composer.gotoScene("menu", { effect = "slideRight", time = 250 })
            else
                composer.gotoScene("settings", { effect = "slideRight", time = 250 })
            end
        end
    })
    self._header = header

    local function fitHeaderTitle()
        if not header or not header.title then return end
        local pad = 16
        local currentSafeW = display.safeActualContentWidth or display.contentWidth
        local maxTitleW = currentSafeW - (hitSize * 2) - (pad * 2)
        fitTextToWidth(header.title, maxTitleW, 0.70)
    end
    self._fitHeaderTitle = fitHeaderTitle
    fitHeaderTitle()

    --------------------------------------------------------
    -- Text shadows
    --------------------------------------------------------
    titleShadow = display.newText({
        parent = sceneGroup,
        text = tr("paywall_title", "1 Month Free Trial"),
        x = display.contentCenterX + 2,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.048)
    })
    titleShadow:setFillColor(unpack(SHADOW))

    priceShadow = display.newText({
        parent = sceneGroup,
        text = tr("paywall_price_default", "1 month free, then $9.99/month"),
        x = display.contentCenterX + 2,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.029)
    })
    priceShadow:setFillColor(unpack(SHADOW))

    cancelShadow = display.newText({
        parent = sceneGroup,
        text = tr("paywall_cancel_anytime", "Cancel anytime through " .. cancelSourceName()),
        x = display.contentCenterX + 2,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.027)
    })
    cancelShadow:setFillColor(unpack(SHADOW))

    benefitShadow = display.newText({
        parent = sceneGroup,
        text = tr("paywall_benefit", "Create and update unlimited classes and levels"),
        x = display.contentCenterX + 2,
        y = 0,
        width = display.contentWidth * 0.90,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.028)
    })
    benefitShadow:setFillColor(unpack(SHADOW))

    statusShadow = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX + 2,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.020)
    })
    statusShadow:setFillColor(unpack(SHADOW))
    statusShadow.isVisible = false

    --------------------------------------------------------
    -- Main copy
    --------------------------------------------------------
    titleText = display.newText({
        parent = sceneGroup,
        text = tr("paywall_title", "1 Month Free Trial"),
        x = display.contentCenterX,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.048)
    })
    titleText:setFillColor(unpack(NAVY_TEXT))

    priceText = display.newText({
        parent = sceneGroup,
        text = tr("paywall_price_default", "1 month free, then $9.99/month"),
        x = display.contentCenterX,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.029)
    })
    priceText:setFillColor(unpack(SUBTEXT))

    cancelText = display.newText({
        parent = sceneGroup,
        text = tr("paywall_cancel_anytime", "Cancel anytime through " .. cancelSourceName()),
        x = display.contentCenterX,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.027)
    })
    cancelText:setFillColor(unpack(SUBTEXT))

    benefitText = display.newText({
        parent = sceneGroup,
        text = tr("paywall_benefit", "Create and update unlimited classes and levels"),
        x = display.contentCenterX,
        y = 0,
        width = display.contentWidth * 0.90,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.028)
    })
    benefitText:setFillColor(unpack(SUBTEXT))

    statusText = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX,
        y = 0,
        width = display.contentWidth * 0.88,
        align = "center",
        font = native.systemFontBold,
        fontSize = math.floor(display.contentHeight * 0.020)
    })
    statusText:setFillColor(unpack(SUBTEXT))
    statusText.isVisible = false

    --------------------------------------------------------
    -- Buttons
    --------------------------------------------------------
    subscribeButton = makeButton(sceneGroup, {
        label       = tr("paywall_start_trial", "Start Free Trial"),
        y           = 0,
        fillColor   = colors.subscribeAction,
        strokeColor = colors.subscribeActionBorder,
        textColor   = colors.textOnPrimary or { 1, 1, 1 },
        onTap       = startPurchase,
        width       = display.contentWidth * 0.82,
        height      = display.contentHeight * 0.082,
        fontScale   = 1.0,
        iconText    = "▶"
    })
    subscribeButton:setEnabled(false)

    restoreButton = makeButton(sceneGroup, {
        label       = tr("paywall_restore_purchases", "Restore Purchases"),
        y           = 0,
        fillColor   = BLUE_BUTTON,
        strokeColor = BLUE_BUTTON_STROKE,
        textColor   = BLUE_BUTTON_TEXT,
        onTap       = restorePurchases,
        width       = display.contentWidth * 0.62,
        height      = display.contentHeight * 0.052,
        fontScale   = 0.90,
        strokeWidth = 4,
        iconText    = ""
    })
    restoreButton:setEnabled(false)

    --------------------------------------------------------
    -- Sheep overlay
    --------------------------------------------------------
    sheep = display.newImage(sceneGroup, "sheep-trio.png")
    if sheep then
        local targetW = display.contentWidth * 0.70
        local scale = targetW / sheep.width
        sheep.xScale, sheep.yScale = scale, scale
        sheep.alpha = 0.90
        sheep.anchorY = 0
    end

    --------------------------------------------------------
    -- Layout
    --------------------------------------------------------
    local function layoutScene()
        local left   = display.safeScreenOriginX or 0
        local top    = display.safeScreenOriginY or 0
        local swSafe = display.safeActualContentWidth or display.contentWidth

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

        local centerX = left + swSafe * 0.5
        local maxTextW = math.min(display.contentWidth * 0.90, swSafe * 0.92)
        local blockGap = display.contentHeight * 0.018
        local sectionGap = display.contentHeight * 0.028
        local baseY = headerBottomY + display.contentHeight * 0.055

        if titleText then
            titleText.width = maxTextW
            titleText.x = centerX
            titleText.y = baseY
            fitTextToWidth(titleText, maxTextW, 0.72)
            syncShadow(titleShadow, titleText, 2, 2)
        end

        local nextY = baseY + effectiveHeight(titleText) * 0.5 + blockGap

        if priceText then
            priceText.width = maxTextW
            priceText.x = centerX
            priceText.y = nextY + effectiveHeight(priceText) * 0.5
            fitTextToWidth(priceText, maxTextW, 0.78)
            syncShadow(priceShadow, priceText, 2, 2)
            nextY = priceText.y + effectiveHeight(priceText) * 0.5 + blockGap
        end

        if cancelText then
            cancelText.width = maxTextW
            cancelText.x = centerX
            cancelText.y = nextY + effectiveHeight(cancelText) * 0.5
            fitTextToWidth(cancelText, maxTextW, 0.80)
            syncShadow(cancelShadow, cancelText, 2, 2)
            nextY = cancelText.y + effectiveHeight(cancelText) * 0.5 + blockGap
        end

        if benefitText then
            benefitText.width = maxTextW
            benefitText.x = centerX
            benefitText.y = nextY + effectiveHeight(benefitText) * 0.5
            fitTextToWidth(benefitText, maxTextW, 0.78)
            syncShadow(benefitShadow, benefitText, 2, 2)
            nextY = benefitText.y + effectiveHeight(benefitText) * 0.5 + sectionGap
        end

        if subscribeButton then
            subscribeButton.x = centerX
            subscribeButton.y = nextY + (subscribeButton._btnHeight * 0.5)
            if subscribeButton.fitLabel then subscribeButton.fitLabel() end
            nextY = subscribeButton.y + (subscribeButton._btnHeight * 0.5) + sectionGap
        end

        if restoreButton then
            restoreButton.x = centerX
            restoreButton.y = nextY + (restoreButton._btnHeight * 0.5)
            if restoreButton.fitLabel then restoreButton.fitLabel() end
            nextY = restoreButton.y + (restoreButton._btnHeight * 0.5) + blockGap
        end

        if statusText then
            statusText.width = maxTextW
            statusText.x = centerX
            if statusText.isVisible then
                statusText.y = nextY + effectiveHeight(statusText) * 0.5
                fitTextToWidth(statusText, maxTextW, 0.78)
                syncShadow(statusShadow, statusText, 2, 2)
                nextY = statusText.y + effectiveHeight(statusText) * 0.5 + sectionGap
            else
                statusText.y = nextY
                if statusShadow then
                    statusShadow.y = nextY + 2
                end
            end
        end

        if sheep and sheep.removeSelf then
            local targetW = display.contentWidth * 0.70
            local scale = targetW / sheep.width
            sheep.xScale, sheep.yScale = scale, scale
            sheep.x = centerX

            local sheepTop = nextY + display.contentHeight * 0.010
            local maxBottom = (display.safeScreenOriginY or 0) + (display.safeActualContentHeight or display.contentHeight) - display.contentHeight * 0.03
            local sheepHeight = sheep.height * sheep.yScale
            local clampedTop = math.min(sheepTop, maxBottom - sheepHeight)
            sheep.y = clampedTop
        end

        if background then background:toBack() end
        if sheep then sheep:toFront() end
        if self._header and self._header.group then self._header.group:toFront() end

        if titleShadow then titleShadow:toFront() end
        if priceShadow then priceShadow:toFront() end
        if cancelShadow then cancelShadow:toFront() end
        if benefitShadow then benefitShadow:toFront() end
        if statusShadow and statusShadow.isVisible then statusShadow:toFront() end

        if titleText then titleText:toFront() end
        if priceText then priceText:toFront() end
        if cancelText then cancelText:toFront() end
        if benefitText then benefitText:toFront() end
        if statusText and statusText.isVisible then statusText:toFront() end

        if subscribeButton then subscribeButton:toFront() end
        if restoreButton then restoreButton:toFront() end
    end

    self._layoutScene = layoutScene
    layoutScene()
end
scene:addEventListener("create", scene)

------------------------------------------------------------
-- Show / Hide / Destroy
------------------------------------------------------------
function scene:show(event)
    if event.phase == "did" then
        local userId = getResolvedUserId()
        syncComposerUserIdIfNeeded(userId)

        paywallLog(
            "scene:show did",
            "userId=", tostring(userId),
            "platform=", tostring(platformName),
            "store=", storeName()
        )

        if self._layoutScene then
            self._layoutScene()
        end

        setCancelLine(tr("paywall_cancel_anytime", "Cancel anytime through " .. cancelSourceName()))

        if not self._onResize then
            self._onResize = function()
                if self._layoutScene then
                    self._layoutScene()
                end
            end
            Runtime:addEventListener("resize", self._onResize)
        end

        setButtonsEnabled(false)
        setStatus("")

        if not userId then
            paywallLog("scene:show no logged in user; showing login-first state")
            setPriceLine(tr("paywall_price_default", "1 month free, then $9.99/month"))
            setStatus(tr("paywall_status_login_first", "Please log in first."))
            if self._layoutScene then self._layoutScene() end
            return
        end

        billing.setUserId(tonumber(userId))
        billing.init()

        paywallLog(
            "scene:show billing initialized",
            "isReady=", tostring(billing.isReady()),
            "hasProduct=", tostring(billing.getProduct() ~= nil)
        )

        setPriceLine("Loading subscription from " .. storeName() .. "...")
        setStatus("")
        if self._layoutScene then self._layoutScene() end

        local attempts = 0
        local maxAttempts = 20

        if refreshTimer then
            timer.cancel(refreshTimer)
            refreshTimer = nil
        end

        refreshTimer = timer.performWithDelay(500, function()
            if not scene.view or not priceText then
                paywallLog("refresh timer aborted because scene/view missing")
                return
            end

            attempts = attempts + 1

            paywallLog(
                "refresh timer tick",
                "attempt=", tostring(attempts),
                "isReady=", tostring(billing.isReady()),
                "hasProduct=", tostring(billing.getProduct() ~= nil)
            )

            if billing.isReady() then
                timer.cancel(refreshTimer)
                refreshTimer = nil

                paywallLog("billing became ready during refresh polling")

                updateProductUI()
                refreshEntitlementUI()
                if scene._layoutScene then scene._layoutScene() end
                return
            end

            if attempts >= maxAttempts then
                timer.cancel(refreshTimer)
                refreshTimer = nil

                paywallLog("billing did not become ready before timeout")

                if billing.getProduct() then
                    paywallLog("timeout path still has product; updating product UI")
                    updateProductUI()
                else
                    paywallLog("timeout path no product available; showing failure state")
                    setPriceLine(tr("paywall_status_product_not_found_short", "Subscription product not found."))
                    setStatus(storeName() .. " product details could not be loaded.")
                    if restoreButton and restoreButton.setEnabled then
                        restoreButton:setEnabled(true)
                    end
                end

                if scene._layoutScene then scene._layoutScene() end
            end
        end, 0)
    end
end
scene:addEventListener("show", scene)

function scene:hide(event)
    if event.phase == "will" then
        paywallLog("scene:hide will")

        if self._onResize then
            Runtime:removeEventListener("resize", self._onResize)
            self._onResize = nil
        end

        if refreshTimer then
            timer.cancel(refreshTimer)
            refreshTimer = nil
        end
    end
end
scene:addEventListener("hide", scene)

function scene:destroy(event)
    paywallLog("scene:destroy")

    if self._onResize then
        Runtime:removeEventListener("resize", self._onResize)
        self._onResize = nil
    end

    if refreshTimer then
        timer.cancel(refreshTimer)
        refreshTimer = nil
    end

    if sheep and sheep.removeSelf then
        sheep:removeSelf()
        sheep = nil
    end

    if background and background.removeSelf then
        background:removeSelf()
        background = nil
    end

    titleText = nil
    titleShadow = nil
    priceText = nil
    priceShadow = nil
    cancelText = nil
    cancelShadow = nil
    benefitText = nil
    benefitShadow = nil
    statusText = nil
    statusShadow = nil
    subscribeButton = nil
    restoreButton = nil
end
scene:addEventListener("destroy", scene)

return scene
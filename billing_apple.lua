--------------------------------------------------------
-- billing_apple.lua
-- Smart Sheep Creator Apple subscription helper
--------------------------------------------------------

local M = {}

local json = require("json")
local network = require("network")
local store = require("plugin.apple.iap")

--------------------------------------------------------
-- Config
--------------------------------------------------------

local PRODUCT_ID = "smartsheepcreator_monthly"

local BACKEND_BASE = "https://infoshagame.com"
local ENDPOINT_ACTIVATE = BACKEND_BASE .. "/user/list/Subscription.php/activateApple"
local ENDPOINT_CHECK = BACKEND_BASE .. "/user/list/Subscription.php/status"
local ENDPOINT_DEBUG_SETTINGS = BACKEND_BASE .. "/user/list/DebugSettings.php/status"

local BILLING_VERSION = "apple-1.1.0"

--------------------------------------------------------
-- State
--------------------------------------------------------

local isInitialized = false
local isProductLoaded = false
local currentProduct = nil
local currentUserId = nil
local remoteDebugEnabled = false
local lastEntitlement = nil

local pendingPurchaseCallback = nil
local pendingRestoreCallback = nil
local isInitInProgress = false
local isRestoreInProgress = false

--------------------------------------------------------
-- Helpers
--------------------------------------------------------

local function getIosBundleId()
    return tostring(system.getInfo("bundleID") or "com.infoshagame.smartsheepcreator")
end

local function urlEncode(str)
    str = tostring(str or "")
    str = str:gsub("\n", " ")
    str = str:gsub("\r", " ")
    str = str:gsub("([^%w %-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
    return str
end

local function debugLog(...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end

    local msg = table.concat(parts, " ")
    print(os.date("%Y-%m-%d %H:%M:%S") .. " userId=" .. tostring(currentUserId or "") .. " " .. msg)

    if not remoteDebugEnabled then
        return
    end

    network.request(
        BACKEND_BASE .. "/debug.php?msg=" .. urlEncode(msg) ..
        "&userId=" .. urlEncode(currentUserId or ""),
        "GET"
    )
end

local function safeCallback(cb, payload)
    if cb then
        cb(payload)
    end
end

local function httpPostJson(url, bodyTable, callback)
    local function listener(event)
        if event.isError then
            debugLog("HTTP ERROR:", url, event.errorMessage)

            callback({
                success = false,
                error = event.errorMessage or "network error",
                rawResponse = event.response
            })
            return
        end

        local status = event.status or 0

        debugLog("HTTP status:", url, status)
        debugLog("HTTP raw response:", event.response)

        if status < 200 or status >= 300 then
            callback({
                success = false,
                error = "HTTP " .. tostring(status),
                rawResponse = event.response
            })
            return
        end

        local ok, data = pcall(json.decode, event.response or "")
        if not ok then
            callback({
                success = false,
                error = "invalid JSON response",
                rawResponse = event.response
            })
            return
        end

        callback({
            success = true,
            data = data
        })
    end

    local params = {
        headers = {
            ["Content-Type"] = "application/json",
        },
        body = json.encode(bodyTable or {})
    }

    debugLog("POST url:", url)
    debugLog("POST body:", params.body)

    network.request(url, "POST", listener, params)
end

local function mapStatusToClientResponse(data)
    local active = (data and data.active == true) or false
    local status = data and data.status or "UNKNOWN"
    local subscriptionRequired = (data and data.subscriptionRequired == true) or false

    return {
        success = true,
        active = active,
        needsSubscription = subscriptionRequired,
        isPreview = (status == "FREE_ACCESS"),
        source = data and data.entitlementSource or nil,
        data = data
    }
end

local function finishTransactionSafe(transaction)
    if transaction then
        pcall(function()
            store.finishTransaction(transaction)
        end)
    end
end

local function clearPurchaseState()
    pendingPurchaseCallback = nil
end

local function clearRestoreState()
    pendingRestoreCallback = nil
    isRestoreInProgress = false
end

local function extractSignedValue(transaction, ...)
    local keys = { ... }

    for i = 1, #keys do
        local key = keys[i]
        local value = transaction and transaction[key]
        if value ~= nil and value ~= "" then
            return value
        end
    end

    return nil
end

--------------------------------------------------------
-- Public debug wrapper
--------------------------------------------------------

function M.logDebug(...)
    debugLog(...)
end

--------------------------------------------------------
-- Backend activation
--------------------------------------------------------

function M.activateApplePurchase(purchaseData, callback)
    debugLog("billing.activateApplePurchase called")

    if not currentUserId then
        safeCallback(callback, {
            success = false,
            error = "No logged in userId set for billing"
        })
        return
    end

    purchaseData = purchaseData or {}

    local signedTransactionInfo = purchaseData.signedTransactionInfo
    local signedRenewalInfo = purchaseData.signedRenewalInfo
    local productId = purchaseData.productId or PRODUCT_ID
    local bundleId = purchaseData.bundleId or getIosBundleId()
    local reason = purchaseData.reason or "purchase"

    debugLog("activateApplePurchase reason:", reason)
    debugLog("activateApplePurchase bundleId:", tostring(bundleId))
    debugLog("activateApplePurchase productId:", tostring(productId))
    debugLog("activateApplePurchase hasSignedTransactionInfo:", tostring(signedTransactionInfo ~= nil and signedTransactionInfo ~= ""))
    debugLog("activateApplePurchase hasSignedRenewalInfo:", tostring(signedRenewalInfo ~= nil and signedRenewalInfo ~= ""))

    if not signedTransactionInfo or signedTransactionInfo == "" then
        safeCallback(callback, {
            success = false,
            error = "Missing signedTransactionInfo"
        })
        return
    end

    httpPostJson(ENDPOINT_ACTIVATE, {
        userId = currentUserId,
        bundleId = bundleId,
        productId = productId,
        signedTransactionInfo = signedTransactionInfo,
        signedRenewalInfo = signedRenewalInfo,
        billingVersion = BILLING_VERSION,
        platform = "ios",
        store = "apple",
        reason = reason
    }, function(result)
        if not result.success then
            debugLog("Apple activation backend error:", result.error)

            safeCallback(callback, {
                success = false,
                error = result.error,
                rawResponse = result.rawResponse
            })
            return
        end

        debugLog("Apple activation success")
        debugLog("Apple activation backend active:", tostring(result.data and result.data.active))
        debugLog("Apple activation backend status:", tostring(result.data and result.data.status))
        debugLog("Apple activation backend planCode:", tostring(result.data and result.data.planCode))
        debugLog("Apple activation backend currentPeriodEnd:", tostring(result.data and result.data.currentPeriodEnd))

        M.checkEntitlement(function(entitlement)
            debugLog("Post-activation entitlement refresh success:", tostring(entitlement and entitlement.success))
            debugLog("Post-activation entitlement active:", tostring(entitlement and entitlement.active))
            safeCallback(callback, entitlement)
        end)
    end)
end

--------------------------------------------------------
-- Product loading
--------------------------------------------------------

local function onProductsLoaded(event)
    debugLog("onProductsLoaded called")

    if not event then
        debugLog("Product load event was nil")
        isProductLoaded = false
        currentProduct = nil
        return
    end

    if event.isError then
        debugLog("Product load error:", tostring(event.errorMessage or "unknown"))
        isProductLoaded = false
        currentProduct = nil
        return
    end

    local products = event.products or {}
    debugLog("Product count:", #products)

    if #products > 0 then
        currentProduct = products[1]
        isProductLoaded = true

        debugLog("Loaded productIdentifier:", tostring(currentProduct.productIdentifier))
        debugLog("Loaded title:", tostring(currentProduct.title))
        debugLog("Loaded localizedPrice:", tostring(currentProduct.localizedPrice))
        debugLog("Loaded price:", tostring(currentProduct.price))
        debugLog("Loaded description:", tostring(currentProduct.description))
    else
        currentProduct = nil
        isProductLoaded = false
        debugLog("No Apple products returned")
    end

    if event.invalidProducts then
        for i = 1, #event.invalidProducts do
            debugLog("Invalid product:", tostring(event.invalidProducts[i]))
        end
    end
end

--------------------------------------------------------
-- Transaction listener
--------------------------------------------------------

local function handleActivatedTransaction(transaction, callback, reason)
    local signedTransactionInfo = extractSignedValue(
        transaction,
        "signedTransactionInfo",
        "signedTransaction",
        "transactionReceipt",
        "receipt"
    )

    local signedRenewalInfo = extractSignedValue(
        transaction,
        "signedRenewalInfo",
        "renewalInfo"
    )

    debugLog("handleActivatedTransaction reason:", tostring(reason))
    debugLog("handleActivatedTransaction productIdentifier:", tostring(transaction and transaction.productIdentifier))
    debugLog("handleActivatedTransaction identifier:", tostring(transaction and transaction.identifier))
    debugLog("handleActivatedTransaction originalIdentifier:", tostring(transaction and transaction.originalIdentifier))
    debugLog("handleActivatedTransaction hasSignedTransactionInfo:", tostring(signedTransactionInfo ~= nil and signedTransactionInfo ~= ""))
    debugLog("handleActivatedTransaction hasSignedRenewalInfo:", tostring(signedRenewalInfo ~= nil and signedRenewalInfo ~= ""))

    if not signedTransactionInfo then
        debugLog("Missing signed transaction info on transaction object")
        finishTransactionSafe(transaction)
        safeCallback(callback, {
            success = false,
            error = "Missing signedTransactionInfo from Apple transaction"
        })
        return
    end

    M.activateApplePurchase({
        productId = transaction.productIdentifier or PRODUCT_ID,
        bundleId = getIosBundleId(),
        signedTransactionInfo = signedTransactionInfo,
        signedRenewalInfo = signedRenewalInfo,
        reason = reason
    }, function(result)
        debugLog("handleActivatedTransaction backend callback success:", tostring(result and result.success))
        debugLog("handleActivatedTransaction backend callback active:", tostring(result and result.active))
        finishTransactionSafe(transaction)
        safeCallback(callback, result)
    end)
end

local function onTransaction(event)
    local transaction = event and event.transaction or nil

    if not transaction then
        debugLog("Transaction event missing transaction object")
        return
    end

    local state = transaction.state
    debugLog("Transaction state:", tostring(state))
    debugLog("Transaction productIdentifier:", tostring(transaction.productIdentifier))
    debugLog("Transaction identifier:", tostring(transaction.identifier))
    debugLog("Transaction originalIdentifier:", tostring(transaction.originalIdentifier))
    debugLog("Transaction errorType:", tostring(transaction.errorType))
    debugLog("Transaction errorString:", tostring(transaction.errorString))
    debugLog("Transaction has signedTransactionInfo:", tostring(transaction.signedTransactionInfo ~= nil and transaction.signedTransactionInfo ~= ""))
    debugLog("Transaction has signedRenewalInfo:", tostring(transaction.signedRenewalInfo ~= nil and transaction.signedRenewalInfo ~= ""))
    debugLog("Transaction has receipt:", tostring(transaction.receipt ~= nil and transaction.receipt ~= ""))
    debugLog("Transaction has transactionReceipt:", tostring(transaction.transactionReceipt ~= nil and transaction.transactionReceipt ~= ""))

    if state == "purchased" then
        local cb = pendingPurchaseCallback
        clearPurchaseState()

        debugLog("Processing purchased transaction")
        handleActivatedTransaction(transaction, cb, "purchase")

    elseif state == "restored" then
        local cb = pendingRestoreCallback or pendingPurchaseCallback
        clearRestoreState()
        clearPurchaseState()

        debugLog("Processing restored transaction")
        handleActivatedTransaction(transaction, cb, "restore")

    elseif state == "failed" or transaction.isError then
        finishTransactionSafe(transaction)

        local cb = pendingPurchaseCallback or pendingRestoreCallback
        local err = transaction.errorString or transaction.errorType or "Apple purchase failed"

        debugLog("Transaction failed:", tostring(err))

        clearPurchaseState()
        clearRestoreState()

        safeCallback(cb, {
            success = false,
            active = false,
            error = err,
            cancelled = false,
            transactionState = state
        })

    elseif state == "cancelled" then
        finishTransactionSafe(transaction)

        local cb = pendingPurchaseCallback or pendingRestoreCallback

        debugLog("Transaction cancelled by user")

        clearPurchaseState()
        clearRestoreState()

        safeCallback(cb, {
            success = false,
            active = false,
            cancelled = true,
            error = "Purchase cancelled",
            transactionState = state
        })

    elseif state == "purchasing" or state == "deferred" then
        debugLog("Transaction pending state:", tostring(state))

    else
        debugLog("Unhandled transaction state:", tostring(state))
    end
end

--------------------------------------------------------
-- Public API
--------------------------------------------------------

function M.setUserId(userId)
    currentUserId = tonumber(userId)
    debugLog("billing.setUserId:", currentUserId)
end

function M.clearUserId()
    debugLog("billing.clearUserId called")

    currentUserId = nil
    remoteDebugEnabled = false
    isInitialized = false
    isProductLoaded = false
    currentProduct = nil
    lastEntitlement = nil
    clearPurchaseState()
    clearRestoreState()
    isInitInProgress = false
end

function M.setRemoteDebugEnabled(enabled)
    remoteDebugEnabled = (enabled == true)
    print("billing.setRemoteDebugEnabled:", tostring(remoteDebugEnabled))
    debugLog("Remote debug enabled:", tostring(remoteDebugEnabled))
end

function M.isRemoteDebugEnabled()
    return remoteDebugEnabled
end

function M.init()
    debugLog("billing.init called")
    debugLog("Package:", getIosBundleId())
    debugLog("BILLING_VERSION:", BILLING_VERSION)
    debugLog("PRODUCT_ID:", PRODUCT_ID)
    debugLog("ENDPOINT_ACTIVATE:", ENDPOINT_ACTIVATE)
    debugLog("Platform:", tostring(system.getInfo("platformName")))
    debugLog("Environment:", tostring(system.getInfo("environment")))
    debugLog("Already initialized:", tostring(isInitialized))
    debugLog("Init in progress:", tostring(isInitInProgress))

    if isInitialized or isInitInProgress then
        debugLog("billing.init skipped because already initialized or in progress")
        return true
    end

    isInitInProgress = true

    local ok, err = pcall(function()
        store.init(onTransaction)
    end)

    if not ok then
        debugLog("store.init failed:", tostring(err))
        isInitialized = false
        isProductLoaded = false
        isInitInProgress = false
        return false
    end

    debugLog("store.init succeeded")

    isInitialized = true
    isInitInProgress = false

    timer.performWithDelay(500, function()
        debugLog("Calling store.loadProducts for PRODUCT_ID:", PRODUCT_ID)

        local okLoad, loadErr = pcall(function()
            store.loadProducts({ PRODUCT_ID }, onProductsLoaded)
        end)

        if not okLoad then
            debugLog("store.loadProducts failed:", tostring(loadErr))
            isProductLoaded = false
            currentProduct = nil
        end
    end)

    return true
end

function M.isReady()
    local ready = isInitialized and isProductLoaded and currentProduct ~= nil
    return ready
end

function M.getProduct()
    return currentProduct
end

function M.getProductId()
    return PRODUCT_ID
end

function M.getBundleId()
    return getIosBundleId()
end

function M.getLastEntitlement()
    return lastEntitlement
end

function M.isPreviewActive()
    return lastEntitlement
        and lastEntitlement.success
        and lastEntitlement.isPreview == true
        and lastEntitlement.active == true
end

function M.shouldShowPaywall()
    if not lastEntitlement then
        return false
    end

    return lastEntitlement.active ~= true
        and lastEntitlement.needsSubscription == true
end

function M.purchase(callback)
    debugLog("billing.purchase called")
    debugLog("currentUserId:", tostring(currentUserId))
    debugLog("bundleID:", getIosBundleId())
    debugLog("productId:", PRODUCT_ID)
    debugLog("isInitialized:", tostring(isInitialized))
    debugLog("isProductLoaded:", tostring(isProductLoaded))
    debugLog("hasCurrentProduct:", tostring(currentProduct ~= nil))

    if not currentUserId then
        safeCallback(callback, {
            success = false,
            error = "No logged in userId set for billing"
        })
        return
    end

    if not isInitialized then
        safeCallback(callback, {
            success = false,
            error = "Apple billing not initialized"
        })
        return
    end

    if not isProductLoaded or not currentProduct then
        safeCallback(callback, {
            success = false,
            error = "Apple product not loaded yet"
        })
        return
    end

    pendingPurchaseCallback = callback

    local ok, err = pcall(function()
        store.purchase(PRODUCT_ID)
    end)

    if not ok then
        debugLog("store.purchase failed:", tostring(err))
        clearPurchaseState()
        safeCallback(callback, {
            success = false,
            error = "store.purchase failed: " .. tostring(err)
        })
        return
    end

    debugLog("store.purchase dispatched successfully for:", PRODUCT_ID)
end

function M.restorePurchases(callback)
    debugLog("billing.restorePurchases called")
    debugLog("currentUserId:", tostring(currentUserId))
    debugLog("isInitialized:", tostring(isInitialized))
    debugLog("isRestoreInProgress:", tostring(isRestoreInProgress))

    if not currentUserId then
        safeCallback(callback, {
            success = false,
            error = "No logged in userId set for billing"
        })
        return
    end

    if not isInitialized then
        safeCallback(callback, {
            success = false,
            error = "Apple billing not initialized"
        })
        return
    end

    if isRestoreInProgress then
        safeCallback(callback, {
            success = false,
            error = "Restore already in progress"
        })
        return
    end

    isRestoreInProgress = true
    pendingRestoreCallback = callback

    local ok, err = pcall(function()
        store.restore()
    end)

    if not ok then
        debugLog("store.restore failed:", tostring(err))
        clearRestoreState()
        safeCallback(callback, {
            success = false,
            error = "store.restore failed: " .. tostring(err)
        })
        return
    end

    debugLog("store.restore dispatched successfully")
end

function M.checkEntitlement(callback)
    debugLog("billing.checkEntitlement")
    debugLog("currentUserId:", tostring(currentUserId))
    debugLog("bundleID:", getIosBundleId())

    if not currentUserId then
        local result = {
            success = false,
            active = false,
            needsSubscription = true,
            error = "No logged in userId set for billing"
        }
        lastEntitlement = result
        callback(result)
        return
    end

    httpPostJson(ENDPOINT_CHECK, {
        userId = currentUserId,
        packageName = getIosBundleId(),
        platform = "ios",
        store = "apple",
        productId = PRODUCT_ID
    }, function(result)
        if not result.success then
            debugLog("Entitlement backend error:", result.error)

            local response = {
                success = false,
                active = false,
                needsSubscription = true,
                error = result.error
            }
            lastEntitlement = response
            callback(response)
            return
        end

        local mapped = mapStatusToClientResponse(result.data or {})
        lastEntitlement = mapped

        debugLog("Entitlement success")
        debugLog("active:", tostring(mapped.active))
        debugLog("status:", tostring(mapped.data and mapped.data.status))
        debugLog("source:", tostring(mapped.source))
        debugLog("subscriptionRequired:", tostring(mapped.data and mapped.data.subscriptionRequired))
        debugLog("freeAccessEndsAt:", tostring(mapped.data and mapped.data.freeAccessEndsAt))
        debugLog("currentPeriodEnd:", tostring(mapped.data and mapped.data.currentPeriodEnd))

        callback(mapped)
    end)
end

function M.refreshDebugSettings(callback)
    debugLog("billing.refreshDebugSettings")
    debugLog("currentUserId:", tostring(currentUserId))

    if not currentUserId then
        if callback then
            callback({
                success = false,
                error = "No logged in userId set for billing"
            })
        end
        return
    end

    httpPostJson(ENDPOINT_DEBUG_SETTINGS, {
        userId = currentUserId
    }, function(result)
        if not result.success then
            debugLog("Debug settings backend error:", result.error)

            if callback then
                callback({
                    success = false,
                    error = result.error,
                    rawResponse = result.rawResponse
                })
            end
            return
        end

        local data = result.data or {}
        remoteDebugEnabled = (data.remoteLoggingEnabled == true)

        print("billing.setRemoteDebugEnabled:", tostring(remoteDebugEnabled))
        debugLog("Debug settings loaded")
        debugLog("remoteLoggingEnabled:", tostring(data.remoteLoggingEnabled))
        debugLog("expiresAt:", tostring(data.expiresAt))

        if callback then
            callback({
                success = true,
                data = data
            })
        end
    end)
end

return M
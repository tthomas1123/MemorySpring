--------------------------------------------------------
-- billing_google.lua
-- Smart Sheep Creator Google Play subscription helper
--------------------------------------------------------

local M = {}

local store = require("plugin.google.iap.billing.v2")
local json = require("json")
local network = require("network")
local timer = require("timer")

--------------------------------------------------------
-- Config
--------------------------------------------------------

local PRODUCT_ID = "smartsheepcreator"
local SUBSCRIPTION_ID = "smartsheepcreator"

local BACKEND_BASE = "https://infoshagame.com"
local ENDPOINT_ACTIVATE = BACKEND_BASE .. "/user/list/Subscription.php/activate"
local ENDPOINT_CHECK = BACKEND_BASE .. "/user/list/Subscription.php/status"
local ENDPOINT_DEBUG_SETTINGS = BACKEND_BASE .. "/user/list/DebugSettings.php/status"

local BILLING_VERSION = "google-1.0.0"
local MAX_LOAD_RETRIES = 2
local LOAD_RETRY_DELAY_MS = 2000

--------------------------------------------------------
-- State
--------------------------------------------------------

local isInitialized = false
local isProductLoaded = false
local isLoadingProducts = false
local currentProducts = {}
local onPurchaseResult = nil
local currentUserId = nil
local remoteDebugEnabled = false
local loadRetryCount = 0

--------------------------------------------------------
-- Helpers
--------------------------------------------------------

local function getAndroidPackageName()
   -- return "com.infoshagame.sscreator"
    return tostring(system.getInfo("androidAppPackageName") or "")
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

local function decodeOriginalPurchaseJson(originalJson)
    if not originalJson or originalJson == "" then
        return nil, "originalJson missing"
    end

    local ok, decoded = pcall(json.decode, originalJson)
    if not ok or type(decoded) ~= "table" then
        return nil, "failed to decode originalJson"
    end

    return decoded, nil
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

local function handleLoadProductsResult(e)
    print("LOADPRODUCTS CALLBACK FIRED")
    print("LOADPRODUCTS isError:", tostring(e and e.isError))
    print("LOADPRODUCTS errorType:", tostring(e and e.errorType))
    print("LOADPRODUCTS errorString:", tostring(e and e.errorString))

    debugLog("loadProducts callback")
    debugLog("requested PRODUCT_ID:", PRODUCT_ID)
    debugLog("loadProducts isError:", tostring(e and e.isError))
    debugLog("loadProducts errorType:", tostring(e and e.errorType))
    debugLog("loadProducts errorString:", tostring(e and e.errorString))

    if e and e.products and #e.products > 0 then
        print("LOADPRODUCTS count:", #e.products)
        debugLog("e.products count:", #e.products)

        currentProducts = e.products
        isProductLoaded = true
        loadRetryCount = 0

        for i = 1, #currentProducts do
            local p = currentProducts[i]
            print("PRODUCT:", tostring(p.productIdentifier), tostring(p.title), tostring(p.localizedPrice))
            debugLog("Loaded product:", p.productIdentifier, p.title, p.localizedPrice)
        end

        debugLog("isProductLoaded:", tostring(isProductLoaded))
        return
    end

    local count = 0
    if e and e.products then
        count = #e.products
    end

    print("LOADPRODUCTS returned no usable products. count:", count)
    debugLog("LOADPRODUCTS returned no usable products. count:", count)

    if e and e.invalidProducts then
        print("invalidProducts count:", #e.invalidProducts)
        debugLog("invalidProducts count:", #e.invalidProducts)

        for i = 1, #e.invalidProducts do
            print("invalidProduct:", tostring(e.invalidProducts[i]))
            debugLog("invalidProduct:", tostring(e.invalidProducts[i]))
        end
    else
        print("invalidProducts: nil")
        debugLog("invalidProducts: nil")
    end

    currentProducts = {}
    isProductLoaded = false
    debugLog("isProductLoaded:", tostring(isProductLoaded))

    if e and e.isError and loadRetryCount < MAX_LOAD_RETRIES then
        loadRetryCount = loadRetryCount + 1
        debugLog("Retrying loadProducts after error. Attempt:", loadRetryCount, "of", MAX_LOAD_RETRIES)

        timer.performWithDelay(LOAD_RETRY_DELAY_MS, function()
            M.init()
        end)
    end
end

local function loadSubscriptionProducts()
    if isLoadingProducts then
        debugLog("loadSubscriptionProducts skipped: already loading")
        return
    end

    isLoadingProducts = true
    isProductLoaded = false
    currentProducts = {}

    print("CALLING loadProducts FOR:", PRODUCT_ID)
    debugLog("Calling loadProducts for:", PRODUCT_ID)
    debugLog("Subscription ID:", SUBSCRIPTION_ID)

    store.loadProducts(
        { PRODUCT_ID },
        { SUBSCRIPTION_ID },
        function(event)
            isLoadingProducts = false
            handleLoadProductsResult(event)
        end
    )
end

--------------------------------------------------------
-- Store listener
--------------------------------------------------------

local function storeListener(event)
    print("STORE LISTENER EVENT:", tostring(event and event.name))
    debugLog("storeListener event:", event and event.name)

    if not event then
        debugLog("storeListener received nil event")
        return
    end

    if event.name == "init" then
        print("INIT EVENT isError:", tostring(event.isError))
        print("INIT EVENT errorType:", tostring(event.errorType))
        print("INIT EVENT errorString:", tostring(event.errorString))

        if not event.isError then
            print("BILLING INIT SUCCESS")
            debugLog("Billing init success")
            isInitialized = true
            loadSubscriptionProducts()
        else
            print("BILLING INIT ERROR:", tostring(event.errorType), tostring(event.errorString))
            debugLog("Billing init error:", event.errorType, event.errorString)
        end

        return
    end

    if event.name == "storeTransaction" or event.transaction then
        local transaction = event.transaction or event

        debugLog("**************** TRANSACTION EVENT ****************")
        debugLog("transaction.state:", tostring(transaction.state))
        debugLog("transaction.productIdentifier:", tostring(transaction.productIdentifier))
        debugLog("transaction.identifier:", tostring(transaction.identifier))
        debugLog("transaction.errorType:", tostring(transaction.errorType))
        debugLog("transaction.errorString:", tostring(transaction.errorString))
        debugLog("transaction.originalJson:", tostring(transaction.originalJson))
        debugLog("transaction.signature:", tostring(transaction.signature))
        debugLog("***************************************************")

        local decodedPurchase, decodeError = decodeOriginalPurchaseJson(transaction.originalJson)
        local purchaseToken = decodedPurchase and decodedPurchase.purchaseToken or nil
        local packageName = decodedPurchase and decodedPurchase.packageName or nil
        local orderId = decodedPurchase and decodedPurchase.orderId or nil
        local purchaseTime = decodedPurchase and decodedPurchase.purchaseTime or nil

        if decodedPurchase then
            debugLog("decoded purchaseToken:", tostring(purchaseToken))
            debugLog("decoded packageName:", tostring(packageName))
            debugLog("decoded orderId:", tostring(orderId))
            debugLog("decoded purchaseTime:", tostring(purchaseTime))

            print("PURCHASE TOKEN:", tostring(purchaseToken))
            print("PURCHASE PACKAGE:", tostring(packageName))
            print("PURCHASE ORDER ID:", tostring(orderId))
            print("PURCHASE TIME:", tostring(purchaseTime))
        else
            debugLog("decodeOriginalPurchaseJson error:", tostring(decodeError))
        end

        if transaction.state == "purchased" or transaction.state == "restored" then
            if not currentUserId then
                debugLog("ERROR purchase completed but userId is nil")

                if onPurchaseResult then
                    onPurchaseResult({
                        success = false,
                        error = "No logged in userId set for billing"
                    })
                end

                store.finishTransaction(transaction)
                return
            end

            local purchaseInfo = {
                userId = currentUserId,
                productId = transaction.productIdentifier,
                transactionId = transaction.identifier,
                originalJson = transaction.originalJson,
                signature = transaction.signature,
                purchaseToken = purchaseToken,
                packageName = packageName or getAndroidPackageName(),
                orderId = orderId,
                purchaseTime = purchaseTime
            }

            httpPostJson(ENDPOINT_ACTIVATE, purchaseInfo, function(result)
                if not result.success then
                    debugLog("Backend activate error:", result.error)
                    if result.rawResponse then
                        debugLog("Backend activate raw response:", result.rawResponse)
                    end
                else
                    debugLog("Backend activate success")

                    if result.data then
                        debugLog("Backend activate active:", result.data.active)
                        debugLog("Backend activate status:", result.data.status)
                        debugLog("Backend activate currentPeriodEnd:", result.data.currentPeriodEnd)
                        debugLog("Backend activate planCode:", result.data.planCode)
                        debugLog("Backend activate packageName:", result.data.packageName)
                        debugLog("Backend activate verifiedProductId:", result.data.verifiedProductId)
                    end
                end

                if onPurchaseResult then
                    onPurchaseResult({
                        success = result.success,
                        backendData = result.data,
                        error = result.error,
                        rawResponse = result.rawResponse
                    })
                end

                store.finishTransaction(transaction)
            end)

        elseif transaction.state == "failed" then
            debugLog("Purchase failed:", transaction.errorString)
            debugLog("Purchase errorType:", transaction.errorType)

            if onPurchaseResult then
                onPurchaseResult({
                    success = false,
                    cancelled = (transaction.errorType == "cancelled"),
                    error = transaction.errorString
                })
            end

            store.finishTransaction(transaction)
        else
            debugLog("Unhandled transaction state:", transaction.state)
            store.finishTransaction(transaction)
        end
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
    currentUserId = nil
    remoteDebugEnabled = false
    isInitialized = false
    isProductLoaded = false
    isLoadingProducts = false
    currentProducts = {}
    onPurchaseResult = nil
    loadRetryCount = 0
    debugLog("billing.clearUserId")
end

function M.setRemoteDebugEnabled(enabled)
    remoteDebugEnabled = (enabled == true)
    print("billing.setRemoteDebugEnabled:", tostring(remoteDebugEnabled))
end

function M.isRemoteDebugEnabled()
    return remoteDebugEnabled
end

function M.init()
    print("BILLING INIT ENTER")
    print("PRODUCT_ID:", PRODUCT_ID)
    print("store.isActive:", tostring(store.isActive))
    print("store.canMakePurchases:", tostring(store.canMakePurchases))
    print("isInitialized:", tostring(isInitialized))
    print("isProductLoaded:", tostring(isProductLoaded))

    debugLog("billing.init called")
    debugLog("Package:", getAndroidPackageName())
    debugLog("BILLING_VERSION:", BILLING_VERSION)
    debugLog("PRODUCT_ID:", PRODUCT_ID)
    debugLog("SUBSCRIPTION_ID:", SUBSCRIPTION_ID)
    debugLog("canLoadProducts", tostring(store.canLoadProducts))
    debugLog("store.isActive:", tostring(store.isActive))
    debugLog("store.canMakePurchases:", tostring(store.canMakePurchases))
    debugLog("isInitialized:", tostring(isInitialized))
    debugLog("isProductLoaded:", tostring(isProductLoaded))

    if not isInitialized then
        print("CALLING store.init")
        debugLog("Calling store.init")
        store.init(storeListener)
    else
        print("BILLING ALREADY INITIALIZED")
        debugLog("Billing already initialized")

        if not isProductLoaded then
            print("PRODUCTS NOT LOADED YET, LOADING NOW")
            debugLog("Products not loaded yet, loading now")
            loadSubscriptionProducts()
        end
    end
end

function M.isReady()
    return isInitialized and isProductLoaded
end

function M.getProduct()
    if not isProductLoaded then
        debugLog("getProduct not ready yet")
        return nil
    end

    for i = 1, #currentProducts do
        if currentProducts[i].productIdentifier == PRODUCT_ID then
            return currentProducts[i]
        end
    end

    debugLog("getProduct loaded but matching PRODUCT_ID not found")
    return nil
end

function M.purchase(callback)
    debugLog("billing.purchase called")
    debugLog("isInitialized:", tostring(isInitialized))
    debugLog("isProductLoaded:", tostring(isProductLoaded))
    debugLog("store.canMakePurchases:", tostring(store.canMakePurchases))
    debugLog("currentUserId:", tostring(currentUserId))
    debugLog("packageName:", getAndroidPackageName())

    if not isInitialized then
        if callback then
            callback({ success = false, error = "Billing not initialized" })
        end
        return
    end

    if not isProductLoaded then
        if callback then
            callback({ success = false, error = "Subscription product not loaded yet" })
        end
        return
    end

    if not store.canMakePurchases then
        if callback then
            callback({ success = false, error = "Purchases not allowed" })
        end
        return
    end

    if not currentUserId then
        if callback then
            callback({ success = false, error = "No logged in userId set for billing" })
        end
        return
    end

    onPurchaseResult = callback

    debugLog("Calling store.purchaseSubscription:", PRODUCT_ID)
    store.purchaseSubscription(PRODUCT_ID)
end

function M.checkEntitlement(callback)
    debugLog("billing.checkEntitlement")
    debugLog("currentUserId:", currentUserId)
    debugLog("packageName:", getAndroidPackageName())

    if not currentUserId then
        callback({
            success = false,
            active = false,
            error = "No logged in userId set for billing"
        })
        return
    end

    httpPostJson(ENDPOINT_CHECK, {
        userId = currentUserId,
        packageName = getAndroidPackageName()
    }, function(result)
        if not result.success then
            debugLog("Entitlement backend error:", result.error)

            callback({
                success = false,
                active = false,
                error = result.error
            })
            return
        end

        local data = result.data or {}
        local active = (data.active == true)

        debugLog("Entitlement success")
        debugLog("active:", active)
        debugLog("status:", data.status)
        debugLog("appCode:", data.appCode)
        debugLog("planCode:", data.planCode)
        debugLog("currentPeriodEnd:", data.currentPeriodEnd)

        callback({
            success = true,
            active = active,
            data = data
        })
    end)
end

function M.refreshDebugSettings(callback)
    debugLog("billing.refreshDebugSettings")
    debugLog("currentUserId:", currentUserId)

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
        M.setRemoteDebugEnabled(data.remoteLoggingEnabled == true)

        debugLog("Debug settings loaded")
        debugLog("remoteLoggingEnabled:", data.remoteLoggingEnabled)
        debugLog("expiresAt:", data.expiresAt)

        if callback then
            callback({
                success = true,
                data = data
            })
        end
    end)
end

return M
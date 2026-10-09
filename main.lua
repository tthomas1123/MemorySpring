-- Memory Spring prototype entry point. Legacy SmartSheep flow remains below for rollback.
local MEMORY_SPRING_LOCAL_PROTOTYPE = true
if MEMORY_SPRING_LOCAL_PROTOTYPE then
    display.setStatusBar(display.HiddenStatusBar)
    require("composer").gotoScene("memorySpringHome")
    return
end

------------------------------------------------------------
-- main.lua
-- SmartSheep Main Entry with Localization + Entitlement Init
------------------------------------------------------------

------------------------------------------------------------
-- Core Requires
------------------------------------------------------------
local composer = require("composer")
local json = require("json")
local sqlite3 = require("sqlite3")

-- Localization modules
local languages = require("languages")
local languageLoader = require("languageLoader")

-- Shared app modules
local appState = require("appState")
local billing = require("billing")
local entitlement = require("entitlement")

------------------------------------------------------------
-- Display and Audio Setup
------------------------------------------------------------
display.setStatusBar(display.HiddenStatusBar)
math.randomseed(os.time())

audio.reserveChannels(1)
audio.setVolume(0.5, { channel = 1 })

------------------------------------------------------------
-- File Setup
------------------------------------------------------------
filePath = system.pathForFile("share.json", system.DocumentsDirectory)

------------------------------------------------------------
-- Database Setup
------------------------------------------------------------
local path = system.pathForFile("data.db", system.DocumentsDirectory)
local path2 = system.pathForFile("data2.db", system.DocumentsDirectory)
local path3 = system.pathForFile("data3.db", system.DocumentsDirectory)
local path4 = system.pathForFile("data4.db", system.DocumentsDirectory)

local db = sqlite3.open(path)
local db2 = sqlite3.open(path2)
local db3 = sqlite3.open(path3)
local db4 = sqlite3.open(path4)

local ownerSetup = [[
CREATE TABLE IF NOT EXISTS Owner (
    OwnerID INTEGER PRIMARY KEY autoincrement,
    FirstName,
    LastName,
    email,
    phone
);
]]
db:exec(ownerSetup)

local verseSetup = [[
CREATE TABLE IF NOT EXISTS Levels (
    LevelID INTEGER PRIMARY KEY autoincrement,
    Title,
    Text
);
]]
db3:exec(verseSetup)

local recallSetup = [[
CREATE TABLE IF NOT EXISTS RECALL (
    SOSID INTEGER PRIMARY KEY autoincrement,
    OwnerID,
    LevelID,
    RECALL
);
]]
db2:exec(recallSetup)

if (db and db:isopen()) then db:close() end
if (db2 and db2:isopen()) then db2:close() end
if (db3 and db3:isopen()) then db3:close() end
if (db4 and db4:isopen()) then db4:close() end

------------------------------------------------------------
-- Localization Initialization
------------------------------------------------------------
local savedUserId = system.getPreference("app", "userId", "string")
local savedUserName = system.getPreference("app", "userName", "string")
local savedLang   = system.getPreference("app", "language", "string")
local savedEmail  = system.getPreference("app", "email", "string")

if savedLang and savedLang ~= "" then
    languages.setLanguage(savedLang)
else
    languages.setLanguage("en")
end

------------------------------------------------------------
-- Navigation helper
------------------------------------------------------------
local function gotoMenu(userIdValue, emailValue)
    local options = {
        params = {
            user = userIdValue,
            name = emailValue or ""
        }
    }

    composer.gotoScene("menu", options)
end

------------------------------------------------------------
-- Continue App Flow
------------------------------------------------------------
if savedUserId and savedUserId ~= "" then
    composer.setVariable("userId", savedUserId)
    composer.setVariable("email", savedEmail or "")

    appState.set({
        userId = tonumber(savedUserId),
        userName = savedUserName or ""
    })

    billing.setUserId(tonumber(savedUserId))

    languageLoader.loadUserLanguage(savedUserId, function(lang)
        lang = lang or "en"

        languages.setLanguage(lang)
        system.setPreferences("app", { language = lang })

        print("🌍 Language set globally to: " .. lang)

        ------------------------------------------------------------
        -- Refresh entitlement through shared module
        ------------------------------------------------------------
        entitlement.refresh(function(result)
            if result.success then
                local data = result.data or {}

                print("ENTITLEMENT active:", tostring(data.active))
                print("ENTITLEMENT status:", tostring(data.status))
                print("ENTITLEMENT source:", tostring(data.entitlementSource))
                print("ENTITLEMENT endsAt:", tostring(data.currentPeriodEnd or data.freeAccessEndsAt))
            else
                print("ENTITLEMENT failed:", tostring(result.error))
                print("ENTITLEMENT using cached/local appState if available")
            end

            gotoMenu(savedUserId, savedEmail)
        end)
    end)
else
    print("⚠️ No saved user ID found — defaulting to English and login screen.")
    languages.setLanguage("en")
    composer.gotoScene("menu")
end

------------------------------------------------------------
-- End of main.lua
------------------------------------------------------------
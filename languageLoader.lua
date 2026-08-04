-- languageLoader.lua

local json = require("json")
local languages = require("languages")

local M = {}

function M.loadUserLanguage(userId, callback)
    local savedLang = system.getPreference("app", "language", "string")
    local deviceLang = string.sub(system.getPreference("locale", "language") or "en", 1, 2)

    -- Step 1: Try server setting
    local url = "https://www.infoshagame.com/user/list/getUser.php?user=" .. userId
    network.request(url, "GET", function(event)
        if not event.isError and event.response then
            local data = json.decode(event.response)
            if data and data.language then
                print("🌐 Using server language:", data.language)
                languages.setLanguage(data.language)
                system.setPreferences("app", { language = data.language })
                if callback then callback(data.language) end
                return
            end
        end

        -- Step 2: Fallback to saved preference
        if savedLang and savedLang ~= "" then
            print("💾 Using saved language:", savedLang)
            languages.setLanguage(savedLang)
            if callback then callback(savedLang) end
            return
        end

        -- Step 3: Fallback to device language
        print("📱 Using device language:", deviceLang)
        languages.setLanguage(deviceLang)
        if callback then callback(deviceLang) end
    end)
end

return M

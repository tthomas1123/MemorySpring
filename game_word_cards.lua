-- game_word_cards.lua
local composer = require("composer")
local scene = composer.newScene()

local json      = require("json")
local colors    = require("colors")
local languages = require("languages")
local StandardHeader = require("ui.standardHeader")

local TITLE_FONT = native.systemFontBold
local BODY_FONT  = native.systemFont

local S = {
    userId = nil,
    userName = nil,
    prefix = nil,
    levelId = nil,
    title = "",
    theme = "Original",

    background = nil,
    bgTint = nil,
    headerBand = nil,
    topCard = nil,
    instructionText = nil,
    titleText = nil,
    subtitleText = nil,

    levelText = "",
    allWords = {},
    correctWords = {},
    shuffledWords = {},
    cards = {},
    slots = {},
    placedCount = 0,

    pageSize = 15,
    pageIndex = 1,
    totalPages = 1,

    loadHandle = nil,
    isActive = false,
    header = nil,
}

local function tOr(key, fallback)
    if not languages or not languages.t then return fallback end
    local value = languages.t(key)
    if value == nil or value == "" or value == key then return fallback end
    return value
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function safeRect()
    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight
    return safeX, safeY, safeW, safeH
end

local function clearDisplayObjects(list)
    if not list then return end
    for i = #list, 1, -1 do
        local obj = list[i]
        if obj then display.remove(obj) end
        list[i] = nil
    end
end

local function cancelLoad()
    if S.loadHandle then
        pcall(function() network.cancel(S.loadHandle) end)
        S.loadHandle = nil
    end
end

local function urlencode(str)
    if str then
        str = tostring(str)
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

local function splitWords(text)
    local cleaned = tostring(text or "")
    cleaned = cleaned:gsub("[\r\n\t]+", " ")
    cleaned = cleaned:gsub("[%.,!%%?;:%(%)[%]\"“”‘’/\\]", "")
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("^%s+", "")
    cleaned = cleaned:gsub("%s+$", "")

    local words = {}
    for token in cleaned:gmatch("%S+") do
        words[#words + 1] = token
    end
    return words
end

local function normalizedWord(word)
    return tostring(word or ""):lower()
end

local function shuffledCopy(words)
    local out = {}
    for i = 1, #words do
        out[i] = { word = words[i], correctIndex = i }
    end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

local function updateBackground(theme)
    local themeBackgrounds = {
        Mountain = "themes/Mountain-bg.png",
        Maple    = "themes/Maple-bg.png",
        Undersea = "themes/Undersea-bg.png",
        Jungle   = "themes/Jungle-bg.png",
        Sunshine = "themes/sunshine-bg.png",
        Beach    = "themes/Beach-bg.png",
        Original = "themes/Original-bg.png"
    }

    local filename = themeBackgrounds[theme] or themeBackgrounds.Original

    if S.background then
        display.remove(S.background)
        S.background = nil
    end

    local img = display.newImage(scene.view, filename)
    if img then
        local iw, ih = img.width, img.height
        local sw = display.actualContentWidth
        local sh = display.actualContentHeight
        local scale = math.max(sw / iw, sh / ih)
        img.xScale = scale
        img.yScale = scale
        img.x = display.contentCenterX
        img.y = display.contentCenterY
        S.background = img
        S.background:toBack()
    end

    if S.bgTint then S.bgTint:toBack() end
end

local function clearBoard()
    clearDisplayObjects(S.cards)
    clearDisplayObjects(S.slots)
    S.placedCount = 0
end

local function getPageWords()
    local pageWords = {}
    local startIndex = ((S.pageIndex - 1) * S.pageSize) + 1
    local endIndex = math.min(startIndex + S.pageSize - 1, #S.allWords)

    for i = startIndex, endIndex do
        pageWords[#pageWords + 1] = S.allWords[i]
    end

    return pageWords, startIndex, endIndex
end

local function findNearestOpenSlot(x, y)
    local bestSlot, bestDist = nil, math.huge
    for i = 1, #S.slots do
        local slot = S.slots[i]
        if slot and not slot._occupied then
            local dx = x - slot.x
            local dy = y - slot.y
            local dist = dx * dx + dy * dy
            if dist < bestDist then
                bestDist = dist
                bestSlot = slot
            end
        end
    end
    return bestSlot, bestDist
end

local function goToSuccess()
    composer.gotoScene("success", {
        effect = "slideLeft",
        time = 220,
        params = {
            user = S.userId,
            name = S.userName,
            prefix = S.prefix,
            level = S.levelId,
            title = S.title,
            theme = S.theme or "Original"
        }
    })
end

local function goBack()
    composer.gotoScene("gameMenu", {
        effect = "slideRight",
        time = 220,
        params = {
            user = S.userId,
            name = S.userName,
            prefix = S.prefix,
            level = S.levelId,
            levelId = S.levelId,
            title = S.title,
            theme = S.theme or "Original"
        }
    })
end

local function checkWin()
    if S.placedCount >= #S.correctWords and #S.correctWords > 0 then
        timer.performWithDelay(350, function()
            if not S.isActive then return end

            if S.pageIndex < S.totalPages then
                S.pageIndex = S.pageIndex + 1
                buildBoard()
            else
                goToSuccess()
            end
        end)
    end
end

local function makeCardTouch(card)
    local function touch(self, event)
        if self._locked then return true end
        local phase = event.phase

        if phase == "began" then
            display.getCurrentStage():setFocus(self, event.id)
            self.isFocus = true
            self._touchId = event.id
            self._dragDX = event.x - self.x
            self._dragDY = event.y - self.y
            self:toFront()
            self._shadow.alpha = 0.18
            self._bg.strokeWidth = 3
            return true
        elseif self.isFocus and self._touchId == event.id then
            if phase == "moved" then
                self.x = event.x - self._dragDX
                self.y = event.y - self._dragDY
                return true
            elseif phase == "ended" or phase == "cancelled" then
                display.getCurrentStage():setFocus(self, nil)
                self.isFocus = false
                self._touchId = nil
                self._shadow.alpha = 0.10
                self._bg.strokeWidth = 2

                local slot, dist = findNearestOpenSlot(self.x, self.y)
                local snapThreshold = math.max(120, (self.width or 0) * 0.9)

                if slot and dist <= (snapThreshold * snapThreshold) then
                    if slot._word == self._word then
                        slot._occupied = true
                        self._slot = slot
                        self._locked = true
                        S.placedCount = S.placedCount + 1
                        transition.to(self, {
                            time = 140,
                            x = slot.x,
                            y = slot.y,
                            transition = easing.outQuad,
                            onComplete = function()
                                self._bg:setFillColor(0.92, 0.97, 1.0, 1)
                                self._bg:setStrokeColor(0.13, 0.45, 0.86, 1)
                            end
                        })
                        checkWin()
                    else
                        transition.to(self, { time = 160, x = self._startX, y = self._startY, transition = easing.outQuad })
                    end
                else
                    transition.to(self, { time = 160, x = self._startX, y = self._startY, transition = easing.outQuad })
                end
                return true
            end
        end
        return false
    end
    card.touch = touch
    card:addEventListener("touch", card)
end

function buildBoard()
    clearBoard()

    local safeX, safeY, safeW, safeH = safeRect()
    local centerX = safeX + safeW * 0.5
    local margin = math.floor(safeW * 0.06)
    local cardW = safeW - (margin * 2)
    local innerLeft = centerX - cardW * 0.5 + 18
    local innerRight = centerX + cardW * 0.5 - 18

    if #S.allWords == 0 then
        S.allWords = splitWords(S.levelText)
    end

    S.totalPages = math.max(1, math.ceil(#S.allWords / S.pageSize))
    S.pageIndex = clamp(S.pageIndex, 1, S.totalPages)

    local words = getPageWords()
    S.correctWords = words
    S.shuffledWords = shuffledCopy(words)

    if #S.allWords == 0 then
        if S.instructionText then
            S.instructionText.text = tOr("no_words_saved", "Add some words first, then preview the game.")
        end
        return
    end

    if S.instructionText then
        local baseInstruction = tOr("drag_words_instruction", "Drag each word card into the correct spot.")
        if S.totalPages > 1 then
            S.instructionText.text = baseInstruction .. "  " ..
                "Screen " .. tostring(S.pageIndex) .. " of " .. tostring(S.totalPages)
        else
            S.instructionText.text = baseInstruction
        end
    end

    local headerBottom = safeY + math.floor(safeH * 0.22)
    local slotsTop = headerBottom + 70

    -- Give the answer slots more space.
    -- Important: do not shrink all 15 slots onto one row; wrap them naturally.
    local slotHeight = 50
    local slotGap = 8
    local rowGap = 12
    local minSlotWidth = 74
    local maxSlotWidth = 122

    local slotWidths, totalWidth = {}, 0
    for i = 1, #words do
        local approx = clamp(26 + (#words[i] * 14), minSlotWidth, maxSlotWidth)
        slotWidths[i] = approx
        totalWidth = totalWidth + approx
    end
    totalWidth = totalWidth + math.max(0, #words - 1) * slotGap

    local availableWidth = cardW - 28

    local rows, rowCount, currentWidth = { {} }, 1, 0
    for i = 1, #words do
        local w = slotWidths[i]
        local projected = currentWidth
        if #rows[rowCount] > 0 then projected = projected + slotGap end
        projected = projected + w
        if projected > availableWidth and #rows[rowCount] > 0 then
            rowCount = rowCount + 1
            rows[rowCount] = {}
            currentWidth = 0
        end
        rows[rowCount][#rows[rowCount] + 1] = { index = i, width = w }
        currentWidth = currentWidth + ((#rows[rowCount] > 1) and slotGap or 0) + w
    end

    local slotY = slotsTop
    for r = 1, #rows do
        local row = rows[r]
        local rowWidth = 0
        for i = 1, #row do rowWidth = rowWidth + row[i].width end
        rowWidth = rowWidth + math.max(0, #row - 1) * slotGap
        local x = centerX - rowWidth * 0.5

        for i = 1, #row do
            local item = row[i]
            x = x + item.width * 0.5
            local slot = display.newGroup()
            scene.view:insert(slot)

            local shadow = display.newRoundedRect(slot, 0, 2, item.width, slotHeight, 14)
            shadow:setFillColor(0, 0, 0, 0.05)
            local box = display.newRoundedRect(slot, 0, 0, item.width, slotHeight, 14)
            box:setFillColor(1, 1, 1, 0.70)
            box.strokeWidth = 2
            box:setStrokeColor(0.13, 0.45, 0.86, 0.25)

            local indexText = display.newText({
                parent = slot, text = tostring(item.index), x = 0, y = 0, font = TITLE_FONT, fontSize = 18
            })
            indexText:setFillColor(0.13, 0.45, 0.86, 0.55)

            slot.x, slot.y = x, slotY
            slot._index = item.index
            slot._word = normalizedWord(words[item.index])
            slot._occupied = false
            S.slots[#S.slots + 1] = slot
            x = x + item.width * 0.5 + slotGap
        end
        slotY = slotY + slotHeight + rowGap
    end

    -- Start the draggable card tray after the slot rows instead of using a fixed Y.
    -- This prevents the slot area and card area from overlapping on smaller screens.
    local cardGap = 10
    local cardHeight = 52
    local trayTop = slotY + 100
    local bottomLimit = safeY + safeH - 42
    if trayTop > bottomLimit - (cardHeight * 2) then
        trayTop = bottomLimit - (cardHeight * 2)
    end
    local rowY = trayTop
    local rowX = innerLeft + 14
    local maxCardWidth = 138

    for i = 1, #S.shuffledWords do
        local entry = S.shuffledWords[i]
        local width = clamp(30 + (#entry.word * 14), 82, maxCardWidth)

        if rowX + width > innerRight - 14 then
            rowX = innerLeft + 14
            rowY = rowY + cardHeight + 10
        end

        local card = display.newGroup()
        scene.view:insert(card)

        local shadow = display.newRoundedRect(card, 0, 3, width, cardHeight, 14)
        shadow:setFillColor(0, 0, 0, 0.10)
        local bg = display.newRoundedRect(card, 0, 0, width, cardHeight, 14)
        bg:setFillColor(1, 1, 1, 1)
        bg.strokeWidth = 2
        bg:setStrokeColor(0.13, 0.45, 0.86, 0.85)

        local label = display.newText({
            parent = card, text = entry.word, x = 0, y = 0, font = TITLE_FONT, fontSize = 20,
            align = "center", width = width - 16
        })
        label:setFillColor(0.13, 0.45, 0.86, 1)

        card.x = rowX + width * 0.5
        card.y = rowY
        card._startX = card.x
        card._startY = card.y
        card._correctIndex = entry.correctIndex
        card._word = normalizedWord(entry.word)
        card._bg = bg
        card._shadow = shadow
        card._locked = false

        makeCardTouch(card)
        S.cards[#S.cards + 1] = card
        rowX = rowX + width + cardGap
    end
end

local function layoutChrome()
    local safeX, safeY, safeW, safeH = safeRect()
    local centerX = safeX + safeW * 0.5
    local margin = math.floor(safeW * 0.05)
    local cardW = safeW - (margin * 2)
    local headerH = math.floor(safeH * 0.11)

    if S.bgTint then
        S.bgTint.width = display.actualContentWidth
        S.bgTint.height = display.actualContentHeight
        S.bgTint.x = display.contentCenterX
        S.bgTint.y = display.contentCenterY
    end

    if S.headerBand then
        S.headerBand.x = centerX
        S.headerBand.y = safeY + headerH * 0.5
        S.headerBand.width = safeW
        S.headerBand.height = headerH
    end

    if S.topCard then
        local cardTop = safeY + headerH + 12
        local cardH = safeH - headerH - 400
        S.topCard.x = centerX
        S.topCard.y = cardTop + cardH * 0.5
        S.topCard.width = cardW
        S.topCard.height = cardH
    end

    if S.titleText then
        S.titleText.x = centerX
        S.titleText.y = safeY + headerH + 38
        S.titleText.width = cardW * 0.84
    end
    if S.subtitleText then
        S.subtitleText.x = centerX
        S.subtitleText.y = safeY + headerH + 72
        S.subtitleText.width = cardW * 0.84
    end
    if S.instructionText then
        S.instructionText.x = centerX
        S.instructionText.y = safeY + headerH + 108
        S.instructionText.width = cardW * 0.86
    end

    if S.header and S.header.group and S.header.group.toFront then
        S.header.group:toFront()
    end
end

local function loadLevelText()
    cancelLoad()

    if not S.userId or not S.prefix or not S.levelId then
        buildBoard()
        return
    end

    local req = "https://infoshagame.com/user/list/getLevelP.php?type=getp"
        .. "&user=" .. urlencode(S.userId)
        .. "&prefix=" .. urlencode(S.prefix)

    S.loadHandle = network.request(req, "GET", function(event)
        S.loadHandle = nil
        if not S.isActive then return end
        if event.isError or not event.response or event.response == "" then
            buildBoard()
            return
        end

        local response = json.decode(event.response)
        if type(response) ~= "table" then
            buildBoard()
            return
        end

        for i = 1, #response do
            local row = response[i]
            if row and tostring(row.LevelID or "") == tostring(S.levelId) and row.Status ~= "deleted" then
                S.levelText = tostring(row.Text or "")
                S.title = tostring(row.Title or S.title or "")
                S.theme = tostring(row.ThemeID or S.theme or "Original")
                updateBackground(S.theme)
                if S.titleText then
                    S.titleText.text = S.title ~= "" and S.title or tOr("word_card_game", "Word Card Game")
                end
                break
            end
        end

        buildBoard()
    end)
end

function scene:create(event)
    local sceneGroup = self.view
    math.randomseed(system.getTimer())

    S.bgTint = display.newRect(sceneGroup, display.contentCenterX, display.contentCenterY,
        display.actualContentWidth, display.actualContentHeight)
    S.bgTint:setFillColor(1, 1, 1, 0.06)
    S.bgTint:toBack()

    S.headerBand = display.newRect(sceneGroup, display.contentCenterX, 0, display.actualContentWidth, 10)
    S.headerBand:setFillColor(1, 1, 1, 0.94)

    S.topCard = display.newRoundedRect(sceneGroup, display.contentCenterX, display.contentCenterY,
        display.contentWidth * 0.90, display.contentHeight * 0.82, 24)
    S.topCard:setFillColor(1, 1, 1, 0.5)
    S.topCard.strokeWidth = 2
    S.topCard:setStrokeColor(0.13, 0.45, 0.86, 0.14)

    S.titleText = display.newText({
        parent = sceneGroup, text = tOr("word_card_game", "Word Card Game"),
        x = display.contentCenterX, y = display.contentCenterY,
        width = display.contentWidth * 0.84, font = TITLE_FONT, fontSize = 42, align = "center",
    })
    S.titleText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    S.subtitleText = display.newText({
        parent = sceneGroup, text = "", x = display.contentCenterX, y = display.contentCenterY,
        width = display.contentWidth * 0.84, font = BODY_FONT, fontSize = 18, align = "center",
    })
    S.subtitleText:setFillColor(0.13, 0.45, 0.86, 0.85)

    S.instructionText = display.newText({
        parent = sceneGroup, text = tOr("drag_words_instruction", "Drag each word card into the correct spot."),
        x = display.contentCenterX, y = display.contentCenterY,
        width = display.contentWidth * 0.86, font = BODY_FONT, fontSize = 28, align = "center",
    })
    S.instructionText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    layoutChrome()
end

function scene:show(event)
    if event.phase == "will" then
        local params = event.params or {}
        S.userId = params.user
        S.userName = params.name
        S.prefix = params.prefix
        S.levelId = params.level
        S.title = params.title or ""
        S.theme = params.theme or "Original"
        S.levelText = ""
        S.allWords = {}
        S.correctWords = {}
        S.shuffledWords = {}
        S.pageIndex = 1
        S.totalPages = 1

        S.isActive = true
        clearBoard()
        updateBackground(S.theme)

        if S.titleText then
            S.titleText.text = S.title ~= "" and S.title or tOr("word_card_game", "Word Card Game")
        end
        if S.subtitleText then
        --    S.subtitleText.text = (tOr("level_label", "Level") .. ": " .. tostring(S.levelId or ""))
        end
    elseif event.phase == "did" then
        if not S.header then
            S.header = StandardHeader.new(self.view, {
                titlePlacement = "back",
                fallbackTitle = "",
                onBack = goBack,
                backIconImage = "icons/back.png",
                titleColor = colors.textPrimary,
            })
        end

        layoutChrome()
        loadLevelText()
    end
end

function scene:hide(event)
    if event.phase == "will" then
        S.isActive = false
        cancelLoad()
    end
end

function scene:destroy(event)
    S.isActive = false
    cancelLoad()
    clearBoard()

    if S.header and S.header.destroy then
        S.header:destroy()
        S.header = nil
    end

    if S.background then display.remove(S.background); S.background = nil end
    if S.bgTint then display.remove(S.bgTint); S.bgTint = nil end
    if S.headerBand then display.remove(S.headerBand); S.headerBand = nil end
    if S.topCard then display.remove(S.topCard); S.topCard = nil end
    if S.titleText then display.remove(S.titleText); S.titleText = nil end
    if S.subtitleText then display.remove(S.subtitleText); S.subtitleText = nil end
    if S.instructionText then display.remove(S.instructionText); S.instructionText = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
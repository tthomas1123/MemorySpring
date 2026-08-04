-- game_progressive_hide_fill.lua
-- Solar2D / Composer Scene
-- Kids read the verse, then progressively hidden words must be typed correctly
-- before the game can advance.

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

    titleText = nil,
    subtitleText = nil,
    instructionText = nil,
    progressText = nil,
    statusText = nil,
    verseGroup = nil,
    nextBtn = nil,
    resetBtn = nil,

    levelText = "",
    words = {},
    hiddenMap = {},
    hiddenOrder = {},
    currentStep = 0,

    chunkSize = 25,
    currentChunk = 1,
    chunkStart = 1,
    chunkEnd = 25,
    showFullVerse = true,

    blankInputs = {},
    blankMeta = {},

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

local function cancelLoad()
    if S.loadHandle then
        pcall(function() network.cancel(S.loadHandle) end)
        S.loadHandle = nil
    end
end

local function clearBlankInputs()
    for i = #S.blankInputs, 1, -1 do
        local input = S.blankInputs[i]
        if input then
            pcall(function() input:removeSelf() end)
        end
        S.blankInputs[i] = nil
    end
    S.blankMeta = {}
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

    -- Fix hidden pasted spaces from websites / Bible apps
    cleaned = cleaned:gsub("\194\160", " ") -- non-breaking space
    cleaned = cleaned:gsub("\226\128\175", " ") -- narrow no-break space

    cleaned = cleaned:gsub("[\r\n\t]+", " ")
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("^%s+", "")
    cleaned = cleaned:gsub("%s+$", "")

    local words = {}
    for token in cleaned:gmatch("%S+") do
        words[#words + 1] = token
    end
    return words
end

local function shuffleIndices(n)
    local idx = {}
    for i = 1, n do idx[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        idx[i], idx[j] = idx[j], idx[i]
    end
    return idx
end

local function updateChunkBounds()
    if #S.words == 0 then
        S.chunkStart = 1
        S.chunkEnd = 0
        return
    end

    S.currentChunk = math.max(1, S.currentChunk or 1)
    S.chunkStart = ((S.currentChunk - 1) * S.chunkSize) + 1
    S.chunkEnd = math.min(S.chunkStart + S.chunkSize - 1, #S.words)
end

local function buildChunkOrder()
    S.hiddenOrder = {}

    if #S.words == 0 then return end
    updateChunkBounds()

    for i = S.chunkStart, S.chunkEnd do
        S.hiddenOrder[#S.hiddenOrder + 1] = i
    end

    for i = #S.hiddenOrder, 2, -1 do
        local j = math.random(i)
        S.hiddenOrder[i], S.hiddenOrder[j] = S.hiddenOrder[j], S.hiddenOrder[i]
    end
end

local function normalizeWord(word)
    return tostring(word or "")
        :lower()
        :gsub("\194\160", " ")
        :gsub("[“”‘’]", "")
        :gsub("^[%s%p]+", "")
        :gsub("[%s%p]+$", "")
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

local function clearVerse()
    clearBlankInputs()
    if S.verseGroup then
        display.remove(S.verseGroup)
        S.verseGroup = nil
    end
end

local function countHiddenInRange(startIdx, endIdx)
    local count = 0
    for i = startIdx or 1, endIdx or #S.words do
        if S.hiddenMap[i] then count = count + 1 end
    end
    return count
end

local function countHidden()
    if S.showFullVerse then
        return 0
    end
    return countHiddenInRange(S.chunkStart, S.chunkEnd)
end

local function activeWordCount()
    if #S.words == 0 then return 0 end
    if S.showFullVerse then return #S.words end
    return math.max(0, S.chunkEnd - S.chunkStart + 1)
end

local function totalChunks()
    if #S.words == 0 then return 0 end
    return math.ceil(#S.words / S.chunkSize)
end

local function updateProgressText()
    if not S.progressText then return end
    if #S.words == 0 then
        S.progressText.text = tOr("no_words_saved", "Add some words first, then preview the game.")
    elseif S.showFullVerse then
        S.progressText.text = tOr("read_full_verse", "Read the full verse, then tap Next to begin.")
    else
        S.progressText.text = "Section " .. tostring(S.currentChunk) .. " / " .. tostring(totalChunks()) ..
            "  •  " .. tostring(countHidden()) .. " / " .. tostring(activeWordCount()) .. " " ..
            tOr("words_hidden", "words hidden")
    end
end

local function setStatus(msg, isError)
    if not S.statusText then return end
    S.statusText.text = msg or ""
    if isError then
        S.statusText:setFillColor(unpack(colors.error or {0.85, 0.2, 0.2}))
    else
        S.statusText:setFillColor(0.13, 0.45, 0.86, 0.95)
    end
end

local function allVisible()
    return S.showFullVerse or countHidden() == 0
end

local function validateBlanks(showError)
    if allVisible() then
        return true
    end

    local allCorrect = true
    for i = 1, #S.blankMeta do
        local meta = S.blankMeta[i]
        local input = meta and meta.input
        local typed = normalizeWord(input and input.text or "")
        local expected = normalizeWord(meta and meta.word or "")
        local correct = (typed == expected and typed ~= "")

        if meta and meta.bg then
            if typed == "" then
                meta.bg:setStrokeColor(0.13, 0.45, 0.86, 0.35)
            elseif correct then
                meta.bg:setStrokeColor(0.22, 0.68, 0.35, 1)
            else
                meta.bg:setStrokeColor(unpack(colors.error or {0.85, 0.2, 0.2}))
            end
        end

        if not correct then
            allCorrect = false
        end
    end

    if showError then
        if allCorrect then
            setStatus(tOr("great_job", "Great job! Tap Next."), false)
        else
            setStatus(tOr("fill_blanks_correctly", "Please fill in each blank correctly before continuing."), true)
        end
    end

    return allCorrect
end

local function layoutVerse()
    clearVerse()

    local safeX, safeY, safeW, safeH = safeRect()
    local centerX = safeX + safeW * 0.5
    local margin = math.floor(safeW * 0.08)
    local maxWidth = safeW - (margin * 2)

    S.verseGroup = display.newGroup()
    scene.view:insert(S.verseGroup)

    if #S.words == 0 then
        local emptyText = display.newText({
            parent = S.verseGroup,
            text = tOr("no_words_saved", "Add some words first, then preview the game."),
            x = centerX,
            y = safeY + safeH * 0.48,
            width = maxWidth,
            font = BODY_FONT,
            fontSize = 24,
            align = "center"
        })
        emptyText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))
        updateProgressText()
        return
    end

    local yStart = safeY + safeH * 0.35
    local lineGap = 18
    local wordGap = 14
    local rowHeight = 52
    local left = safeX + margin
    local x = left
    local y = yStart

    local startIdx = 1
    local endIdx = #S.words

    if not S.showFullVerse then
        updateChunkBounds()
        startIdx = S.chunkStart
        endIdx = S.chunkEnd
    end

    for i = startIdx, endIdx do
        local sourceWord = S.words[i]
        local isHidden = S.hiddenMap[i]

        if isHidden then
            local approxChars = math.max(3, #normalizeWord(sourceWord))
            local blankW = clamp(approxChars * 18 + 24, 90, 220)
            if x + blankW > left + maxWidth then
                x = left
                y = y + rowHeight + lineGap
            end

            local bg = display.newRoundedRect(S.verseGroup, x + blankW * 0.5, y + 1, blankW, 42, 12)
            bg:setFillColor(1, 1, 1, 0.92)
            bg.strokeWidth = 2
            bg:setStrokeColor(0.13, 0.45, 0.86, 0.35)

            local input = native.newTextField(x + blankW * 0.5, y + 1, blankW - 10, 34)
            input.hasBackground = false
            input.font = native.newFont(BODY_FONT, 22)
            input.align = "center"
            input.placeholder = tOr("type_word", "Type word")
            scene.view:insert(input)

            local meta = { index = i, word = sourceWord, input = input, bg = bg }
            S.blankMeta[#S.blankMeta + 1] = meta
            S.blankInputs[#S.blankInputs + 1] = input

            input:addEventListener("userInput", function(event)
                if event.phase == "editing" or event.phase == "ended" or event.phase == "submitted" then
                    validateBlanks(false)
                end
            end)

            x = x + blankW + wordGap
        else
            local token = display.newText({
                parent = S.verseGroup,
                text = sourceWord,
                x = 0,
                y = 0,
                font = TITLE_FONT,
                fontSize = 28,
                align = "left"
            })
            token:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

            local tokenW = token.width
            if x + tokenW > left + maxWidth then
                x = left
                y = y + rowHeight + lineGap
            end

            token.anchorX = 0
            token.anchorY = 0.5
            token.x = x
            token.y = y
            x = x + tokenW + wordGap
        end
    end

    updateProgressText()
end

local function setButtonEnabled(btn, enabled)
    if not btn then return end
    btn._enabled = enabled
    btn.alpha = enabled and 1.0 or 0.45
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

local function updateButtonState()
    if #S.words == 0 then
        setButtonEnabled(S.nextBtn, false)
        setButtonEnabled(S.resetBtn, false)
        return
    end

    setButtonEnabled(S.resetBtn, true)
    setButtonEnabled(S.nextBtn, true)
end

local function advanceToNextChunkOrSuccess()
    if S.chunkEnd >= #S.words then
        goToSuccess()
        return
    end

    S.currentChunk = S.currentChunk + 1
    S.currentStep = 0
    S.hiddenMap = {}
    S.showFullVerse = false
    updateChunkBounds()
    buildChunkOrder()

    if S.nextBtn and S.nextBtn._label then
        S.nextBtn._label.text = tOr("next", "Next")
    end

    layoutVerse()
    updateButtonState()
    setStatus(tOr("next_section_unlocked", "Great job! Next section unlocked."), false)
end

local function hideMoreWords()
    if #S.words == 0 then return end

    if S.showFullVerse then
        S.showFullVerse = false
        S.currentChunk = 1
        S.currentStep = 0
        S.hiddenMap = {}
        updateChunkBounds()
        buildChunkOrder()
    end

    local chunkCount = activeWordCount()
    local hiddenNow = countHidden()

    if hiddenNow >= chunkCount then
        advanceToNextChunkOrSuccess()
        return
    end

    S.currentStep = S.currentStep + 1

    local toHide
    if S.currentStep == 1 then
        toHide = math.min(2, chunkCount - hiddenNow)
    else
        -- Increase by a few words each tap so the player progresses toward a fully blank section.
        toHide = math.min(math.random(3, 5), chunkCount - hiddenNow)
    end

    local hiddenAdded = 0
    for i = 1, #S.hiddenOrder do
        local idx = S.hiddenOrder[i]
        if idx >= S.chunkStart and idx <= S.chunkEnd and not S.hiddenMap[idx] then
            S.hiddenMap[idx] = true
            hiddenAdded = hiddenAdded + 1
            if hiddenAdded >= toHide then break end
        end
    end

    layoutVerse()
    updateButtonState()
    setStatus("", false)

    if countHidden() >= activeWordCount() then
        if S.nextBtn and S.nextBtn._label then
            if S.chunkEnd >= #S.words then
                S.nextBtn._label.text = tOr("finish", "Finish")
            else
                S.nextBtn._label.text = tOr("next_section", "Next Section")
            end
        end
    else
        if S.nextBtn and S.nextBtn._label then
            S.nextBtn._label.text = tOr("next", "Next")
        end
    end
end

local function resetRound()
    S.hiddenMap = {}
    S.currentStep = 0
    S.currentChunk = 1
    S.showFullVerse = true
    updateChunkBounds()
    S.hiddenOrder = {}

    if S.nextBtn and S.nextBtn._label then
        S.nextBtn._label.text = tOr("next", "Next")
    end
    layoutVerse()
    updateButtonState()
    setStatus("", false)
end

local function newButton(parent, label, fillColor, strokeColor, onTap)
    local g = display.newGroup()
    parent:insert(g)

    local bg = display.newRoundedRect(g, 0, 0, 180, 54, 16)
    bg:setFillColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] or 1)
    bg.strokeWidth = 2
    bg:setStrokeColor(strokeColor[1], strokeColor[2], strokeColor[3], strokeColor[4] or 1)

    local txt = display.newText({
        parent = g,
        text = label,
        x = 0,
        y = -1,
        font = TITLE_FONT,
        fontSize = 22
    })
    txt:setFillColor(1, 1, 1, 1)

    g._bg = bg
    g._label = txt
    g._enabled = true

    function g:setSize(w, h)
        self._bg.width = w
        self._bg.height = h
    end

    g:addEventListener("tap", function()
        if not g._enabled then return true end
        if onTap then onTap() end
        return true
    end)

    return g
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
        local cardH = safeH - headerH - 24
        S.topCard.x = centerX
        S.topCard.y = cardTop + cardH * 0.5
        S.topCard.width = cardW
        S.topCard.height = cardH
    end

    if S.titleText then
        S.titleText.x = centerX
        S.titleText.y = safeY + headerH + 36
        S.titleText.width = cardW * 0.84
    end
    if S.subtitleText then
        S.subtitleText.x = centerX
        S.subtitleText.y = safeY + headerH + 70
        S.subtitleText.width = cardW * 0.84
    end
    if S.instructionText then
        S.instructionText.x = centerX
        S.instructionText.y = safeY + headerH + 96
        S.instructionText.width = cardW * 0.84
    end
    if S.progressText then
        S.progressText.x = centerX
        S.progressText.y = safeY + headerH + 150
        S.progressText.width = cardW * 0.84
    end
    if S.statusText then
        S.statusText.x = centerX
        S.statusText.y = safeY + headerH + 265
        S.statusText.width = cardW * 0.84
    end

    if S.nextBtn then
        S.nextBtn.x = centerX + 92
        S.nextBtn.y = safeY + headerH + 210
        S.nextBtn:setSize(176, 54)
    end

    if S.resetBtn then
        S.resetBtn.x = centerX - 92
        S.resetBtn.y = safeY + headerH + 210
        S.resetBtn:setSize(176, 54)
    end

    layoutVerse()

    if S.header and S.header.group and S.header.group.toFront then
        S.header.group:toFront()
    end
end

local function loadLevelText()
    cancelLoad()

    if not S.userId or not S.prefix or not S.levelId then
        S.words = {}
        layoutVerse()
        updateButtonState()
        return
    end

    local req = "https://infoshagame.com/user/list/getLevelP.php?type=getp"
        .. "&user=" .. urlencode(S.userId)
        .. "&prefix=" .. urlencode(S.prefix)

    S.loadHandle = network.request(req, "GET", function(event)
        S.loadHandle = nil
        if not S.isActive then return end

        if event.isError or not event.response or event.response == "" then
            S.words = {}
            layoutVerse()
            updateButtonState()
            return
        end

        local response = json.decode(event.response)
        if type(response) ~= "table" then
            S.words = {}
            layoutVerse()
            updateButtonState()
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
                    S.titleText.text = S.title ~= "" and S.title or tOr("progressive_hide_game", "Hide and Repeat")
                end
                break
            end
        end

        S.words = splitWords(S.levelText)
        if S.instructionText then
            S.instructionText.isVisible = (#S.words >= S.chunkSize)
        end
        resetRound()
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
    S.topCard:setFillColor(1, 1, 1, 0.96)
    S.topCard.strokeWidth = 2
    S.topCard:setStrokeColor(0.13, 0.45, 0.86, 0.14)

    S.titleText = display.newText({
        parent = sceneGroup,
        text = tOr("progressive_hide_game", "Hide and Repeat"),
        x = display.contentCenterX,
        y = display.contentCenterY,
        width = display.contentWidth * 0.84,
        font = TITLE_FONT,
        fontSize = 42,
        align = "center"
    })
    S.titleText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    S.subtitleText = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX,
        y = display.contentCenterY,
        width = display.contentWidth * 0.84,
        font = BODY_FONT,
        fontSize = 18,
        align = "center"
    })
    S.subtitleText:setFillColor(0.13, 0.45, 0.86, 0.85)

    S.instructionText = display.newText({
    parent = sceneGroup,
    text = tOr("repeat_then_type",
        "Read the full verse, then master each 25-word section."),
    x = display.contentCenterX,
    y = display.contentCenterY,
    width = display.contentWidth * 0.84,
    height = 70,          -- add this
    font = BODY_FONT,
    fontSize = 22,
    align = "center"
    })

    S.instructionText.anchorY = 0
    S.instructionText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    S.progressText = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX,
        y = display.contentCenterY,
        width = display.contentWidth * 0.84,
        font = BODY_FONT,
        fontSize = 28,
        align = "center"
    })
    S.progressText:setFillColor(0.13, 0.45, 0.86, 0.95)

    S.statusText = display.newText({
        parent = sceneGroup,
        text = "",
        x = display.contentCenterX,
        y = display.contentCenterY,
        width = display.contentWidth * 0.84,
        font = BODY_FONT,
        fontSize = 22,
        align = "center"
    })
    S.statusText:setFillColor(0.13, 0.45, 0.86, 0.95)

    S.resetBtn = newButton(sceneGroup, tOr("start_over", "Start Over"),
        {0.74, 0.80, 0.90, 1}, {0.60, 0.68, 0.80, 1},
        function() resetRound() end)
    S.resetBtn._label:setFillColor(0.20, 0.28, 0.40, 1)

    S.nextBtn = newButton(sceneGroup, tOr("next", "Next"),
        {0.13, 0.45, 0.86, 1}, {0.10, 0.34, 0.68, 1},
        function()
            if #S.words == 0 then return end
            if not validateBlanks(true) then return end

            if not S.showFullVerse and countHidden() >= activeWordCount() then
                advanceToNextChunkOrSuccess()
            else
                hideMoreWords()
            end
        end)

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
        S.words = {}
        S.hiddenMap = {}
        S.hiddenOrder = {}
        S.currentStep = 0
        S.currentChunk = 1
        S.chunkStart = 1
        S.chunkEnd = S.chunkSize
        S.showFullVerse = true

        S.isActive = true
        updateBackground(S.theme)

        if S.titleText then
            S.titleText.text = S.title ~= "" and S.title or tOr("progressive_hide_game", "Hide and Repeat")
        end
        if S.subtitleText then
       --     S.subtitleText.text = (tOr("level_label", "Level") .. ": " .. tostring(S.levelId or ""))
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
        native.setKeyboardFocus(nil)
    end
end

function scene:destroy(event)
    S.isActive = false
    cancelLoad()
    clearVerse()

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
    if S.progressText then display.remove(S.progressText); S.progressText = nil end
    if S.statusText then display.remove(S.statusText); S.statusText = nil end
    if S.nextBtn then display.remove(S.nextBtn); S.nextBtn = nil end
    if S.resetBtn then display.remove(S.resetBtn); S.resetBtn = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene

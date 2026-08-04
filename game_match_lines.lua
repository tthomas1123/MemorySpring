-- game_match_lines.lua
local composer = require("composer")
local scene = composer.newScene()

local json      = require("json")
local colors    = require("colors")
local languages = require("languages")
local StandardHeader = require("ui.standardHeader")
local TITLE_FONT = native.systemFontBold
local BODY_FONT  = native.systemFont

local S = {
    userId = nil, userName = nil, prefix = nil, levelId = nil, title = "", theme = "Original",
    background = nil, bgTint = nil, headerBand = nil, topCard = nil,
    titleText = nil, subtitleText = nil, instructionText = nil, statusText = nil,
    levelText = "", correctWords = {}, shuffledWords = {},
    leftCards = {}, rightTargets = {}, lines = {}, activeDragLine = nil, startNode = nil,
    loadHandle = nil, isActive = false, matchCount = 0,
    header = nil,

    -- Show the level in smaller chunks so the screen has room.
    allWords = {},
    pageWords = {},
    pageSize = 15,
    pageIndex = 1,
    totalPages = 1,
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

local function getPageWords(allWords, pageIndex)
    local page = {}
    local startIndex = ((pageIndex - 1) * S.pageSize) + 1
    local endIndex = math.min(startIndex + S.pageSize - 1, #allWords)

    for i = startIndex, endIndex do
        page[#page + 1] = allWords[i]
    end

    return page
end

local function rebuildCurrentPage()
    S.pageWords = getPageWords(S.allWords, S.pageIndex)
    S.correctWords = S.pageWords
    S.shuffledWords = shuffledCopy(S.pageWords)
end

local function updateBackground(theme)
    local themeBackgrounds = {
        Mountain = "themes/Mountain-bg.png", Maple = "themes/Maple-bg.png",
        Undersea = "themes/Undersea-bg.png", Jungle = "themes/Jungle-bg.png",
        Sunshine = "themes/sunshine-bg.png", Beach = "themes/Beach-bg.png",
        Original = "themes/Original-bg.png"
    }
    local filename = themeBackgrounds[theme] or themeBackgrounds.Original
    if S.background then display.remove(S.background); S.background = nil end
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

local function updateStatusText()
    if not S.statusText then return end
    if #S.correctWords == 0 then
        S.statusText.text = tOr("no_words_saved", "Add some words first, then preview the game.")
    else
        local pageText = ""
        if S.totalPages and S.totalPages > 1 then
            pageText = "  •  " .. tOr("page_label", "Page") .. " " .. tostring(S.pageIndex) .. " / " .. tostring(S.totalPages)
        end
        S.statusText.text = tostring(S.matchCount) .. " / " .. tostring(#S.correctWords) .. " " ..
            tOr("matches_complete", "matches complete") .. pageText
    end
end

local function clearBoard()
    clearDisplayObjects(S.leftCards)
    clearDisplayObjects(S.rightTargets)
    clearDisplayObjects(S.lines)
    if S.activeDragLine then display.remove(S.activeDragLine); S.activeDragLine = nil end
    S.startNode = nil
    S.matchCount = 0
    updateStatusText()
end

local function goToSuccess()
    composer.gotoScene("success", {
        effect = "slideLeft", time = 220,
        params = { user = S.userId, name = S.userName, prefix = S.prefix, level = S.levelId, title = S.title, theme = S.theme or "Original" }
    })
end

local buildBoard

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
    if #S.correctWords > 0 and S.matchCount >= #S.correctWords then
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

local function setMatchedVisual(node, matched)
    if not node or not node._bg or not node._label then return end
    if matched then
        node._bg:setFillColor(0.92, 0.97, 1.0, 1)
        node._bg:setStrokeColor(0.13, 0.45, 0.86, 1)
    else
        node._bg:setFillColor(1, 1, 1, 1)
        node._bg:setStrokeColor(0.13, 0.45, 0.86, 0.80)
    end
    node._label:setFillColor(0.13, 0.45, 0.86, 1)
    if node._dot then node._dot:setFillColor(0.13, 0.45, 0.86, 1) end
end

local function clearExistingMatchForLeft(leftNode)
    if not leftNode or not leftNode._matchLine then return end
    local line = leftNode._matchLine
    local rightNode = leftNode._matchedTarget
    display.remove(line)
    leftNode._matchLine, leftNode._matchedTarget, leftNode._matched = nil, nil, false
    setMatchedVisual(leftNode, false)
    if rightNode then
        rightNode._matchLine, rightNode._matchedFrom, rightNode._matched = nil, nil, false
        setMatchedVisual(rightNode, false)
    end
    S.matchCount = math.max(0, S.matchCount - 1)
    updateStatusText()
end

local function clearExistingMatchForRight(rightNode)
    if not rightNode or not rightNode._matchLine then return end
    local line = rightNode._matchLine
    local leftNode = rightNode._matchedFrom
    display.remove(line)
    rightNode._matchLine, rightNode._matchedFrom, rightNode._matched = nil, nil, false
    setMatchedVisual(rightNode, false)
    if leftNode then
        leftNode._matchLine, leftNode._matchedTarget, leftNode._matched = nil, nil, false
        setMatchedVisual(leftNode, false)
    end
    S.matchCount = math.max(0, S.matchCount - 1)
    updateStatusText()
end

local function makePermanentLine(x1, y1, x2, y2)
    local line = display.newLine(scene.view, x1, y1, x2, y2)
    line.strokeWidth = 6
    line:setStrokeColor(0.13, 0.45, 0.86, 0.95)
    S.lines[#S.lines + 1] = line
    return line
end

local function completeMatch(leftNode, rightNode)
    clearExistingMatchForLeft(leftNode)
    clearExistingMatchForRight(rightNode)
    local line = makePermanentLine(leftNode._dotWorldX, leftNode._dotWorldY, rightNode._dotWorldX, rightNode._dotWorldY)
    leftNode._matchLine, leftNode._matchedTarget, leftNode._matched = line, rightNode, true
    rightNode._matchLine, rightNode._matchedFrom, rightNode._matched = line, leftNode, true
    setMatchedVisual(leftNode, true)
    setMatchedVisual(rightNode, true)
    S.matchCount = S.matchCount + 1
    updateStatusText()
    checkWin()
end

local function findRightTargetAt(x, y)
    for i = 1, #S.rightTargets do
        local node = S.rightTargets[i]
        if node then
            local b = node.contentBounds
            if b and x >= b.xMin and x <= b.xMax and y >= b.yMin and y <= b.yMax then
                return node
            end
        end
    end
    return nil
end

local function onStageTouch(event)
    if not S.startNode then return false end
    if event.phase == "moved" and S.activeDragLine then
        display.remove(S.activeDragLine)
        S.activeDragLine = display.newLine(scene.view, S.startNode._dotWorldX, S.startNode._dotWorldY, event.x, event.y)
        S.activeDragLine.strokeWidth = 5
        S.activeDragLine:setStrokeColor(0.13, 0.45, 0.86, 0.50)
        return true
    elseif event.phase == "ended" or event.phase == "cancelled" then
        local target = findRightTargetAt(event.x, event.y)
        if S.activeDragLine then display.remove(S.activeDragLine); S.activeDragLine = nil end
        if target and S.startNode and target._word == S.startNode._word then
            completeMatch(S.startNode, target)
        end
        S.startNode = nil
        return true
    end
    return false
end

local function beginLineFromLeft(node)
    if not node then return end
    S.startNode = node
    if S.activeDragLine then display.remove(S.activeDragLine); S.activeDragLine = nil end
    S.activeDragLine = display.newLine(scene.view, node._dotWorldX, node._dotWorldY, node._dotWorldX + 1, node._dotWorldY + 1)
    S.activeDragLine.strokeWidth = 5
    S.activeDragLine:setStrokeColor(0.13, 0.45, 0.86, 0.50)
end

local function makeLeftNodeTouch(node)
    local function touch(self, event)
        local phase = event.phase
        if phase == "began" then
            display.getCurrentStage():setFocus(self, event.id)
            self.isFocus = true
            self._touchId = event.id
            beginLineFromLeft(self)
            return true
        elseif self.isFocus and self._touchId == event.id then
            if phase == "moved" then
                if S.activeDragLine then
                    display.remove(S.activeDragLine)
                    S.activeDragLine = display.newLine(scene.view, self._dotWorldX, self._dotWorldY, event.x, event.y)
                    S.activeDragLine.strokeWidth = 5
                    S.activeDragLine:setStrokeColor(0.13, 0.45, 0.86, 0.50)
                end
                return true
            elseif phase == "ended" or phase == "cancelled" then
                display.getCurrentStage():setFocus(self, nil)
                self.isFocus = false
                self._touchId = nil

                local target = findRightTargetAt(event.x, event.y)
                if S.activeDragLine then display.remove(S.activeDragLine); S.activeDragLine = nil end
                if target and target._word == self._word then
                    completeMatch(self, target)
                end
                S.startNode = nil
                return true
            end
        end
        return false
    end

    node.touch = touch
    node:addEventListener("touch", node)
end

local function makeNode(parent, x, y, width, height, text, dotOnRight)
    local node = display.newGroup()
    parent:insert(node)

    local shadow = display.newRoundedRect(node, 0, 3, width, height, 14)
    shadow:setFillColor(0, 0, 0, 0.10)

    local bg = display.newRoundedRect(node, 0, 0, width, height, 14)
    bg:setFillColor(1, 1, 1, 1)
    bg.strokeWidth = 2
    bg:setStrokeColor(0.13, 0.45, 0.86, 0.80)

    local label = display.newText({
        parent = node, text = text, x = 0, y = -1, width = width - 34,
        font = TITLE_FONT, fontSize = 20, align = "center"
    })
    label:setFillColor(0.13, 0.45, 0.86, 1)

    -- Larger invisible hit area makes it easier for kids to grab/tap the card.
    local hitArea = display.newRoundedRect(node, 0, 0, width + 28, height + 24, 18)
    hitArea:setFillColor(1, 1, 1, 0.01)
    hitArea.isHitTestable = true
    hitArea:toBack()

    local dotOffset = dotOnRight and (width * 0.5 - 14) or (-width * 0.5 + 14)
    local dot = display.newCircle(node, dotOffset, 0, 10)
    dot:setFillColor(0.13, 0.45, 0.86, 1)

    node.x, node.y = x, y
    node._bg, node._label, node._dot, node._hitArea = bg, label, dot, hitArea
    node._dotLocalX, node._dotLocalY = dotOffset, 0
    return node
end

buildBoard = function()
    clearBoard()

    local safeX, safeY, safeW, safeH = safeRect()
    local cardW = safeW - (math.floor(safeW * 0.06) * 2)

    if #S.allWords == 0 then
        S.allWords = splitWords(S.levelText)
        S.totalPages = math.max(1, math.ceil(#S.allWords / S.pageSize))
        S.pageIndex = clamp(S.pageIndex or 1, 1, S.totalPages)
    end

    rebuildCurrentPage()
    local words = S.correctWords
    updateStatusText()

    if #words == 0 then
        if S.instructionText then
            S.instructionText.text = tOr("no_words_saved", "Add some words first, then preview the game.")
        end
        return
    end

    if S.instructionText then
        S.instructionText.text = tOr("draw_line_instruction", "Draw a line from each word to its matching spot.")
    end

    local topY = safeY + math.floor(safeH * 0.24)
    local bottomY = safeY + safeH - 42
    local availableH = bottomY - topY
    local rowGap = clamp(math.floor(availableH / math.max(1, #words)), 42, 70)
    local startY = topY + math.floor(rowGap * 0.5)

    local leftX = safeX + math.floor(cardW * 0.24)
    local rightX = safeX + safeW - math.floor(cardW * 0.24)
    local boxW = clamp(math.floor(cardW * 0.34), 128, 186)
    local boxH = clamp(rowGap - 8, 42, 56)

    for i = 1, #S.shuffledWords do
        local entry = S.shuffledWords[i]
        local y = startY + ((i - 1) * rowGap)
        local node = makeNode(scene.view, leftX, y, boxW, boxH, entry.word, true)
        node._correctIndex = entry.correctIndex
        node._word = normalizedWord(entry.word)
        makeLeftNodeTouch(node)
        S.leftCards[#S.leftCards + 1] = node
    end

    for i = 1, #words do
        local y = startY + ((i - 1) * rowGap)
        local node = makeNode(scene.view, rightX, y, boxW, boxH, tostring(i), false)
        node._correctIndex = i
        node._word = normalizedWord(words[i])
        S.rightTargets[#S.rightTargets + 1] = node
    end

    for i = 1, #S.leftCards do
        local node = S.leftCards[i]
        node._dotWorldX = node.x + node._dotLocalX
        node._dotWorldY = node.y + node._dotLocalY
    end
    for i = 1, #S.rightTargets do
        local node = S.rightTargets[i]
        node._dotWorldX = node.x + node._dotLocalX
        node._dotWorldY = node.y + node._dotLocalY
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
        S.instructionText.y = safeY + headerH + 104
        S.instructionText.width = cardW * 0.84
    end
    if S.statusText then
        S.statusText.x = centerX
        S.statusText.y = safeY + headerH + 134
        S.statusText.width = cardW * 0.84
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
                    S.titleText.text = S.title ~= "" and S.title or tOr("line_match_game", "Line Match Game")
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
    S.topCard:setFillColor(1, 1, 1, 0.75)
    S.topCard.strokeWidth = 2
    S.topCard:setStrokeColor(0.13, 0.45, 0.86, 0.14)

    S.titleText = display.newText({
        parent = sceneGroup, text = tOr("line_match_game", "Line Match Game"),
        x = display.contentCenterX, y = display.contentCenterY, width = display.contentWidth * 0.84,
        font = TITLE_FONT, fontSize = 42, align = "center"
    })
    S.titleText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    S.subtitleText = display.newText({
        parent = sceneGroup, text = "", x = display.contentCenterX, y = display.contentCenterY,
        width = display.contentWidth * 0.84, font = BODY_FONT, fontSize = 18, align = "center"
    })
    S.subtitleText:setFillColor(0.13, 0.45, 0.86, 0.85)

    S.instructionText = display.newText({
        parent = sceneGroup, text = tOr("draw_line_instruction", "Draw a line from each word to its matching spot."),
        x = display.contentCenterX, y = display.contentCenterY, width = display.contentWidth * 0.84,
        font = BODY_FONT, fontSize = 28, align = "center"
    })
    S.instructionText:setFillColor(unpack(colors.textPrimary or {0.12, 0.20, 0.30}))

    S.statusText = display.newText({
        parent = sceneGroup, text = "", x = display.contentCenterX, y = display.contentCenterY + 20,
        width = display.contentWidth * 0.84, font = BODY_FONT, fontSize = 24, align = "center"
    })
    S.statusText:setFillColor(0.13, 0.45, 0.86, 0.95)

    layoutChrome()
    Runtime:addEventListener("touch", onStageTouch)
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
        S.pageWords = {}
        S.pageIndex = 1
        S.totalPages = 1

        S.isActive = true
        clearBoard()
        updateBackground(S.theme)

        if S.titleText then
            S.titleText.text = S.title ~= "" and S.title or tOr("line_match_game", "Line Match Game")
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
        if S.activeDragLine then display.remove(S.activeDragLine); S.activeDragLine = nil end
        S.startNode = nil
    end
end

function scene:destroy(event)
    S.isActive = false
    cancelLoad()
    clearBoard()
    Runtime:removeEventListener("touch", onStageTouch)

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
    if S.statusText then display.remove(S.statusText); S.statusText = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
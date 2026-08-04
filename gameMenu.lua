------------------------------------------------------------
-- gameMenu.lua
-- 4 Game Selection Menu
------------------------------------------------------------

local composer = require("composer")
local scene = composer.newScene()

local colors = require("colors")
local languages = require("languages")
local StandardHeader = require("ui.standardHeader")

------------------------------------------------------------
-- State
------------------------------------------------------------
local S = {
    params = {},
    sheep = nil,
    cards = {},

    passedTitleText = nil,
    titleText = nil,
    titleRibbon = nil,

    header = nil,
    gearGroup = nil,
    decoGroup = nil,
    _onResize = nil,
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function setFill(obj, color, alpha)
    if not obj then return end
    alpha = alpha or color[4] or 1
    obj:setFillColor(color[1], color[2], color[3], alpha)
end

local function makeText(parent, text, x, y, size, bold, width)
    local t = display.newText({
        parent = parent,
        text = text,
        x = x,
        y = y,
        width = width,
        font = bold and native.systemFontBold or native.systemFont,
        fontSize = size,
        align = "center"
    })
    t:setFillColor(unpack(colors.textPrimary or {0.2, 0.14, 0.10}))
    return t
end

local function safeRect()
    local safeX = display.safeScreenOriginX or 0
    local safeY = display.safeScreenOriginY or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight
    return safeX, safeY, safeW, safeH
end

local function getSelectedLevelId()
    return tostring(
        (S.params and (
            S.params.levelId
            or S.params.desiredLevel
            or S.params.level
        )) or ""
    )
end

local function getPassedTitle()
    return tostring(
        (S.params and (
            S.params.title
            or S.params.gameTitle
            or S.params.lessonTitle
            or S.params.name
            or S.params.className
        )) or ""
    )
end

local function syncIncomingParams(params)
    S.params = params or S.params or {}
    S.params.levelId = getSelectedLevelId()
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function goBack()
    composer.gotoScene("customize", {
        effect = "slideRight",
        time = 220,
        params = S.params
    })
end

local function gotoSettings()
    composer.gotoScene("settings", {
        effect = "slideLeft",
        time = 220,
        params = {
            returnTo = "gameMenu",
            menuParams = S.params
        }
    })
end

local function launchGame(game)
    if not game or not game.targetScene then return end

    local selectedLevelId = getSelectedLevelId()

    composer.gotoScene(game.targetScene, {
        effect = "slideLeft",
        time = 220,
        params = {
            user = S.params.user,
            name = S.params.name,
            prefix = S.params.prefix,
            className = S.params.className,
            theme = S.params.theme,

            desiredLevel = selectedLevelId,
            level = selectedLevelId,
            levelId = selectedLevelId,

            gameId = game.id,
            gameTitle = game.title,
            useFirstAvailable = false
        }
    })
end

------------------------------------------------------------
-- Decorations
------------------------------------------------------------
local function drawCloud(group, x, y, scale, alpha)
    scale = scale or 1
    alpha = alpha or 0.75

    local c1 = display.newCircle(group, x - 24 * scale, y + 8 * scale, 26 * scale)
    local c2 = display.newCircle(group, x, y, 34 * scale)
    local c3 = display.newCircle(group, x + 30 * scale, y + 10 * scale, 28 * scale)
    local base = display.newRoundedRect(group, x + 3 * scale, y + 23 * scale, 105 * scale, 36 * scale, 18 * scale)

    for _, obj in ipairs({c1, c2, c3, base}) do
        obj:setFillColor(1, 1, 1, alpha)
    end
end

local function drawSpark(group, x, y, s, color)
    local ray1 = display.newLine(group, x - s, y, x + s, y)
    local ray2 = display.newLine(group, x, y - s, x, y + s)

    ray1.strokeWidth = 3
    ray2.strokeWidth = 3

    ray1:setStrokeColor(color[1], color[2], color[3], color[4] or 1)
    ray2:setStrokeColor(color[1], color[2], color[3], color[4] or 1)

    return ray1, ray2
end

local function buildDecorations(parent)
    S.decoGroup = display.newGroup()
    parent:insert(S.decoGroup)

    drawCloud(S.decoGroup, -12, display.contentHeight * 0.23, 0.95, 0.55)
    drawCloud(S.decoGroup, display.contentWidth + 10, display.contentHeight * 0.25, 0.85, 0.55)
end

local function createTitleRibbon(parent)
    local g = display.newGroup()
    parent:insert(g)

    local leftTail = display.newPolygon(g, -128, 0, {
        -24, -17,
        0, 0,
        -24, 17,
        26, 17,
        26, -17
    })
    leftTail:setFillColor(0.58, 0.22, 0.06)

    local rightTail = display.newPolygon(g, 128, 0, {
        24, -17,
        0, 0,
        24, 17,
        -26, 17,
        -26, -17
    })
    rightTail:setFillColor(0.58, 0.22, 0.06)

    local body = display.newRoundedRect(g, 0, 0, 230, 38, 8)
    body:setFillColor(0.86, 0.34, 0.06)

    local shine = display.newRoundedRect(g, 0, -8, 210, 10, 5)
    shine:setFillColor(1, 0.66, 0.22, 0.22)

    return g
end

------------------------------------------------------------
-- Card Icons
------------------------------------------------------------
local function drawBasket(group, x, y)
    local basket = display.newRoundedRect(group, x, y + 18, 78, 34, 10)
    basket:setFillColor(0.95, 0.66, 0.04)

    local lip = display.newRect(group, x, y + 1, 86, 8)
    lip:setFillColor(0.82, 0.64, 0.05)

    local handleL = display.newLine(group, x - 18, y + 1, x - 2, y - 28)
    handleL.strokeWidth = 5
    handleL:setStrokeColor(0.58, 0.47, 0.12)

    local handleR = display.newLine(group, x + 18, y + 1, x + 2, y - 28)
    handleR.strokeWidth = 5
    handleR:setStrokeColor(0.58, 0.47, 0.12)

    local labels = {
        { "the", -30, -44, 0.89, 0.45, 0.12 },
        { "and", 0, -50, 0.42, 0.65, 0.22 },
        { "is", 30, -44, 0.22, 0.38, 0.78 },
    }

    for i = 1, #labels do
        local item = labels[i]
        local chip = display.newRoundedRect(group, x + item[2], y + item[3], 34, 22, 6)
        chip.rotation = (i - 2) * 10
        chip:setFillColor(1, 1, 1)
        chip.strokeWidth = 2
        chip:setStrokeColor(item[4], item[5], item[6])

        local txt = makeText(group, item[1], chip.x, chip.y, 11, true)
        txt:setFillColor(0, 0, 0)
        txt.rotation = chip.rotation
    end
end

local function drawCards(group, x, y)
    local board = display.newRoundedRect(group, x + 8, y - 2, 82, 50, 10)
    board:setFillColor(0.72, 0.48, 0.94)
    board.strokeWidth = 3
    board:setStrokeColor(0.60, 0.35, 0.86)

    for i = -1, 1 do
        local slot = display.newRoundedRect(group, x + 8 + i * 22, y - 2, 18, 36, 5)
        slot:setFillColor(1, 1, 1, 0.22)
        slot.strokeWidth = 2
        slot:setStrokeColor(0.92, 0.79, 1.0, 0.85)
    end

    local c1 = display.newRoundedRect(group, x - 34, y + 10, 35, 47, 7)
    c1.rotation = -8
    c1:setFillColor(1, 1, 1)
    c1.strokeWidth = 2
    c1:setStrokeColor(0.55, 0.38, 0.93)

    local c2 = display.newRoundedRect(group, x + 40, y + 20, 35, 47, 7)
    c2.rotation = 10
    c2:setFillColor(1, 1, 1)
    c2.strokeWidth = 2
    c2:setStrokeColor(0.95, 0.55, 0.07)

    local t1 = makeText(group, "good", c1.x, c1.y, 11, true)
    t1:setFillColor(0.15, 0.33, 0.72)
    t1.rotation = c1.rotation

    local t2 = makeText(group, "day", c2.x, c2.y, 11, true)
    t2:setFillColor(0.89, 0.39, 0.05)
    t2.rotation = c2.rotation
end

local function drawLines(group, x, y)
    local pts = {
        { x, y - 18, "1", {0.27, 0.56, 0.89} },
        { x - 28, y + 10, "2", {0.95, 0.33, 0.39} },
        { x, y + 36, "3", {0.98, 0.66, 0.12} },
        { x + 28, y + 10, "4", {0.53, 0.72, 0.24} },
    }

    local pairs = { {1,2}, {2,3}, {3,4}, {4,1} }

    for i = 1, #pairs do
        local a = pts[pairs[i][1]]
        local b = pts[pairs[i][2]]
        local ln = display.newLine(group, a[1], a[2], b[1], b[2])
        ln.strokeWidth = 4
        ln:setStrokeColor(0.38, 0.61, 0.92, 0.85)
    end

    for i = 1, #pts do
        local p = pts[i]
        local c = display.newCircle(group, p[1], p[2], 15)
        c:setFillColor(unpack(p[4]))
        c.strokeWidth = 3
        c:setStrokeColor(1, 1, 1, 0.95)

        local txt = makeText(group, p[3], p[1], p[2], 14, true)
        txt:setFillColor(1, 1, 1)
    end
end

local function drawVerse(group, x, y)
    local frame = display.newRoundedRect(group, x, y + 10, 104, 60, 10)
    frame.rotation = -5
    frame:setFillColor(0.77, 0.89, 1.0)
    frame.strokeWidth = 3
    frame:setStrokeColor(0.39, 0.66, 0.96)

    local l1 = makeText(group, "lamp to my ___", x, y + 4, 11, true, 86)
    local l2 = makeText(group, "to my ___", x, y + 23, 11, true, 86)

    l1:setFillColor(0.08, 0.12, 0.28)
    l2:setFillColor(0.08, 0.12, 0.28)
    l1.rotation = frame.rotation
    l2.rotation = frame.rotation
end

------------------------------------------------------------
-- Card Factory
------------------------------------------------------------
local CARD_COLORS = {
    basket = {1.00, 0.96, 0.82},
    cards  = {0.95, 0.88, 1.00},
    lines  = {0.90, 0.98, 0.87},
    verse  = {0.88, 0.96, 1.00},
}

local ARROW_COLORS = {
    basket = {1.00, 0.74, 0.05},
    cards  = {0.67, 0.37, 0.94},
    lines  = {0.36, 0.74, 0.28},
    verse  = {0.27, 0.57, 0.92},
}

local function createCard(parent, game)
    local g = display.newGroup()
    parent:insert(g)

    local shadow = display.newRoundedRect(g, 0, 8, 170, 220, 18)
    shadow:setFillColor(0.12, 0.35, 0.72, 0.18)

    local bg = display.newRoundedRect(g, 0, 0, 170, 220, 18)
    bg:setFillColor(1, 1, 1, 0.95)
    bg.strokeWidth = 2

    local wash = display.newRoundedRect(g, 0, -45, 146, 108, 16)
    setFill(wash, CARD_COLORS[game.id] or {0.92, 0.97, 1.0}, 0.78)

    drawSpark(g, -58, -78, 6, {1.0, 0.77, 0.14, 0.85})
    drawSpark(g, 58, -48, 5, {0.47, 0.75, 0.30, 0.75})

    local iconY = -35
    local iconGroup = display.newGroup()
g:insert(iconGroup)

if game.id == "basket" then
    drawBasket(iconGroup, 0, iconY)
elseif game.id == "cards" then
    drawCards(iconGroup, 0, iconY)
elseif game.id == "lines" then
    drawLines(iconGroup, 0, iconY)
elseif game.id == "verse" then
    drawVerse(iconGroup, 0, iconY)
end

-- 🔥 scale up icons
iconGroup.xScale = 1.25
iconGroup.yScale = 1.25

    local title = makeText(g, game.title or "Game", 0, 52, 30, true, 140)
    title:setFillColor(0.04, 0.10, 0.30)

    local subtitle = makeText(g, game.subtitle or "", 0, 100, 22, true, 150)
    subtitle:setFillColor(0.18, 0.18, 0.32) -- darker for contrast

    local arrow = display.newGroup()
    g:insert(arrow)
    arrow.y = 100

    local arrowShadow = display.newCircle(arrow, 0, 4, 20)
    arrowShadow:setFillColor(0, 0, 0, 0.12)

    local arrowBg = display.newCircle(arrow, 0, 0, 20)
    setFill(arrowBg, ARROW_COLORS[game.id] or {0.22, 0.52, 0.95}, 1)

    local arrowLine = display.newLine(arrow, -8, 0, 8, 0, 1, -7)
    arrowLine.strokeWidth = 5
    arrowLine:setStrokeColor(1, 1, 1)

    local arrowLine2 = display.newLine(arrow, 8, 0, 1, 7)
    arrowLine2.strokeWidth = 5
    arrowLine2:setStrokeColor(1, 1, 1)

    local hit = display.newRoundedRect(g, 0, 0, 170, 220, 18)
    hit.isVisible = false
    hit.isHitTestable = true
    hit:addEventListener("tap", function()
    transition.to(g, {
        time = 80,
        xScale = 0.96,
        yScale = 0.96,
        onComplete = function()
            transition.to(g, {
                time = 90,
                xScale = 1,
                yScale = 1,
                onComplete = function()
                    launchGame(game)
                end
            })
        end
    })
    return true
end)

    g._shadow = shadow
    g._bg = bg
    g._wash = wash
    g._arrow = arrow
    g._title = title
    g._subtitle = subtitle
    g._hit = hit

    return g
end

------------------------------------------------------------
-- Layout
------------------------------------------------------------
local function layoutScene()
    local safeX, safeY, safeW, safeH = safeRect()
    local centerX = safeX + safeW * 0.5

    if S.passedTitleText then
        S.passedTitleText.x = centerX
        S.passedTitleText.y = safeY + math.floor(safeH * 0.095)
    end

    if S.titleRibbon then
        S.titleRibbon.x = centerX
        S.titleRibbon.y = safeY + math.floor(safeH * 0.145)
    end

    local outerMargin = 2
    local colGap = 8
    local rowGap = 10

    local titleShadow = makeText(
    S.titleRibbon,
    languages.t("choose_a_game") or "Choose a Game",
    1,
    2,
    24,
    true,
    200
)
titleShadow:setFillColor(0.25, 0.08, 0.02, 0.45)

S.titleText = makeText(
    S.titleRibbon,
    languages.t("choose_a_game") or "Choose a Game",
    0,
    0,
    24,
    true,
    200
)
S.titleText:setFillColor(1, 1, 1)
    local cardW = math.floor((safeW - outerMargin * 2 - colGap) * 0.5)
    local cardH = math.floor(math.min(400, safeH * 0.40))

    local totalW = cardW * 2 + colGap
    local leftX = centerX - totalW * 0.5 + cardW * 0.5
    local rightX = leftX + cardW + colGap

    local startY = safeY + math.floor(safeH * 0.345)

    local positions = {
        { leftX,  startY },
        { rightX, startY },
        { leftX,  startY + cardH + rowGap },
        { rightX, startY + cardH + rowGap },
    }

    for i = 1, #S.cards do
        local card = S.cards[i]
        local p = positions[i]

        if card and p then
            card.x = p[1]
            card.y = p[2]

            card._shadow.width = cardW
            card._shadow.height = cardH

            card._bg.width = cardW
            card._bg.height = cardH

            card._hit.width = cardW
            card._hit.height = cardH

            card._wash.width = math.max(120, cardW - 12)
            card._wash.height = math.floor(cardH * 0.42)

            card._arrow.y = cardH * 0.5 - 40
        end
    end

    if S.sheep then
        S.sheep.x = centerX
        S.sheep.y = safeY + safeH * 0.985
        S.sheep:toFront()
    end

    if S.header and S.header.group and S.header.group.toFront then
        S.header.group:toFront()
    end

    if S.gearGroup then
        S.gearGroup.x = safeX + safeW - 50
        S.gearGroup.y = safeY + 77
        S.gearGroup:toFront()
    end
end

------------------------------------------------------------
-- Scene
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    syncIncomingParams(event.params)

    local bg = display.newRect(
        sceneGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.actualContentWidth,
        display.actualContentHeight
    )
    bg:setFillColor(0.94, 0.97, 1.0)

    buildDecorations(sceneGroup)

    S.passedTitleText = makeText(
        sceneGroup,
        getPassedTitle(),
        display.contentCenterX,
        40,
        18,
        true,
        display.contentWidth * 0.88
    )
    S.passedTitleText:setFillColor(0.04, 0.10, 0.30)

    S.titleRibbon = createTitleRibbon(sceneGroup)

S.titleText = makeText(
    S.titleRibbon, -- 👈 attach to ribbon instead of sceneGroup
    languages.t("choose_a_game") or "Choose a Game",
    0, -- 👈 centered inside ribbon
    0,
    24,
    true,
    200
)
-- white text
S.titleText:setFillColor(1, 1, 1)


    local games = S.params.games or {
        { id = "basket", title = "Catch", subtitle = "Catch the words", targetScene = "game" },
        { id = "cards", title = "Match", subtitle = "Drag words to spot", targetScene = "game_word_cards" },
        { id = "lines", title = "Order", subtitle = "Connect the order", targetScene = "game_match_lines" },
        { id = "verse", title = "Build", subtitle = "Fill missing words", targetScene = "game_progressive_hide_fill" }
    }

    for i = 1, math.min(4, #games) do
        S.cards[i] = createCard(sceneGroup, games[i])
    end

    S.sheep = display.newImage(sceneGroup, "sheep.png")
    if S.sheep then
        local targetW = (display.safeActualContentWidth or display.contentWidth) * 0.24
        local scale = targetW / S.sheep.width
        S.sheep.xScale, S.sheep.yScale = scale, scale
        S.sheep.anchorX = 0.5
        S.sheep.anchorY = 1.0
    end

    layoutScene()
end

function scene:show(event)
    if event.phase == "will" then
        syncIncomingParams(event.params)

        if S.passedTitleText then
            S.passedTitleText.text = getPassedTitle()
        end
    end

    if event.phase == "did" then
        local sceneGroup = self.view

        if not S.header then
            S.header = StandardHeader.new(sceneGroup, {
                titlePlacement = "back",
                fallbackTitle = "",
                onBack = goBack,
                backIconImage = "icons/back.png",
                titleColor = colors.textPrimary,
                backLabelFontSize = 44,
                backLabelGap = 8,
            })
        end

        if not S.gearGroup then
            S.gearGroup = display.newGroup()
            sceneGroup:insert(S.gearGroup)

           
            local gearIcon = display.newImageRect(S.gearGroup, "icons/gear6-blue.png", 64, 64)

            gearIcon.x, gearIcon.y = 0, 0

            local gearHit = display.newRect(S.gearGroup, 0, 0, 80, 80)
            gearHit.isVisible = false
            gearHit.isHitTestable = true
            gearHit:addEventListener("tap", function()
                gotoSettings()
                return true
            end)
        end

        if not S._onResize then
            S._onResize = function()
                layoutScene()
            end
            Runtime:addEventListener("resize", S._onResize)
        end

        layoutScene()
    end
end

function scene:hide(event)
    if event.phase == "will" then
        if S._onResize then
            Runtime:removeEventListener("resize", S._onResize)
            S._onResize = nil
        end
    end
end

function scene:destroy(event)
    if S.header and S.header.destroy then
        S.header:destroy()
        S.header = nil
    end

    if S.gearGroup then
        display.remove(S.gearGroup)
        S.gearGroup = nil
    end

    if S.sheep then
        display.remove(S.sheep)
        S.sheep = nil
    end

    if S.passedTitleText then
        display.remove(S.passedTitleText)
        S.passedTitleText = nil
    end

    if S.titleText then
        display.remove(S.titleText)
        S.titleText = nil
    end

    if S.titleRibbon then
        display.remove(S.titleRibbon)
        S.titleRibbon = nil
    end

    if S.decoGroup then
        display.remove(S.decoGroup)
        S.decoGroup = nil
    end

    for i = 1, #S.cards do
        if S.cards[i] then
            display.remove(S.cards[i])
            S.cards[i] = nil
        end
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
-- game.lua (complete)
-- Creator preview version with SmartSheep adaptive gameplay
-- Keeps:
--  - adaptive gameplay + smart eraser + assist
--  - creator-specific navigation/back flow
-- UI:
--  - StandardHeader back -> customize
--  - Always-visible hint panel under header
--  - Hint button toggles: instruction <-> active 7-word hint chunk
--  - Tap hint panel/text to open full verse modal
--  - Light bottom collection panel + thin dark footer bar above it
-- Gameplay:
--  - Only current 7-word hint chunk spawns
--  - Hint window advances only after the full current chunk is correct
--  - Already collected words do not respawn
--  - Active words do not duplicate
--  - Eraser protection turns on after 50 spawned words
--  - Strict exact-next-word collection turns on after 200 spawned words
--
-- FIXED:
--  - Background now aspect-fills actual screen size
--  - Prevents white bands with letterbox scaling
--  - Modal blocker also covers full actual screen

local composer = require("composer")
local scene    = composer.newScene()

local json             = require("json")
local physics          = require("physics")
local colors           = require("colors")
local widget           = require("widget")
local accessibleButton = require("accessibleButton")
local languages        = require("languages")
local StandardHeader   = require("ui.standardHeader")
local logger           = require("logger")

local user, name, level, classCode, className
local memorySpringSample = false
local useFirstAvailable = false
local requestedLevelId = nil

------------------------------------------------------------
-- Locals / State
------------------------------------------------------------
local versesTable = {}
local myTable
local filePath = system.pathForFile("verses.json", system.DocumentsDirectory)

local ThemeLabel
local LevelID_return
local Text_return
local Prefix_return

local wordsTable        = {}
local verseTextTable    = {}
local expectedWords     = {}
local verseWords        = {}
local activeWordByIndex = {}

local basket
local gameLoopTimer
local originalVerse
local originalTitle
local verse
local backGroup
local mainGroup
local uiGroup
local bottomPanel
local bottomPanelExpanded = false
local lastWord

-- ADAPTIVE: counters
local playCount = 0

-- Smart eraser gating + expected words
local eraserProtectionEnabled = false
local strictCollectionEnabled = false

-- Assist mode
local assistEnabled      = false
local assistLoopCount    = 0
local assistMaxIndex     = 0
local ASSIST_EVERY_LOOPS = 25

-- Hint behavior state

local hintDefaultText = languages.t("hint_instruction") or "Move basket to catch words in order."

local hintShowingVerse    = false
local hintWindowStartIndex = 1
local HINT_WINDOW_SIZE     = 7

-- Hint modal
local hintModalGroup
local hintModalScrollView
local hintModalText

-- Forward declarations
local onCollision
local isCurrentTextCorrectPrefix
local fitCollectedVerseText
local updateCollectedVerseDisplay
local hintPanelTap
local hintPanel, hintText, levelLabel
local hintBasket, hintEraser, hintLegend, hintTap
local EraserWord
local instructionFontSize = 26

local function getEraserSheet()

    local sheetOptions1 =
    {
        frames =
        {
            { x = 0, y = 0, width = 220,  height = 210  },
            { x = 0, y = 0, width = 1300, height = 1010 },
        }
    }

    local eraserFile
    if (ThemeLabel == nil or ThemeLabel == "") then
        eraserFile = "themes/Original-eraser.png"
    else
        eraserFile = "themes/" .. ThemeLabel .. "-eraser.png"
    end

    local imageSheetPath = system.pathForFile(eraserFile, system.ResourceDirectory)
    if imageSheetPath == nil then
        print("⚠️ Could not find eraser file at path: " .. tostring(eraserFile))
        eraserFile = "original/eraser.png"
    end

    return graphics.newImageSheet(eraserFile, sheetOptions1)
end

local function buildHintPanel(params)
    local uiGroup = params.uiGroup
    local headerGroup = params.headerGroup
    local objectSheet2 = params.objectSheet2
    local hintPanelY = params.hintPanelY
    local hintPanelH = params.hintPanelH
    local safeX = params.safeX
    local safeW = params.safeW
    local localizedEraser = params.localizedEraser

    hintPanel = display.newRoundedRect(
        uiGroup,
        safeX + safeW * 0.5,
        hintPanelY,
        safeW * 0.92,
        hintPanelH,
        18
    )
    hintPanel:setFillColor(1, 1, 1, 0.92)
    hintPanel.strokeWidth = 2
    hintPanel:setStrokeColor(0, 0, 0, 0.15)
    hintPanel:addEventListener("tap", hintPanelTap)

    levelLabel = display.newText({
        parent = uiGroup,
        text = tostring(LevelID_return or ""),
        x = hintPanel.x - hintPanel.width * 0.5 + 18,
        y = hintPanel.y - hintPanel.height * 0.33,
        width = hintPanel.width - 36,
        font = native.systemFontBold,
        fontSize = 36,
        align = "left"
    })
    levelLabel.anchorX = 0
    levelLabel:setFillColor(unpack(colors.textOnLight))

    hintBasket = display.newImageRect(uiGroup, objectSheet2, 2, 56, 56)
    hintBasket.anchorX = 0
    hintBasket.anchorY = 0.5
    hintBasket.x = hintPanel.x - hintPanel.width * 0.5 + 18
    hintBasket.y = hintPanel.y - hintPanel.height * 0.10

    hintText = display.newText({
        parent = uiGroup,
        text = hintDefaultText,
        x = hintBasket.x + 64,
        y = hintPanel.y - hintPanel.height * 0.07,
        width = hintPanel.width - 100,
        font = native.systemFont,
        fontSize = instructionFontSize,
        align = "left"
    })
    hintText.anchorX = 0
    hintText:setFillColor(unpack(colors.textOnLight))
    hintText:addEventListener("tap", hintPanelTap)

    local legendY = hintPanel.y + hintPanel.height * 0.28

    hintEraser = display.newImageRect(uiGroup, getEraserSheet(), 1, 72, 72)
    hintEraser.anchorX = 0
    hintEraser.anchorY = 0.5
    hintEraser.x = hintPanel.x - hintPanel.width * 0.5 + 35
    hintEraser.y = legendY - hintPanel.height * 0.04

    local removeHint = string.format(
        languages.t("hint_remove_last_word") or "Catch %s to erase the last word.",
        localizedEraser or "eraser"
    )

    hintLegend = display.newText({
        parent = uiGroup,
        text = removeHint,
        x = hintEraser.x + 52,
        y = legendY - hintPanel.height * 0.14,
        width = hintPanel.width - 100,
        font = native.systemFont,
        fontSize = instructionFontSize,
        align = "left"
    })
    hintLegend.anchorX = 0
    hintLegend.anchorY = 0.5
    hintLegend:setFillColor(unpack(colors.textOnLight))

    if hintLegend.contentHeight > instructionFontSize * 1.6 then
        hintLegend.y = hintLegend.y + 10
    end

    hintTap = display.newText({
        parent = uiGroup,
        text = languages.t("hint_tap_panel") or "Tap this panel to view the verse.",
        x = hintEraser.x + 52,
        y = hintLegend.y + (hintLegend.contentHeight * 0.5) + 30,
        width = hintPanel.width - 100,
        font = native.systemFont,
        fontSize = instructionFontSize,
        align = "left"
    })
    hintTap.anchorX = 0
    hintTap.anchorY = 0.5
    hintTap:setFillColor(unpack(colors.textOnLight))

    if hintLegend.contentHeight > instructionFontSize * 1.6 then
        hintTap.y = hintTap.y - 13
    end

    headerGroup:toFront()
    hintPanel:toFront()
    levelLabel:toFront()
    hintBasket:toFront()
    hintText:toFront()
    hintEraser:toFront()
    hintLegend:toFront()
    hintTap:toFront()
end
------------------------------------------------------------
-- Helpers: safe center / clamp / text fitting / truncation
------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function safeXW()
    local safeX = display.safeScreenOriginX or 0
    local safeW = display.safeActualContentWidth or display.contentWidth
    return safeX, safeW
end

local function safeCenterX()
    local safeX, safeW = safeXW()
    return safeX + safeW * 0.5
end

local function splitWords(s)
    local t = {}
    for w in string.gmatch(s or "", "%S+") do
        t[#t + 1] = w
    end
    return t
end

local function fitTextToHeight(textObj, maxFontSize, minFontSize, maxHeight)
    if not textObj then return end

    maxFontSize = maxFontSize or 42
    minFontSize = minFontSize or 18
    maxHeight   = maxHeight or 200

    local fs = maxFontSize
    textObj.size = fs

    local guard = 0
    while textObj.contentHeight > maxHeight and fs > minFontSize and guard < 60 do
        fs = fs - 1
        textObj.size = fs
        guard = guard + 1
    end
end

local function removeWordObjectFromTables(obj)
    if not obj then return end

    if obj.myName == "word" and obj.wordIndex then
        activeWordByIndex[obj.wordIndex] = nil
    end

    for i = #wordsTable, 1, -1 do
        if wordsTable[i] == obj then
            table.remove(wordsTable, i)
            break
        end
    end
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

------------------------------------------------------------
-- string:split helper
------------------------------------------------------------
function string:split(inSplitPattern)
    local outResults = {}
    local theStart = 1
    local theSplitStart, theSplitEnd = string.find(self, inSplitPattern, theStart)
    while theSplitStart do
        table.insert(outResults, string.sub(self, theStart, theSplitStart - 1))
        theStart = theSplitEnd + 1
        theSplitStart, theSplitEnd = string.find(self, inSplitPattern, theStart)
    end
    table.insert(outResults, string.sub(self, theStart))
    return outResults
end

physics.start()
physics.setGravity(0, 0)

------------------------------------------------------------
-- Smart prefix checks + Assist logic
------------------------------------------------------------
local function getCollectedVerseText()
    return table.concat(verseTextTable, ""):gsub("%s+$", "")
end

isCurrentTextCorrectPrefix = function()
    local typedText  = table.concat(verseTextTable, ""):gsub("%s+$", "")
    local typedWords = splitWords(typedText)

    for i = 1, #typedWords do
        if typedWords[i] ~= (expectedWords[i] or "") then
            return false, #typedWords
        end
    end
    return true, #typedWords
end

local function getCorrectProgress()
    local ok, typedCount = isCurrentTextCorrectPrefix()
    if ok then
        return typedCount
    end
    return 0
end

local function updateHintWindowProgress()
    local progress = getCorrectProgress()
    local oldStart = hintWindowStartIndex

    while progress >= (hintWindowStartIndex + HINT_WINDOW_SIZE - 1)
      and hintWindowStartIndex + HINT_WINDOW_SIZE <= #expectedWords do
        hintWindowStartIndex = hintWindowStartIndex + HINT_WINDOW_SIZE
    end

    if oldStart ~= hintWindowStartIndex then
        logger.scene("game", "updateHintWindowProgress advanced from=", tostring(oldStart), " to=", tostring(hintWindowStartIndex), " progress=", tostring(progress))
    end
end

local function updateAssistState()
    if not eraserProtectionEnabled then
        if assistEnabled or assistLoopCount ~= 0 or assistMaxIndex ~= 0 then
            logger.scene("game", "updateAssistState reset because eraserProtectionEnabled=false")
        end
        assistEnabled   = false
        assistLoopCount = 0
        assistMaxIndex  = 0
        return
    end

    local wasAssistEnabled = assistEnabled
    local prevAssistMaxIndex = assistMaxIndex

    local ok, typedCount = isCurrentTextCorrectPrefix()

    if ok then
        assistEnabled = true
        assistMaxIndex = math.max(assistMaxIndex, typedCount + 1)
    else
        assistEnabled   = false
        assistLoopCount = 0
        assistMaxIndex  = 0
    end

    if wasAssistEnabled ~= assistEnabled or prevAssistMaxIndex ~= assistMaxIndex then
        logger.scene("game", "updateAssistState assistEnabled=", tostring(assistEnabled), " typedCount=", tostring(typedCount), " assistMaxIndex=", tostring(assistMaxIndex))
    end
end

------------------------------------------------------------
-- Navigation
------------------------------------------------------------
local function gotoMemorySpringHome()
    if gameLoopTimer then
        timer.cancel(gameLoopTimer)
        gameLoopTimer = nil
    end
    Runtime:removeEventListener("collision", onCollision)
    physics.pause()
    composer.gotoScene("memorySpringHome", {effect = "slideRight", time = 250})
end

local function gotoCustomize() gotoMemorySpringHome() end
local function gotoSelectLevel() gotoMemorySpringHome() end
local function gotoMenu() gotoMemorySpringHome() end

------------------------------------------------------------
-- Hint modal
------------------------------------------------------------
local function hideHintModal()
    if hintModalGroup then
        logger.scene("game", "hideHintModal")
        display.remove(hintModalGroup)
        hintModalGroup = nil
        hintModalScrollView = nil
        hintModalText = nil
    end
end

local function showHintModal()
    logger.scene("game", "showHintModal levelTitle=", tostring(LevelID_return), " textLen=", tostring(#tostring(Text_return or "")))
    hideHintModal()

    local safeX, safeW = safeXW()
    local safeY = display.safeScreenOriginY or 0
    local safeH = display.safeActualContentHeight or display.contentHeight

    hintModalGroup = display.newGroup()
    uiGroup:insert(hintModalGroup)

    local blocker = display.newRect(
        hintModalGroup,
        display.contentCenterX,
        display.contentCenterY,
        display.actualContentWidth + 40,
        display.actualContentHeight + 40
    )
    blocker:setFillColor(0, 0, 0, 0.45)
    blocker:addEventListener("tap", function()
        logger.scene("game", "hint modal blocker tapped")
        hideHintModal()
        return true
    end)

    local popupW = safeW * 0.88
    local popupH = safeH * 0.68
    local popupX = safeX + safeW * 0.5
    local popupY = safeY + safeH * 0.5

    local popup = display.newRoundedRect(
        hintModalGroup,
        popupX,
        popupY,
        popupW,
        popupH,
        24
    )
    popup:setFillColor(1, 1, 1, 0.97)
    popup.strokeWidth = 2
    popup:setStrokeColor(0, 0, 0, 0.14)
    popup:addEventListener("tap", function() return true end)

    local title = display.newText({
        parent = hintModalGroup,
        text = tostring(LevelID_return or languages.t("hint") or "Hint"),
        x = popupX,
        y = popupY - popupH * 0.5 + 42,
        width = popupW - 140,
        font = native.systemFontBold,
        fontSize = 38,
        align = "center"
    })
    title:setFillColor(unpack(colors.textOnLight))

    local closeBtnW = 72
    local closeBtnH = 52
    local closeBtn = display.newRoundedRect(
        hintModalGroup,
        popupX + popupW * 0.5 - 54,
        popupY - popupH * 0.5 + 42,
        closeBtnW,
        closeBtnH,
        16
    )
    closeBtn:setFillColor(0.92, 0.92, 0.95)

    local closeLabel = display.newText({
        parent = hintModalGroup,
        text = "✕",
        x = closeBtn.x,
        y = closeBtn.y,
        font = native.systemFontBold,
        fontSize = 34
    })
    closeLabel:setFillColor(0.1, 0.1, 0.1)

    local function closeModalTap()
        logger.scene("game", "hint modal close tapped")
        hideHintModal()
        return true
    end
    closeBtn:addEventListener("tap", closeModalTap)
    closeLabel:addEventListener("tap", closeModalTap)

    local bodyTop = popupY - popupH * 0.5 + 82
    local bodyHeight = popupH - 126
    local bodyLeft = popupX - popupW * 0.5 + 18
    local bodyWidth = popupW - 36

    hintModalScrollView = widget.newScrollView({
        left = bodyLeft,
        top = bodyTop,
        width = bodyWidth,
        height = bodyHeight,
        hideBackground = false,
        backgroundColor = { 1, 1, 1, 0.01 },
        horizontalScrollDisabled = true,
        isBounceEnabled = true,
        friction = 0.94
    })
    hintModalGroup:insert(hintModalScrollView)

    local fullVerse = tostring(Text_return or (originalVerse and originalVerse.text) or "")

    local fullVerse = tostring(Text_return or ""):gsub("\n\n+", "\n")

    hintModalText = display.newText({
        text = fullVerse,
        width = bodyWidth - 24,
        font = native.systemFont,
        fontSize = 34,
        align = "left",
        lineHeight = .9
    })
    hintModalText.anchorX = 0
    hintModalText.anchorY = 0
    hintModalText.x = 12
    hintModalText.y = 18
    hintModalText:setFillColor(unpack(colors.textOnLight))
    hintModalScrollView:insert(hintModalText)

    local neededHeight = math.max(bodyHeight, hintModalText.contentHeight + 36)

    if hintModalScrollView.setScrollHeight then
        hintModalScrollView:setScrollHeight(neededHeight)
    else
        local spacer = display.newRect(0, 0, 2, 2)
        spacer.x = bodyWidth * 0.5
        spacer.y = neededHeight - 1
        spacer.isVisible = false
        hintModalScrollView:insert(spacer)
    end

    hintModalGroup:toFront()
end

------------------------------------------------------------
-- Helpers for bottom panel text
------------------------------------------------------------
local function getVerseLineHeight(sampleFontSize)
    if not verse then
        return (sampleFontSize or 42) * 1.25
    end

    local originalText = verse.text
    local originalSize = verse.size

    local probeSize = sampleFontSize or originalSize or 42
    verse.size = probeSize

    verse.text = "Ag\nAg"
    local twoLineHeight = verse.contentHeight

    verse.text = "Ag"
    local oneLineHeight = verse.contentHeight

    verse.text = originalText
    verse.size = originalSize

    local lineHeight = twoLineHeight - oneLineHeight
    if lineHeight <= 0 then
        lineHeight = probeSize * 1.25
    end

    return lineHeight
end

local function buildCollapsedCollectedText(allCollected, maxLines)
    if not verse or not bottomPanel then
        return table.concat(allCollected, " ")
    end

    maxLines = maxLines or 3

    local fullText = table.concat(allCollected, " ")
    if fullText == "" then
        return ""
    end

    local collapsedFontSize = 42
    verse.size = collapsedFontSize

    local actualLineHeight = getVerseLineHeight(collapsedFontSize)
    local maxCollapsedHeight = actualLineHeight * maxLines

    verse.text = fullText
    if verse.contentHeight <= maxCollapsedHeight then
        return fullText, maxCollapsedHeight
    end

    local startIndex = 1
    local bestText = fullText

    while startIndex <= #allCollected do
        local candidate = "... " .. table.concat(allCollected, " ", startIndex, #allCollected)
        verse.text = candidate

        if verse.contentHeight <= maxCollapsedHeight then
            bestText = candidate
            break
        end

        startIndex = startIndex + 1
    end

    return bestText, maxCollapsedHeight
end

fitCollectedVerseText = function(maxHeightOverride)
    if not verse or not bottomPanel then return end

    local maxFontSize = bottomPanelExpanded and 34 or 42
    local minFontSize = bottomPanelExpanded and 16 or 20
    local maxHeight   = maxHeightOverride or (bottomPanel.height - 24)

    verse.size = maxFontSize

    local guard = 0
    while verse.contentHeight > maxHeight and verse.size > minFontSize and guard < 60 do
        verse.size = verse.size - 1
        guard = guard + 1
    end
end

updateCollectedVerseDisplay = function()
    if not verse then return end

    local allCollected = {}
    for i = 1, #verseTextTable do
        local w = tostring(verseTextTable[i] or ""):gsub("%s+$", "")
        if w ~= "" then
            allCollected[#allCollected + 1] = w
        end
    end

    if #allCollected == 0 then
        verse.text = ""
        return
    end

    if bottomPanelExpanded then
        verse.text = table.concat(allCollected, " ")
        fitCollectedVerseText(bottomPanel.height - 24)
        return
    end

    local collapsedText, collapsedMaxHeight = buildCollapsedCollectedText(allCollected, 3)
    verse.text = collapsedText
    fitCollectedVerseText(collapsedMaxHeight)
end

------------------------------------------------------------
-- Hint UI logic
------------------------------------------------------------
local function updateHintDisplay()
    if not hintText or not hintPanel then return end

    if not hintShowingVerse then
        hintText.text = hintDefaultText
        fitTextToHeight(hintText, instructionFontSize, 22, hintPanel.height * 0.60)
        if hintBasket then hintBasket.isVisible = true end
        if hintEraser then hintEraser.isVisible = true end
        if hintLegend then hintLegend.isVisible = true end

        if hintTap then hintTap.isVisible = true end
        return
    end

    local allWords = expectedWords or {}

    if #allWords == 0 then
        hintText.text = ""
        fitTextToHeight(hintText, instructionFontSize, 24, hintPanel.height * 0.60)
        return
    end

    local startIndex = math.max(1, hintWindowStartIndex)
    local endIndex = math.min(startIndex + HINT_WINDOW_SIZE - 1, #allWords)

    local visibleWords = {}
    for i = startIndex, endIndex do
        visibleWords[#visibleWords + 1] = allWords[i]
    end

    local preview = table.concat(visibleWords, " ")
    if endIndex < #allWords then
        preview = preview .. " ..."
    end

    if hintBasket then hintBasket.isVisible = false end
    if hintEraser then hintEraser.isVisible = false end
    if hintLegend then hintLegend.isVisible = false end
    if hintTap then hintTap.isVisible = false end
    hintText.text = preview
    fitTextToHeight(hintText, instructionFontSize, 24, hintPanel.height * 0.60)
end


local function gotoHint()
    hintShowingVerse = not hintShowingVerse
    logger.scene("game", "gotoHint hintShowingVerse=", tostring(hintShowingVerse), " hintWindowStartIndex=", tostring(hintWindowStartIndex))
    updateHintDisplay()
end

local function bottomPanelTap(event)
    bottomPanelExpanded = not bottomPanelExpanded
    logger.scene("game", "bottomPanelTap bottomPanelExpanded=", tostring(bottomPanelExpanded))
    updateCollectedVerseDisplay()
    return true
end

hintPanelTap = function(event)
    if hintShowingVerse then
        logger.scene("game", "hintPanelTap opening modal")
        showHintModal()
    else
        hintShowingVerse = true
        logger.scene("game", "hintPanelTap switching to verse preview")
        updateHintDisplay()
    end
    return true
end

------------------------------------------------------------
-- Word & Flower Spawning
------------------------------------------------------------
local function removeInactiveWindowWords(startIndex, endIndex)
    for idx, obj in pairs(activeWordByIndex) do
        if idx < startIndex or idx > endIndex then
            removeWordObjectFromTables(obj)
            display.remove(obj)
        end
    end
end

local function loadWord(tbl)
    if not tbl or #tbl == 0 then return end

    local progress = getCorrectProgress()
    local spawnWindowSize = 7

    if assistEnabled then
        assistLoopCount = assistLoopCount + 1
        if assistLoopCount >= ASSIST_EVERY_LOOPS then
            assistLoopCount = 0
        end
    end

    local startIndex = progress + 1
    local endIndex   = math.min(startIndex + spawnWindowSize - 1, #tbl)

    if startIndex > #tbl then
        removeInactiveWindowWords(999999, 999999)
        return
    end

    removeInactiveWindowWords(startIndex, endIndex)

    for idx, obj in pairs(activeWordByIndex) do
    if not obj
        or not obj.removeSelf
        or obj.x < -120
        or obj.x > display.contentWidth + 120
        or obj.y < -180
        or obj.y > display.contentHeight + 120
    then
        activeWordByIndex[idx] = nil
        removeWordObjectFromTables(obj)
        display.remove(obj)
    end
end

    for i = startIndex, endIndex do
        local wordData = tbl[i]

        if i <= progress then
            -- already collected: never respawn
        elseif activeWordByIndex[i] and activeWordByIndex[i].removeSelf then
            -- already active on screen: do not duplicate
        elseif wordData and wordData.text ~= "" then
            playCount = playCount + 1

            if playCount == 50 then
                eraserProtectionEnabled = true
                logger.scene("game", "eraserProtectionEnabled true at playCount=50")
            elseif playCount > 50 then
                eraserProtectionEnabled = true
            end

            if playCount == 200 then
                strictCollectionEnabled = true
                logger.scene("game", "strictCollectionEnabled true at playCount=200")
            elseif playCount > 200 then
                strictCollectionEnabled = true
            end

            local newWord = display.newText(wordData.text, 1, 1, native.systemFontBold, 34)
            newWord:setFillColor(0, 0, 0.7)
            mainGroup:insert(newWord)

            physics.addBody(newWord, {
                radius = 18,
                bounce = 1.1,
                friction = 0,
                density = 1
            })

            newWord.isFixedRotation = true
            newWord.myName = "word"
            newWord.wordIndex = i
            newWord.wordText = wordData.text

            table.insert(wordsTable, newWord)
            activeWordByIndex[i] = newWord

           newWord.x = math.random(60, display.contentWidth - 60)
            newWord.y = -60

            local direction = 1
            if newWord.x > display.contentCenterX then
                direction = -1
            end

            newWord:setLinearVelocity(
                direction * math.random(80, 140),
                math.random(60, 110)
            )
        end
    end
end

local function loadFlower()
    local objectSheet = getEraserSheet()
    local sheetOptions1 =
    {
        frames =
        {
            { x = 0, y = 0, width = 220,  height = 210  },
            { x = 0, y = 0, width = 1300, height = 1010 },
        }
    }

    local eraserFile
    if (ThemeLabel == nil or ThemeLabel == "") then
        eraserFile = "themes/Original-eraser.png"
    else
        eraserFile = "themes/" .. ThemeLabel .. "-eraser.png"
    end

    local imageSheetPath = system.pathForFile(eraserFile, system.ResourceDirectory)
    if imageSheetPath == nil then
        logger.warn("[scene:game] loadFlower missing theme eraser file fallback from=", tostring(eraserFile))
        print("⚠️ Could not find eraser file at path: " .. tostring(eraserFile))
        eraserFile = "original/eraser.png"
    end

    local objectSheet = graphics.newImageSheet(eraserFile, sheetOptions1)

    local newFlower = display.newImageRect(mainGroup, objectSheet, 1, 120, 120)
    table.insert(wordsTable, newFlower)

    physics.addBody(newFlower, {
        radius = 18,
        bounce = 1.1,
        friction = 0,
        density = 1
    })

    newFlower.isFixedRotation = true
    newFlower.myName = "flower"

   newFlower.x = math.random(60, display.contentWidth - 60)
    newFlower.y = -60

    local direction = 1
    if newFlower.x > display.contentCenterX then
        direction = -1
    end

    newFlower:setLinearVelocity(
        direction * math.random(80, 140),
        math.random(60, 110)
    )
end

local function moveBasket(event)
    local target = event.target
    local phase  = event.phase

    if phase == "began" then
        display.currentStage:setFocus(target)
        target.isFocus = true
        target.touchOffsetX = event.x - target.x
        target.touchOffsetY = event.y - target.y

    elseif target.isFocus and phase == "moved" then
        local ox = target.touchOffsetX or 0
        local oy = target.touchOffsetY or 0
        target.x = event.x - ox
        target.y = event.y - oy

    elseif target.isFocus and (phase == "ended" or phase == "cancelled") then
        display.currentStage:setFocus(nil)
        target.isFocus = false
        target.touchOffsetX = nil
        target.touchOffsetY = nil
    end

    return true
end

local function gameLoop(tbl)
    loadWord(tbl)
    loadFlower(); --loadFlower(); loadFlower()

    for i = #wordsTable, 1, -1 do
        local obj = wordsTable[i]
       if obj and obj.y > display.contentHeight + 100 then
        removeWordObjectFromTables(obj)
            display.remove(obj)
        end
    end
end

------------------------------------------------------------
-- Success Handling
------------------------------------------------------------
local function success()
    if memorySpringSample then
        hideHintModal()
        if gameLoopTimer then timer.cancel(gameLoopTimer); gameLoopTimer = nil end
        Runtime:removeEventListener("collision", onCollision)
        physics.pause()
        composer.gotoScene("memorySpringSampleSuccess", {params = {title = LevelID_return}})
        return
    end
    logger.scene("game", "success start user=", tostring(user), " prefix=", tostring(Prefix_return or classCode), " level=", tostring(level), " title=", tostring(LevelID_return))

    local keyPrefix = Prefix_return or classCode or ""
    if keyPrefix ~= "" and level then
        local lastLevelKey = "lastLevel_" .. tostring(keyPrefix)
        system.setPreferences("app", {
            [lastLevelKey] = level
        })
        print("Saved last level", level, "for class", keyPrefix)
        logger.scene("game", "saved last level preference lastLevelKey=", tostring(lastLevelKey), " value=", tostring(level))
    end

    hideHintModal()

    if gameLoopTimer then
        timer.cancel(gameLoopTimer)
        gameLoopTimer = nil
    end
    Runtime:removeEventListener("collision", onCollision)
    physics.pause()

    for i = #wordsTable, 1, -1 do
        display.remove(wordsTable[i])
        wordsTable[i] = nil
    end
    activeWordByIndex = {}

    local options = {
        params = {
            user   = user,
            name   = name,
            level  = level,
            title  = LevelID_return,
            text   = Text_return,
            theme  = ThemeLabel,
            prefix = classCode
        }
    }

    composer.removeScene("game")
    composer.gotoScene("success", options)
end

------------------------------------------------------------
-- Collision Handling
------------------------------------------------------------
onCollision = function(event)
    if event.phase ~= "began" then return end

    local obj1 = event.object1
    local obj2 = event.object2

    if not verse or not originalVerse then return end

    local function checkForSuccess()
        local ok, typedCount = isCurrentTextCorrectPrefix()
        if ok and typedCount == #expectedWords then
            logger.scene("game", "checkForSuccess complete typedCount=", tostring(typedCount))
            success()
        end
    end

    local function refreshHintIfNeeded()
        updateHintDisplay()
    end

    local function tryEraseLastWord()
        local lastIndex = #verseTextTable
        if lastIndex == 0 then
            logger.scene("game", "tryEraseLastWord ignored no collected words")
            return
        end

        if not eraserProtectionEnabled then
            logger.scene("game", "tryEraseLastWord erased without protection lastIndex=", tostring(lastIndex))
            table.remove(verseTextTable, lastIndex)
            updateCollectedVerseDisplay()
            updateHintWindowProgress()
            updateAssistState()
            refreshHintIfNeeded()
            return
        end

        local okPrefix = isCurrentTextCorrectPrefix()
        if okPrefix then
            logger.scene("game", "tryEraseLastWord blocked by eraser protection because prefix correct")
            updateAssistState()
            refreshHintIfNeeded()
            return
        end

        logger.scene("game", "tryEraseLastWord erased with protection enabled because prefix incorrect lastIndex=", tostring(lastIndex))
        table.remove(verseTextTable, lastIndex)
        updateCollectedVerseDisplay()
        updateHintWindowProgress()
        updateAssistState()
        refreshHintIfNeeded()
    end

    local function collectWordObject(wordObj)
        if not wordObj or not wordObj.wordIndex then return end

        local expectedNextIndex = #verseTextTable + 1

        if strictCollectionEnabled then
            if wordObj.wordIndex ~= expectedNextIndex then
                logger.warn("[scene:game] collectWordObject blocked strictCollection expectedNextIndex=", tostring(expectedNextIndex), " got=", tostring(wordObj.wordIndex), " word=", tostring(wordObj.wordText))
                return
            end
        end

        logger.scene("game", "collectWordObject wordIndex=", tostring(wordObj.wordIndex), " word=", tostring(wordObj.wordText))
        table.insert(verseTextTable, wordObj.wordText .. " ")
        updateCollectedVerseDisplay()
        updateHintWindowProgress()

        activeWordByIndex[wordObj.wordIndex] = nil
        removeWordObjectFromTables(wordObj)
        display.remove(wordObj)

        updateAssistState()
        refreshHintIfNeeded()
        checkForSuccess()
    end

    if (obj1.myName == "basket" and obj2.myName == "word") then
        collectWordObject(obj2)

    elseif (obj1.myName == "word" and obj2.myName == "basket") then
        collectWordObject(obj1)

    elseif (obj1.myName == "flower" and obj2.myName == "basket") then
        logger.scene("game", "flower collision basket obj1")
        tryEraseLastWord()
        removeWordObjectFromTables(obj1)
        display.remove(obj1)
        checkForSuccess()

    elseif (obj1.myName == "basket" and obj2.myName == "flower") then
        logger.scene("game", "flower collision basket obj2")
        tryEraseLastWord()
        removeWordObjectFromTables(obj2)
        display.remove(obj2)
        checkForSuccess()
    end
end

------------------------------------------------------------
-- Level Loading helper
------------------------------------------------------------
local function startLevelFromRow(levelData)
    if gameLoopTimer then timer.cancel(gameLoopTimer); gameLoopTimer = nil end
    Runtime:removeEventListener("collision", onCollision)
    hideHintModal()

    for i = #wordsTable, 1, -1 do
        display.remove(wordsTable[i])
        wordsTable[i] = nil
    end

    verseTextTable = {}
    expectedWords = {}
    verseWords = {}
    activeWordByIndex = {}
    playCount = 0
    eraserProtectionEnabled = false
    strictCollectionEnabled = false

    assistEnabled   = false
    assistLoopCount = 0
    assistMaxIndex  = 0
    bottomPanelExpanded = false

    if not levelData then
        logger.error("[scene:game] startLevelFromRow nil levelData")
        print("startLevelFromRow: nil levelData")
        return
    end

    LevelID_return = levelData.Title
    Text_return    = levelData.Text or ""
    ThemeLabel     = levelData.ThemeID or ThemeLabel
    Prefix_return  = Prefix_return or classCode or ""

    EraserWord = levelData.EraserWord or "eraser"

    local eraserKey = "eraser_" .. string.lower(EraserWord or "flower")
    local localizedEraser = languages.t(eraserKey)

    logger.scene(
        "game",
        "startLevelFromRow title=", tostring(LevelID_return),
        " theme=", tostring(ThemeLabel),
        " prefix=", tostring(Prefix_return),
        " textLen=", tostring(#tostring(Text_return))
    )

    hintShowingVerse = false
    hintWindowStartIndex = 1

    --------------------------------------------------------
    -- Background based on theme
    --------------------------------------------------------
    local backgroundTheme
    if (ThemeLabel == nil or ThemeLabel == "") then
        backgroundTheme = "themes/Original-bg.png"
    else
        backgroundTheme = "themes/" .. ThemeLabel .. "-bg.png"
    end

    if backGroup and backGroup.numChildren then
        for i = backGroup.numChildren, 1, -1 do
            display.remove(backGroup[i])
        end
    end

    -- Memory Spring sample uses its own watercolor artwork; all gameplay stays unchanged.
    if memorySpringSample then
        backgroundTheme = "MemorySpringGameBackground.png"
    end

    local background = newAspectFillImage(backGroup, backgroundTheme)
    if background then background:toBack() end

    --------------------------------------------------------
    -- Basket
    --------------------------------------------------------
    local sheetOptions =
    {
        frames =
        {
            { x = 0, y = 0, width = 220,  height = 210  },
            { x = 0, y = 0, width = 1300, height = 1010 },
        }
    }

    local objectSheet2 = graphics.newImageSheet("basket.png", sheetOptions)

    if basket then display.remove(basket); basket = nil end
    basket = display.newImageRect(mainGroup, objectSheet2, 2, 200, 200)
    basket.x = display.contentCenterX
    basket.y = display.contentHeight - 300
    basket:addEventListener("touch", moveBasket)
  --  physics.addBody(basket, { radius = 30, isSensor = true })
    physics.addBody(basket, "kinematic", {
    radius = 30,
    isSensor = true
})
    basket.myName = "basket"

    --------------------------------------------------------
    -- UI: clear old children
    --------------------------------------------------------
    if uiGroup and uiGroup.numChildren then
        for i = uiGroup.numChildren, 1, -1 do
            display.remove(uiGroup[i])
        end
    end

    local headerGroup = display.newGroup()
    uiGroup:insert(headerGroup)

    local safeX, safeW = safeXW()
    local safeY = display.safeScreenOriginY or 0

    local headerH = math.floor(display.contentHeight * 0.11)
    local headerCenterY = safeY + headerH * 0.5

    local headerBar = display.newRect(headerGroup, safeX + safeW * 0.5, headerCenterY, safeW, headerH)
    local bg = colors.appBackgroundSoft or { 1, 1, 1 }
    headerBar:setFillColor(bg[1], bg[2], bg[3], 0.28)
    headerBar:toBack()

    local headerDivider = display.newRect(
        headerGroup,
        safeX + safeW * 0.5,
        safeY + headerH,
        safeW,
        1
    )
    headerDivider:setFillColor(0, 0, 0, 0.10)
    headerDivider:toBack()

    header = StandardHeader.new(scene.view, {
        titlePlacement    = "back",
        fallbackTitle     = "",
        onBack            = gotoMemorySpringHome,
        backIconImage     = "icons/back.png",
        titleColor        = colors.textPrimary,
        backLabelFontSize = 44,
        backLabelGap      = 8,
    })
    logger.scene("game", "header created")

    local hintBtn = accessibleButton.new(
        headerGroup,
        languages.t("hint") or "Hint",
        safeCenterX(),
        headerCenterY,
        colors.secondaryAction,
        function()
            logger.scene("game", "hint button tapped")
            gotoHint()
        end,
        "",
        0.7
    )

    timer.performWithDelay(1, function()
        if not hintBtn then return end

        local btnW = 220
        if hintBtn.front and hintBtn.front.width then
            btnW = hintBtn.front.width
        end

        local approxBackContentRight = safeX + math.floor(safeW * 0.28)
        local leftClear  = approxBackContentRight + 24 + (btnW * 0.5)
        local rightClear = safeX + safeW - 24 - (btnW * 0.5)

        hintBtn.x = clamp(safeCenterX(), leftClear, rightClear)
    end)

    --------------------------------------------------------
    -- Always-visible hint panel under header
    --------------------------------------------------------
    local hintPanelH = math.floor(display.contentHeight * 0.18)
local hintPanelY = (safeY + headerH) + hintPanelH * 0.5 + math.floor(display.contentHeight * 0.01)

buildHintPanel({
    uiGroup = uiGroup,
    headerGroup = headerGroup,
    objectSheet2 = objectSheet2,
    hintPanelY = hintPanelY,
    hintPanelH = hintPanelH,
    safeX = safeX,
    safeW = safeW,
    localizedEraser = localizedEraser
})

   

    --------------------------------------------------------
    -- Bottom collection panel + thin dark footer bar above it
    --------------------------------------------------------
    local bottomPanelH = math.floor(display.contentHeight * 0.13)
    bottomPanel = display.newRoundedRect(
        uiGroup,
        display.contentCenterX,
        display.contentHeight - bottomPanelH * 0.5 - math.floor(display.contentHeight * 0.03),
        safeW * 0.92,
        bottomPanelH,
        18
    )
    bottomPanel:setFillColor(1, 1, 1, 0.92)
    bottomPanel.strokeWidth = 2
    bottomPanel:setStrokeColor(0, 0, 0, 0.15)
    bottomPanelExpanded = false
    bottomPanel:addEventListener("tap", bottomPanelTap)

    if basket and bottomPanel then
        local pad = math.floor(display.contentHeight * 0.02)
        local topOfBottomPanel = bottomPanel.y - (bottomPanel.height * 0.5)

        basket.y = topOfBottomPanel - (basket.height * 0.5) - pad

        local minY = (hintPanel and (hintPanel.y + hintPanel.height * 0.5) or 0) + basket.height * 0.6
        if basket.y < minY then basket.y = minY end
    end

    local footerBarH = math.floor(display.contentHeight * 0.018)
    local footerBarY = (bottomPanel.y - bottomPanel.height * 0.5) - (footerBarH * 0.5) - 6

    local footerBar = display.newRect(
        uiGroup,
        safeX + safeW * 0.5,
        footerBarY,
        safeW,
        footerBarH
    )
    footerBar:setFillColor(0, 0, 0, 0.10)

    --------------------------------------------------------
    -- Verse data holders
    --------------------------------------------------------
    originalVerse = display.newText(
        uiGroup,
        tostring(Text_return or ""),
        0, 0, display.contentWidth, 0, native.systemFont, 1
    )
    originalVerse.isVisible = false

    verse = display.newText(
        uiGroup,
        "",
        bottomPanel.x - bottomPanel.width * 0.5 + 18,
        bottomPanel.y,
        bottomPanel.width - 36,
        0,
        native.systemFontBold,
        42
    )
    verse.anchorX = 0
    verse:setFillColor(unpack(colors.textOnLight))

    updateCollectedVerseDisplay()

    --------------------------------------------------------
    -- Gameplay setup
    --------------------------------------------------------
    expectedWords = splitWords(Text_return)

    verseWords = {}
    for i = 1, #expectedWords do
        verseWords[i] = {
            index = i,
            text = expectedWords[i]
        }
    end

    myTable = verseWords

    updateHintDisplay()

    Runtime:addEventListener("collision", onCollision)

    local myParams = function() return gameLoop(myTable) end
    if gameLoopTimer then timer.cancel(gameLoopTimer); gameLoopTimer = nil end
    gameLoopTimer = timer.performWithDelay(5000, myParams, 0)
    logger.scene("game", "game loop started expectedWords=", tostring(#expectedWords), " timerIntervalMs=5000")
end

------------------------------------------------------------
-- Load a specific LevelID using getLevelP.php?level=
------------------------------------------------------------
local function requestLevelById(levelId)
    if not levelId or tostring(levelId) == "" then
        logger.error("[scene:game] requestLevelById missing levelId")
        native.showAlert(
            languages.t("error") or "Error",
            languages.t("please_select_level_first") or "Please select a level first.",
            { languages.t("ok") or "OK" },
            function() gotoSelectLevel() end
        )
        return
    end

    local url = "https://www.infoshagame.com/user/list/getLevelP.php"
        .. "?level=" .. tostring(levelId)

    logger.scene("game", "requestLevelById start levelId=", tostring(levelId), " url=", url)

    network.request(url, "GET", function(event)
        if event.isError or not event.response or event.response == "" then
            logger.error("[scene:game] requestLevelById network error or empty response levelId=", tostring(levelId))
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("error_connection") or "Could not connect to server.",
                { languages.t("ok") or "OK" },
                function() gotoCustomize() end
            )
            return
        end

        local ok, data = pcall(json.decode, event.response)
        if not ok or not data or #data == 0 then
            logger.error("[scene:game] requestLevelById invalid decoded data levelId=", tostring(levelId))
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("no_passages_found") or "No passages found",
                { languages.t("ok") or "OK" },
                function() gotoCustomize() end
            )
            return
        end

        logger.scene("game", "requestLevelById success levelId=", tostring(levelId), " rows=", tostring(#data))
        startLevelFromRow(data[1])
    end)
end

------------------------------------------------------------
-- Scene events
------------------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    local params = event.params or {}

    memorySpringSample = params.memorySpringSample == true
    user      = params.user
    name      = params.name
    level     = params.desiredLevel or params.level

    classCode = params.prefix or composer.getVariable("prefix")
    className = params.className or composer.getVariable("className")
    useFirstAvailable = params.useFirstAvailable or false

    logger.scene(
        "game",
        "create start user=", tostring(user),
        " name=", tostring(name),
        " level=", tostring(level),
        " classCode=", tostring(classCode),
        " className=", tostring(className),
        " useFirstAvailable=", tostring(useFirstAvailable)
    )

    composer.setVariable("prefix", classCode)

    playCount = 0
    eraserProtectionEnabled = false
    strictCollectionEnabled = false
    expectedWords = {}
    verseWords = {}
    activeWordByIndex = {}
    verseTextTable = {}
    bottomPanelExpanded = false

    assistEnabled   = false
    assistLoopCount = 0
    assistMaxIndex  = 0

    hintShowingVerse = false
    hintWindowStartIndex = 1

    physics.pause()

    backGroup = display.newGroup()
    sceneGroup:insert(backGroup)

    mainGroup = display.newGroup()
    sceneGroup:insert(mainGroup)

    uiGroup = display.newGroup()
    sceneGroup:insert(uiGroup)

    lastWord = display.newText(uiGroup, "", 1, 1, native.systemFont, 2)

    physics.start()

    local wallThickness = 40

local leftWall = display.newRect(
    mainGroup,
    -wallThickness * 0.5,
    display.contentCenterY,
    wallThickness,
    display.contentHeight * 2
)
leftWall.isVisible = false
physics.addBody(leftWall, "static", {
    bounce = 1,
    friction = 0
})

local rightWall = display.newRect(
    mainGroup,
    display.contentWidth + wallThickness * 0.5,
    display.contentCenterY,
    wallThickness,
    display.contentHeight * 2
)
rightWall.isVisible = false
physics.addBody(rightWall, "static", {
    bounce = 1,
    friction = 0
})

    logger.scene("game", "create complete physics started")
end

function scene:show(event)
    logger.scene("game", "show phase=", event.phase or "nil")

    if event.phase == "did" then
        if memorySpringSample then
            startLevelFromRow({
                Title = "Abraham Lincoln",
                Text = "Honest Kind Brave Leader",
                ThemeID = "Original",
                EraserWord = "eraser"
            })
            return
        end
        if not level or tostring(level) == "" then
            logger.error("[scene:game] show did missing level")
            native.showAlert(
                languages.t("error") or "Error",
                languages.t("please_select_level_first") or "Please select a level first.",
                { languages.t("ok") or "OK" },
                function() gotoSelectLevel() end
            )
            return
        end

        requestedLevelId = tonumber(level)
        logger.scene("game", "show did requestLevelById requestedLevelId=", tostring(requestedLevelId))
        requestLevelById(requestedLevelId)
    end
end

function scene:hide(event)
    logger.scene("game", "hide phase=", event.phase or "nil")

    if event.phase == "will" then
        hideHintModal()
        if gameLoopTimer then
            timer.cancel(gameLoopTimer)
            gameLoopTimer = nil
        end
        physics.stop()
        logger.scene("game", "hide will stopped timer and physics")
    elseif event.phase == "did" then
        hideHintModal()
        Runtime:removeEventListener("collision", onCollision)
        physics.pause()
        audio.stop(1)
        composer.removeScene("game")
        logger.scene("game", "hide did removed collision listener paused physics removed scene")
    end
end

function scene:destroy(event)
    logger.scene("game", "destroy start")

    hideHintModal()

    if gameLoopTimer then
        timer.cancel(gameLoopTimer)
        gameLoopTimer = nil
    end
    Runtime:removeEventListener("collision", onCollision)
    physics.stop()

    verseTextTable = {}
    expectedWords  = {}
    verseWords = {}
    activeWordByIndex = {}
    playCount = 0
    eraserProtectionEnabled = false
    strictCollectionEnabled = false
    bottomPanelExpanded = false

    assistEnabled   = false
    assistLoopCount = 0
    assistMaxIndex  = 0

    hintShowingVerse = false
    hintWindowStartIndex = 1

    if verse then verse.text = "" end
    if originalVerse then originalVerse.text = "" end
    if originalTitle then originalTitle.text = "" end

    if myTable and #myTable > 0 then
        for i = #myTable, 1, -1 do
            myTable[i] = nil
        end
        myTable = nil
    end

    requestedLevelId = nil
    useFirstAvailable = false
    Prefix_return = nil
    ThemeLabel = nil
    LevelID_return = nil
    Text_return = nil
    header = nil

    logger.scene("game", "destroy complete")
end

------------------------------------------------------------
-- Listeners
------------------------------------------------------------
scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
scene:addEventListener("destroy", scene)

return scene
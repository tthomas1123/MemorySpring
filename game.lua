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

-- UI references
local hintPanel, hintText, levelLabel
local header
local orderLabels = {}
local progressLabel
local praiseLabel
local profilePhoto
local memoryProfile = {}
local encouragements = {
    "Great job!",
    "Nice work!",
    "You're doing well!",
    "Excellent!",
    "Keep it up!",
    "Wonderful!",
    "That's right!"
}

-- Hint behavior state
local hintDefaultText = languages.t("hint_instruction") or "Hint: Catch the next words. Tap the panel to read the full verse."
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
local updateOrderStrip

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
    composer.gotoScene("memorySpringHome", {effect="slideRight", time=250})
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

    hintModalText = display.newText({
        text = fullVerse,
        x = 0,
        y = 0,
        width = bodyWidth - 24,
        font = native.systemFont,
        fontSize = 34,
        align = "left"
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
-- Memory Spring order/progress strip
------------------------------------------------------------
updateOrderStrip = function()
    local progress = getCorrectProgress()
    for i, label in ipairs(orderLabels or {}) do
        if label and label.removeSelf then
            if i <= progress then
                label:setFillColor(0.55, 0.72, 0.43)
                label.strokeWidth = 0
                label.xScale, label.yScale = 1, 1
                if label.textObject then label.textObject:setFillColor(1, 1, 1) end
            elseif i == progress + 1 then
                label:setFillColor(0.95, 0.98, 1.00)
                label.strokeWidth = 3
                label:setStrokeColor(0.20, 0.56, 0.35)
                label.xScale, label.yScale = 1.06, 1.06
                if label.textObject then label.textObject:setFillColor(0.10, 0.25, 0.52) end
            else
                label:setFillColor(0.88, 0.91, 0.97)
                label.strokeWidth = 0
                label.xScale, label.yScale = 1, 1
                if label.textObject then label.textObject:setFillColor(0.40, 0.43, 0.58) end
            end
        end
    end
    if progressLabel then
        local currentWord = math.min(progress + 1, #expectedWords)
        progressLabel.text = "Word\n" .. tostring(currentWord) .. " of " .. tostring(#expectedWords)
        if progress >= #expectedWords and #expectedWords > 0 then
            progressLabel.text = "Complete\n" .. tostring(#expectedWords) .. " of " .. tostring(#expectedWords)
        end
    end

    if praiseLabel and progress > 0 then
        local praiseIndex = ((progress - 1) % #encouragements) + 1
        praiseLabel.text = "★   " .. encouragements[praiseIndex]
    end
end

------------------------------------------------------------
-- Hint UI logic
------------------------------------------------------------
local function updateHintDisplay()
    if not hintText or not hintPanel then return end

    if not hintShowingVerse then
        hintText.text = hintDefaultText
        fitTextToHeight(hintText, 42, 22, hintPanel.height * 0.60)
        return
    end

    local allWords = expectedWords or {}

    if #allWords == 0 then
        hintText.text = ""
        fitTextToHeight(hintText, 42, 24, hintPanel.height * 0.60)
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

    hintText.text = preview
    fitTextToHeight(hintText, 42, 24, hintPanel.height * 0.60)
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

local function hintPanelTap(event)
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

            local newWord = display.newText(wordData.text, 1, 1, native.systemFontBold, 36)
            newWord:setFillColor(0.02, 0.10, 0.48)
            newWord.strokeWidth = 3
            newWord:setStrokeColor(1, 1, 1, 0.98)
            mainGroup:insert(newWord)

            physics.addBody(newWord, "dynamic", { radius = 40, bounce = 0.8 })
            newWord.myName = "word"
            newWord.wordIndex = i
            newWord.wordText = wordData.text

            table.insert(wordsTable, newWord)
            activeWordByIndex[i] = newWord

            local safeX, safeW = safeXW()
            local topY = basket and (basket.minGameY or 260) or 260
            local bottomY = basket and (basket.maxGameY or display.contentHeight - 220) or display.contentHeight - 220
            newWord.x = math.random(math.floor(safeX + 55), math.floor(safeX + safeW - 55))
            newWord.y = math.random(math.floor(topY), math.floor(math.max(topY + 20, bottomY - 70)))
            newWord:setLinearVelocity(math.random(-25, 25), math.random(18, 38))
        end
    end
end

local function loadFlower()
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

    local newFlower = display.newImageRect(mainGroup, objectSheet, 1, 86, 86)
    table.insert(wordsTable, newFlower)

    physics.addBody(newFlower, "dynamic", { radius = 30, bounce = 0.8 })
    newFlower.myName = "flower"

    local whereFrom = math.random(3)
    if whereFrom == 1 then
        newFlower.x = -60
        newFlower.y = math.random(500)
        newFlower:setLinearVelocity(math.random(40, 120), math.random(20, 60))
    elseif whereFrom == 2 then
        newFlower.x = math.random(display.contentWidth)
        newFlower.y = -60
        newFlower:setLinearVelocity(math.random(-40, 40), math.random(40, 120))
    else
        newFlower.x = display.contentWidth + 60
        newFlower.y = math.random(500)
        newFlower:setLinearVelocity(math.random(-120, -40), math.random(20, 60))
    end
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
        target.x = clamp(event.x - ox, target.minGameX or 0, target.maxGameX or display.contentWidth)
        target.y = clamp(event.y - oy, target.minGameY or 0, target.maxGameY or display.contentHeight)
        if progressLabel then
            progressLabel.x = target.x
            progressLabel.y = target.y + 18
        end

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
  --  loadFlower(); loadFlower(); loadFlower()

    for i = #wordsTable, 1, -1 do
        local obj = wordsTable[i]
        if obj and (obj.x < -100 or obj.x > display.contentWidth + 100 or obj.y < -100 or obj.y > display.contentHeight + 100) then
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
        composer.gotoScene("memorySpringSampleSuccess", {params={title=LevelID_return}})
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
        updateOrderStrip()
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
        updateOrderStrip()
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
    physics.addBody(basket, { radius = 30, isSensor = true })
    basket.myName = "basket"

    --------------------------------------------------------
    -- Memory Spring UI
    --------------------------------------------------------
    if uiGroup and uiGroup.numChildren then
        for i = uiGroup.numChildren, 1, -1 do
            display.remove(uiGroup[i])
        end
    end
    orderLabels = {}
    progressLabel = nil
    praiseLabel = nil

    local safeX, safeW = safeXW()
    local safeY = display.safeScreenOriginY or 0
    local safeH = display.safeActualContentHeight or display.contentHeight
    local cx = safeX + safeW * 0.5

    -- Compact blue header
    local headerH = math.max(48, math.floor(safeH * 0.055))
    local headerBar = display.newRect(uiGroup, cx, safeY + headerH * 0.5, safeW, headerH)
    headerBar:setFillColor(0.16, 0.23, 0.58, 0.96)

    header = StandardHeader.new(scene.view, {
        titlePlacement    = "back",
        fallbackTitle     = "",
        onBack            = gotoMemorySpringHome,
        backIconImage     = "icons/back.png",
        titleColor        = {1,1,1},
        backLabelFontSize = 34,
        backLabelGap      = 6,
    })

    local hintBtn = accessibleButton.new(
        uiGroup,
        languages.t("hint") or "Hint",
        cx,
        safeY + headerH * 0.5,
        {0.80, 0.90, 0.96},
        function() gotoHint() end,
        "",
        0.52
    )

    -- Simple sample layout: keep the full play area available.
    local cardTop = safeY + headerH + 12
    local instructionH = math.floor(safeH * 0.17)
    local instructionY = cardTop + instructionH * 0.5
    hintPanel = display.newRoundedRect(uiGroup, cx, instructionY, safeW * 0.96, instructionH, 14)
    hintPanel:setFillColor(1, 1, 1, 0.94)
    hintPanel.strokeWidth = 1
    hintPanel:setStrokeColor(0.72, 0.72, 0.72)
    hintPanel:addEventListener("tap", hintPanelTap)

    local heading = display.newText({
        parent=uiGroup, text=tostring(LevelID_return or ""),
        x=safeX+18, y=cardTop+9, width=safeW-36,
        font=native.systemFontBold, fontSize=22, align="left"
    })
    heading.anchorX, heading.anchorY = 0, 0
    heading:setFillColor(0.12, 0.17, 0.21)

    hintText = display.newText({
        parent=uiGroup,
        text="Move basket to catch words in order.\nCatch flower to erase the last word.\nTap this panel to view the words.",
        x=safeX+56, y=cardTop+42, width=safeW-74,
        font=native.systemFont, fontSize=16, align="left"
    })
    hintText.anchorX, hintText.anchorY = 0, 0
    hintText:setFillColor(0.12, 0.17, 0.21)
    hintText:addEventListener("tap", hintPanelTap)

    levelLabel = display.newText({parent=uiGroup, text=tostring(LevelID_return or ""), x=0, y=0, font=native.systemFont, fontSize=1})
    levelLabel.isVisible=false

    -- Game bounds are the open area between instruction and order strip
    local orderStripH = math.floor(safeH * 0.065)
    local actionBarH = math.floor(safeH * 0.09)
    local orderStripY = safeY + safeH - actionBarH - orderStripH * 0.5
    local gameTop = instructionY + instructionH * 0.5 + 5
    local gameBottom = orderStripY - orderStripH * 0.5 - 4

    if basket then
        basket.width, basket.height = 92, 78
        basket.x = cx
        basket.y = gameBottom - 44
        basket.minGameY = gameTop + 35
        basket.maxGameY = gameBottom - 35
        basket.minGameX = safeX + 45
        basket.maxGameX = safeX + safeW - 45
    end

    -- Invisible collected text holder retained for game logic
    bottomPanel = display.newRect(uiGroup, cx, orderStripY, safeW, orderStripH)
    bottomPanel:setFillColor(0.80, 0.87, 0.98, 0.96)
    bottomPanelExpanded = false

    originalVerse = display.newText(uiGroup, tostring(Text_return or ""), 0, 0, display.contentWidth, 0, native.systemFont, 1)
    originalVerse.isVisible = false
    verse = display.newText(uiGroup, "", 0, 0, 1, 0, native.systemFont, 1)
    verse.isVisible = false

    -- Order to catch row
    local orderCaption = display.newText({parent=uiGroup, text="Order to catch:", x=safeX+7, y=orderStripY, font=native.systemFontBold, fontSize=18})
    orderCaption.anchorX=0
    orderCaption:setFillColor(0.25,0.30,0.66)

    local orderWords = splitWords(Text_return)
    local maxVisible = math.min(#orderWords, 5)
    local rowLeft = safeX + 92
    local available = safeW - 98
    local chipW = available / math.max(maxVisible,1) - 4
    for i=1,maxVisible do
        local chipX = rowLeft + (i-0.5)*(available/maxVisible)
        local chip = display.newRoundedRect(uiGroup, chipX, orderStripY, chipW, orderStripH*0.58, 12)
        chip:setFillColor(i==1 and 0.78 or 0.88, i==1 and 0.88 or 0.91, 0.98)
        local label = display.newText({parent=uiGroup, text=tostring(i).."  "..tostring(orderWords[i]), x=chipX, y=orderStripY, width=chipW-5, font=native.systemFontBold, fontSize=16, align="center"})
        label:setFillColor(0.20,0.27,0.60)
        chip.textObject=label
        orderLabels[i]=chip
    end

    -- Bottom action bar
    local actionY = safeY + safeH - actionBarH*0.5
    local actionBar = display.newRect(uiGroup, cx, actionY, safeW, actionBarH)
    actionBar:setFillColor(0.70,0.79,0.94,0.98)
    local editBtn = display.newCircle(uiGroup, safeX+34, actionY, 25)
    editBtn:setFillColor(0.49,0.57,0.72)
    local editText = display.newText({parent=uiGroup, text="Edit", x=editBtn.x, y=editBtn.y, font=native.systemFontBold, fontSize=13})
    editText:setFillColor(1,1,1)
    editBtn:addEventListener("tap", function() gotoCustomize(); return true end)
    editText:addEventListener("tap", function() gotoCustomize(); return true end)

    praiseLabel = display.newText({parent=uiGroup, text="★   Great job!", x=cx, y=actionY, font=native.systemFontBold, fontSize=22})
    praiseLabel:setFillColor(0.27,0.24,0.68)
    local share = display.newCircle(uiGroup, safeX+safeW-34, actionY, 25)
    share:setFillColor(0.49,0.57,0.72)
    local shareText = display.newText({parent=uiGroup, text="↑", x=share.x, y=share.y-1, font=native.systemFontBold, fontSize=24})
    shareText:setFillColor(1,1,1)

    progressLabel = display.newText({parent=uiGroup, text="Word\n1 of "..tostring(#orderWords), x=basket and basket.x or cx, y=basket and basket.y+18 or gameBottom-20, font=native.systemFontBold, fontSize=18, align="center"})
    progressLabel:setFillColor(0.23,0.31,0.62)

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
    updateOrderStrip()

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
    memoryProfile = params.memoryProfile or {}

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
    logger.scene("game", "create complete physics started")
end

function scene:show(event)
    logger.scene("game", "show phase=", event.phase or "nil")

    if event.phase == "did" then
        if memorySpringSample then
            startLevelFromRow({Title="Abraham Lincoln",Text="Honest Kind Brave Leader",ThemeID="Original",EraserWord="eraser"})
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
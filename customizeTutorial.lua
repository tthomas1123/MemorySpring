-- customizeTutorial.lua
local tutorial = {}

local languages = require("languages")

local group
local currentStep = 1
local onStopCallback = nil

local function tOr(key, fallback)
    local value = languages.t(key)
    if value == nil or value == "" or value == key then
        return fallback
    end
    return value
end

local steps = {
    {
        titleKey = "tutorial_level_title_title",
        title = "Level Title",
        textKey = "tutorial_level_title_text",
        text = "Give your level a title. Students will see this when choosing what to play.",
        mode = "title"
    },
    {
        titleKey = "tutorial_choose_theme_title",
        title = "Choose Theme",
        textKey = "tutorial_choose_theme_text",
        text = "Pick a theme to change how the game looks.",
        mode = "theme"
    },
    {
        titleKey = "tutorial_words_to_remember_title",
        title = "Words to Remember",
        textKey = "tutorial_words_to_remember_text",
        text = "Add a memory verse or words you want students to remember.",
        mode = "words"
    },
    {
        titleKey = "tutorial_success_message_title",
        title = "Success Message",
        textKey = "tutorial_success_message_text",
        text = "Add encouragement, verse notes, next class plans, or reminders.",
        mode = "success"
    },
    {
        titleKey = "tutorial_preview_game_title",
        title = "Preview Game",
        textKey = "tutorial_preview_game_text",
        text = "Tap Preview Game to test the game before students play.",
        mode = "previewGame"
    },
    {
        titleKey = "tutorial_preview_success_title",
        title = "Preview Success",
        textKey = "tutorial_preview_success_text",
        text = "Tap Preview Success to see the message students get after finishing.",
        mode = "previewSuccess"
    },
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function clearStep()
    if group then
        transition.cancel(group)
        group:removeSelf()
        group = nil
    end
end

local function makeDot(parent, x, y, active)
    local dot = display.newCircle(parent, x, y, 8)

    if active then
        dot:setFillColor(0.02, 0.22, 0.50)
    else
        dot:setFillColor(0.42, 0.64, 0.86)
    end

    return dot
end

local function addTitleThemeSave(parent, centerX, panelY, panelW, panelH, mode)
    local titleY = panelY - panelH * 0.24

    local titleField = display.newRoundedRect(
        parent,
        centerX,
        titleY,
        panelW * 0.82,
        46,
        8
    )
    titleField:setFillColor(1, 1, 1)
    titleField.strokeWidth = mode == "title" and 4 or 2
    titleField:setStrokeColor(
        mode == "title" and 1 or 0.70,
        mode == "title" and 0.70 or 0.78,
        0.12
    )

    local titleText = display.newText({
        parent = parent,
        text = tOr("tutorial_sample_level_name", "Early Learners - Psalm 118:1"),
        x = centerX,
        y = titleY,
        font = native.systemFontBold,
        fontSize = 21,
        width = panelW * 0.76,
        align = "center"
    })
    titleText:setFillColor(0.02, 0.20, 0.46)

    local rowY = panelY + panelH * 0.10

    local themeLabel = display.newText({
        parent = parent,
        text = tOr("tutorial_theme_label", "Theme"),
        x = centerX - panelW * 0.40,
        y = rowY,
        font = native.systemFontBold,
        fontSize = 19,
        align = "left"
    })
    themeLabel.anchorX = 0
    themeLabel:setFillColor(0.02, 0.20, 0.46)

    local themeBtn = display.newRoundedRect(
        parent,
        centerX - panelW * 0.12,
        rowY,
        150,
        42,
        12
    )
    themeBtn:setFillColor(1, 1, 1)
    themeBtn.strokeWidth = mode == "theme" and 4 or 2
    themeBtn:setStrokeColor(
        mode == "theme" and 1 or 0.13,
        mode == "theme" and 0.70 or 0.45,
        mode == "theme" and 0.12 or 0.86
    )

    local themeText = display.newText({
        parent = parent,
        text = tOr("tutorial_sample_theme", "Undersea ▼"),
        x = themeBtn.x,
        y = themeBtn.y,
        font = native.systemFontBold,
        fontSize = 18
    })
    themeText:setFillColor(0.02, 0.20, 0.46)

    local saveBtn = display.newRoundedRect(
        parent,
        centerX + panelW * 0.30,
        rowY,
        130,
        44,
        14
    )
    saveBtn:setFillColor(0.13, 0.45, 0.86, 0.42)

    local saveText = display.newText({
        parent = parent,
        text = tOr("tutorial_save_button", "Save"),
        x = saveBtn.x,
        y = saveBtn.y,
        font = native.systemFontBold,
        fontSize = 18
    })
    saveText:setFillColor(1, 1, 1)
end

local function addTabs(parent, centerX, y, panelW, activeMode)
    local tabW = panelW * 0.40
    local tabH = 44

    local wordsTab = display.newRoundedRect(
        parent,
        centerX - panelW * 0.23,
        y,
        tabW,
        tabH,
        14
    )
    wordsTab:setFillColor(1, 1, 1)
    wordsTab.strokeWidth = activeMode == "words" and 4 or 2
    wordsTab:setStrokeColor(0.13, 0.45, 0.86)

    local wordsText = display.newText({
        parent = parent,
        text = tOr("tutorial_words_tab", "Words to Remember"),
        x = wordsTab.x,
        y = wordsTab.y,
        font = native.systemFontBold,
        fontSize = 17,
        width = tabW * 0.90,
        align = "center"
    })
    wordsText:setFillColor(0.13, 0.45, 0.86)

    local successTab = display.newRoundedRect(
        parent,
        centerX + panelW * 0.23,
        y,
        tabW,
        tabH,
        14
    )
    successTab:setFillColor(1, 1, 1)
    successTab.strokeWidth = activeMode == "success" and 4 or 2
    successTab:setStrokeColor(0.13, 0.45, 0.86)

    local successText = display.newText({
        parent = parent,
        text = tOr("tutorial_success_tab", "Success Message"),
        x = successTab.x,
        y = successTab.y,
        font = native.systemFontBold,
        fontSize = 17,
        width = tabW * 0.90,
        align = "center"
    })
    successText:setFillColor(0.13, 0.45, 0.86)
end

local function addPreviewButton(parent, centerX, y, panelW, mode)
    local isSuccess = mode == "previewSuccess" or mode == "success"
    local isHighlighted = mode == "previewGame" or mode == "previewSuccess"

    local preview = display.newRoundedRect(
        parent,
        centerX + panelW * 0.28,
        y,
        170,
        42,
        14
    )
    preview:setFillColor(1, 1, 1)
    preview.strokeWidth = isHighlighted and 4 or 2
    preview:setStrokeColor(
        isHighlighted and 1 or 0.13,
        isHighlighted and 0.70 or 0.45,
        isHighlighted and 0.12 or 0.86
    )

    local previewText = display.newText({
        parent = parent,
        text = isSuccess
            and tOr("tutorial_preview_success_button", "Preview Success")
            or tOr("tutorial_preview_game_button", "Preview Game"),
        x = preview.x,
        y = preview.y,
        font = native.systemFontBold,
        fontSize = 17,
        width = preview.width * 0.90,
        align = "center"
    })
    previewText:setFillColor(0.13, 0.45, 0.86)
end

local function addWordsSection(parent, centerX, panelY, panelW, panelH, mode)
    local headerY = panelY - panelH * 0.18

    addTabs(parent, centerX, headerY, panelW, "words")

    local labelY = panelY + panelH * 0.13

    local label = display.newText({
        parent = parent,
        text = tOr("tutorial_add_words_label", "Add Words to Remember"),
        x = centerX - panelW * 0.40,
        y = labelY,
        font = native.systemFontBold,
        fontSize = 19,
        align = "left"
    })
    label.anchorX = 0
    label:setFillColor(0.02, 0.20, 0.46)

    addPreviewButton(parent, centerX, labelY, panelW, "previewGame")

    local textBox = display.newRoundedRect(
        parent,
        centerX,
        panelY + panelH * 0.42,
        panelW * 0.84,
        78,
        8
    )
    textBox:setFillColor(1, 1, 1)
    textBox.strokeWidth = mode == "words" and 4 or 2
    textBox:setStrokeColor(
        mode == "words" and 1 or 0.70,
        mode == "words" and 0.70 or 0.78,
        0.12
    )

    local sample = display.newText({
        parent = parent,
        text = tOr("tutorial_sample_words", "God is good"),
        x = centerX - textBox.width * 0.40,
        y = textBox.y - textBox.height * 0.25,
        font = native.systemFont,
        fontSize = 18,
        width = textBox.width * 0.80,
        align = "left"
    })
    sample.anchorX = 0
    sample:setFillColor(0, 0, 0)
end

local function addSuccessSection(parent, centerX, panelY, panelW, panelH, mode)
    local headerY = panelY - panelH * 0.18

    addTabs(parent, centerX, headerY, panelW, "success")

    local labelY = panelY + panelH * 0.13

    local label = display.newText({
        parent = parent,
        text = tOr("tutorial_add_success_label", "Add Success Message"),
        x = centerX - panelW * 0.40,
        y = labelY,
        font = native.systemFontBold,
        fontSize = 19,
        align = "left"
    })
    label.anchorX = 0
    label:setFillColor(0.02, 0.20, 0.46)

    addPreviewButton(parent, centerX, labelY, panelW, "previewSuccess")

    local textBox = display.newRoundedRect(
        parent,
        centerX,
        panelY + panelH * 0.42,
        panelW * 0.84,
        78,
        8
    )
    textBox:setFillColor(1, 1, 1)
    textBox.strokeWidth = mode == "success" and 4 or 2
    textBox:setStrokeColor(
        mode == "success" and 1 or 0.70,
        mode == "success" and 0.70 or 0.78,
        0.12
    )

    local sample = display.newText({
        parent = parent,
        text = tOr("tutorial_sample_success_message", "Great job! Remember this verse this week."),
        x = centerX - textBox.width * 0.40,
        y = textBox.y - textBox.height * 0.25,
        font = native.systemFont,
        fontSize = 17,
        width = textBox.width * 0.80,
        align = "left"
    })
    sample.anchorX = 0
    sample:setFillColor(0, 0, 0)
end

local function addPreviewOnlySection(parent, centerX, panelY, panelW, panelH, mode)
    local tabsY = panelY - panelH * 0.12
    addTabs(parent, centerX, tabsY, panelW, mode == "previewSuccess" and "success" or "words")

    local previewY = panelY + panelH * 0.28
    addPreviewButton(parent, centerX, previewY, panelW, mode)
end

local function addMiniCustomizeCard(parent, centerX, centerY, cardW, cardH, mode)
    local panelW = cardW * 0.82
    local panelH = cardH * 0.30
    local panelY = centerY + cardH * 0.15

    if mode == "words" or mode == "success" then
        panelH = cardH * 0.36
        panelY = centerY + cardH * 0.14
    elseif mode == "previewGame" or mode == "previewSuccess" then
        panelH = cardH * 0.24
        panelY = centerY + cardH * 0.17
    end

    local panel = display.newRoundedRect(parent, centerX, panelY, panelW, panelH, 18)
    panel:setFillColor(1, 1, 1, 0.94)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.55, 0.72, 0.90)

    if mode == "title" or mode == "theme" then
        addTitleThemeSave(parent, centerX, panelY, panelW, panelH, mode)
    elseif mode == "words" then
        addWordsSection(parent, centerX, panelY, panelW, panelH, mode)
    elseif mode == "success" then
        addSuccessSection(parent, centerX, panelY, panelW, panelH, mode)
    elseif mode == "previewGame" or mode == "previewSuccess" then
        addPreviewOnlySection(parent, centerX, panelY, panelW, panelH, mode)
    end
end

------------------------------------------------------------
-- Main Step Renderer
------------------------------------------------------------
local function showStep()
    clearStep()

    local step = steps[currentStep]
    if not step then return end

    group = display.newGroup()
    display.getCurrentStage():insert(group)

    local safeW = display.safeActualContentWidth or display.contentWidth
    local safeH = display.safeActualContentHeight or display.contentHeight

    local centerX = display.contentCenterX
    local centerY = display.contentCenterY

    local dim = display.newRect(
        group,
        centerX,
        centerY,
        display.actualContentWidth * 1.4,
        display.actualContentHeight * 1.4
    )
    dim:setFillColor(0, 0, 0, 0.45)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local cardW = math.min(safeW * 0.86, 620)
    local cardH = math.min(safeH * 0.72, 620)

    local shadow = display.newRoundedRect(group, centerX + 6, centerY + 8, cardW, cardH, 26)
    shadow:setFillColor(0, 0, 0, 0.18)

    local card = display.newRoundedRect(group, centerX, centerY, cardW, cardH, 26)
    card:setFillColor(0.97, 0.98, 1)
    card.strokeWidth = 4
    card:setStrokeColor(0.02, 0.32, 0.68)

    local groundY = centerY + cardH * 0.24

    local sheepArea = display.newRect(group, centerX, groundY, cardW - 10, cardH * 0.24)
    sheepArea:setFillColor(0.80, 0.90, 1.0)

    local hill = display.newCircle(group, centerX, groundY + 25, cardW * 0.40)
    hill.xScale = 1.2
    hill.yScale = 0.22
    hill:setFillColor(0.68, 0.83, 0.96)

    local footer = display.newRect(
        group,
        centerX,
        centerY + cardH * 0.36,
        cardW - 8,
        cardH * 0.20
    )
    footer:setFillColor(0.74, 0.84, 0.95)

    local title = display.newText({
        parent = group,
        text = tOr(step.titleKey, step.title),
        x = centerX,
        y = centerY - cardH * 0.34,
        font = native.systemFontBold,
        fontSize = 42,
        width = cardW * 0.86,
        align = "center"
    })
    title:setFillColor(0.02, 0.20, 0.46)

    local lineY = title.y + 60

    local leftLine = display.newRect(group, centerX - 115, lineY, 170, 4)
    leftLine:setFillColor(0.55, 0.72, 0.90)

    local rightLine = display.newRect(group, centerX + 115, lineY, 170, 4)
    rightLine:setFillColor(0.55, 0.72, 0.90)

    local star = display.newText({
        parent = group,
        text = "★",
        x = centerX,
        y = lineY,
        font = native.systemFontBold,
        fontSize = 28
    })
    star:setFillColor(0.42, 0.64, 0.86)

    local body = display.newText({
        parent = group,
        text = tOr(step.textKey, step.text),
        x = centerX,
        y = centerY - cardH * 0.10,
        width = cardW * 0.82,
        font = native.systemFont,
        fontSize = 30,
        align = "center"
    })
    body:setFillColor(0.02, 0.20, 0.46)

    addMiniCustomizeCard(group, centerX, centerY, cardW, cardH, step.mode)

    local dotY = footer.y
    local dotStartX = centerX - cardW * 0.35

    for i = 1, #steps do
        makeDot(group, dotStartX + ((i - 1) * 30), dotY, i == currentStep)
    end

    local btnX = centerX + cardW * 0.27

    local nextBtn = display.newRoundedRect(group, btnX, dotY, 180, 72, 24)
    nextBtn:setFillColor(0.02, 0.22, 0.50)

    local nextText = display.newText({
        parent = group,
        text = currentStep == #steps and tOr("done", "Done") or tOr("tutorial_next", "Next ›"),
        x = btnX,
        y = dotY,
        font = native.systemFontBold,
        fontSize = 30
    })
    nextText:setFillColor(1, 1, 1)

    local function nextStep()
        currentStep = currentStep + 1

        if currentStep > #steps then
            tutorial.stop()
        else
            showStep()
        end

        return true
    end

    nextBtn:addEventListener("tap", nextStep)
    nextText:addEventListener("tap", nextStep)

    group.alpha = 0
    group.xScale = 0.96
    group.yScale = 0.96

    transition.to(group, {
        time = 180,
        alpha = 1,
        xScale = 1,
        yScale = 1,
        transition = easing.outQuad
    })

    group:toFront()
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------
function tutorial.start(callback)
    onStopCallback = callback
    currentStep = 1
    showStep()
end

function tutorial.stop()
    clearStep()

    if onStopCallback then
        local cb = onStopCallback
        onStopCallback = nil
        cb()
    end
end

return tutorial
-- tutorial.lua
local tutorial = {}

local languages = require("languages")

local function tOr(key, fallback)
    local value = languages.t(key)
    if value == nil or value == "" or value == key then
        return fallback
    end
    return value
end


local group
local currentStep = 1

local steps = {
    {
        titleKey = "tutorial_welcome_title",
        titleFallback = "Welcome!",
        textKey = "tutorial_welcome_text",
        textFallback = "Create fun Bible games for your students. They will play what you build.",
        mode = "sheep"
    },
    {
        titleKey = "tutorial_students_play_title",
        titleFallback = "Students Play",
        textKey = "tutorial_students_play_text",
        textFallback = "Your classes and levels become games for students.",
        mode = "appIcon",
        image = "smartsheep_rounded.png"
    },
    {
        titleKey = "tutorial_students_play_title",
        titleFallback = "Students Play",
        textKey = "tutorial_student_app_text",
        textFallback = "Your students install the SmartSheep student app. It is free and has NO ads.",
        mode = "appIcon",
        image = "smartsheep_rounded.png"
    },
    {
        titleKey = "tutorial_add_class_title",
        titleFallback = "Add Class",
        textKey = "tutorial_add_class_text",
        textFallback = "Tap the Add Class button below to create your first class.",
        mode = "sheep"
    },
    {
        titleKey = "tutorial_class_details_title",
        titleFallback = "Class Details",
        textKey = "tutorial_class_details_text",
        textFallback = "Students will access your game with the generated ID.",
        mode = "classPopup",
        image = "add_class.png"
    },
    {
        titleKey = "tutorial_students_join_title",
        titleFallback = "Students Join",
        textKey = "tutorial_students_join_text",
        textFallback = "In the SmartSheep app, students will enter your Class ID.",
        mode = "phoneScreenshot",
        image = "home_class_screen.png"
    },
    {
        titleKey = "tutorial_students_play_title",
        titleFallback = "Students Play",
        textKey = "tutorial_students_replay_text",
        textFallback = "After joining, students will see your class in their app to play again and again.",
        mode = "phoneScreenshot",
        image = "home_class_screen2.png"
    },
    {
        titleKey = "tutorial_tutorials_title",
        titleFallback = "Tutorials",
        textKey = "tutorial_tutorials_text",
        textFallback = "Review the tutorials under the ? in the upper right on each screen.",
        mode = "sheep",
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

local function addSheep(parent, centerX, y, cardW)
    local sheep = display.newImage(parent, "sheep.png")

    if sheep then
        local targetW = cardW * 0.20
        local scale = targetW / sheep.width

        sheep.xScale = scale
        sheep.yScale = scale
        sheep.x = centerX
        sheep.y = y

        local shadow = display.newCircle(parent, centerX, y + sheep.contentHeight * 0.34, targetW * 0.35)
        shadow.xScale = 1.8
        shadow.yScale = 0.28
        shadow:setFillColor(0, 0, 0, 0.16)
        shadow:toBack()
        sheep:toFront()
    end
end

local function addRoundedAppIcon(parent, imageName, centerX, centerY, cardW, cardH)
    local iconGroup = display.newGroup()
    parent:insert(iconGroup)

    local iconSize = math.min(cardW * 0.30, cardH * 0.25)
    local cornerRadius = iconSize * 0.24

    local shadow = display.newRoundedRect(
        iconGroup,
        centerX + 4,
        centerY + 6,
        iconSize,
        iconSize,
        cornerRadius
    )
    shadow:setFillColor(0, 0, 0, 0.18)

    local iconBg = display.newRoundedRect(
        iconGroup,
        centerX,
        centerY,
        iconSize,
        iconSize,
        cornerRadius
    )
    iconBg:setFillColor(1.0, 0.45, 0.05)

    local icon = display.newImage(iconGroup, imageName)

    if icon then
        local scale = math.max(iconSize / icon.width, iconSize / icon.height)
        icon.xScale = scale
        icon.yScale = scale
        icon.x = centerX
        icon.y = centerY
    end

    local border = display.newRoundedRect(
        iconGroup,
        centerX,
        centerY,
        iconSize,
        iconSize,
        cornerRadius
    )
    border:setFillColor(1, 1, 1, 0)
    border.strokeWidth = 3
    border:setStrokeColor(1, 1, 1, 0.9)

    return iconGroup
end

local function createGameplayAnimation(parent, centerX, centerY, cardW, cardH)
    local animGroup = display.newGroup()
    parent:insert(animGroup)

    local areaY = centerY + cardH * 0.14
    local areaW = cardW * 0.78
    local areaH = cardH * 0.25

    local gameArea = display.newRoundedRect(
        animGroup,
        centerX,
        areaY,
        areaW,
        areaH,
        18
    )
    gameArea:setFillColor(0.78, 0.90, 1)

    local instruction = display.newText({
        parent = animGroup,
        text = tOr("tutorial_catch_words", "Catch the words!"),
        x = centerX,
        y = areaY - areaH * 0.34,
        font = native.systemFontBold,
        fontSize = 18,
        align = "center"
    })
    instruction:setFillColor(0.02, 0.20, 0.46)

    local basket = display.newRoundedRect(
        animGroup,
        centerX,
        areaY + areaH * 0.28,
        areaW * 0.26,
        areaH * 0.18,
        8
    )
    basket:setFillColor(0.72, 0.65, 0.08)

    local basketTop = display.newRect(
        animGroup,
        centerX,
        basket.y - basket.height * 0.35,
        basket.width * 1.08,
        basket.height * 0.28
    )
    basketTop:setFillColor(0.62, 0.56, 0.06)

    local words = {
        tOr("tutorial_word_god", "God"),
        tOr("tutorial_word_loves", "loves"),
        tOr("tutorial_word_you", "you")
    }

    for i = 1, #words do
        local startX = centerX - areaW * 0.30 + ((i - 1) * areaW * 0.30)

        local word = display.newText({
            parent = animGroup,
            text = words[i],
            x = startX,
            y = areaY - areaH * 0.05,
            font = native.systemFontBold,
            fontSize = 22
        })
        word:setFillColor(0.02, 0.20, 0.46)

        transition.to(word, {
            delay = (i - 1) * 450,
            time = 1100,
            x = centerX,
            y = basket.y - basket.height,
            alpha = 0.08,
            transition = easing.inOutQuad
        })
    end

    transition.to(basketTop, {
        delay = 1400,
        time = 320,
        xScale = 1.12,
        yScale = 1.12,
        iterations = 2,
        transition = easing.continuousLoop
    })

    return animGroup
end

local function addClassPopup(parent, imageName, centerX, centerY, cardW, cardH)
    local img = display.newImage(parent, imageName)
    if not img then return end

    local scale = math.min((cardW * 0.82) / img.width, (cardH * 0.36) / img.height)
    img.xScale, img.yScale = scale, scale
    img.x = centerX
    img.y = centerY + cardH * 0.14
end

local function addPhoneScreenshot(parent, imageName, centerX, centerY, cardW, cardH)
    local img = display.newImage(parent, imageName)
    if not img then return end

    local scale = math.min((cardW * 0.75) / img.width, (cardH * 0.32) / img.height)
    img.xScale, img.yScale = scale, scale
    img.x = centerX
    img.y = centerY + cardH * 0.10

    img.xScale = img.xScale * 0.95
    img.yScale = img.yScale * 0.95

    transition.to(img, {
        time = 400,
        xScale = img.xScale / 0.95,
        yScale = img.yScale / 0.95,
        transition = easing.outQuad
    })
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

    ------------------------------------------------------------
    -- Dim background
    ------------------------------------------------------------
    local dim = display.newRect(
        group,
        centerX,
        centerY,
        display.actualContentWidth * 1.4,
        display.actualContentHeight * 1.4
    )
    dim:setFillColor(0, 0, 0, 0.45)
    dim.isHitTestable = true
    dim:addEventListener("touch", function()
        return true
    end)

    ------------------------------------------------------------
    -- Card
    ------------------------------------------------------------
    local cardW = math.min(safeW * 0.86, 620)
    local cardH = math.min(safeH * 0.72, 620)

    local shadow = display.newRoundedRect(
        group,
        centerX + 6,
        centerY + 8,
        cardW,
        cardH,
        26
    )
    shadow:setFillColor(0, 0, 0, 0.18)

    local card = display.newRoundedRect(
        group,
        centerX,
        centerY,
        cardW,
        cardH,
        26
    )
    card:setFillColor(0.97, 0.98, 1)
    card.strokeWidth = 4
    card:setStrokeColor(0.02, 0.32, 0.68)

    ------------------------------------------------------------
    -- Blue ground
    ------------------------------------------------------------
    local groundY = centerY + cardH * 0.24

    local sheepArea = display.newRect(
        group,
        centerX,
        groundY,
        cardW - 10,
        cardH * 0.24
    )
    sheepArea:setFillColor(0.80, 0.90, 1.0)

    local hill = display.newCircle(
        group,
        centerX,
        groundY + 25,
        cardW * 0.40
    )
    hill.xScale = 1.2
    hill.yScale = 0.22
    hill:setFillColor(0.68, 0.83, 0.96)

    ------------------------------------------------------------
    -- Footer strip
    ------------------------------------------------------------
    local footer = display.newRect(
        group,
        centerX,
        centerY + cardH * 0.36,
        cardW - 8,
        cardH * 0.20
    )
    footer:setFillColor(0.74, 0.84, 0.95)

    ------------------------------------------------------------
    -- Title
    ------------------------------------------------------------
    local title = display.newText({
        parent = group,
        text = tOr(step.titleKey, step.titleFallback),
        x = centerX,
        y = centerY - cardH * 0.34,
        font = native.systemFontBold,
        fontSize = 42,
        width = cardW * 0.86,
        align = "center"
    })
    title:setFillColor(0.02, 0.20, 0.46)

    ------------------------------------------------------------
    -- Divider
    ------------------------------------------------------------
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

    ------------------------------------------------------------
    -- Body text
    ------------------------------------------------------------
    local body = display.newText({
        parent = group,
        text = tOr(step.textKey, step.textFallback),
        x = centerX,
        y = centerY - cardH * 0.10,
        width = cardW * 0.82,
        font = native.systemFont,
        fontSize = 32,
        align = "center"
    })
    body:setFillColor(0.02, 0.20, 0.46)

    ------------------------------------------------------------
    -- Visual area
    ------------------------------------------------------------
    if step.mode == "gameplay" then
        createGameplayAnimation(group, centerX, centerY, cardW, cardH)

    elseif step.mode == "appIcon" and step.image then
        addRoundedAppIcon(
            group,
            step.image,
            centerX,
            centerY + cardH * 0.16,
            cardW,
            cardH
        )

    elseif step.mode == "image" and step.image then
        local img = display.newImage(group, step.image)

        if img then
            local maxW = cardW * 0.55
            local maxH = cardH * 0.30
            local scale = math.min(maxW / img.width, maxH / img.height)

            img.xScale = scale
            img.yScale = scale
            img.x = centerX
            img.y = centerY + cardH * 0.20
        end

    elseif step.mode == "classPopup" then
        addClassPopup(group, step.image, centerX, centerY, cardW, cardH)

    elseif step.mode == "phoneScreenshot" then
        addPhoneScreenshot(group, step.image, centerX, centerY, cardW, cardH)
    else
        addSheep(group, centerX, groundY, cardW)
    end

    ------------------------------------------------------------
    -- Dots
    ------------------------------------------------------------
    local dotY = footer.y
    local dotStartX = centerX - cardW * 0.35

    for i = 1, #steps do
        makeDot(group, dotStartX + ((i - 1) * 30), dotY, i == currentStep)
    end

    ------------------------------------------------------------
    -- Next button
    ------------------------------------------------------------
    local btnX = centerX + cardW * 0.27

    local nextBtn = display.newRoundedRect(group, btnX, dotY, 180, 72, 24)
    nextBtn:setFillColor(0.02, 0.22, 0.50)

    local nextText = display.newText({
        parent = group,
        text = currentStep == #steps and tOr("done", "Done") or (tOr("next", "Next") .. " ›"),
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
function tutorial.start()
    currentStep = 1
    showStep()
end

function tutorial.stop()
    clearStep()
end

return tutorial
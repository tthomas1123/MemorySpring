-- selectLevelsTutorial.lua
local tutorial = {}

local languages = require("languages")

local group
local currentStep = 1

local function tOr(key, fallback)
    local value = languages.t(key)
    if value == nil or value == "" or value == key then
        return fallback
    end
    return value
end

local steps = {
    {
        titleKey = "tutorial_class_settings_title",
        title = "Class Settings",
        textKey = "tutorial_class_settings_text",
        text = "This is where you can update your class.",
        mode = "sheep"
    },
    {
        titleKey = "tutorial_change_class_name_title",
        title = "Change Class Name",
        textKey = "tutorial_change_class_name_text",
        text = "Tap the Class Name box to rename your class.",
        mode = "className"
    },
    {
        titleKey = "tutorial_publish_class_title",
        title = "Publish Class",
        textKey = "tutorial_publish_class_text",
        text = "Tap Published when your class is ready for students.",
        mode = "publish"
    },
    {
        titleKey = "tutorial_save_changes_title",
        title = "Save Changes",
        textKey = "tutorial_save_changes_text",
        text = "Tap Save to update your class name and publish setting.",
        mode = "save"
    },
    {
        titleKey = "tutorial_add_level_title",
        title = "Add a Level",
        textKey = "tutorial_add_level_text",
        text = "Tap Add Level to create game levels for this class.",
        mode = "addLevel"
    },
}

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

        local shadow = display.newCircle(
            parent,
            centerX,
            y + sheep.contentHeight * 0.34,
            targetW * 0.35
        )

        shadow.xScale = 1.8
        shadow.yScale = 0.28
        shadow:setFillColor(0, 0, 0, 0.16)
        shadow:toBack()
        sheep:toFront()
    end
end

local function addMiniClassCard(parent, centerX, centerY, cardW, cardH, mode)
    local panelW = cardW * 0.78
    local panelH = cardH * 0.30
    local panelY = centerY + cardH * 0.13

    local panel = display.newRoundedRect(parent, centerX, panelY, panelW, panelH, 18)
    panel:setFillColor(1, 1, 1, 0.92)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.55, 0.72, 0.90)

    if mode == "addLevel" then
        local addBtn = display.newRoundedRect(
            parent,
            centerX,
            panelY,
            panelW * 0.58,
            62,
            22
        )

        addBtn:setFillColor(0.02, 0.22, 0.50)
        addBtn.strokeWidth = 4
        addBtn:setStrokeColor(1, 0.70, 0.12)

        local addText = display.newText({
            parent = parent,
            text = tOr("tutorial_add_level_button", "➕ Add Level"),
            x = addBtn.x,
            y = addBtn.y,
            font = native.systemFontBold,
            fontSize = 26
        })
        addText:setFillColor(1, 1, 1)

        return
    end

    local label = display.newText({
        parent = parent,
        text = tOr("tutorial_class_name_label", "Class Name:"),
        x = centerX - panelW * 0.38,
        y = panelY - panelH * 0.30,
        font = native.systemFontBold,
        fontSize = 20,
        align = "left"
    })
    label.anchorX = 0
    label:setFillColor(0.02, 0.20, 0.46)

    local field = display.newRoundedRect(
        parent,
        centerX,
        panelY - panelH * 0.06,
        panelW * 0.78,
        46,
        10
    )

    field:setFillColor(1, 1, 1)
    field.strokeWidth = mode == "className" and 4 or 2
    field:setStrokeColor(
        mode == "className" and 1 or 0.75,
        mode == "className" and 0.70 or 0.75,
        0.12
    )

    local fieldText = display.newText({
        parent = parent,
        text = tOr("tutorial_sample_class_name", "Sunday School"),
        x = centerX,
        y = field.y,
        font = native.systemFontBold,
        fontSize = 22
    })
    fieldText:setFillColor(0.02, 0.20, 0.46)

    local pillY = panelY + panelH * 0.28
    local leftX = centerX - panelW * 0.28

    local draft = display.newRoundedRect(parent, leftX, pillY, 88, 44, 14)
    draft:setFillColor(0.65, 0.78, 0.92, 0.95)

    local draftText = display.newText({
        parent = parent,
        text = tOr("tutorial_draft", "Draft"),
        x = draft.x,
        y = draft.y,
        font = native.systemFontBold,
        fontSize = 20
    })
    draftText:setFillColor(1, 1, 1)

    local published = display.newRoundedRect(parent, leftX + 118, pillY, 116, 44, 14)

    if mode == "publish" then
        published:setFillColor(0.38, 0.75, 0.62, 0.95)
        published.strokeWidth = 4
        published:setStrokeColor(1, 0.70, 0.12)
    else
        published:setFillColor(1, 1, 1, 0.92)
        published.strokeWidth = 2
        published:setStrokeColor(0.02, 0.22, 0.50)
    end

    local publishedText = display.newText({
        parent = parent,
        text = tOr("tutorial_published", "Published"),
        x = published.x,
        y = published.y,
        font = native.systemFontBold,
        fontSize = 20
    })

    publishedText:setFillColor(
        mode == "publish" and 1 or 0.02,
        mode == "publish" and 1 or 0.22,
        mode == "publish" and 1 or 0.50
    )

    local save = display.newRoundedRect(
        parent,
        centerX + panelW * 0.31,
        pillY,
        100,
        48,
        16
    )

    save:setFillColor(0.02, 0.22, 0.50)

    if mode == "save" then
        save.strokeWidth = 4
        save:setStrokeColor(1, 0.70, 0.12)
    end

    local saveText = display.newText({
        parent = parent,
        text = tOr("tutorial_save_button", "Save"),
        x = save.x,
        y = save.y,
        font = native.systemFontBold,
        fontSize = 21
    })
    saveText:setFillColor(1, 1, 1)
end

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
        fontSize = 32,
        align = "center"
    })
    body:setFillColor(0.02, 0.20, 0.46)

    if step.mode == "sheep" then
        addSheep(group, centerX, groundY, cardW)
    else
        addMiniClassCard(group, centerX, centerY, cardW, cardH, step.mode)
    end

    local dotY = footer.y
    local dotStartX = centerX - cardW * 0.30

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

function tutorial.start()
    currentStep = 1
    showStep()
end

function tutorial.stop()
    clearStep()
end

return tutorial
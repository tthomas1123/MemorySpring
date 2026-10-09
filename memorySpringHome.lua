-- Memory Spring welcome screen, inspired by the original botanical mockup.
-- Only this scene changes; the Creator Catch game is untouched.
local composer = require("composer")
local scene = composer.newScene()
local unpack = table.unpack or unpack

local C = {
    cream = {0.992, 0.973, 0.929},
    green = {0.29, 0.42, 0.34},
    sage = {0.69, 0.75, 0.60},
    pale = {0.85, 0.86, 0.70},
    gold = {0.69, 0.48, 0.22},
    ink = {0.25, 0.25, 0.18},
}
local function fill(shape, color, alpha)
    shape:setFillColor(color[1], color[2], color[3], alpha or 1)
    return shape
end
local function label(group, value, x, y, width, size, color, font)
    local obj = display.newText({
        parent = group, text = value, x = x, y = y, width = width,
        font = font or native.systemFont, fontSize = size, align = "center"
    })
    obj:setFillColor(unpack(color))
    return obj
end
local function leaf(group, x, y, rx, ry, rotation, color, alpha)
    local l = display.newCircle(group, x, y, math.max(rx, ry))
    l.xScale = rx / math.max(rx, ry)
    l.yScale = ry / math.max(rx, ry)
    l.rotation = rotation
    fill(l, color, alpha)
    return l
end
local function branch(group, x, y, scale, mirrored)
    local sign = mirrored and -1 or 1
    local stem = display.newLine(group, x, y, x + sign*29*scale, y + 170*scale)
    stem.strokeWidth = 2*scale
    stem:setStrokeColor(0.54, 0.63, 0.44, 0.55)
    for i=0,5 do
        local by = y + (20+i*25)*scale
        local bx = x + sign*(5+i*4)*scale
        local side = (i%2==0) and 1 or -1
        leaf(group,bx+sign*side*17*scale,by,17*scale,7*scale,
            sign*side*43,C.sage,0.72)
    end
end
local function hill(group, x, y, width, height, color, alpha)
    local shape = display.newCircle(group,x,y,math.max(width,height)/2)
    shape.xScale = width / math.max(width,height)
    shape.yScale = height / math.max(width,height)
    fill(shape,color,alpha)
    return shape
end

function scene:create()
    local g = self.view
    local left = display.screenOriginX or 0
    local top = display.screenOriginY or 0
    local width = display.actualContentWidth or display.contentWidth
    local height = display.actualContentHeight or display.contentHeight
    local cx = left + width/2
    local bottom = top + height
    local safeTop = display.safeScreenOriginY or top
    local safeBottom = safeTop + (display.safeActualContentHeight or height)
    local safeHeight = safeBottom - safeTop
    local scale = math.min(width/390, height/800)

    fill(display.newRect(g,cx,top+height/2,width+4,height+4),C.cream)
    local background = display.newImageRect(g,"MemorySpringHomeBackground.png",986,1536)
    if background then
        local factor = math.max(width/986,height/1536)
        background.width,background.height = 986*factor,1536*factor
        background.x,background.y = cx,top+height/2
    else
        print("Missing MemorySpringHomeBackground.png beside main.lua")
    end

    local titleY = safeTop + safeHeight*0.255
    label(g,"Memory",cx,titleY-18*scale,width-44,57*scale,C.green,"Georgia")
    label(g,"Spring",cx,titleY+38*scale,width-44,62*scale,C.gold,"Georgia")
    label(g,"Keep special people\nclose in your heart.",cx,
        titleY+125*scale,width-60,22*scale,C.ink,"Georgia")

    local buttonY = safeBottom - 105*scale
    local buttonWidth = math.min(width-60*scale,330*scale)
    local btn = display.newRoundedRect(g,cx,buttonY,buttonWidth,60*scale,30*scale)
    fill(btn,C.green)
    label(g,"Get Started  →",cx,buttonY,buttonWidth-20,22*scale,{1,1,1},"Georgia")
    btn:addEventListener("tap",function()
        composer.removeScene("game")
        composer.gotoScene("game",{
            effect="slideLeft",time=220,params={memorySpringSample=true}
        })
        return true
    end)

    -- Setup remains accessible, but doesn't compete with the main action.
    local setup = label(g,"Create a Memory",cx,safeBottom-39*scale,
        width-50,19*scale,C.green,"Georgia")
    setup:addEventListener("tap",function()
        -- Always display the account gate during login-flow testing.
        composer.gotoScene("memorySpringLogin",{effect="slideLeft",time=220})
        return true
    end)
end
scene:addEventListener("create",scene)
return scene

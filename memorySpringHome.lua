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
    local l = display.newEllipse(group, x, y, rx * 2, ry * 2)
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
    local shape = display.newEllipse(group,x,y,width,height)
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
    -- Quiet botanical edges, like the original illustrated welcome mockup.
    branch(g,left+4,top+6,scale,false)
    branch(g,left+width-4,top+12,scale,true)
    branch(g,left+4,top+height*0.47,scale,false)

    local titleY = safeTop + safeHeight*0.27
    -- Tiny sprout above the wordmark.
    local stem = display.newLine(g,cx,titleY-72*scale,cx,titleY-42*scale)
    stem.strokeWidth=3*scale
    stem:setStrokeColor(unpack(C.green))
    leaf(g,cx-12*scale,titleY-65*scale,16*scale,8*scale,38,C.sage)
    leaf(g,cx+13*scale,titleY-69*scale,16*scale,8*scale,-38,C.green)
    label(g,"Memory",cx,titleY-14*scale,width-50,55*scale,C.green,native.systemFont)
    label(g,"Spring",cx,titleY+42*scale,width-50,59*scale,C.gold,native.systemFont)
    label(g,"Keep special people\nclose in your heart.",cx,
        titleY+127*scale,width-55,23*scale,C.ink,native.systemFont)

    -- Soft sunrise and layered rolling hills behind a young sprout.
    local groundY = safeTop + safeHeight*0.82
    fill(display.newCircle(g,cx,groundY-80*scale,92*scale),{1,0.85,0.53},0.32)
    hill(g,cx-width*0.32,groundY+55*scale,width*1.08,190*scale,C.pale,0.57)
    hill(g,cx+width*0.38,groundY+70*scale,width*1.17,195*scale,C.sage,0.48)
    hill(g,cx,groundY+115*scale,width*1.35,170*scale,C.green,0.33)
    hill(g,cx,groundY+118*scale,width*0.55,88*scale,C.gold,0.18)
    local plantY=groundY+24*scale
    local plantStem=display.newLine(g,cx,plantY+18*scale,cx,plantY-52*scale)
    plantStem.strokeWidth=4*scale
    plantStem:setStrokeColor(unpack(C.green))
    leaf(g,cx-23*scale,plantY-45*scale,32*scale,13*scale,30,C.sage)
    leaf(g,cx+25*scale,plantY-56*scale,36*scale,14*scale,-35,C.green)

    local buttonY = safeBottom - 75*scale
    local buttonWidth = math.min(width-52*scale,340*scale)
    local btn = display.newRoundedRect(g,cx,buttonY,buttonWidth,66*scale,32*scale)
    fill(btn,C.green)
    label(g,"Get Started  →",cx,buttonY,buttonWidth-20,23*scale,{1,1,1},native.systemFont)
    btn:addEventListener("tap",function()
        composer.removeScene("game")
        composer.gotoScene("game",{
            effect="slideLeft",time=220,params={memorySpringSample=true}
        })
        return true
    end)

    -- Setup remains accessible, but doesn't compete with the main action.
    local setup = label(g,"Create a Memory",cx,safeBottom-23*scale,
        width-50,15*scale,C.green,native.systemFont)
    setup:addEventListener("tap",function()
        composer.gotoScene("memorySpringSetup",{effect="slideLeft",time=220})
        return true
    end)
end
scene:addEventListener("create",scene)
return scene

-- Memory Spring sample success: calm, accessible celebration.
local composer = require("composer")
local scene = composer.newScene()

local C = {
    cream = {0.992,0.972,0.927},
    ink = {0.19,0.27,0.23},
    green = {0.27,0.42,0.34},
    gold = {0.66,0.45,0.22},
}

local function makeText(group,value,x,y,width,size,color,bold)
    local t=display.newText({
        parent=group,text=value,x=x,y=y,width=width,
        font=bold and native.systemFontBold or native.systemFont,
        fontSize=size,align="center"
    })
    t:setFillColor(color[1],color[2],color[3])
    return t
end

function scene:create()
    local g=self.view
    local x0=display.screenOriginX or 0
    local y0=display.screenOriginY or 0
    local width=display.actualContentWidth or display.contentWidth
    local height=display.actualContentHeight or display.contentHeight
    local cx=x0+width*0.5
    local cy=y0+height*0.5
    local safeTop=display.safeScreenOriginY or y0
    local safeHeight=display.safeActualContentHeight or height
    local safeBottom=safeTop+safeHeight
    local scale=math.min(width/390,safeHeight/800)

    local bg=display.newRect(g,cx,cy,width+4,height+4)
    bg:setFillColor(C.cream[1],C.cream[2],C.cream[3])

    -- Same watercolor landscape as the Catch sample.
    local art=display.newImageRect(g,"MemorySpringGameBackground.png",986,1536)
    if art then
        local factor=math.max(width/986,height/1536)
        art.width,art.height=986*factor,1536*factor
        art.x,art.y=cx,cy
    end

    -- Opaque enough for legible text against detailed scenery.
    local cardWidth=width-36*scale
    local cardHeight=math.min(safeHeight*0.69,535*scale)
    local cardY=safeTop+safeHeight*0.435
    local card=display.newRoundedRect(g,cx,cardY,cardWidth,cardHeight,22*scale)
    card:setFillColor(1,0.972,0.919,0.96)
    card.strokeWidth=2*scale
    card:setStrokeColor(0.71,0.56,0.39,0.55)

    local top=cardY-cardHeight*0.5
    makeText(g,"A moment worth remembering",cx,top+38*scale,
        cardWidth-26*scale,21*scale,C.green,true)

    local portrait=display.newImageRect(g,"AbrahamLincoln.png",130*scale,130*scale)
    if portrait then
        portrait.x,portrait.y=cx,top+140*scale
    end

    makeText(g,"Abraham Lincoln",cx,top+232*scale,
        cardWidth-26*scale,29*scale,C.ink,true)
    makeText(g,"Honest  •  Kind  •  Brave  •  Leader",cx,top+276*scale,
        cardWidth-22*scale,18*scale,C.ink,false)

    makeText(g,"You did beautifully!",cx,top+351*scale,
        cardWidth-26*scale,27*scale,C.green,true)

    local buttonY=safeBottom-116*scale
    local buttonWidth=math.min(width-60*scale,320*scale)
    local button=display.newRoundedRect(g,cx,buttonY,buttonWidth,62*scale,31*scale)
    button:setFillColor(C.green[1],C.green[2],C.green[3])
    makeText(g,"Play Again",cx,buttonY,buttonWidth-18*scale,23*scale,{1,1,1},true)
    button:addEventListener("tap",function()
        composer.removeScene("game")
        composer.gotoScene("game",{effect="fade",time=250,params={memorySpringSample=true}})
        return true
    end)

    local homeY=safeBottom-43*scale
    local homeTarget=display.newRect(g,cx,homeY,buttonWidth,48*scale)
    homeTarget.isVisible=false
    homeTarget.isHitTestable=true
    -- A light backing keeps the secondary action readable over dark watercolor grass.
    local homeBacking=display.newRoundedRect(g,cx,homeY,buttonWidth*0.62,44*scale,22*scale)
    homeBacking:setFillColor(1,0.972,0.919,0.95)
    homeBacking.strokeWidth=1.5*scale
    homeBacking:setStrokeColor(0.27,0.42,0.34,0.5)
    makeText(g,"Home",cx,homeY,buttonWidth,23*scale,C.ink,true)
    homeTarget:toFront()
    homeTarget:addEventListener("tap",function()
        composer.gotoScene("memorySpringHome",{effect="fade",time=250})
        return true
    end)
end

scene:addEventListener("create",scene)
return scene

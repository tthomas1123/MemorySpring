local composer=require("composer")
local scene=composer.newScene()
local C={bg={0.976,0.966,0.94},green={0.25,0.40,0.32},light={0.87,0.92,0.85},gold={0.72,0.55,0.30},ink={0.18,0.28,0.23}}
local function txt(g,s,x,y,w,size,color,bold)
 local t=display.newText({parent=g,text=s,x=x,y=y,width=w,font=bold and native.systemFontBold or native.systemFont,fontSize=size,align="center"})
 t:setFillColor(unpack(color));return t
end
local function button(g,text,y,color,action)
 local x=display.contentCenterX
 local w=math.min(display.safeActualContentWidth-44,390)
 local b=display.newRoundedRect(g,x,y,w,58,20);b:setFillColor(unpack(color))
 txt(g,text,x,y,w-20,20,{1,1,1},true)
 b:addEventListener("tap",function() action();return true end)
end
function scene:create()
 local g=self.view;local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 local bg=display.newRect(g,cx,display.contentCenterY,display.actualContentWidth+4,display.actualContentHeight+4)
 bg:setFillColor(unpack(C.bg))
 local circle=display.newCircle(g,cx,top+h*0.30,math.min(display.safeActualContentWidth*0.30,112))
 circle:setFillColor(unpack(C.light))
 txt(g,"✿",cx,top+h*0.30,170,84,C.green,true)
 txt(g,"MEMORY SPRING",cx,top+h*0.12,display.safeActualContentWidth-30,27,C.green,true)
 txt(g,"A moment to remember",cx,top+h*0.51,display.safeActualContentWidth-30,24,C.ink,true)
 txt(g,"Gentle play. Familiar memories.\nAlways a reason to smile.",cx,top+h*0.60,display.safeActualContentWidth-45,17,C.green,false)
 button(g,"Get Started",top+h*0.76,C.green,function() composer.removeScene("game"); composer.gotoScene("game",{effect="slideLeft",time=220,params={memorySpringSample=true}}) end)
 button(g,"Setup",top+h*0.87,C.gold,function() composer.gotoScene("memorySpringSetup",{effect="slideLeft",time=220}) end)
end
scene:addEventListener("create",scene)
return scene

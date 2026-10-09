-- Memory Spring sample: basket-based, always-winnable catch game.
-- Uses the SmartSheep basket artwork; no scores, time limits, penalties or losing.
local composer=require("composer")
local physics=require("physics")
local scene=composer.newScene()
local words={"Honest","Kind","Brave","Leader"}
local green={0.25,0.40,0.32}
local cream={0.976,0.966,0.94}
local falling, basket, ticker, hint, subtitle, stageGroup
local index=1
local completed=false
local function text(parent,value,x,y,w,size,color)
 local t=display.newText({parent=parent,text=value,x=x,y=y,width=w,font=native.systemFontBold,fontSize=size,align="center"})
 t:setFillColor(unpack(color));return t
end
local function removeFalling()
 if falling then display.remove(falling);falling=nil end
end
local function home()
 if ticker then timer.cancel(ticker);ticker=nil end
 physics.pause()
 composer.gotoScene("memorySpringHome",{effect="slideRight",time=200})
end
local function finish()
 completed=true
 if ticker then timer.cancel(ticker);ticker=nil end
 removeFalling()
 hint.text="You did beautifully!"
 subtitle.text="A moment worth remembering"
 local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 text(stageGroup,"ABRAHAM LINCOLN",cx,top+h*0.41,display.safeActualContentWidth-32,25,green)
 text(stageGroup,"Honest  •  Kind  •  Brave  •  Leader",cx,top+h*0.52,display.safeActualContentWidth-32,17,green)
 text(stageGroup,"Every moment matters.",cx,top+h*0.63,display.safeActualContentWidth-32,19,green)
 local again=text(stageGroup,"Play Again",cx,top+h*0.76,display.safeActualContentWidth-32,23,green)
 again:addEventListener("tap",function()
  composer.removeScene("memorySpringDemo")
  composer.gotoScene("memorySpringDemo")
  return true
 end)
end
local function spawn()
 if completed or falling then return end
 local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local w=display.safeActualContentWidth or display.contentWidth
 local x=cx+math.random(-math.floor(w*0.30),math.floor(w*0.30))
 local group=display.newGroup()
 stageGroup:insert(group)
 local leaf=display.newRoundedRect(group,0,0,math.min(170,w*0.45),64,27)
 leaf:setFillColor(0.84,0.91,0.80)
 text(group,words[index],0,0,150,22,green)
 group.x=x;group.y=top+150
 falling=group
 -- A simple falling motion; if missed, the same word returns.
 local dest=display.contentCenterY+math.min(185,(display.safeActualContentHeight or display.contentHeight)*0.27)
 transition.to(group,{time=4100,y=dest,onComplete=function()
  if falling==group and not completed then removeFalling();ticker=timer.performWithDelay(400,spawn) end
 end})
end
local function checkCatch()
 if not falling or completed then return end
 local dx=math.abs(falling.x-basket.x)
 local dy=math.abs(falling.y-basket.y)
 if dx<100 and dy<95 then
  transition.cancel(falling)
  removeFalling()
  index=index+1
  if index>#words then finish() else
   hint.text="Catch: "..words[index]
   ticker=timer.performWithDelay(400,spawn)
  end
 end
end
local function dragBasket(event)
 if event.phase=="began" then
  display.currentStage:setFocus(event.target)
  event.target.isFocus=true
 elseif event.target.isFocus and (event.phase=="moved" or event.phase=="ended" or event.phase=="cancelled") then
  local left=display.screenOriginX+55
  local right=display.screenOriginX+display.actualContentWidth-55
  basket.x=math.max(left,math.min(right,event.x))
  checkCatch()
  if event.phase~="moved" then
   display.currentStage:setFocus(nil)
   event.target.isFocus=false
  end
 end
 return true
end
function scene:create()
 local g=self.view
 local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 local w=display.safeActualContentWidth or display.contentWidth
 local bg=display.newRect(g,cx,display.contentCenterY,display.actualContentWidth+4,display.actualContentHeight+4)
 bg:setFillColor(unpack(cream))
 text(g,"MEMORY SPRING",cx,top+40,w-35,25,green)
 hint=text(g,"Catch: "..words[1],cx,top+91,w-35,22,green)
 subtitle=text(g,"Move the basket to catch each word",cx,top+128,w-35,15,green)
 stageGroup=display.newGroup();g:insert(stageGroup)
 basket=display.newImageRect(stageGroup,"basket.png",120,120)
 if not basket then
  basket=display.newRoundedRect(stageGroup,cx,top+h*0.77,125,60,16)
  basket:setFillColor(0.68,0.47,0.28)
 end
 basket.x=cx;basket.y=top+h*0.76
 basket:addEventListener("touch",dragBasket)
 local back=text(g,"‹ Home",cx,top+h-34,w-35,20,green)
 back:addEventListener("tap",function()home();return true end)
end
function scene:show(event)
 if event.phase=="did" then
  physics.start();physics.setGravity(0,0)
  index=1;completed=false
  hint.text="Catch: "..words[1]
  subtitle.text="Move the basket to catch each word"
  spawn()
  self.frameListener=function()checkCatch()end
  Runtime:addEventListener("enterFrame",self.frameListener)
 end
end
function scene:hide(event)
 if event.phase=="will" then
  if self.frameListener then Runtime:removeEventListener("enterFrame",self.frameListener);self.frameListener=nil end
  if ticker then timer.cancel(ticker);ticker=nil end
  if falling then transition.cancel(falling) end
  removeFalling()
  physics.pause()
 end
end
scene:addEventListener("create",scene)
scene:addEventListener("show",scene)
scene:addEventListener("hide",scene)
return scene

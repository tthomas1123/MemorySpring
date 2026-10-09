-- Self-contained sample catch game: no account, scores, penalties or failure states.
local composer=require("composer")
local scene=composer.newScene()
local words={"Honest","Kind","Brave","Leader"}
local green={0.25,0.40,0.32};local cream={0.976,0.966,0.94}
local tokens={};local timerHandle;local index=1;local finished=false
local function label(g,s,x,y,w,size,color)
 local t=display.newText({parent=g,text=s,x=x,y=y,width=w,font=native.systemFontBold,fontSize=size,align="center"})
 t:setFillColor(unpack(color));return t
end
local function clearTokens()
 for _,v in ipairs(tokens) do display.remove(v) end
 tokens={}
end
local function goHome()
 if timerHandle then timer.cancel(timerHandle);timerHandle=nil end
 composer.gotoScene("memorySpringHome",{effect="slideRight",time=220})
end
function scene:create()
 local g=self.view;local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 local w=display.safeActualContentWidth or display.contentWidth
 local bg=display.newRect(g,cx,display.contentCenterY,display.actualContentWidth+4,display.actualContentHeight+4)
 bg:setFillColor(unpack(cream))
 label(g,"A GENTLE MOMENT",cx,top+42,w-40,22,green)
 self.instruction=label(g,"Catch the word: "..words[1],cx,top+100,w-40,23,green)
 self.message=label(g,"Tap the floating word to catch it.",cx,top+h*0.20,w-45,17,green)
 local home=label(g,"‹ Home",cx,top+h-44,w-45,20,green)
 home:addEventListener("tap",goHome)
end
local function complete(self)
 finished=true
 clearTokens()
 self.instruction.text="A moment worth remembering"
 self.message.text="You did beautifully."
 local g=self.view;local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 label(g,"ABRAHAM LINCOLN",cx,top+h*0.38,display.safeActualContentWidth-45,26,green)
 label(g,"Honest • Kind • Brave • Leader",cx,top+h*0.48,display.safeActualContentWidth-45,18,green)
 label(g,"Every moment matters.",cx,top+h*0.62,display.safeActualContentWidth-45,20,green)
 local again=label(g,"Play again",cx,top+h*0.75,display.safeActualContentWidth-45,23,green)
 again:addEventListener("tap",function()
  composer.removeScene("memorySpringDemo")
  composer.gotoScene("memorySpringDemo")
 end)
end
local function spawn(self)
 if finished then return end
 clearTokens()
 local g=self.view;local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 local y=top+h*0.44
 local pill=display.newRoundedRect(g,cx,y,math.min(display.safeActualContentWidth-72,250),88,36)
 pill:setFillColor(0.87,0.92,0.85)
 tokens[#tokens+1]=pill
 local word=label(g,words[index],cx,y,210,28,green)
 tokens[#tokens+1]=word
 local function catch()
  if finished then return true end
  index=index+1
  if index>#words then complete(self) else
   self.instruction.text="Catch the word: "..words[index]
   spawn(self)
  end
  return true
 end
 pill:addEventListener("tap",catch);word:addEventListener("tap",catch)
 -- The word stays available until caught. No timeout, no failure.
end
function scene:show(event)
 if event.phase=="did" then index=1;finished=false;self.instruction.text="Catch the word: "..words[1];self.message.text="Tap the floating word to catch it.";spawn(self) end
end
function scene:hide(event)
 if event.phase=="will" then clearTokens();if timerHandle then timer.cancel(timerHandle);timerHandle=nil end end
end
scene:addEventListener("create",scene);scene:addEventListener("show",scene);scene:addEventListener("hide",scene)
return scene

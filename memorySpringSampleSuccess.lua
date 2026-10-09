-- Bundled sample completion. Personal memories continue to use the server-backed success scene.
local composer=require("composer")
local scene=composer.newScene()
function scene:create()
 local g=self.view
 local cx=display.contentCenterX
 local top=display.safeScreenOriginY or 0
 local h=display.safeActualContentHeight or display.contentHeight
 local w=display.safeActualContentWidth or display.contentWidth
 local bg=display.newRect(g,cx,display.contentCenterY,display.actualContentWidth+4,display.actualContentHeight+4)
 bg:setFillColor(0.976,0.966,0.94)
 local function label(s,y,size)
  local t=display.newText({parent=g,text=s,x=cx,y=y,width=w-44,font=native.systemFontBold,fontSize=size,align="center"})
  t:setFillColor(0.25,0.40,0.32)
  return t
 end
 label("A moment worth remembering",top+h*0.19,25)
 label("Abraham Lincoln",top+h*0.38,28)
 label("Honest • Kind • Brave • Leader",top+h*0.48,19)
 label("You did beautifully!",top+h*0.61,23)
 local again=label("Play Again",top+h*0.77,22)
 again:addEventListener("tap",function()
  composer.removeScene("game")
  composer.gotoScene("game",{params={memorySpringSample=true}})
  return true
 end)
 local back=label("Home / Setup",top+h*0.88,20)
 back:addEventListener("tap",function()composer.gotoScene("memorySpringHome");return true end)
end
scene:addEventListener("create",scene)
return scene

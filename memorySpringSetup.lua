-- Memory Spring local-first prototype. No account or server required.
local composer = require("composer")
local json = require("json")
local scene = composer.newScene()
local media = require("media")
local filename = "memory-spring-first-memory.json"
local photoFilename = "memory-spring-photo.jpg"
local bg = {0.975,0.965,0.938}
local ink = {0.18,0.29,0.26}
local sage = {0.31,0.46,0.38}
local muted = {0.43,0.49,0.44}
local gold = {0.77,0.59,0.34}
local state = {words="", success="", photo=false}
local fields = {}
local photoGroup, feedback, previewGroup
local function load()
    local path = system.pathForFile(filename,system.DocumentsDirectory)
    local f = path and io.open(path,"r")
    if f then
        local raw=f:read("*a"); f:close()
        local ok,value=pcall(json.decode,raw)
        if ok and type(value)=="table" then state=value end
    end
end
local function save()
    local path=system.pathForFile(filename,system.DocumentsDirectory)
    if not path then return false end
    local f=io.open(path,"w")
    if not f then return false end
    f:write(json.encode(state)); f:close()
    return true
end
local function rect(parent,x,y,w,h,color,r)
    local obj=display.newRoundedRect(parent,x,y,w,h,r or 18)
    obj:setFillColor(unpack(color)); return obj
end
local function label(parent,value,x,y,w,size,color,bold)
    local obj=display.newText({parent=parent,text=value,x=x,y=y,width=w,font=bold and native.systemFontBold or native.systemFont,fontSize=size,align="center"})
    obj:setFillColor(unpack(color)); return obj
end
local function clearGroup(g)
    if g then display.remove(g) end
end
local function refreshPhoto()
    clearGroup(photoGroup)
    photoGroup=display.newGroup()
    scene.view:insert(photoGroup)
    local sw=display.safeActualContentWidth or display.contentWidth
    local cx=display.contentCenterX
    local y=scene.photoY
    rect(photoGroup,cx,y,sw-64,110,{0.90,0.93,0.88},18)
    local path=system.pathForFile(photoFilename,system.DocumentsDirectory)
    local f=path and io.open(path,"rb")
    if f then
        f:close()
        local img=display.newImageRect(photoGroup,photoFilename,system.DocumentsDirectory,94,94)
        if img then img.x=cx-(sw-64)/2+59;img.y=y end
        label(photoGroup,"Change photo",cx+42,y,sw-170,18,ink,true)
    else
        label(photoGroup,"+  Choose a favorite photo",cx,y,sw-90,18,ink,true)
    end
    photoGroup:addEventListener("tap",function()
        if not media.hasSource or media.hasSource(media.PhotoLibrary) then
            media.selectPhoto({
                mediaSource=media.PhotoLibrary,
                destination={baseDir=system.DocumentsDirectory,filename=photoFilename},
                listener=function(event)
                    if event and event.completed then
                        state.photo=true
                        save()
                        refreshPhoto()
                    end
                end
            })
        else
            native.showAlert("Photo library","No photo library is available on this device.",{"OK"})
        end
        return true
    end)
end
local function field(parent,title,value,y,h,key)
    local sw=display.safeActualContentWidth or display.contentWidth
    local cx=display.contentCenterX
    label(parent,title,cx-sw/2+36+((sw-72)/2),y-43,sw-72,17,ink,true)
    rect(parent,cx,y+15,sw-64,h,{1,1,1},14)
    local input=native.newTextBox(cx,y+15,sw-88,h-16)
    input.isEditable=true
    input.hasBackground=false
    input.font=native.newFont(native.systemFont,18)
    input.text=value or ""
    input:setTextColor(unpack(ink))
    input:addEventListener("userInput",function(event)
        if event.phase=="ended" or event.phase=="submitted" then
            state[key]=input.text or ""
            save()
        end
    end)
    fields[#fields+1]=input
end
local function sync()
    if fields[1] then state.words=fields[1].text or "" end
    if fields[2] then state.success=fields[2].text or "" end
    return save()
end
local function showPreview()
    sync()
    clearGroup(previewGroup)
    previewGroup=display.newGroup()
    scene.view:insert(previewGroup)
    local sw=display.safeActualContentWidth or display.contentWidth
    local sh=display.safeActualContentHeight or display.contentHeight
    local cx,cy=display.contentCenterX,display.contentCenterY
    rect(previewGroup,cx,cy,sw,sh+100,bg,0)
    label(previewGroup,"A moment worth remembering",cx,cy-sh*0.32,sw-50,23,ink,true)
    local photo=display.newImageRect(previewGroup,photoFilename,system.DocumentsDirectory,180,180)
    if photo then photo.x=cx;photo.y=cy-sh*0.11 end
    label(previewGroup,state.success~="" and state.success or "You did beautifully.",cx,cy+sh*0.17,sw-64,25,ink,true)
    label(previewGroup,"Every moment matters.",cx,cy+sh*0.30,sw-64,17,muted,false)
    local close=rect(previewGroup,cx,cy+sh*0.41,sw-80,54,sage,17)
    label(previewGroup,"Back to my memory",cx,cy+sh*0.41,sw-90,18,{1,1,1},true)
    close:addEventListener("tap",function() clearGroup(previewGroup);previewGroup=nil;return true end)
end
function scene:create(event)
    load()
    local g=self.view
    local sw=display.safeActualContentWidth or display.contentWidth
    local sh=display.safeActualContentHeight or display.contentHeight
    local cx=display.contentCenterX
    local top=display.safeScreenOriginY or 0
    rect(g,cx,display.contentCenterY,display.actualContentWidth+10,display.actualContentHeight+10,bg,0)
    label(g,"MEMORY SPRING",cx,top+38,sw-50,16,sage,true)
    label(g,"A familiar face. A joyful moment.",cx,top+84,sw-42,23,ink,true)
    label(g,"Create one simple memory to begin.",cx,top+120,sw-52,16,muted,false)
    self.photoY=top+205
    label(g,"1  A PHOTO TO TREASURE",cx,top+156,sw-60,14,gold,true)
    label(g,"2  WORDS TO REMEMBER",cx,top+300,sw-60,14,gold,true)
    label(g,"3  A MESSAGE OF ENCOURAGEMENT",cx,top+sh*0.58,sw-60,14,gold,true)
    local firstY=top+sh*0.41
    local secondY=top+sh*0.68
    field(g,"A name, phrase, or a few special words",state.words,firstY,math.max(76,sh*0.14),"words")
    field(g,"What would you like them to hear?",state.success,secondY,math.max(76,sh*0.12),"success")
    local by=top+sh-57
    local button=rect(g,cx,by,sw-64,56,sage,17)
    label(g,"Save & see the encouragement",cx,by,sw-80,17,{1,1,1},true)
    button:addEventListener("tap",function()
        if sync() then showPreview() else native.showAlert("Save failed","Please try again.",{"OK"}) end
        return true
    end)
    refreshPhoto()
end
function scene:hide(event)
    if event.phase=="will" then
        sync()
        for _,input in ipairs(fields) do display.remove(input) end
        fields={}
    end
end
function scene:destroy(event)
    for _,input in ipairs(fields) do display.remove(input) end
    fields={}
end
scene:addEventListener("create",scene)
scene:addEventListener("hide",scene)
scene:addEventListener("destroy",scene)
return scene

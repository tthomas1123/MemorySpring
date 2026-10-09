-- Memory Spring local-first prototype. No account or server required.
local composer = require("composer")
local json = require("json")
local scene = composer.newScene()
local media = require("media")
local filename = "memory-spring-first-memory.json"
local photoFilename = "memory-spring-photo.jpg"
local bg = {0.992,0.973,0.929}
local ink = {0.18,0.29,0.26}
local sage = {0.31,0.46,0.38}
local muted = {0.43,0.49,0.44}
local gold = {0.77,0.59,0.34}
local state = {words="", success="", photo=false}
local fields = {}
local photoGroup, feedback, previewGroup, fieldGroup
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
    rect(photoGroup,cx,y,sw-44,110,{0.90,0.93,0.88},18)
    local path=system.pathForFile(photoFilename,system.DocumentsDirectory)
    local f=path and io.open(path,"rb")
    if f then
        f:close()
        local img=display.newImageRect(photoGroup,photoFilename,system.DocumentsDirectory,102,102)
        if img then img.x=cx-(sw-44)/2+62;img.y=y end
        label(photoGroup,"Change photo",cx+54,y,sw-160,21,ink,true)
    else
        label(photoGroup,"+  Choose a favorite photo",cx,y,sw-70,21,ink,true)
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
    label(parent,title,cx,y-43,sw-54,20,ink,true)
    local backing=rect(parent,cx,y+15,sw-44,h,{1,0.985,0.956},14)
    backing.strokeWidth=1.5
    backing:setStrokeColor(0.72,0.62,0.49)
    local input=native.newTextBox(cx,y+15,sw-64,h-16)
    input.isEditable=true
    input.hasBackground=false
    input.font=native.newFont(native.systemFont,22)
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
    local scale=math.min(sw/390,sh/800)
    rect(g,cx,display.contentCenterY,display.actualContentWidth+10,display.actualContentHeight+10,bg,0)

    -- Watercolor scenery behind an opaque, readable form surface.
    local art=display.newImageRect(g,"MemorySpringHomeBackground.png",986,1536)
    if art then
        local aw=display.actualContentWidth or sw
        local ah=display.actualContentHeight or sh
        local factor=math.max(aw/986,ah/1536)
        art.width,art.height=986*factor,1536*factor
        art.x,art.y=display.contentCenterX,display.contentCenterY
    end
    local wash=rect(g,cx,top+sh*0.48,sw-12,sh*0.91,{1,0.976,0.938},20)
    wash.alpha=0.96

    local back=label(g,"‹ Back",cx-sw*0.38,top+26*scale,sw*0.24,20*scale,sage,true)
    back:addEventListener("tap",function()
        sync()
        native.setKeyboardFocus(nil)
        composer.gotoScene("memorySpringHome",{effect="slideRight",time=220})
        return true
    end)
    label(g,"MEMORY SPRING",cx,top+26*scale,sw-40,15*scale,sage,true)
    label(g,"Create a Memory",cx,top+68*scale,sw-36,31*scale,ink,true)
    label(g,"A familiar face. A joyful moment.",cx,top+110*scale,sw-38,18*scale,muted,false)

    label(g,"1  CHOOSE A FAVORITE PHOTO",cx,top+153*scale,sw-40,16*scale,gold,true)
    self.photoY=top+212*scale

    label(g,"2  WORDS TO REMEMBER",cx,top+284*scale,sw-40,16*scale,gold,true)

    label(g,"3  MESSAGE OF ENCOURAGEMENT",cx,top+483*scale,sw-40,16*scale,gold,true)

    local by=top+sh-47*scale
    local button=rect(g,cx,by,sw-44,58*scale,sage,21*scale)
    label(g,"Save Memory",cx,by,sw-60,22*scale,{1,1,1},true)
    button:addEventListener("tap",function()
        if sync() then showPreview() else native.showAlert("Save failed","Please try again.",{"OK"}) end
        return true
    end)
    refreshPhoto()
end
-- Native controls do not belong to Composer's display group.
-- Recreate them whenever this cached scene is shown after login/navigation.
function scene:show(event)
    if event.phase=="did" and #fields==0 then
        local sw=display.safeActualContentWidth or display.contentWidth
        local sh=display.safeActualContentHeight or display.contentHeight
        local top=display.safeScreenOriginY or 0
        local scale=math.min(sw/390,sh/800)
        fieldGroup=display.newGroup()
        self.view:insert(fieldGroup)
        field(fieldGroup,"Name or special words",state.words,top+352*scale,88*scale,"words")
        field(fieldGroup,"What would you like them to hear?",state.success,top+548*scale,92*scale,"success")
    end
end
function scene:hide(event)
    if event.phase=="will" then
        sync()
        for _,input in ipairs(fields) do display.remove(input) end
        fields={}
        clearGroup(fieldGroup)
        fieldGroup=nil
    end
end
function scene:destroy(event)
    for _,input in ipairs(fields) do display.remove(input) end
    fields={}
    clearGroup(fieldGroup)
    fieldGroup=nil
end
scene:addEventListener("create",scene)
scene:addEventListener("show",scene)
scene:addEventListener("hide",scene)
scene:addEventListener("destroy",scene)
return scene

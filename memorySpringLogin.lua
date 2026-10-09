-- Memory Spring account gate. Existing Infosha login/register web pages.
-- No passwords are collected or stored by this scene.
local composer=require("composer")
local appState=require("appState")
local scene=composer.newScene()
local webview

local function decode(s)
    if not s then return "" end
    s=s:gsub("+"," ")
    return (s:gsub("%%(%x%x)",function(h)return string.char(tonumber(h,16))end))
end

local function queryValue(url,key)
    return decode(url:match("[?&]"..key.."=([^&#]*)"))
end

local function clearWebView()
    if webview then display.remove(webview);webview=nil end
end

local function trustedSuccess(url)
    if type(url)~="string" then return false end
    local host=url:match("^https://([^/%?#]+)")
    if host~="www.infoshagame.com" and host~="infoshagame.com" then return false end
    return queryValue(url,"status")=="success"
end

local function openAccountPage(page)
    clearWebView()
    local sw=display.safeActualContentWidth or display.contentWidth
    local sh=display.safeActualContentHeight or display.contentHeight
    local cx=display.contentCenterX
    local cy=display.contentCenterY
    webview=native.newWebView(cx,cy+18,sw*0.96,sh*0.82)
    webview:request("https://www.infoshagame.com/user/list/"..page..".html?lang=en")
    webview:addEventListener("urlRequest",function(event)
        local url=event and event.url
        if not trustedSuccess(url) then return end
        local id=queryValue(url,"id")
        local username=queryValue(url,"username")
        local token=queryValue(url,"token")
        if not id:match("^%d+$") or username=="" or token=="" then
            native.showAlert("Sign-in incomplete","Please try signing in again.",{"OK"})
            return
        end
        appState.set({userId=id,userName=username,apiToken=token})
        system.setPreferences("app",{userId=id,userName=username,apiToken=token})
        clearWebView()
        composer.gotoScene("memorySpringSetup",{effect="fade",time=220})
    end)
end

function scene:create()
    local g=self.view
    local sw=display.safeActualContentWidth or display.contentWidth
    local sh=display.safeActualContentHeight or display.contentHeight
    local cx=display.contentCenterX
    local top=display.safeScreenOriginY or 0
    local bg=display.newRect(g,cx,display.contentCenterY,display.actualContentWidth+4,display.actualContentHeight+4)
    bg:setFillColor(0.992,0.973,0.929)
    local function txt(value,y,size,color)
        local t=display.newText({parent=g,text=value,x=cx,y=y,width=sw-36,font=native.systemFontBold,fontSize=size,align="center"})
        t:setFillColor(unpack(color))
        return t
    end
    txt("Create a Memory",top+sh*0.13,29,{0.27,0.42,0.34})
    txt("Sign in to create and save a memory.",top+sh*0.20,19,{0.25,0.29,0.25})
    local function button(value,y,action)
        local rect=display.newRoundedRect(g,cx,y,sw-54,56,24)
        rect:setFillColor(0.29,0.42,0.34)
        local label=txt(value,y,21,{1,1,1})
        rect:addEventListener("tap",function()action();return true end)
        label:addEventListener("tap",function()action();return true end)
    end
    button("Log In",top+sh*0.34,function()openAccountPage("login")end)
    button("Create an Account",top+sh*0.45,function()openAccountPage("register")end)
    local back=txt("Back to Home",top+sh*0.57,20,{0.27,0.42,0.34})
    back:addEventListener("tap",function()
        clearWebView()
        composer.gotoScene("memorySpringHome",{effect="slideRight",time=220})
        return true
    end)
end

function scene:hide(event)
    if event.phase=="will" then clearWebView() end
end
scene:addEventListener("create",scene)
scene:addEventListener("hide",scene)
return scene

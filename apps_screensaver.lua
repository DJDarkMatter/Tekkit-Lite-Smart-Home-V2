-- Animated terminal patterns, CC BY-SA 3.0.
-- Matrix visual inspiration: DJDarkMatter/TekkitSwitchBoard,
-- ConvertToScreenSaverLater.lua and ConvertToScreenSaverLater2.lua.
-- The latter credits Felix Maxwell, 2013, CC BY-SA 3.0.
-- These renderers are new implementations; no IO or standalone loops are used.
-- https://creativecommons.org/licenses/by-sa/3.0/
local app={title="Screensaver",minWidth=2,minHeight=2,fullscreenOnly=true,transientWindow=true,hideTaskbar=true,handlesFullscreenCorner=true,animationInterval=0.2}
local titles={"Matrix streams","Matrix wall","Plasma","Ripple fields","Truchet flow","Silk waves","Kaleidoscope","Life garden",
    "Nyan Cat","Starflight","Northern lights","Lava lamp","Neon tunnel","Fireworks","Spiral ribbons"}
local name="screensaver"
local runtime={}
local pi=math.pi
local palette={2048,1024,4,64,2,16,32,512,8}
local letters="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:;<>+-*/={}[]"
-- nyancat.lua
-- Cropped animation frames adapted from K. Lange's ComputerCraft port.
-- Original Nyan Cat animation: prguitarman (Chris Torres).
--
-- https://github.com/klange/nyancat-cc
-- https://github.com/klange/nyancat
--
-- Copyright 2016-2022 K. Lange <klange@toaruos.org>
--
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
-- ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
-- IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


local nyanFrames={
    {",,,,,,,,''''''''''''''',,,,,,",",>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,",">>>>>>'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$''$-$$@','',","&&&&&&'@$$$$$$$$'**'$$$@''**'","&'''++'@$$$$$-$$'***$$$@'***'","+**''+'@$$$$$$$$'***''''****'","+'**'''@$$$$$$$$'***********'","+''**''@$$$$$$-'*************","##''**'@$-$$$$$'***.'****.'**","###''''@$$$$$$$'***''**'*''**","#====''@@$$$-$$'*%%********%%","======'@@@$$$$$$'***''''''**'","=;;;;'''@@@@@@@@@'*********',",";;;;'***''''''''''''''''''',,",";;;;'**'','*',,,,,'*','**',,,",";,,,'''',,'',,,,,,,'',,'',,,,",",,,,,,,,,,,,,,,,,,,,,,,,,,,,,"},
    {",,,,,,,,''''''''''''''',,,,,,",",>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,",">>>>>>'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&&&&&&'@$$$$$$$$$'**'$$@','**","&+++++'@$$$$$-$$$'***$$@''***","++'+++'@$$$$$$$$$'***''''****","+'*'++'@$$$$$$$$$'***********","+'*''''@$$$$$$-$'************","##****'@$-$$$$$$'***.'****.'*","##''**'@$$$$$$$$'***''**'*''*","#==='''@@$$$-$$$'*%%********%","======'@@@$$$$$$$'***''''''**","=;;;;;''@@@@@@@@@@'*********'",";;;;;'**'''''''''''''''''''',",";;;;;'**','*',,,,,,**','**',,",";,,,,''',,,'',,,,,,''',,''',,",",,,,,,,,,,,,,,,,,,,,,,,,,,,,,"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",,,,,,,,''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&&&&&&'@$$$$$$$$$'**'$$@','**","++++++'@$$$$$-$$$'***$$@''***","++++++'@$$$$$$$$$'***''''****","++++++'@$$$$$$$$$'***********","#####''@$$$$$$-$'************","##'''''@$-$$$$$$'***.'****.'*","#'****'@$$$$$$$$'***''**'*''*","=='''='@@$$$-$$$'*%%********%","======'@@@$$$$$$$'***''''''**",";;;;;;''@@@@@@@@@@'*********'",";;;;;;'*'''''''''''''''''''',",";;;;;;'**',**',,,,,,**','**',",",,,,,,''',,''',,,,,,''',,''',"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",,,,,,,,''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&&&&&&'@$$$$$$$$$'**'$$@','**","++++++'@$$$$$-$$$'***$$@''***","++++++'@$$$$$$$$$'***''''****","++++++'@$$$$$$$$$'***********","####'''@$$$$$$-$'************","##''**'@$-$$$$$$'***.'****.'*","##****'@$$$$$$$$'***''**'*''*","='*'=='@@$$$-$$$'*%%********%","=='==='@@@$$$$$$$'***''''''**",";;;;;;''@@@@@@@@@@'*********'",";;;;;'**'''''''''''''''''''',",";;;;;'**','*',,,,,,'*','**',,",",,,,,''',,,'',,,,,,,'',,''',,"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",>>>>>>>''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$''$-$$@','',","&+++++'@$$$$$$$$'**'$$$@''**'","++++++'@$$$$$-$$'***$$$@'***'","+'''++'@$$$$$$$$'***''''****'","'**''''@$$$$$$$$'***********'","'****''@$$$$$$-'*************","#''''*'@$-$$$$$'***.'****.'**","#==='''@$$$$$$$'***''**'*''**","======'@@$$$-$$'*%%********%%","=;;;;''@@@$$$$$$'***''''''**'",";;;;''''@@@@@@@@@'*********',",";;;'***'''''''''''''''''''',,",";,,'**','**,,,,,,'**,'**',,,,",",,,''',,,'',,,,,,,'',,''',,,,"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",>>>>>>>''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$''$$$@@','',","&&&&&&'@$$-$$$$$'**'-$$@''**'","&+++++'@$$$$$$$$'***$$$@'***'","++'+++'@$$$$$-$$'***''''****'","+'*'++'@$$$$$$$$'***********'","+'*''''@$$$$$$$'*************","##****'@$$$$$$-'***.'****.'**","##''**'@$-$$$$$'***''**'*''**","#==='''@$$$$$$$'*%%********%%","======'@@$$$-$$$'***''''''**'","=;;;;''@@@$$$$$$$'*********',",";;;;'*''@@@@@@@@@@''''''''',,",";;;'***''''''''''''''''*',,,,",";,,'**','**,,,,,,'**,'**',,,,",",,,''',,''',,,,,,''',,''',,,,"},
    {",,,,,,,,''''''''''''''',,,,,,",",,,,,,,'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,",">>>>>>'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$''$-$$@','',","&&&&&&'@$$$$$$$$'**'$$$@''**'","&'''&&'@$$$$$-$$'***$$$@'***'","+'*''+'@$$$$$$$$'***''''****'","+'**'''@$$$$$$$$'***********'","++'**''@$$$$$$-'*************","##''**'@$-$$$$$'***.'****.'**","###''''@$$$$$$$'***''**'*''**","#####''@@$$$-$$'*%%********%%","======'@@@$$$$$$'***''''''**'","====='''@@@@@@@@@'*********',",";;;;'***''''''''''''''''''',,",";;;;'**'','*',,,,,'**,'**',,,",";;;;'''',,'',,,,,,,'',,'',,,,",",,,,,,,,,,,,,,,,,,,,,,,,,,,,,"},
    {",,,,,,,,''''''''''''''',,,,,,",",,,,,,,'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,",">>>>>>'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&&&&&&'@$$$$$$$$$'**'$$@','**","&&&&&&'@$$$$$-$$$'***$$@''***","++'+++'@$$$$$$$$$'***''''****","+'*'++'@$$$$$$$$$'***********","+'*''''@$$$$$$-$'************","##****'@$-$$$$$$'***.'****.'*","##''**'@$$$$$$$$'***''**'*''*","####'''@@$$$-$$$'*%%********%","======'@@@$$$$$$$'***''''''**","======''@@@@@@@@@@'*********'",";;;;;'**'''''''''''''''''''',",";;;;;'**','*',,,,,,**','**',,",";;;;;''',,,'',,,,,,''',,''',,",",,,,,,,,,,,,,,,,,,,,,,,,,,,,,"},
    {",,,,,,,,,,.,,,,,,,,,,,,,,,,,,",",>>>>>>>''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&+++++'@$$$$$$$$$'**'$$@','**","++++++'@$$$$$-$$$'***$$@''***","++++++'@$$$$$$$$$'***''''****","+#####'@$$$$$$$$$'***********","#####''@$$$$$$-$'************","##'''''@$-$$$$$$'***.'****.'*","#'****'@$$$$$$$$'***''**'*''*","=='''='@@$$$-$$$'*%%********%","=;;;;;'@@@$$$$$$$'***''''''**",";;;;;;''@@@@@@@@@@'*********'",";;;;;;'*'''''''''''''''''''',",";,,,,,'**',**',,,,,,**'.'**',",",,,,,,''',,''',,,,,,''',,''',"},
    {",.,,,,,,,,,,,,,,,,,,,,,,,,,,,",",>>>>>>>''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$$''-$$@',,''","&+++++'@$$$$$$$$$'**'$$@','**","++++++'@$$$$$-$$$'***$$@''***","++++++'@$$$$$$$$$'***''''****","+#####'@$$$$$$$$$'***********","####'''@$$$$$$-$'************","##''**'@$-$$$$$$'***.'****.'*","#=****'@$$$$$$$$'***''**'*''*","='*'=='@@$$$-$$$'*%%********%","=;';;;'@@@$$$$$$$'***''''''**",";;;;;;''@@@@@@@@@@'*********'",";;;;;'**'''''''''''''''''''',",";,,,,'**','*',,..,.**','**',,",",,,,,''',,,'',,,,.,''',,''',,"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",,,,,,,,''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$-$$$$@@',,,,","&&&&&&'@$$-$$$$$$''$-$$@','',","&&&&&&'@$$$$$$$$'**'$$$@''**'","++++++'@$$$$$-$$'***$$$@'***'","+'''++'@$$$$$$$$'***''''****'","'**''''@$$$$$$$$'***********'","'****''@$$$$$$-'*************","#''''*'@$-$$$$$'***.'****.'**","####'''@$$$$$$$'***''**'*''**","======'@@$$$-$$'*%%********%%","=====''@@@$$$$$$'***''''''**'",";;;;''''@@@@@@@@@'*********',",";;;'***'''''''''''''''''''',,",";;;'**'.'**..,,,,'**''**',,,,",",,,''',,,'',,,,,,,''',''',,,,"},
    {",,,,,,,,,,,,,,,,,,,,,,,,,,,,,",",,,,,,,,''''''''''''''',,,,,,",">>>>>>>'@@@@@@@@@@@@@@@',,,,,",">>>>>>'@@@$$$$$$$$$$$@@@',,,,","&&&&&&'@@$$$$$-$$''$$$@@','',","&&&&&&'@$$-$$$$$'**'-$$@''**'","&&&&&&'@$$$$$$$$'***$$$@'***'","++'+++'@$$$$$-$$'***''''****'","+'*'++'@$$$$$$$$'***********'","+'*''''@$$$$$$$'*************","##****'@$$$$$$-'***.'****.'**","##''**'@$-$$$$$'***''**'*''**","####'''@$$$$$$$'*%%********%%","======'@@$$$-$$$'***''''''**'","=.===''@@@$$$$$$$'*********',",";;;.'*''@@@@@@@@@@''''''''',,",";;;'***''''''''''''''''*',,,,",";;;'**','**,,,,,,'**''**',,,,",",,,''',,''',,,,,,''',,''',,,,"}
}
local nyanColors={[","]=2048,["."]=1,["'"]=32768,["@"]=16,["$"]=64,["-"]=16384,
    [">"]=16384,["&"]=2,["+"]=16,["#"]=32,["="]=8,[";"]=1024,["*"]=256,["%"]=64}
local function hash(a,b,c)
    local n=(a*7381+b*19391+c*834927+7919)%104729
    return (n*n*31+n*17+97)%104729
end
local function color(v) return palette[math.floor(v*#palette)%#palette+1] end
local function opened(state,api,context,design)
    local view=context.view
    local oldIndex,oldView=state.nextDesign,{}
    for key,value in pairs(view) do oldView[key]=value end
    view.design=design; view.seed=hash(design,context.windowId,state.openings)
    state.nextDesign,state.openings=design%#titles+1,state.openings+1
    local ok,err=api.save()
    if not ok then
        local keys={}; for key in pairs(view) do keys[#keys+1]=key end
        for _,key in ipairs(keys) do view[key]=nil end
        for key,value in pairs(oldView) do view[key]=value end
        state.nextDesign,state.openings=oldIndex,state.openings-1
        return false,err
    end
    runtime[context.windowId]={start=os.clock()}; return true
end
function app.init(state,api,context)
    assert(api.fullscreenApps and api.fullscreenCornerNavigation,"Screensaver requires bundled-v33 OS; run inst server")
    name=context and context.appName or "screensaver"; runtime={}
    if state.version==nil then state.version,state.nextDesign,state.openings=1,1,0 end
    assert(state.version==1 and type(state.nextDesign)=="number" and state.nextDesign==math.floor(state.nextDesign)
        and state.nextDesign>=1 and state.nextDesign<=#titles and type(state.openings)=="number" and state.openings>=0,"Invalid screensaver state")
end
function app.onOpen(state,api,context) return opened(state,api,context,state.nextDesign) end
function app.onClose(state,api,context) runtime[context.windowId]=nil end
local function life(frame,cols,rows,seed,t)
    local function seedGrid(generation)
        local cells={}
        for y=1,rows do for x=1,cols do
            local v=hash(x+generation*17,y,seed); cells[(y-1)*cols+x]=v%7<2 and 1 or 0
        end end
        return cells
    end
    if not frame.life or frame.cols~=cols or frame.rows~=rows then
        frame.cols,frame.rows,frame.life,frame.step,frame.generation=cols,rows,seedGrid(0),-1,0
    end
    local step=math.floor(t/0.24)
    if step>frame.step then
        frame.step=step
        local nextGrid,pop,changed={},0,0
        for y=1,rows do for x=1,cols do
            local count=0
            for dy=-1,1 do for dx=-1,1 do if dx~=0 or dy~=0 then
                local index=((y-1+dy)%rows)*cols+(x-1+dx)%cols+1
                if frame.life[index]>0 then count=count+1 end
            end end end
            local index=(y-1)*cols+x; local old=frame.life[index]
            local age=(count==3 or old>0 and count==2) and old+1 or 0
            nextGrid[index]=age; if age>0 then pop=pop+1 end
            if (age>0)~=(old>0) then changed=changed+1 end
        end end
        frame.life=nextGrid
        if pop<math.min(4,cols*rows/4) or changed==0 or step%240==239 then
            frame.generation=frame.generation+1; frame.life=seedGrid(frame.generation)
        end
    end
    return frame.life
end
local function pattern(design,x,y,cols,rows,t,seed,cells)
    if design<=2 then
        local speed=2+hash(x,0,seed)%8
        local length=3+hash(x,1,seed)%math.max(4,rows)
        local cycle=rows+length+4
        local head=(math.floor(t*speed)+hash(x,2,seed)%cycle)%cycle
        local distance=(head-(y-1))%cycle
        if design==2 then
            local distance=(math.floor(t*speed)+hash(x,2,seed)-(y-1))%rows
            local index=hash(x,y,math.floor(t*3)+seed)%#letters+1
            return letters:sub(index,index),distance==0 and 1 or distance<3 and 32 or distance<rows*.6 and 8192 or 128,32768
        end
        if x%2==0 then return " ",32768,32768 end
        if distance<length then
            local char=letters:sub(hash(x,y,math.floor(t*3)+seed)%#letters+1,hash(x,y,math.floor(t*3)+seed)%#letters+1)
            local fg=distance==0 and 1 or distance<3 and 32 or distance<length*0.65 and 8192 or design==2 and 128 or 32768
            return char,fg,32768
        end
        return " ",32768,32768
    elseif design==8 then
        local age=cells[(y-1)*cols+x]
        return " ",1,age==0 and 32768 or age<3 and 1 or age<6 and 32 or age<14 and 512 or 2048
    elseif design==9 then
        local width=math.max(2,math.min(math.floor(cols*.68),math.floor(rows*58/19)))
        local height=math.min(rows,math.max(1,math.floor(width*19/58+.5)))
        local left,top=math.max(0,cols-width-math.floor(cols*.05)),math.floor((rows-height)/2)
        local py=1+math.floor((y-top-1)*19/height)
        if x>left and x<=left+width and y>top and y<=top+height then
            local px=math.min(29,1+math.floor((x-left-1)*29/width))
            local key=nyanFrames[math.floor(t*5)%#nyanFrames+1][py]:sub(px,px)
            if key~="," then return " ",1,nyanColors[key] or 2048 end
        end
        local wave=math.floor(t*5)%2
        if x<=left and py>=2+wave and py<=13+wave then
            return " ",1,({16384,2,16,32,8,1024})[math.min(6,1+math.floor((py-2-wave)/2))]
        end
        -- The cropped cat retains the original frames; stars wrap independently.
        local star=hash((x+math.floor(t*4))%cols,y,seed)
        return star%79==0 and "+" or star%47==0 and "." or " ",1,2048
    elseif design==10 then
        local X,Y=(x-(cols+1)/2)/math.max(1,cols), (y-(rows+1)/2)/math.max(1,rows)
        for i=1,42 do
            local depth=(hash(i,0,seed)%997/997-t*(.10+hash(i,1,seed)%5*.015))%1
            depth=math.max(.025,depth)
            local sx=(hash(i,2,seed)%1000/1000-.5)*.35/depth
            local sy=(hash(i,3,seed)%1000/1000-.5)*.35/depth
            if math.abs(X-sx)<.65/cols and math.abs(Y-sy)<.65/rows then
                return depth<.2 and "+" or depth<.5 and "*" or ".",depth<.3 and 1 or depth<.7 and 256 or 128,32768
            end
        end
        return " ",1,32768
    end
    -- Correct the terminal's rectangular character aspect without changing scale.
    local X=(x-(cols+1)/2)*2/math.max(12,cols)
    local Y=(y-(rows+1)/2)*3/math.max(12,cols)
    local v
    if design==11 then
        local curtain=math.sin(X*4+t*.18)*.22+math.sin(X*11-t*.31)*.08
        local distance=math.abs(Y-curtain)
        local glow=math.max(0,1-distance*4)*(math.sin(X*17+t*.7)*.22+.78)
        return " ",1,glow>.75 and 32 or glow>.52 and 8192 or glow>.35 and 512 or glow>.18 and 1024 or 32768
    elseif design==12 then
        local sum=0
        for i=1,6 do
            local bx=math.sin(t*(.11+i*.025)+i*2.1)*.75
            local by=math.cos(t*(.13+i*.017)+i)*.65
            sum=sum+.085/((X-bx)^2+(Y-by)^2+.022)
        end
        return " ",1,sum>3 and 16 or sum>2 and 2 or sum>1.25 and 16384 or sum>.8 and 1024 or 32768
    elseif design==13 then
        local radius=math.max(.02,math.sqrt(X*X+Y*Y))
        local angle=math.atan2(Y,X)+t*.15
        local ring=(1/radius+t*1.7)%2
        local spoke=math.abs((angle/pi*8)%1-.5)
        return " ",1,(ring<.13 or spoke<.055) and color(radius*.5+t*.05) or 32768
    elseif design==14 then
        for i=1,3 do
            local cycle=t*.5+i*.71; local generation=math.floor(cycle); local phase=cycle%1
            local cx=(hash(i,generation,seed)%1000/1000-.5)*1.2
            local cy=(hash(i,generation,seed+1)%1000/1000-.5)*.7
            local radius=phase*.8
            local dx,dy=X-cx,Y-cy+phase*phase*.3
            local distance=math.sqrt(dx*dx+dy*dy)
            local rays=(math.atan2(dy,dx)/pi*9)%1
            if math.abs(distance-radius)<.06 and (rays<.17 or phase<.2) then
                return phase<.2 and "+" or "*",phase>.8 and 128 or color(i*.2+generation*.1),32768
            end
        end
        return " ",1,32768
    elseif design==15 then
        local radius=math.sqrt(X*X+Y*Y); local angle=math.atan2(Y,X)
        local wave=math.sin(angle*4-radius*13+t*1.1)
        return " ",1,wave>-.1 and color(angle/pi*.25+radius*.3+t*.03) or 32768
    elseif design==3 then
        v=(math.sin(X*7+t*.55)+math.sin(Y*9-t*.4)+math.sin((X+Y)*5+t*.3)+math.sin(math.sqrt(X*X+Y*Y)*10-t*.8))/8+.5
    elseif design==4 then
        local ax,ay=.55*math.sin(t*.23),.45*math.cos(t*.31)
        local bx,by=.6*math.cos(t*.19),.5*math.sin(t*.27)
        v=(math.sin(math.sqrt((X-ax)^2+(Y-ay)^2)*18-t*1.6)+math.sin(math.sqrt((X-bx)^2+(Y-by)^2)*14-t*1.3))/4+.5
    elseif design==5 then
        local u,vv=(x-1)/4+t*.16,(y-1)/3+t*.11
        local tx,ty=math.floor(u),math.floor(vv); local fx,fy=u-tx,vv-ty
        if hash(tx,ty,seed)%2==0 then fx=1-fx end
        local d=math.min(math.abs(math.sqrt(fx*fx+fy*fy)-.5),math.abs(math.sqrt((1-fx)^2+(1-fy)^2)-.5))
        return " ",1,d<.14 and color((tx+ty)/14+t*.03) or 32768
    elseif design==6 then
        local a=math.sin(Y*15+math.sin(X*5+t*.4)*1.9-t*.65)
        local b=math.sin(X*15+math.sin(Y*5-t*.3)*1.8+t*.55)
        v=(a+b)/4+.5
        if a*b<-.45 then return " ",1,32768 end
    else
        local angle=math.atan2(Y,X)+t*.08; local radius=math.sqrt(X*X+Y*Y)
        local sector=math.abs((angle/pi*6)%2-1)
        v=(math.sin(sector*6+radius*14-t*.8)+math.cos(radius*10-sector*4+t*.5))/4+.5
    end
    return " ",1,color(v+t*.015)
end
function app.render(w,h,state,api,context)
    local view=context.view; local design=view.design or state.nextDesign
    local frame=runtime[context.windowId]
    if not frame then frame={start=os.clock()}; runtime[context.windowId]=frame end
    local t=os.clock()-frame.start; local seed=view.seed or context.windowId
    -- Coarse horizontal color runs bound large frames below the legacy modem
    -- packet limit. Tiny screens retain one-cell detail and the same patterns.
    local blockX=design==9 and 1 or math.max(1,math.ceil(w/48))
    local blockY=(design<=2 or design==9) and 1 or math.max(1,math.ceil(h/36))
    local cols,rows=math.ceil(w/blockX),math.ceil(h/blockY)
    local cells=design==8 and life(frame,cols,rows,seed,t)
    local ui=api.ui.content(w,h)
    for by=1,rows do
        local parts,runX,runFG,runBG={}
        local y=(by-1)*blockY+1
        local height=math.min(blockY,h-y+1)
        for bx=1,cols do
            local char,fg,bg=pattern(design,bx,by,cols,rows,t,seed,cells)
            local x=(bx-1)*blockX+1
            local width=math.min(blockX,w-x+1)
            if design==2 then
                local glyphs={}
                for offset=0,width-1 do local index=hash(x+offset,by,math.floor(t*3)+seed)%#letters+1; glyphs[#glyphs+1]=letters:sub(index,index) end
                parts[#parts+1]=table.concat(glyphs)
            else parts[#parts+1]=char..string.rep(" ",width-1) end
            if not runX then runX,runFG,runBG=x,fg,bg
            elseif fg~=runFG or bg~=runBG then
                ui.style(runX,y,x-runX,height,runFG,runBG); runX,runFG,runBG=x,fg,bg
            end
        end
        if runX then ui.style(runX,y,w-runX+1,height,runFG,runBG) end
        local line=table.concat(parts)
        for y=(by-1)*blockY+1,math.min(h,by*blockY) do ui.lines[y]=line end
    end
    ui.hits[1]={x1=1,x2=1,y=1,action="previousDesign"}
    ui.hits[2]={x1=w,x2=w,y=1,action="nextDesign"}
    return ui.lines
end
function app.handleTouch(x,y,w,h,state,api,context)
    if y==1 and (x==1 or x==w) then
        local current=context.view.design or state.nextDesign
        local nextIndex=(current-1+(x==1 and -1 or 1))%#titles+1
        local ok,err=opened(state,api,context,nextIndex)
        if ok then api.invalidateAppViews(name) end
        return ok,err
    end
    return api.closeWindow(context.windowId)
end
function app.shutdown() runtime={} end
return app

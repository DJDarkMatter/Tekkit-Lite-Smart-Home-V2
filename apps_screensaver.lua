-- Animated terminal patterns, CC BY-SA 3.0.
-- Matrix visual inspiration: DJDarkMatter/TekkitSwitchBoard,
-- ConvertToScreenSaverLater.lua and ConvertToScreenSaverLater2.lua.
-- The latter credits Felix Maxwell, 2013, CC BY-SA 3.0.
-- These renderers are new implementations; no IO or standalone loops are used.
-- https://creativecommons.org/licenses/by-sa/3.0/
local app={title="Screensaver",minWidth=2,minHeight=2,fullscreenOnly=true,transientWindow=true,hideTaskbar=true,animationInterval=0.2}
local titles={"Matrix streams","Matrix afterglow","Plasma","Ripple fields","Truchet flow","Silk waves","Kaleidoscope","Life garden"}
local name="screensaver"
local runtime={}
local pi=math.pi
local palette={2048,1024,4,64,2,16,32,512,8}
local letters="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:;<>+-*/={}[]"
local function hash(a,b,c) return (a*7381+b*19391+c*834927+7919)%104729 end
local function colour(v) return palette[math.floor(v*#palette)%#palette+1] end
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
    assert(api.fullscreenApps,"Screensaver requires bundled-v30 OS")
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
        if design==1 and x%2==0 then return " ",32768,32768 end
        if distance<length then
            local char=letters:sub(hash(x,y,math.floor(t*3)+seed)%#letters+1,hash(x,y,math.floor(t*3)+seed)%#letters+1)
            local fg=distance==0 and 1 or distance<3 and 32 or distance<length*0.65 and 8192 or design==2 and 128 or 32768
            return char,fg,32768
        end
        return " ",32768,32768
    elseif design==8 then
        local age=cells[(y-1)*cols+x]
        return " ",1,age==0 and 32768 or age<3 and 1 or age<6 and 32 or age<14 and 512 or 2048
    end
    -- Correct the terminal's rectangular character aspect without changing scale.
    local X=(x-(cols+1)/2)*2/math.max(12,cols)
    local Y=(y-(rows+1)/2)*3/math.max(12,cols)
    local v
    if design==3 then
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
        return " ",1,d<.14 and colour((tx+ty)/14+t*.03) or 32768
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
    return " ",1,colour(v+t*.015)
end
function app.render(w,h,state,api,context)
    local view=context.view; local design=view.design or state.nextDesign
    local frame=runtime[context.windowId]
    if not frame then frame={start=os.clock()}; runtime[context.windowId]=frame end
    local t=os.clock()-frame.start; local seed=view.seed or context.windowId
    -- Coarse horizontal colour runs bound large frames below the legacy modem
    -- packet limit. Tiny screens retain one-cell detail and the same patterns.
    local blockX=math.max(1,math.ceil(w/48))
    local blockY=design<=2 and 1 or math.max(1,math.ceil(h/36))
    local cols,rows=math.ceil(w/blockX),math.ceil(h/blockY)
    local cells=design==8 and life(frame,cols,rows,seed,t)
    local ui=api.ui.content(w,h)
    for by=1,rows do
        local parts={}
        for bx=1,cols do
            local char,fg,bg=pattern(design,bx,by,cols,rows,t,seed,cells)
            local x,y=(bx-1)*blockX+1,(by-1)*blockY+1
            local width,height=math.min(blockX,w-x+1),math.min(blockY,h-y+1)
            parts[#parts+1]=char..string.rep(" ",width-1)
            ui.style(x,y,width,height,fg,bg)
        end
        local line=table.concat(parts)
        for y=(by-1)*blockY+1,math.min(h,by*blockY) do ui.lines[y]=line end
    end
    ui.hits[1]={x1=1,x2=1,y=1,action="nextDesign"}
    return ui.lines
end
function app.handleTouch(x,y,w,h,state,api,context)
    if x==1 and y==1 then
        local ok,err=opened(state,api,context,(context.view.design or state.nextDesign)%#titles+1)
        if ok then api.invalidateAppViews(name) end
        return ok,err
    end
    return false
end
function app.shutdown() runtime={} end
return app

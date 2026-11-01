-- Independent item-monitor app through actual OS, sensor and monitor entry points.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local function read(path) local file=assert(io.open(path,"r")); local text=file:read("*a"); file:close(); return text end
    local source=read("apps_me_monitor.lua")
    local function setup()
        local bus=newBus()
        local central=bus.computer(10,"server",{apps={["apps_me_monitor.lua"]=source,["apps_me_storage.lua"]=read("apps_me_storage.lua")}}):start()
        local items={
            {Name="Iron Ingot",RawName="item.iron",DamageValue=0,Size=37389404},
            {Name="Copper Ingot",RawName="item.copper",DamageValue=0,Size=40},
            {Name="Gold Ingot",RawName="item.gold",DamageValue=0,Size=100},
            {Name="UU Matter",RawName="ic2.matter",DamageValue=0,Size=200},
            {Name="Copper Ore",RawName="tile.copper",DamageValue=0,Size=10},
            {Name="Tool",RawName="item.tool",DamageValue=1,Size=3},
            {Name="Tool",RawName="item.tool",DamageValue=2,Size=7},
            {Name="Tagged",RawName="item.tagged",DamageValue=0,Size=2},
            {Name="Tagged",RawName="item.tagged",DamageValue=0,Size=5},
        }
        local ae={card="openccsensors.item.appliedenergisticssensor",targets={["1,0,0"]={Name="ME Wireless Access Point"},["2,0,0"]={Name="ME Wireless Access Point"}},
            details={["1,0,0"]={Powered=true,UsedBytes=1024,FreeBytes=3072,UsedCount=37389771,FreeCount=20000,UsedTypes=8,FreeTypes=100,Items=items},
                ["2,0,0"]={Powered=true,UsedBytes=1,FreeBytes=1023,UsedCount=99,FreeCount=900,UsedTypes=1,FreeTypes=62,
                    Items={{Name="Iron Ingot",RawName="item.iron",Size=99,DamageValue=0}}}}}
        local sensor=bus.computer(14,"sensor",{sensors={top=ae}}):start()
        local top,left=monitor(64,26),monitor(15,10)
        local display=bus.computer(13,"monitor",{monitors={top=top,left=left}}):start()
        local t={bus=bus,central=central,sensor=sensor,ae=ae,items=items,top=top,left=left,display=display}
        function t.reload() t.api,t.app,t.state=t.central.server.api,t.central.server.apps.me_monitor,t.central.server.state.appStates.me_monitor end
        t.reload()
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.window(id) return t.central.server.state.windows[id] end
        function t.view(id) return t.central.server.views[id] end
        function t.open(side,name)
            local id=assert(t.api.openApp(name or "me_monitor","monitor_13:"..(side or "top"),1,1)); t.paint(); return id
        end
        function t.content(id)
            local win=t.window(id)
            return t.central.server.apps[win.appName].render(win.width-2,win.height-2,t.central.server.state.appStates[win.appName],t.api,
                {windowId=id,monitorId=win.monitorId,appName=win.appName,view=t.view(id)})
        end
        function t.hits(id)
            local dialog=t.central.server.dialogs[id]
            return dialog and dialog.hits or t.content(id).hits
        end
        function t.touch(id,hit)
            local win=t.window(id)
            bus.queue(display,{"monitor_touch",win.monitorId:match(":([^:]+)$"),win.x+math.floor((hit.x1+hit.x2)/2),win.y+(hit.y or hit.y1)})
            bus.pump()
        end
        function t.click(id,action,value)
            for _=1,600 do
                t.paint()
                local nextHit,previous
                for _,hit in ipairs(t.hits(id) or {}) do if hit.enabled~=false then
                    local item=type(hit.value)=="table" and hit.value.value or hit.value
                    if hit.action==action and (value==nil or type(value)=="function" and value(hit.value) or item==value) then t.touch(id,hit); return end
                    if hit.action=="next" or hit.action=="page" and hit.value.delta==1 then nextHit=hit end
                    if hit.action=="prev" or hit.action=="page" and hit.value.delta==-1 then previous=hit end
                end end
                local hit=nextHit or previous; if not hit then break end; t.touch(id,hit)
            end
            error("Missing monitor action "..action.." on "..tostring(t.view(id).screen))
        end
        function t.grid(id,columns,rows)
            for key,count in pairs({columns=columns,rows=rows}) do
                while t.view(id).gridDraft[key]~=count do
                    local delta=t.view(id).gridDraft[key]<count and 1 or -1
                    t.click(id,"gridStep",function(value) return value.key==key and value.delta==delta end)
                end
            end
        end
        function t.create(id,columns,rows,target)
            t.click(id,"add"); t.click(id,"select","sensor_14"); t.click(id,"select","top"); t.click(id,"select",target or "1,0,0"); t.click(id,"use")
            t.grid(id,columns or 2,rows or 2); t.click(id,"saveGrid"); bus.advance(3)
            return t.state.boards[#t.state.boards]
        end
        function t.choose(id,label)
            for _=1,600 do
                t.paint(); local lines=t.content(id); local nextHit
                for _,hit in ipairs(lines.hits) do if hit.enabled~=false then
                    if hit.action=="selectItem" and lines[hit.y1]:find(label,1,true) then t.touch(id,hit); return end
                    if hit.action=="page" and hit.value.key=="items" and hit.value.delta==1 then nextHit=hit end
                end end
                if not nextHit then break end; t.touch(id,nextHit)
            end
            error("Item not listed: "..label)
        end
        function t.bind(id,board,index,label)
            t.click(id,"tile",board.tiles[index].id)
            if t.view(id).screen=="item" then t.click(id,"changeItem") end
            t.choose(id,label)
        end
        function t.rowNames(id)
            local lines,result=t.content(id),{}
            for _,hit in ipairs(lines.hits) do if hit.action=="selectItem" then result[#result+1]=lines[hit.y1]:gsub("%s+%d[%d ]*$",""):gsub("%s+$","") end end
            return result
        end
        function t.text(id) return table.concat(t.content(id),"\n") end
        bus.advance(2); t.id=t.open()
        return t
    end
    function tests.me_monitors_saved_custom_views_bind_items_and_update_plain_counts_without_outputs()
        local t=setup(); equal(#t.state.boards,0)
        local board=t.create(t.id,2,3)
        equal(#board.tiles,6); equal(board.columns,2); equal(board.rows,3)
        t.bind(t.id,board,1,"Iron Ingot"); t.bind(t.id,board,2,"UU Matter")
        assert(t.text(t.id):find("37 389 404",1,true)); assert(not t.text(t.id):find("E7",1,true))
        equal(board.tiles[1].item.raw,"item.iron"); equal(board.tiles[2].item.raw,"ic2.matter")
        t.items[1].Size=37389405; t.bus.advance(3)
        assert(t.text(t.id):find("37 389 405",1,true))
        equal(#t.sensor.client.watches,1); equal(t.sensor.client.watches[1].profile,"ae_items")
        equal(next(t.central.server.state.outputMap),nil); equal(#t.sensor.redstoneWrites,0)
    end
    function tests.me_monitors_item_picker_sorts_both_ways_shows_amounts_and_searches_without_row_jumps()
        local t=setup(); local board=t.create(t.id,1,1)
        t.click(t.id,"tile",board.tiles[1].id)
        equal(t.rowNames(t.id)[1],"Copper Ingot")
        assert(t.text(t.id):find("37 389 404",1,true))
        t.click(t.id,"direction"); equal(t.rowNames(t.id)[1],"UU Matter")
        t.click(t.id,"sort"); equal(t.rowNames(t.id)[1],"Iron Ingot")
        t.click(t.id,"direction"); equal(t.rowNames(t.id)[1],"Tool [1]")
        local before=t.rowNames(t.id)[1]
        t.items[6].Size=100000000; t.bus.advance(3)
        equal(t.rowNames(t.id)[1],before,"Live count updates must not move a different item under a tap")
        t.click(t.id,"refresh"); equal(t.rowNames(t.id)[1],"Tagged")
        t.click(t.id,"search"); t.click(t.id,"clearText")
        for letter in ("copper"):gmatch(".") do t.click(t.id,"key",letter) end
        t.click(t.id,"saveText")
        local rows=t.rowNames(t.id); equal(#rows,2)
        assert(rows[1]:find("Copper",1,true)); assert(rows[2]:find("Copper",1,true))
        t.choose(t.id,"Copper Ore"); equal(board.tiles[1].item.raw,"tile.copper")
    end
    function tests.me_monitors_damage_variants_are_distinct_and_indistinguishable_nbt_variants_are_combined()
        local t=setup(); local board=t.create(t.id,2,2)
        t.bind(t.id,board,1,"Tool [1]"); t.bind(t.id,board,2,"Tool [2]"); t.bind(t.id,board,3,"Tagged")
        equal(board.tiles[1].item.damage,1); equal(board.tiles[2].item.damage,2)
        t.click(t.id,"tile",board.tiles[3].id)
        assert(t.text(t.id):find("Count: 7",1,true)); assert(t.text(t.id):find("Variants combined: 2",1,true))
        t.click(t.id,"board"); t.items[3].Size=0
        t.bind(t.id,board,4,"Gold Ingot"); t.bus.advance(3)
        assert(t.text(t.id):find("0",1,true))
    end
    function tests.me_monitors_share_a_sensor_with_capacity_app_and_release_only_their_own_watches()
        local t=setup(); local board=t.create(t.id,1,1); t.bind(t.id,board,1,"Iron Ingot")
        local capacity=t.open("left","me_storage")
        t.click(capacity,"add"); t.click(capacity,"select","sensor_14"); t.click(capacity,"select","top"); t.click(capacity,"select","1,0,0"); t.click(capacity,"use")
        t.bus.advance(3); equal(#t.sensor.client.watches,1); equal(t.sensor.client.watches[1].profile,"ae_items")
        local reading=t.api.getSensorReading(board.sensor,{profile="ae_storage"})
        equal(reading.data.Items,nil); equal(reading.data.UsedBytes,1024)
        assert(t.api.closeWindow(t.id)); t.bus.advance(3)
        equal(t.central.server.running.me_monitor,nil); equal(t.central.server.running.me_storage,true)
        equal(#t.sensor.client.watches,1); equal(t.sensor.client.watches[1].profile,"ae_storage")
    end
    function tests.me_monitors_compact_and_native_readings_can_switch_without_changing_selected_items()
        local t=setup(); local board=t.create(t.id,1,1); t.bind(t.id,board,1,"Iron Ingot")
        assert(t.api.watchSensor("legacy_full_consumer",board.sensor))
        t.bus.advance(3); equal(t.sensor.client.watches[1].profile,nil)
        equal(t.api.getSensorReading(board.sensor).data.Items[1].RawName,"item.iron")
        assert(t.text(t.id):find("37 389 404",1,true))
        t.api.unwatchSensor("legacy_full_consumer"); t.bus.advance(3)
        equal(t.sensor.client.watches[1].profile,"ae_items")
        equal(t.api.getSensorReading(board.sensor).data.ItemsFormat,"ae_compact_v1")
        assert(t.text(t.id):find("37 389 404",1,true))
    end
    function tests.me_monitors_picker_restores_its_page_after_a_restart_before_the_catalog_returns()
        local t=setup(); local board=t.create(t.id,1,1)
        local other=t.open("left"); t.click(other,"open",board.id); t.click(other,"tile",board.tiles[1].id)
        for _=1,3 do t.click(other,"page",function(value) return value.key=="items" and value.delta==1 end) end
        equal(t.view(other).pages.items.page,4)
        t.sensor.active=false
        t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start(); t.reload(); t.paint()
        equal(t.view(other).screen,"picker"); equal(t.view(other).pages.items.page,4)
        t.sensor=t.bus.computer(14,"sensor",{disk=t.sensor.disk,sensors={top=t.ae}}):start(); t.bus.advance(6); t.paint()
        equal(t.view(other).pages.items.page,4)
    end
    function tests.me_monitors_grid_edits_preserve_bindings_and_saved_views_restore_without_restoring_telemetry()
        local t=setup(); local board=t.create(t.id,2,2); t.bind(t.id,board,1,"Iron Ingot")
        local original=board.tiles[1].id
        t.click(t.id,"edit"); t.click(t.id,"resize"); t.grid(t.id,3,2); t.click(t.id,"saveGrid")
        equal(#board.tiles,6); equal(board.tiles[1].id,original); equal(board.tiles[1].item.raw,"item.iron")
        t.click(t.id,"resize"); t.grid(t.id,1,1); t.click(t.id,"saveGrid")
        equal(t.view(t.id).screen,"shrink"); equal(#board.tiles,6)
        t.click(t.id,"confirm"); equal(#board.tiles,1)
        t.click(t.id,"board")
        t.sensor.active=false
        t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start(); t.reload(); t.bus.advance(2); t.paint()
        equal(t.view(t.id).screen,"board"); equal(t.view(t.id).boardId,board.id)
        assert(t.text(t.id):find("--",1,true))
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.me_monitor.boards[1].tiles[1].item.count,nil)
        t.sensor=t.bus.computer(14,"sensor",{disk=t.sensor.disk,sensors={top=t.ae}}):start(); t.bus.advance(6)
        assert(t.text(t.id):find("37 389 404",1,true))
    end
    function tests.me_monitors_failed_saves_and_concurrent_view_removal_do_not_rebind_or_move_items()
        local t=setup()
        t.click(t.id,"add"); t.click(t.id,"select","sensor_14"); t.click(t.id,"select","top"); t.click(t.id,"select","1,0,0"); t.click(t.id,"use")
        t.central.disk.failWrite=true; t.click(t.id,"saveGrid"); equal(#t.state.boards,0)
        t.central.disk.failWrite=false; t.click(t.id,"messageBack"); t.click(t.id,"saveGrid"); t.bus.advance(3)
        local board=t.state.boards[1]
        t.click(t.id,"tile",board.tiles[1].id)
        t.central.disk.failWrite=true; t.choose(t.id,"Iron Ingot")
        equal(t.state.boards[1].tiles[1].item,nil)
        t.central.disk.failWrite=false; t.click(t.id,"messageBack"); t.choose(t.id,"Iron Ingot")
        board=t.state.boards[1]; equal(board.tiles[1].item.raw,"item.iron")
        local other=t.open("left"); t.click(other,"open",board.id)
        t.click(t.id,"tile",board.tiles[1].id); t.click(t.id,"changeItem")
        t.click(other,"edit"); t.click(other,"delete"); t.click(other,"confirm"); t.paint()
        equal(t.view(t.id).screen,"home"); equal(#t.state.boards,0); equal(next(t.central.server.state.outputMap),nil)
    end
    function tests.me_monitors_large_compact_catalogs_reassemble_atomically_and_failed_refreshes_never_show_zero()
        local t=setup()
        for i=10,4000 do t.items[i]={Name="Part "..i,RawName="item.component_"..i,DamageValue=0,Size=i} end
        local board=t.create(t.id,1,1); t.bind(t.id,board,1,"Iron Ingot")
        local large=false
        for _,packet in ipairs(t.bus.wire) do if packet.message.type=="sensorSample" and packet.message.profile=="ae_items" and packet.message.parts>16 then large=true end end
        assert(large,"Dense item catalogs must support more than the legacy 16-part raw limit")
        equal(t.api.getSensorReading(board.sensor).status,"ok")
        t.items[1].Size=123
        t.bus.drop=function(packet) return packet.message.type=="sensorSample" and packet.message.profile=="ae_items" and packet.message.part==2 end
        t.bus.advance(13); assert(t.text(t.id):find("--",1,true),"A lost new snapshot cannot become a fresh zero")
        t.bus.drop=nil; t.bus.advance(6); assert(t.text(t.id):find("123",1,true))
    end
    function tests.me_monitors_all_screens_and_maximum_grid_keep_styles_and_touches_in_bounds()
        local t=setup(); local board=t.create(t.id,16,16); t.bind(t.id,board,1,"Iron Ingot")
        local checked=0
        for _,width in ipairs({12,13,24,38,50,79}) do for _,height in ipairs({6,7,10,14,18,30}) do
            for _,screen in ipairs({"home","board","tiles","picker","item","edit","settings","grid","keyboard","delete","shrink","source","about","message"}) do
                local view={screen=screen,boardId=board.id,tileId=board.tiles[1].id,pages={},sort="name",query="",message="Test message",
                    gridDraft={target="edit",columns=16,rows=16,beforeColumns=16,beforeRows=16},keyboard={kind="name",draft="Main",bank=0,page=1}}
                local lines=t.app.render(width,height,t.state,t.api,{appName="me_monitor",windowId=t.id,view=view})
                equal(#lines,height)
                for _,line in ipairs(lines) do equal(#line,width) end
                local occupied={}
                for _,hit in ipairs(lines.hits) do
                    local y1,y2=hit.y or hit.y1,hit.y or hit.y2
                    assert(hit.x1>=1 and hit.x2<=width and hit.x1<=hit.x2 and y1>=1 and y2<=height,screen.." hit outside content")
                    for y=y1,y2 do for x=hit.x1,hit.x2 do local key=x..":"..y; assert(not occupied[key],screen.." overlapping controls"); occupied[key]=true end end
                end
                for _,style in ipairs(lines.styles) do assert(style.x>=1 and style.y>=1 and style.width>=1 and style.height>=1 and style.x+style.width-1<=width and style.y+style.height-1<=height,screen.." style outside content") end
                checked=checked+1
            end
        end end
        equal(checked,504)
    end
end

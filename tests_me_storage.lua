-- Native AE1 card fields and optional inventory surveys through real clients.
return function(tests,newBus,monitor,serialize,unserialize,equal)
    local f=assert(io.open("apps_me_storage.lua","r")); local source=f:read("*a"); f:close()
    local function setup()
        local bus=newBus()
        local central=bus.computer(10,"server",{apps={["apps_me_storage.lua"]=source}}):start()
        local ae={card="openccsensors.item.appliedenergisticssensor",targets={["1,0,0"]={Name="ME Wireless Access Point"},["2,0,0"]={Name="ME Wireless Access Point"}},
            details={["1,0,0"]={Powered=true,UsedBytes=1024,FreeBytes=3072,UsedCount=7000,FreeCount=20000,UsedTypes=42,FreeTypes=84,
                Items={[1]={Name="Iron",RawName="item.ingotIron",Size=7000}}},
                ["2,0,0"]={Powered=true,UsedBytes=0,FreeBytes=0,UsedCount=0,FreeCount=0,UsedTypes=0,FreeTypes=0,Items={}}}}
        local inv={card="openccsensors.item.inventorysensor",targets={["3,0,0"]={Name="ME Drive"},["4,0,0"]={Name="ME Drive"}},
            details={["3,0,0"]={Slots={[1]={Name="1k ME Storage",RawName="appeng.storagecell1k",Size=1},
                [2]={Name="4k ME Storage",RawName="appeng.storagecell4k",Size=1},[3]={Name="Scrap",RawName="ic2.scrap",Size=1},
                [4]={Name="empty",Size=0}}},
                ["4,0,0"]={Slots={[1]={Name="16k ME Storage",RawName="appeng.storagecell16k",Size=1},
                [2]={Name="64k ME Storage",RawName="appeng.storagecell64k",Size=1},[3]={Name="empty",Size=0}}}}}
        local sensor=bus.computer(14,"sensor",{sensors={top=ae,bottom=inv}}):start()
        local top,left=monitor(64,26),monitor(15,10)
        local display=bus.computer(13,"monitor",{monitors={top=top,left=left}}):start()
        local t={bus=bus,central=central,sensor=sensor,ae=ae,inv=inv,top=top,left=left,display=display}
        function t.reload() t.api,t.app,t.state=t.central.server.api,t.central.server.apps.me_storage,t.central.server.state.appStates.me_storage end
        t.reload()
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.open(side)
            local id=assert(t.api.openApp("me_storage","monitor_13:"..(side or "top"),1,1)); t.paint(); return id
        end
        function t.view(id) return t.central.server.views[id] end
        function t.window(id) return t.central.server.state.windows[id] end
        function t.context(id) return {appName="me_storage",windowId=id,monitorId=t.window(id).monitorId,view=t.view(id)} end
        function t.content(id) local w=t.window(id); return t.app.render(w.width-2,w.height-2,t.state,t.api,t.context(id)) end
        function t.click(id,action,value)
            for _=1,80 do
                t.paint()
                local dialog=t.central.server.dialogs[id]
                local hits=dialog and dialog.hits or t.content(id).hits
                local advance,previous
                for _,hit in ipairs(hits or {}) do if hit.enabled~=false then
                    local selected=type(hit.value)=="table" and hit.value.value or hit.value
                    if hit.action==action and (value==nil or selected==value) then
                        local w=t.window(id)
                        bus.queue(display,{"monitor_touch",w.monitorId:match(":([^:]+)$"),w.x+math.floor((hit.x1+hit.x2)/2),w.y+(hit.y or hit.y1)})
                        bus.pump(); return
                    end
                    if hit.action=="next" then advance=hit elseif hit.action=="prev" then previous=hit end
                end end
                local hit=advance or previous
                if not hit then break end
                local w=t.window(id); bus.queue(display,{"monitor_touch",w.monitorId:match(":([^:]+)$"),w.x+hit.x1,w.y+(hit.y or hit.y1)}); bus.pump()
            end
            error("Missing ME action "..action.." on "..tostring(t.view(id).screen))
        end
        function t.add(id,target)
            t.click(id,"add"); t.click(id,"select","sensor_14"); t.click(id,"select","top"); t.click(id,"select",target or "1,0,0"); t.click(id,"use")
            bus.advance(2); return t.state.networks[#t.state.networks]
        end
        function t.drive(id,target)
            if t.view(id).screen~="cells" then t.click(id,"cells") end
            t.click(id,"addDrive"); t.click(id,"select","sensor_14"); t.click(id,"select","bottom"); t.click(id,"select",target or "3,0,0"); t.click(id,"use")
            bus.advance(2)
        end
        function t.allText(id)
            t.view(id).page=1
            local result={}
            repeat
                result[#result+1]=table.concat(t.content(id),"\n")
                if t.view(id).page >= t.view(id).pageCount then break end
                t.click(id,"next")
            until #result>100
            return table.concat(result,"\n")
        end
        bus.advance(2); t.id=t.open()
        return t
    end
    function tests.me_storage_native_ae_fields_show_bytes_items_and_type_slots_without_guessing_cells()
        local t=setup()
        equal(#t.state.networks,0)
        local entry=t.add(t.id)
        local data=t.api.getSensorReading(entry.sensor)
        equal(data.status,"ok"); equal(data.data.UsedBytes,1024); equal(data.data.Items,nil); equal(data.data.ItemsOmitted,true)
        local text=t.allText(t.id)
        for _,value in ipairs({"25.0%","1 024","3 072","4 096","7 000","20 000","42","84","Cells surveyed","Unavailable"}) do assert(text:find(value,1,true),value) end
        equal(#t.sensor.client.watches,1); equal(t.sensor.client.watches[1].profile,"ae_storage")
        equal(next(t.central.server.state.outputMap),nil); equal(#t.sensor.redstoneWrites,0)
        t.click(t.id,"home"); local empty=t.add(t.id,"2,0,0")
        equal(t.api.getSensorReading(empty.sensor).data.UsedBytes,0)
        assert(t.allText(t.id):find("0.0%",1,true),"Genuine empty storage remains zero")
    end
    function tests.me_storage_large_item_lists_are_projected_and_full_subscribers_share_one_target_poll()
        local t=setup(); local entry=t.add(t.id)
        for i=1,5000 do t.ae.details["1,0,0"].Items[i]={Name="Item "..i,RawName="item.test"..i,Size=i} end
        t.bus.advance(2); equal(t.api.getSensorReading(entry.sensor).status,"ok")
        equal(t.api.getSensorReading(entry.sensor).data.Items,nil)
        t.ae.details["1,0,0"].Items={[1]={Name="Iron",Size=7000}}
        assert(t.api.watchSensor("future_item_app",entry.sensor))
        t.bus.advance(2); equal(#t.sensor.client.watches,1); equal(t.sensor.client.watches[1].profile,nil)
        equal(t.api.getSensorReading(entry.sensor).data.Items[1].Size,7000)
        equal(t.api.getSensorReading(entry.sensor).data.ItemsOmitted,nil)
        t.api.unwatchSensor("future_item_app"); t.bus.advance(2)
        equal(t.sensor.client.watches[1].profile,"ae_storage"); equal(t.api.getSensorReading(entry.sensor).data.ItemsOmitted,true)
        equal(t.api.watchSensor("bad",entry.sensor,{profile="invented"}),false)
    end
    function tests.me_storage_optional_drive_surveys_count_cell_sizes_and_keep_unexposed_fill_unavailable()
        local t=setup(); local entry=t.add(t.id)
        t.drive(t.id,"3,0,0"); t.drive(t.id,"4,0,0")
        equal(#entry.drives,2); equal(#t.sensor.client.watches,3)
        t.click(t.id,"audit")
        local text=t.allText(t.id)
        for _,value in ipairs({"Identified cells: 4","1k cells: 1","4k cells: 1","16k cells: 1","64k cells: 1","Unknown items: 1","87 040"}) do assert(text:find(value,1,true),value) end
        t.click(t.id,"cells"); t.click(t.id,"drive",entry.drives[1].id); t.click(t.id,"cell",1)
        text=t.allText(t.id); assert(text:find("1k ME Storage",1,true)); assert(text:find("Bytes used: Unavailable",1,true))
        t.click(t.id,"drive"); t.click(t.id,"driveSource"); assert(t.allText(t.id):find("3,0,0",1,true))
        t.click(t.id,"drive"); t.click(t.id,"cells"); t.drive(t.id,"3,0,0")
        equal(#entry.drives,2); assert(t.central.server.dialogs[t.id].error:find("already added",1,true))
        t.click(t.id,"cancel"); t.click(t.id,"drive",entry.drives[1].id); t.click(t.id,"removeDrive"); t.click(t.id,"confirmRemove")
        equal(#entry.drives,1); t.bus.advance(2); equal(#t.sensor.client.watches,2)
    end
    function tests.me_storage_save_failures_and_missing_power_or_sensor_data_never_turn_into_zero_capacity()
        local t=setup()
        t.click(t.id,"add"); t.click(t.id,"select","sensor_14"); t.click(t.id,"select","top"); t.click(t.id,"select","1,0,0")
        t.central.disk.failWrite=true; t.click(t.id,"use"); equal(#t.state.networks,0)
        t.central.disk.failWrite=false; t.click(t.id,"use"); t.bus.advance(2)
        local entry=t.state.networks[1]
        t.ae.details["1,0,0"]={Powered=false}; t.bus.advance(2)
        local text=t.allText(t.id); assert(text:find("ME is unpowered",1,true)); assert(text:find("Unavailable",1,true))
        t.ae.details["1,0,0"]={Powered=true,UsedBytes=-1,FreeBytes=math.huge}; t.bus.advance(2)
        equal(t.api.getSensorReading(entry.sensor).status,"error")
        t.ae.details["1,0,0"]={Powered=true,UsedBytes=-1,FreeBytes=20}; t.bus.advance(2)
        assert(t.allText(t.id):find("Invalid AE counter",1,true))
        t.sensor.active=false; t.bus.advance(20); assert(t.allText(t.id):find("Sensor client offline",1,true))
    end
    function tests.me_storage_windows_restore_independently_without_restoring_live_telemetry_and_close_stops_reads()
        local t=setup(); local entry=t.add(t.id)
        local other=t.open("left"); t.click(other,"open",entry.id); t.click(other,"next")
        t.click(t.id,"edit"); t.click(t.id,"source")
        local page=t.view(other).page
        t.sensor.active=false
        t.central=t.bus.computer(10,"server",{disk=t.central.disk}):start(); t.reload(); t.paint()
        equal(t.view(t.id).screen,"source"); equal(t.view(other).screen,"network"); equal(t.view(other).page,page)
        local saved=unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.me_storage.networks[1].UsedBytes,nil)
        assert(t.api.getSensorReading(t.state.networks[1].sensor).status~="ok")
        t.sensor=t.bus.computer(14,"sensor",{disk=t.sensor.disk,sensors={top=t.ae,bottom=t.inv}}):start()
        t.bus.advance(6); equal(t.api.getSensorReading(t.state.networks[1].sensor).status,"ok")
        assert(t.api.closeWindow(t.id)); assert(t.central.server.running.me_storage)
        assert(t.api.closeWindow(other)); t.bus.advance(2); equal(t.central.server.running.me_storage,nil); equal(#t.sensor.client.watches,0)
    end
    function tests.me_storage_all_views_fit_small_windows_and_use_disjoint_touch_regions()
        local t=setup(); local entry=t.add(t.id); t.drive(t.id)
        local count=0
        for _,width in ipairs({12,13,24,38,50,79}) do for _,height in ipairs({6,7,10,14,18,30}) do
            for _,screen in ipairs({"home","network","cells","audit","drive","cell","source","driveSource","edit","settings","rename","remove","removeDrive","about","message"}) do
                local view={screen=screen,id=entry.id,driveId=entry.drives[1].id,slot=1,page=1,message="Test message",keyboard={draft="Main ME",bank=0,page=1}}
                local lines=t.app.render(width,height,t.state,t.api,{appName="me_storage",windowId=t.id,view=view})
                equal(#lines,height)
                for _,line in ipairs(lines) do equal(#line,width) end
                local occupied={}
                for _,hit in ipairs(lines.hits) do
                    assert(hit.x1>=1 and hit.x2<=width and hit.y>=1 and hit.y<=height,screen.." hit outside content")
                    for x=hit.x1,hit.x2 do local key=x..":"..hit.y; assert(not occupied[key],screen.." overlapping hits"); occupied[key]=true end
                end
                for _,style in ipairs(lines.styles) do assert(style.x>=1 and style.y>=1 and style.x+style.width-1<=width and style.y+style.height-1<=height,screen.." style outside content") end
                count=count+1
            end
        end end
        equal(count,540)
    end
end

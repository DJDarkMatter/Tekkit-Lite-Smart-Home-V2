return function(tests, newBus, monitor, serialize, unserialize, equal)
    local file = assert(io.open("apps_reactors.lua", "r")); local source = file:read("*a"); file:close()
    local function setup(options)
        options = options or {}
        local bus = newBus()
        local central = bus.computer(10, "server", {apps = {["apps_reactors.lua"] = source}}):start()
        local ioClient = bus.computer(11, "io", {modemSide = "right"}):start()
        local machine = {card = "openccsensors.item.industrialcraftsensor", async = options.async, yielding = options.yielding,
            targets = {["1,0,0"] = {Name = "Nuclear Reactor", RawName = "ic2.blockreactor"},
                ["-1,0,0"] = {Name = "Nuclear Reactor", RawName = "ic2.blockreactor"}},
            details = {["1,0,0"] = {Heat = 48036, MaxHeat = 58000, Active = true, Output = 30, RemainingTime = 9705},
                ["-1,0,0"] = {Heat = 7, MaxHeat = 10000, Active = false, Output = 0, RemainingTime = 0}}}
        local ae = {card = "openccsensors.item.appliedenergisticssensor", targets = {["0,0,1"] = {Type = "ME Controller"}},
            details = {["0,0,1"] = {UsedBytes = 100, TotalBytes = 4096, Items = {iron = 1000}}}}
        local sensor = bus.computer(14, "sensor", {modemSide = "left", sensors = {top = machine, bottom = ae}}):start()
        local top, left = monitor(options.width or 64, options.height or 26), monitor(45, 20)
        local display = bus.computer(13, "monitor", {monitors = {top = top, left = left}}):start()
        local t = {bus = bus, central = central, io = ioClient, sensor = sensor, machine = machine, ae = ae, top = top, left = left, display = display}
        function t.reload()
            t.api, t.app, t.state = t.central.server.api, t.central.server.apps.reactors, t.central.server.state.appStates.reactors
        end
        t.reload()
        function t.paint() t.central.server.refreshMonitors(true); bus.pump() end
        function t.open(side)
            local id = assert(t.api.openApp("reactors", "monitor_13:" .. (side or "top"), 1, 1))
            t.paint(); return id
        end
        function t.view(id) return t.central.server.views[id] end
        function t.window(id) return t.central.server.state.windows[id] end
        function t.context(id) return {windowId = id, monitorId = t.window(id).monitorId, appName = "reactors", view = t.view(id)} end
        function t.content(id)
            local win = t.window(id)
            return t.app.render(win.width - 2, win.height - 2, t.state, t.api, t.context(id))
        end
        function t.click(id, action, value)
            for _ = 1, 50 do
                t.paint()
                local dialog = t.central.server.dialogs[id]
                local hits = dialog and dialog.hits or t.content(id).hits
                local nextHit, previousHit
                for _, hit in ipairs(hits) do if hit.enabled ~= false then
                    local item = type(hit.value) == "table" and hit.value.value or hit.value
                    if hit.action == action and (value == nil or item == value) then
                        local win = t.window(id)
                        bus.queue(display, {"monitor_touch", win.monitorId:match(":([^:]+)$"), win.x + math.floor((hit.x1 + hit.x2) / 2),
                            win.y + math.floor(((hit.y1 or hit.y) + (hit.y2 or hit.y)) / 2)})
                        bus.pump(); return
                    end
                    if hit.action == "next" or hit.action == "page" and hit.value.delta == 1 then nextHit = hit end
                    if hit.action == "previous" or hit.action == "prev" or hit.action == "page" and hit.value.delta == -1 then previousHit = hit end
                end end
                local hit = nextHit or previousHit
                if not hit then break end
                local win = t.window(id)
                bus.queue(display, {"monitor_touch", win.monitorId:match(":([^:]+)$"), win.x + hit.x1, win.y + (hit.y1 or hit.y)})
                bus.pump()
            end
            error("Missing reactor action " .. action .. " on " .. tostring(t.view(id).screen))
        end
        function t.add(id, target)
            if t.view(id).screen and t.view(id).screen ~= "home" then t.click(id, "home") end
            t.click(id, "add"); t.click(id, "select", "sensor_14"); t.click(id, "select", "top"); t.click(id, "select", target or "1,0,0"); t.click(id, "use")
            return t.state.reactors[#t.state.reactors]
        end
        function t.route(id, entry, color)
            t.view(id).id = entry.id
            t.click(id, "output", entry.id); t.click(id, "select", "io_11"); t.click(id, "select", "left")
            t.click(id, "select", color or false); t.click(id, "use")
        end
        function t.reboot()
            t.central = bus.computer(10, "server", {disk = t.central.disk}):start()
            t.reload(); bus.advance(6); t.paint()
        end
        bus.advance(2); t.id = t.open()
        return t
    end
    function tests.sensor_target_names_fall_back_safely_and_raw_ids_identify_localized_reactors()
        local Data = assert(loadfile("lib_sensor_data.lua"))()
        local target = Data.target("1,0,0", {Type = "", Name = " \n ", RawName = "ic2.blockreactor"})
        equal(target.type, "ic2.blockreactor"); equal(target.kind, "reactor")
        target = Data.target("2,0,0", {Name = "Reaktor", RawName = "ic2.blockreactor"})
        equal(target.type, "Reaktor"); equal(target.rawName, "ic2.blockreactor"); equal(target.kind, "reactor")
        target = Data.target("3,0,0", {Type = false, Name = "", RawName = ""})
        equal(target.type, "Unknown"); equal(target.label, "Unknown")
        equal(Data.target("4,0,0", {Name = "Cable", RawName = "ic2.blockcable"}).kind, "other")
    end
    function tests.sensor_generic_client_detects_multiple_ports_and_dedicated_ae_card_without_inventory_assumptions()
        local t = setup()
        local clients = t.api.getSensorClients()
        equal(#clients, 1); equal(clients[1].id, "sensor_14"); equal(clients[1].online, true)
        equal(#clients[1].ports, 2)
        equal(clients[1].ports[1].side, "bottom"); equal(clients[1].ports[1].cardKind, "ae")
        equal(clients[1].ports[2].side, "top"); equal(#clients[1].ports[2].targets, 2)
        equal(#t.sensor.redstoneWrites, 0)
    end
    function tests.reactors_two_targets_on_one_card_produce_screenshot_readings_and_independent_io_switches()
        local t = setup()
        local a, b = t.add(t.id), t.add(t.id, "-1,0,0")
        equal(#t.state.reactors, 2); equal(a.sensor.side, b.sensor.side)
        t.route(t.id, b, 2)
        t.view(t.id).id = a.id; t.route(t.id, a, 1)
        t.bus.advance(3)
        local reading = t.api.getSensorReading(a.sensor)
        equal(reading.status, "ok"); equal(reading.reactor.heat, 48036); equal(reading.reactor.maxHeat, 58000)
        equal(reading.reactor.melting, 49300); equal(reading.reactor.output, 30); equal(reading.reactor.remaining, 9705)
        equal(t.api.getSensorReading(b.sensor).reactor.active, false)
        equal(t.api.getSensorReading(b.sensor).reactor.remaining, 0)
        t.click(t.id, "toggle", a.id); t.bus.advance(1)
        equal(t.io.bundled.left, 1)
        t.view(t.id).id = b.id; t.click(t.id, "toggle", b.id); t.bus.advance(1)
        equal(t.io.bundled.left, 3)
        t.click(t.id, "toggle", b.id); t.bus.advance(1); equal(t.io.bundled.left, 1)
        t.view(t.id).id = a.id
        local text = table.concat(t.content(t.id), "\n")
        assert(text:find("48 036", 1, true) and text:find("49 300", 1, true) and text:find("02:41:45", 1, true))
    end
    function tests.sensor_direct_and_yielding_peripherals_work_without_yielding_through_pcall()
        for _, options in ipairs({{async = false}, {yielding = true}}) do
            local t = setup(options)
            local entry = t.add(t.id); t.bus.advance(3)
            equal(t.api.getSensorReading(entry.sensor).status, "ok")
            equal(t.api.getSensorReading(entry.sensor).reactor.heat, 48036)
        end
    end
    function tests.sensor_card_swap_detach_and_client_restart_never_reuse_old_values_as_live()
        local t = setup()
        local entry = t.add(t.id); t.bus.advance(2)
        equal(t.api.getSensorReading(entry.sensor).status, "ok")
        t.machine.card = "openccsensors.item.proximitysensor"
        t.bus.advance(6); equal(t.api.getSensorReading(entry.sensor).status, "card_changed")
        t.machine.card = "openccsensors.item.industrialcraftsensor"
        t.bus.advance(7); equal(t.api.getSensorReading(entry.sensor).status, "ok")
        t.sensor.sensors.top = nil
        t.bus.advance(2); assert(t.api.getSensorReading(entry.sensor).status ~= "ok")
        t.sensor.sensors.top = t.machine
        t.bus.advance(7); equal(t.api.getSensorReading(entry.sensor).status, "ok")
        t.sensor = t.bus.computer(14, "sensor", {disk = t.sensor.disk, modemSide = "back", sensors = {top = t.machine}}):start()
        assert(t.api.getSensorReading(entry.sensor).status ~= "ok")
        t.bus.advance(4); equal(t.api.getSensorReading(entry.sensor).status, "ok")
    end
    function tests.sensor_sample_loss_marks_stale_while_heartbeats_keep_client_online()
        local t = setup()
        local entry = t.add(t.id); t.bus.advance(2)
        t.bus.drop = function(packet) return packet.message.type == "sensorSample" end
        t.bus.advance(12)
        equal(t.api.getSensorClients()[1].online, true)
        local reading = t.api.getSensorReading(entry.sensor)
        equal(reading.status, "stale"); equal(reading.reactor.heat, 48036)
        t.bus.drop = nil; t.bus.advance(3); equal(t.api.getSensorReading(entry.sensor).status, "ok")
        t.sensor.active = false; t.bus.advance(20); equal(t.api.getSensorReading(entry.sensor).status, "offline")
    end
    function tests.sensor_disappearing_targets_and_missing_remaining_time_are_not_zero_readings()
        local t = setup()
        local entry = t.add(t.id); t.machine.details["1,0,0"].RemainingTime = nil
        t.bus.advance(3)
        equal(t.api.getSensorReading(entry.sensor).reactor.remaining, nil)
        assert(table.concat(t.content(t.id), "\n"):find("Unavailable", 1, true))
        t.machine.targets["1,0,0"] = nil; t.machine.details["1,0,0"] = nil
        t.bus.advance(6); equal(t.api.getSensorReading(entry.sensor).status, "missing")
    end
    function tests.sensor_multipart_ae_readings_are_reassembled_atomically_and_duplicate_watches_are_deduplicated()
        local t = setup()
        local address = {clientId = "sensor_14", side = "bottom", target = "0,0,1", card = t.ae.card}
        for i = 1, 300 do t.ae.details["0,0,1"].Items["item_" .. i] = {Count = i, Name = string.rep("a", 35)} end
        assert(t.api.watchSensor("test_a", address)); assert(t.api.watchSensor("test_b", address))
        t.bus.advance(4)
        local reading = t.api.getSensorReading(address)
        equal(reading.status, "ok"); equal(reading.data.Items.item_300.Count, 300)
        local chunks = 0
        for _, packet in ipairs(t.bus.wire) do if packet.message.type == "sensorSample" and packet.message.parts > 1 then chunks = chunks + 1 end end
        assert(chunks > 1)
        equal(#t.sensor.client.watches, 1)
        t.bus.advance(12); equal(#t.sensor.client.watches, 0, "Expired unused subscriptions stop detailed polling")
    end
    function tests.reactors_failed_sensor_binding_and_output_changes_roll_back_and_never_write_hardware()
        local t = setup()
        t.click(t.id, "add"); t.click(t.id, "select", "sensor_14"); t.click(t.id, "select", "top"); t.click(t.id, "select", "1,0,0")
        t.central.disk.failWrite = true; t.click(t.id, "use")
        equal(#t.state.reactors, 0)
        t.central.disk.failWrite = false; t.click(t.id, "use")
        local entry = t.state.reactors[1]
        t.central.disk.failWrite = true; t.route(t.id, entry, 1)
        equal(t.state.reactors[1].outputAddress, nil); equal(t.io.bundled.left, 0)
        t.central.disk.failWrite = false; t.click(t.id, "use")
        t.click(t.id, "toggle", entry.id); t.bus.advance(1); equal(t.io.bundled.left, 1)
        t.central.disk.failWrite = true; t.click(t.id, "toggle", entry.id)
        equal(t.api.getOutput("reactors_switch_" .. entry.id), true); equal(t.io.bundled.left, 1)
    end
    function tests.reactors_restart_restores_bindings_names_output_and_layout_without_persisting_live_telemetry()
        local t = setup()
        local entry = t.add(t.id); t.route(t.id, entry, 1); t.bus.advance(2)
        t.click(t.id, "toggle", entry.id); t.bus.advance(1)
        t.click(t.id, "edit"); t.click(t.id, "rename"); t.click(t.id, "clearName"); t.click(t.id, "key", "a"); t.click(t.id, "saveName")
        equal(entry.name, "a")
        t.reboot(); equal(t.state.reactors[1].name, "a"); equal(t.io.bundled.left, 1)
        equal(t.state.reactors[1].sensor.target, "1,0,0")
        local saved = unserialize(t.central.disk.files["configs_os_state.txt"])
        equal(saved.appStates.reactors.reactors[1].Heat, nil)
        equal(saved.sensorClients, nil)
        equal(t.window(t.id).appName, "reactors")
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).status, "ok")
    end
    function tests.reactors_duplicate_targets_share_one_poll_and_delete_releases_only_unused_control_wire()
        local t = setup()
        local a, b = t.add(t.id), t.add(t.id)
        t.route(t.id, b, 1); t.view(t.id).id = a.id; t.route(t.id, a, 1)
        t.bus.advance(2); equal(#t.sensor.client.watches, 1)
        t.click(t.id, "toggle", a.id); t.bus.advance(1)
        local id2 = t.open("left"); t.click(id2, "open", b.id)
        equal(t.api.getOutput("reactors_switch_" .. b.id), true)
        t.click(t.id, "edit"); t.click(t.id, "delete"); t.click(t.id, "confirmDelete"); t.bus.advance(1)
        equal(t.io.bundled.left, 1)
        t.click(id2, "edit"); t.click(id2, "delete"); t.click(id2, "confirmDelete"); t.bus.advance(1)
        equal(t.io.bundled.left, 0)
    end
    function tests.sensor_role_installs_and_boots_from_extracted_files_without_http_or_ocs_lua_api()
        local bus = newBus()
        local comp = bus.computer(14, "sensor")
        comp.env.shell, comp.env.http = {dir = function() return "" end}, nil
        assert(comp.env.loadfile("install.lua"))("sensor", "--startup")
        assert(comp.disk.files.startup:find("clients_sensor_client.lua", 1, true))
        comp.env.loadfile = function(path)
            local fn = assert(loadstring(assert(comp.disk.files[path], path), path)); setfenv(fn, comp.env); return fn
        end
        comp:start(); bus.advance(2)
        assert(comp.client); equal(#comp.redstoneWrites, 0)
        assert(comp.disk.files["configs_sensor.txt"])
    end
    function tests.sensor_dropped_catalog_chunks_never_publish_half_a_target_list_and_retry_recovers()
        local t = setup()
        for i = 1, 70 do t.machine.targets["target_" .. i] = {Type = "Nuclear Reactor"} end
        t.bus.drop = function(packet)
            local m = packet.message
            return m.type == "sensorCatalog" and m.side == "top" and m.parts > 1 and m.part == 2
        end
        t.bus.advance(7)
        local function count()
            for _, port in ipairs(t.api.getSensorClients()[1].ports) do if port.side == "top" then return #port.targets end end
        end
        equal(count(), 2, "An incomplete catalog must not replace the last complete snapshot")
        t.bus.drop = nil; t.bus.advance(6); equal(count(), 72)
    end
    function tests.sensor_request_errors_and_timeouts_keep_network_alive_and_late_results_cannot_change_another_card()
        local t = setup()
        local entry = t.add(t.id); t.bus.advance(2)
        t.machine.errors = {getTargetDetails = "Test read error"}
        t.bus.advance(2)
        equal(t.api.getSensorReading(entry.sensor).status, "error")
        t.machine.errors, t.machine.hang = nil, "getTargetDetails"
        local before = #t.sensor.sensorCalls
        t.bus.advance(5)
        equal(t.api.getSensorClients()[1].online, true)
        local timedOut
        for i = before + 1, #t.sensor.sensorCalls do
            local call = t.sensor.sensorCalls[i]
            if call.method == "getTargetDetails" then timedOut = timedOut or call.id end
        end
        assert(timedOut)
        t.machine.hang = nil
        t.bus.queue(t.sensor, {"ocs_success", timedOut, {Heat = 999999, MaxHeat = 10000, Active = true}})
        t.bus.pump(); t.bus.advance(11)
        local reading = t.api.getSensorReading(entry.sensor)
        equal(reading.status, "ok"); equal(reading.reactor.heat, 48036)
    end
    function tests.sensor_old_sessions_and_malformed_packets_do_not_replace_live_data_or_server_state()
        local t = setup()
        local entry = t.add(t.id); t.bus.advance(2)
        local recorded
        for _, packet in ipairs(t.bus.wire) do if packet.message.type == "sensorSample" then recorded = packet.message end end
        assert(recorded)
        local old = unserialize(serialize(recorded))
        t.reboot()
        t.central.server.handle(old, 1014, t.bus.now)
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).reactor.heat, 48036)
        local client = t.central.server.sensorClients.sensor_14
        local bad = {type = "sensorSample", clientId = "sensor_14", sender = 14, serverSession = t.central.server.session,
            bootId = client.bootId, sequence = t.sensor.client.sequence + 1, side = "top", target = "1,0,0", card = t.machine.card,
            part = 1, parts = 1, status = "ok", data = '{windows="bad"}'}
        t.central.server.handle(bad, 1014, t.bus.now)
        equal(type(t.central.server.state.windows), "table")
        bad.sequence, bad.parts, bad.data = bad.sequence + 1, 99, "{}"
        t.central.server.handle(bad, 1014, t.bus.now)
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).data.windows, "bad", "Raw sensor fields remain isolated from OS state")
        t.bus.advance(6)
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).status, "ok")
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).reactor.heat, 48036)
    end
    function tests.reactors_closing_last_view_stops_polling_and_preserves_manual_output_intent()
        local t = setup()
        local entry = t.add(t.id); t.route(t.id, entry, nil); t.bus.advance(2)
        t.click(t.id, "toggle", entry.id); t.bus.advance(1)
        equal(t.io.digital.left, true)
        assert(t.api.closeWindow(t.id)); t.bus.advance(12)
        equal(t.central.server.running.reactors, nil); equal(#t.sensor.client.watches, 0)
        equal(t.io.digital.left, true)
        local before = #t.sensor.sensorCalls
        t.bus.advance(3)
        for i = before + 1, #t.sensor.sensorCalls do assert(t.sensor.sensorCalls[i].method ~= "getTargetDetails") end
        t.id = t.open(); t.bus.advance(3)
        equal(t.api.getSensorReading(t.state.reactors[1].sensor).status, "ok")
    end
    function tests.sensor_compact_unchanged_heartbeats_cannot_renew_a_dropped_changed_snapshot()
        local t = setup()
        local entry = t.add(t.id); t.bus.advance(2)
        t.machine.details["1,0,0"].Heat = 40000
        t.bus.drop = function(packet) return packet.message.type == "sensorSample" and packet.message.unchanged ~= true end
        t.bus.advance(12)
        local reading = t.api.getSensorReading(entry.sensor)
        equal(reading.status, "stale"); equal(reading.reactor.heat, 48036)
        t.bus.drop = nil; t.bus.advance(6)
        equal(t.api.getSensorReading(entry.sensor).reactor.heat, 40000)
        equal(t.api.getSensorReading(entry.sensor).status, "ok")
    end
    function tests.reactors_structural_edits_reject_stale_touches_on_other_monitors()
        local t = setup()
        local a, b = t.add(t.id), t.add(t.id, "-1,0,0")
        t.route(t.id, b, 2); t.view(t.id).id = a.id; t.route(t.id, a, 1); t.bus.advance(2)
        local other = t.open("left")
        local win, hit = t.window(other), nil
        for _, item in ipairs(t.content(other).hits) do if item.action == "toggle" and item.value == a.id then hit = item end end
        assert(hit)
        local monitorId = win.monitorId
        local revision = t.central.server.monitors[monitorId].inputRevision or 0
        local old = {type = "touch", clientId = monitorId, sender = 13, serverSession = t.central.server.session,
            inputRevision = revision, x = win.x + hit.x1, y = win.y + (hit.y1 or hit.y)}
        t.click(t.id, "edit"); t.click(t.id, "delete"); t.click(t.id, "confirmDelete")
        assert(t.central.server.monitors[monitorId].inputRevision > revision)
        t.central.server.handle(old, 1013, t.bus.now); t.bus.pump()
        equal(t.api.getOutput("reactors_switch_" .. b.id), false, "Old coordinates must not toggle the reactor that moved into the deleted slot")
    end
    function tests.reactors_all_screens_fit_small_large_and_resized_content_without_overlapping_hits()
        local t = setup()
        local a = t.add(t.id); t.bus.advance(2)
        t.add(t.id, "-1,0,0")
        local checked = 0
        for _, w in ipairs({12, 13, 17, 24, 35, 50, 79}) do for _, h in ipairs({6, 7, 9, 12, 13, 15, 18, 25}) do
            for _, screen in ipairs({"home", "reactor", "edit", "settings", "palette", "rename", "delete", "raw", "about", "message"}) do
                local view = {id = a.id, screen = screen, colourField = "panel", colourDraft = 1, keyboard = {draft = "Core", original = "Core", page = 1, bank = "abc"}, message = "Save failed"}
                local lines = t.app.render(w, h, t.state, t.api, {appName = "reactors", windowId = t.id, view = view})
                equal(#lines, h)
                for _, line in ipairs(lines) do equal(#line, w) end
                local occupied = {}
                for _, hit in ipairs(lines.hits) do
                    local y1, y2 = hit.y1 or hit.y, hit.y2 or hit.y
                    assert(hit.x1 >= 1 and hit.x2 <= w and hit.x1 <= hit.x2 and y1 >= 1 and y2 <= h and y1 <= y2, screen .. " out of bounds")
                    for x = hit.x1, hit.x2 do for y = y1, y2 do
                        local key = x .. ":" .. y; assert(not occupied[key], screen .. " overlapping at " .. key); occupied[key] = true
                    end end
                end
                for _, style in ipairs(lines.styles) do assert(style.x >= 1 and style.y >= 1 and style.width >= 1 and style.height >= 1
                    and style.x + style.width - 1 <= w and style.y + style.height - 1 <= h, screen .. " style bounds") end
                checked = checked + 1
            end
        end end
        equal(checked, 560)
    end

    function tests.sensor_server_accepts_blank_names_from_older_catalogs_without_hiding_the_side()
        local t = setup()
        local client = t.central.server.sensorClients.sensor_14
        client.ports = {}
        local message = {type = "sensorCatalog", clientId = "sensor_14", sender = 14, serverSession = t.central.server.session,
            bootId = client.bootId, sequence = t.sensor.client.sequence + 1, side = "top", card = t.machine.card,
            part = 1, parts = 1, status = "ok", targets = {{key = "1,0,0", type = ""},
                {key = "-1,0,0", type = "Nuclear Reactor"}}}
        t.central.server.handle(message, 1014, t.bus.now)
        local clients = t.api.getSensorClients()
        equal(#clients[1].ports, 1); equal(#clients[1].ports[1].targets, 2)
        local found
        for _, target in ipairs(clients[1].ports[1].targets) do if target.key == "1,0,0" then found = target end end
        equal(found.type, "Unknown"); equal(clients[1].catalogError, nil)
    end

    function tests.sensor_catalog_rejections_are_visible_in_picker_and_os_diagnostics()
        local t = setup()
        local client = t.central.server.sensorClients.sensor_14
        client.ports = {}
        t.central.server.handle({type = "sensorCatalog", clientId = "sensor_14", sender = 14,
            serverSession = t.central.server.session, bootId = client.bootId, sequence = t.sensor.client.sequence + 1,
            side = "top", card = t.machine.card, part = 1, parts = 1, status = "ok", targets = {{key = "1,0,0", type = {}}}}, 1014, t.bus.now)
        local clients = t.api.getSensorClients()
        equal(clients[1].catalogError, "Invalid target metadata"); equal(clients[1].catalogRejected, 1)
        local Picker = t.central.env.dofile("lib_sensor_picker.lua")
        local dialog = Picker.new("test", {clientId = "sensor_14"}, "reactor"); dialog.stage = 2
        assert(table.concat(Picker.render(dialog, 30, 10, clients), "\n"):find("Catalog rejected", 1, true))
        local listing = table.concat(t.central.server.command("sensors sensor_14"), "\n")
        assert(listing:find("Invalid target metadata", 1, true))
        assert(listing:find("protocol=1", 1, true)); assert(listing:find("Waiting for sensor catalog", 1, true))
        t.bus.advance(6); equal(t.api.getSensorClients()[1].catalogError, nil)
        assert(table.concat(t.central.server.command("sensors sensor_14"), "\n"):find("targets=2 reactors=2", 1, true))
    end

    function tests.sensor_picker_explains_waiting_and_shows_unusable_known_sides_as_disabled()
        local t = setup()
        local Picker = t.central.env.dofile("lib_sensor_picker.lua")
        local dialog = Picker.new("test", {clientId = "sensor_14"}, "reactor"); dialog.stage = 2
        local clients = t.api.getSensorClients()
        Picker.render(dialog, 40, 10, clients)
        local top, bottom
        for _, hit in ipairs(dialog.hits) do if hit.action == "select" then
            if hit.value.value == "top" then top = hit elseif hit.value.value == "bottom" then bottom = hit end
        end end
        assert(top and top.enabled ~= false); assert(bottom and bottom.enabled == false)
        Picker.touch(dialog, bottom.x1, bottom.y1 or bottom.y); equal(dialog.stage, 2)
        clients[1].ports = {}
        assert(table.concat(Picker.render(dialog, 30, 10, clients), "\n"):find("Waiting for catalog", 1, true))
        clients[1].online = false
        assert(table.concat(Picker.render(dialog, 30, 10, clients), "\n"):find("Sensor client offline", 1, true))
    end

    function tests.sensor_diagnostics_show_missing_catalog_parts_and_recovery()
        local t = setup()
        for i = 1, 70 do t.machine.targets["extra_" .. i] = {Name = "IC2 machine", RawName = "ic2.machine"} end
        t.bus.drop = function(packet) return packet.message.type == "sensorCatalog" and packet.message.parts > 1 and packet.message.part == 2 end
        t.bus.advance(7)
        local clients = t.api.getSensorClients()
        equal(#clients[1].pending, 1); equal(clients[1].pending[1].received, 1); equal(clients[1].pending[1].parts, 2)
        assert(table.concat(t.central.server.command("sensors sensor_14"), "\n"):find("catalog parts=1/2", 1, true))
        t.bus.drop = nil; t.bus.advance(6)
        equal(#t.api.getSensorClients()[1].pending, 0)
        local listing = table.concat(t.central.server.command("sensors sensor_14"), "\n")
        assert(listing:find("targets=72 reactors=2", 1, true))
        equal(t.central.server.command("sensors unknown")[1], "No matching sensor clients")
    end
end

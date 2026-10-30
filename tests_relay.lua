return function(tests, newBus, monitor, serialize, unserialize, equal)
    local function fixture(options)
        options = options or {}
        local bus = newBus()
        local range = options.range or 64
        local app = [[return {minWidth = 8, minHeight = 2,
            init = function(s) s.taps = s.taps or 0 end,
            render = function(w, h, s) return {"Tap me", tostring(s.taps)} end,
            handleTouch = function(x, y, w, h, s) s.taps = s.taps + 1; return true end}]]
        local central = bus.computer(10, "server", {range = range, position = {0, 0, 0}, apps = {["apps_relaytest.lua"] = app}}):start()
        local machine = {card = "openccsensors.item.industrialcraftsensor", targets = {["1,0,0"] = {Type = "Nuclear Reactor"}},
            details = {["1,0,0"] = {Heat = 48036, MaxHeat = 58000, Active = true, Output = 30}}}
        local sensor = bus.computer(14, "sensor", {range = range, position = {6, 120, 0}, sensors = {top = machine}}):start()
        local ioClient = bus.computer(11, "io", {range = range, position = {6, 120, 0}, modemSide = "right"}):start()
        local screen = monitor(40, 18)
        local display = bus.computer(13, "monitor", {range = range, position = {6, 120, 0}, monitors = {top = screen}}):start()
        local t = {bus = bus, central = central, sensor = sensor, io = ioClient, display = display, screen = screen, machine = machine}
        function t.addRelay(id, y)
            return bus.computer(id, "relay", {range = range, position = {3, y, 0}}):start()
        end
        function t.clients()
            local result = {}
            for _, c in ipairs(t.central.server.api.getClients()) do result[c.id] = c end
            return result
        end
        function t.watch()
            local address = {clientId = "sensor_14", side = "top", target = "1,0,0", card = machine.card, targetType = "Nuclear Reactor"}
            assert(t.central.server.api.watchSensor("relay_test", address))
            bus.advance(3)
            return t.central.server.api.getSensorReading(address), address
        end
        function t.open()
            local id = assert(t.central.server.api.openApp("relaytest", "monitor_13:top", 1, 1))
            t.central.server.refreshMonitors(true); bus.pump()
            return t.central.server.state.windows[id]
        end
        return t
    end

    function tests.relay_bridges_120_vertical_blocks_and_lists_every_endpoint_independently()
        local t = fixture()
        t.bus.advance(6)
        equal(t.sensor.client.connected, false); equal(t.central.server.sensorClients.sensor_14, nil)
        local relay = t.addRelay(20, 60)
        t.bus.advance(6)
        equal(relay.client.connected, true); equal(t.sensor.client.connected, true)
        local clients = t.clients()
        equal(#t.central.server.api.getClients(), 4)
        for id, kind in pairs({sensor_14 = "sensor", io_11 = "io", ["monitor_13:top"] = "monitor", relay_20 = "relay"}) do
            equal(clients[id].type, kind); equal(clients[id].online, true)
        end
        equal(clients.sensor_14.computerId, 14); equal(clients.io_11.computerId, 11)
        equal(clients.sensor_14.via[1], "relay_20"); equal(clients.sensor_14.hops, 1)
        equal(clients.relay_20.hops, 0)
        local listing = table.concat(t.central.server.command("clients"), "\n")
        assert(listing:find("sensor_14 sensor ONLINE computer=14 via=relay_20", 1, true))
        assert(listing:find("relay_20 relay ONLINE computer=20 direct", 1, true))
        local reading = t.watch()
        equal(reading.status, "ok"); equal(reading.reactor.heat, 48036); equal(reading.reactor.active, true)
        equal(#relay.redstoneWrites, 0)
    end

    function tests.relay_carries_io_commands_acks_inputs_and_monitor_touches_in_both_directions()
        local t = fixture(); t.addRelay(20, 60); t.bus.advance(6)
        assert(t.central.server.api.mapOutput("remote", "io_11", "left", 1))
        assert(t.central.server.api.setOutput("remote", true)); t.bus.advance(2)
        equal(t.io.bundled.left, 1); equal(t.central.server.api.getOutputs()[1].confirmed, true)
        t.io.bundledInputs.front, t.io.digitalInputs.front = 4, true
        t.bus.queue(t.io, {"redstone"}); t.bus.advance(1)
        local input = t.central.server.api.getInput("io_11", "front")
        equal(input.value, 4); equal(input.digital, true)
        local win = t.open()
        assert(table.concat(t.screen.lines, "\n"):find("Tap me", 1, true))
        t.bus.queue(t.display, {"monitor_touch", "top", win.x + 1, win.y + 1}); t.bus.pump()
        equal(t.central.server.state.appStates.relaytest.taps, 1)
        assert(table.concat(t.screen.lines, "\n"):find("1", 1, true))
    end

    function tests.relay_chains_preserve_original_ids_and_report_source_to_os_paths()
        local t = fixture({range = 45})
        t.addRelay(20, 40); t.addRelay(21, 80); t.bus.advance(6)
        local clients = t.clients()
        equal(clients.sensor_14.computerId, 14); equal(clients.sensor_14.hops, 2)
        equal(table.concat(clients.sensor_14.via, ">"), "relay_21>relay_20")
        equal(table.concat(clients.relay_21.via, ">"), "relay_20")
        equal(#t.central.server.api.getClients(), 5)
        equal(t.watch().status, "ok")
        local win = t.open()
        t.bus.queue(t.display, {"monitor_touch", "top", win.x + 1, win.y + 1}); t.bus.pump()
        equal(t.central.server.state.appStates.relaytest.taps, 1)
    end

    function tests.relay_overlapping_paths_never_loop_duplicate_taps_or_reset_earned_io_acks()
        local t = fixture()
        -- Both relays can hear both ends and each other.
        t.sensor.position, t.io.position, t.display.position = {0, 100, 0}, {0, 100, 0}, {0, 100, 0}
        t.addRelay(20, 45); t.addRelay(21, 55); t.bus.advance(6)
        local win = t.open()
        t.bus.queue(t.display, {"monitor_touch", "top", win.x + 1, win.y + 1}); t.bus.pump()
        equal(t.central.server.state.appStates.relaytest.taps, 1)
        assert(t.central.server.api.mapOutput("remote", "io_11", "left", 1))
        assert(t.central.server.api.setOutput("remote", true)); t.bus.advance(2)
        local revision, writes = t.central.server.ioClients.io_11.revision, #t.io.redstoneWrites
        t.bus.advance(20)
        equal(t.central.server.ioClients.io_11.revision, revision)
        equal(t.central.server.api.getOutputs()[1].confirmed, true); equal(#t.io.redstoneWrites, writes)
        local counts = {}
        for _, wire in ipairs(t.bus.wire) do
            local p, tr = wire.message, wire.message._transport
            if tr and #tr.path > 0 then
                local key = wire.sender.id .. ":" .. p.sender .. ":" .. tr.boot .. ":" .. tr.sequence
                counts[key] = (counts[key] or 0) + 1
                equal(counts[key], 1, "A relay forwards each send only once")
                local seen = {}
                for _, hop in ipairs(tr.path) do assert(not seen[hop.computerId]); seen[hop.computerId] = true end
            end
        end
    end

    function tests.relay_direct_paths_win_and_duplicate_broadcasts_are_delivered_only_once()
        local t = fixture()
        t.sensor.position, t.io.position, t.display.position = {0, 15, 0}, {0, 15, 0}, {0, 15, 0}
        t.addRelay(20, 20); t.addRelay(21, 25); t.bus.advance(6)
        equal(t.clients().sensor_14.hops, 0)
        local win = t.open()
        t.bus.queue(t.display, {"monitor_touch", "top", win.x + 1, win.y + 1}); t.bus.pump()
        equal(t.central.server.state.appStates.relaytest.taps, 1)
        assert(t.central.server.api.mapOutput("remote", "io_11", "left", 1)); t.bus.advance(1)
        local revision = t.central.server.ioClients.io_11.revision
        t.bus.advance(6); equal(t.central.server.ioClients.io_11.revision, revision)
    end

    function tests.relay_power_loss_marks_each_device_offline_and_restart_restores_saved_io_intent()
        local t = fixture(); local relay = t.addRelay(20, 60); t.bus.advance(6)
        assert(t.central.server.api.mapOutput("remote", "io_11", "left", 1))
        assert(t.central.server.api.setOutput("remote", true)); t.bus.advance(2)
        relay.active = false; t.bus.advance(18)
        for _, client in pairs(t.clients()) do equal(client.online, false) end
        equal(t.sensor.client.connected, false); equal(t.io.bundled.left, 0)
        equal(t.central.server.api.getOutput("remote"), true)
        relay = t.bus.computer(20, "relay", {disk = relay.disk}):start(); t.bus.advance(7)
        for _, client in pairs(t.clients()) do equal(client.online, true) end
        equal(t.io.bundled.left, 1); equal(t.central.server.api.getOutputs()[1].confirmed, true)
        equal(#relay.redstoneWrites, 0)
    end

    function tests.relay_alternate_path_recovers_without_reconfiguring_endpoints()
        local t = fixture()
        t.sensor.position, t.io.position, t.display.position = {0, 100, 0}, {0, 100, 0}, {0, 100, 0}
        local a, b = t.addRelay(20, 45), t.addRelay(21, 55); t.bus.advance(6)
        local before = t.clients().sensor_14.via[1]
        if before == "relay_20" then a.active = false else b.active = false end
        t.bus.advance(6)
        local after = t.clients().sensor_14
        equal(after.online, true); assert(after.via[1] ~= before)
        equal(t.watch().status, "ok")
    end

    function tests.relay_and_endpoint_restart_change_packet_boot_ids_and_restore_monitor_windows()
        local t = fixture(); t.addRelay(20, 60); t.bus.advance(6)
        local win = t.open()
        local oldBoot = unserialize(t.sensor.disk.files["configs_transport.txt"]).bootCounter
        t.sensor = t.bus.computer(14, "sensor", {disk = t.sensor.disk, sensors = {top = t.machine}}):start()
        t.bus.advance(1)
        equal(t.sensor.client.connected, true)
        assert(unserialize(t.sensor.disk.files["configs_transport.txt"]).bootCounter > oldBoot)
        local oldSession = t.central.server.session
        t.central = t.bus.computer(10, "server", {disk = t.central.disk}):start(); t.bus.advance(6)
        assert(t.central.server.session ~= oldSession)
        equal(t.sensor.client.connected, true); equal(t.sensor.client.serverSession, t.central.server.session)
        equal(t.central.server.state.windows[win.id].monitorId, "monitor_13:top")
        equal(t.watch().status, "ok")
    end

    function tests.relay_forwards_while_os_is_absent_and_connects_after_os_boots()
        local bus = newBus()
        local edge = bus.computer(14, "sensor", {position = {0, 120, 0}}):start()
        local relay = bus.computer(20, "relay", {position = {0, 60, 0}}):start()
        bus.advance(6)
        equal(relay.client.connected, false); assert(relay.client.forwarded > 0)
        local central = bus.computer(10, "server", {position = {0, 0, 0}}):start(); bus.advance(6)
        equal(relay.client.connected, true); equal(edge.client.connected, true)
        equal(#central.server.api.getClients(), 2)
    end

    function tests.relay_recovers_dropped_handshakes_commands_and_acks_through_normal_retries()
        local t = fixture(); t.addRelay(20, 60)
        local cut = t.bus.now + 6
        t.bus.drop = function(w) return w.message.type == "welcome" and t.bus.now < cut end
        t.bus.advance(6); equal(t.sensor.client.connected, false)
        t.bus.drop = nil; t.bus.advance(6); equal(t.sensor.client.connected, true)
        assert(t.central.server.api.mapOutput("remote", "io_11", "left", 1)); t.bus.advance(1)
        t.bus.drop = function(w) return w.message.type == "ioCommand" end
        assert(t.central.server.api.setOutput("remote", true)); t.bus.advance(2)
        equal(t.io.bundled.left, 0)
        t.bus.drop = function(w) return w.message.type == "ioAck" end
        t.bus.advance(3); equal(t.io.bundled.left, 1)
        equal(t.central.server.api.getOutputs()[1].confirmed, false)
        t.bus.drop = nil; t.bus.advance(3); equal(t.central.server.api.getOutputs()[1].confirmed, true)
    end

    function tests.relay_rejects_other_networks_invalid_paths_and_oversized_or_legacy_bus_packets()
        local t = fixture(); local relay = t.addRelay(20, 60); t.bus.advance(6)
        local original
        for _, wire in ipairs(t.bus.wire) do if wire.sender == t.sensor and wire.message.type == "announce" then original = wire.message; break end end
        local before = relay.client.forwarded
        local changes = {
            function(p) p.networkId = "other" end,
            function(p) p.protocol = "other" end,
            function(p) p._transport = nil end,
            function(p) p._transport.serverChannel = 12345 end,
            function(p) p._transport.path = "bad" end,
            function(p) p._transport.path = {[2] = {id = "relay_fake", computerId = 99}} end,
            function(p) p._transport.path = {{id = "a", computerId = 99}, {id = "b", computerId = 99}} end,
            function(p) p._transport.path = {{id = "self", computerId = 14}} end,
            function(p) p._transport.path = {{id = "relay_20", computerId = 20}} end,
            function(p) p._transport.path = {{id = "bad", computerId = -1}} end,
        }
        for i, change in ipairs(changes) do
            local packet = unserialize(serialize(original)); packet._transport.sequence = 10000 + i; change(packet)
            t.bus.queue(relay, {"modem_message", relay.modemSide, 65533, 1014, serialize(packet), 12})
        end
        t.bus.queue(relay, {"modem_message", relay.modemSide, 65533, 1014, string.rep("x", 65537), 12})
        t.bus.queue(relay, {"modem_message", relay.modemSide, 65533, 999, serialize(original), 12})
        t.bus.pump(); equal(relay.client.forwarded, before)
        equal(type(t.central.server.state.windows), "table")
    end

    function tests.relay_long_chains_reach_devices_through_sixteen_and_seventeen_relays()
        local bus = newBus()
        local central = bus.computer(10, "server", {range = 11, position = {0, 0, 0}}):start()
        for i = 1, 17 do bus.computer(100 + i, "relay", {range = 11, position = {0, i * 10, 0}}):start() end
        local edge16 = bus.computer(20, "sensor", {range = 11, position = {0, 170, 0}}):start()
        local edge17 = bus.computer(21, "sensor", {range = 11, position = {0, 180, 0}}):start()
        bus.advance(6)
        equal(edge16.client.connected, true); equal(edge17.client.connected, true)
        equal(central.server.sensorClients.sensor_20.online, true)
        equal(#central.server.sensorClients.sensor_20.route, 16)
        equal(#central.server.sensorClients.sensor_21.route, 17)
        equal(central.server.sensorClients.sensor_21.online, true)
        equal(#central.server.api.getClients(), 19)
    end

    function tests.relay_role_installs_offline_and_preserves_config_and_transport_generation()
        local bus = newBus()
        local comp = bus.computer(20, "relay")
        comp.env.shell, comp.env.http = {dir = function() return "" end}, nil
        comp.disk.files["configs_relay.txt"] = serialize({clientId = "my_relay", announceInterval = 5, timeout = 15})
        comp.disk.files["configs_transport.txt"] = serialize({bootCounter = 17})
        assert(comp.env.loadfile("install.lua"))("relay", "--startup")
        assert(comp.disk.files.startup:find("clients_relay_client.lua", 1, true))
        assert(comp.disk.files["lib_relay.lua"]); equal(comp.disk.files["lib_monitor.lua"], nil)
        for path in pairs(comp.disk.files) do assert(not path:match("^apps_")) end
        comp.env.loadfile = function(path)
            local fn = assert(loadstring(assert(comp.disk.files[path], path), path)); setfenv(fn, comp.env); return fn
        end
        comp:start(); bus.advance(1)
        assert(comp.client); equal(#comp.redstoneWrites, 0)
        equal(unserialize(comp.disk.files["configs_relay.txt"]).clientId, "my_relay")
        equal(unserialize(comp.disk.files["configs_transport.txt"]).bootCounter, 18)
    end

    function tests.relay_large_packets_cross_sixteen_full_length_relay_ids_within_wire_limit()
        local bus = newBus()
        local central = bus.computer(10, "server", {range = 11, position = {0, 0, 0}}):start()
        for i = 1, 16 do
            local relay = bus.computer(100 + i, "relay", {range = 11, position = {0, i * 10, 0}})
            relay.disk.files["configs_relay.txt"] = serialize({clientId = string.rep("r", 62) .. string.format("%02d", i), announceInterval = 5, timeout = 15})
            relay:start()
        end
        local edge = bus.computer(20, "sensor", {range = 11, position = {0, 170, 0}}):start(); bus.advance(6)
        local received, original = nil, central.server.handle
        central.server.handle = function(message, ...)
            if message.type == "large_test" then received = message end
            return original(message, ...)
        end
        local net = edge.env.dofile("lib_network.lua").new({networkId = "home", channel = 45231}, false)
        local payload = string.rep("x", 58000)
        assert(net.toServer({type = "large_test", clientId = "sensor_20", payload = payload})); bus.pump()
        assert(received); equal(received.payload, payload); equal(#received._route, 16)
        for _, wire in ipairs(bus.wire) do assert(#wire.raw <= 65536) end
        local before = #bus.wire
        equal(net.toServer({type = "large_test", clientId = "sensor_20", payload = string.rep("x", 62000)}), false)
        equal(#bus.wire, before)
    end

    function tests.relay_preserves_pinned_server_checks_in_both_directions()
        local t = fixture()
        local relay = t.bus.computer(20, "relay", {position = {3, 60, 0}, network = {networkId = "home", channel = 45231, serverId = 10}}):start()
        t.bus.advance(6); equal(t.sensor.client.connected, true)
        local before = relay.client.forwarded
        local foreignReply = {protocol = "SmartHomeOS/1", networkId = "home", sender = 99, recipient = 14,
            type = "welcome", clientId = "sensor_14", nonce = t.sensor.client.nonce, serverSession = "foreign",
            _transport = {version = 1, serverChannel = 45231, boot = 1, sequence = 8888, channel = 1014, path = {}}}
        local foreignRequest = {protocol = "SmartHomeOS/1", networkId = "home", sender = 14, recipient = 99,
            type = "announce", clientType = "sensor", clientId = "sensor_14", nonce = 100,
            _transport = {version = 1, serverChannel = 45231, boot = 1, sequence = 8889, channel = 45231, path = {}}}
        t.bus.queue(relay, {"modem_message", relay.modemSide, 65533, 45231, serialize(foreignReply), 12})
        t.bus.queue(relay, {"modem_message", relay.modemSide, 65533, 1014, serialize(foreignRequest), 12})
        t.bus.pump(); equal(relay.client.forwarded, before); equal(t.sensor.client.serverId, 10)
    end

    function tests.relay_updated_os_accepts_legacy_direct_packets_and_direct_only_clients()
        local bus = newBus()
        local central = bus.computer(10, "server"):start()
        local legacy = {protocol = "SmartHomeOS/1", networkId = "home", sender = 77, type = "announce",
            clientId = "legacy_sensor", clientType = "sensor", nonce = 1}
        bus.queue(central, {"modem_message", central.modemSide, 45231, 1077, serialize(legacy), 12}); bus.pump()
        equal(central.server.sensorClients.legacy_sensor.online, true)
        equal(#central.server.sensorClients.legacy_sensor.route, 0)
        local direct = bus.computer(11, "io", {network = {networkId = "home", channel = 45231, relayEnabled = false}}):start()
        equal(direct.client.connected, true); equal(direct.open[65533], nil)
        for _, wire in ipairs(bus.wire) do if wire.sender == direct then assert(wire.channel ~= 65533) end end
        assert(central.server.api.mapOutput("direct", "io_11", "left", nil))
        assert(central.server.api.setOutput("direct", true)); bus.advance(2)
        equal(direct.digital.left, true); equal(central.server.api.getOutputs()[1].confirmed, true)
    end

    function tests.relay_modem_reattachment_recovers_without_new_ids_or_manual_restart()
        local t = fixture(); local relay = t.addRelay(20, 60); t.bus.advance(6)
        relay.modemSide = nil
        t.bus.queue(relay, {"peripheral_detach", "back"}); t.bus.advance(18)
        equal(t.sensor.client.connected, false); equal(relay.client.connected, false)
        relay.modemSide = "left"
        t.bus.queue(relay, {"peripheral", "left"}); t.bus.advance(7)
        equal(relay.client.connected, true); equal(t.sensor.client.connected, true)
        equal(t.clients().sensor_14.via[1], "relay_20")
    end

    function tests.relay_failed_boot_checkpoint_transmits_nothing_and_preserves_generation()
        local bus = newBus()
        local comp = bus.computer(20, "relay", {network = {networkId = "home", channel = 45231}})
        comp.disk.files["configs_relay.txt"] = serialize({clientId = "relay_20", announceInterval = 5, timeout = 15})
        comp.disk.files["configs_transport.txt"] = serialize({bootCounter = 23})
        comp.disk.failWrite = true
        local ok, err = pcall(comp.start)
        equal(ok, false); assert(tostring(err):find("Cannot checkpoint network startup", 1, true))
        equal(#bus.wire, 0); equal(unserialize(comp.disk.files["configs_transport.txt"]).bootCounter, 23)
    end

    function tests.relay_five_hops_at_thirty_block_range_publish_62_pre_discovered_targets_with_empty_names()
        local bus = newBus()
        local central = bus.computer(19623, "server", {range = 30, position = {0, 0, 0}}):start()
        local machine = {card = "openccsensors.item.industrialcraftsensor", targets = {},
            details = {["1,0,0"] = {Heat = 48036, MaxHeat = 58000, Active = true, Output = 30}}}
        for i = 1, 62 do machine.targets[tostring(i) .. ",0,0"] = {Name = "IC2 machine", RawName = "ic2.machine"} end
        machine.targets["1,0,0"] = {Name = "Reaktor", RawName = "ic2.blockreactor", Position = {X = 1, Y = 0, Z = 0}}
        machine.targets["61,0,0"] = {Name = ""}
        machine.targets["62,0,0"] = {Name = "", RawName = "ic2.blockcable"}
        local sensor = bus.computer(20020, "sensor", {range = 30, position = {6, 120, 0}, sensors = {top = machine}}):start()
        bus.advance(6)
        equal(sensor.client.connected, false); equal(#sensor.client.ports.top.targets, 62)
        for i = 1, 5 do bus.computer(20020 + i, "relay", {range = 30, position = {0, i * 20, 0}}):start() end
        bus.advance(12); equal(sensor.client.connected, true)
        local clients = central.server.api.getSensorClients()
        equal(#clients[1].ports, 1); equal(clients[1].ports[1].side, "top")
        equal(#clients[1].ports[1].targets, 62)
        local Picker = central.env.dofile("lib_sensor_picker.lua")
        local dialog = Picker.new("test", {clientId = "sensor_20020"}, "reactor"); dialog.stage = 2
        Picker.render(dialog, 40, 10, clients)
        local chosen
        for _, hit in ipairs(dialog.hits) do if hit.action == "select" and hit.value.value == "top" then chosen = hit end end
        assert(chosen and chosen.enabled ~= false)
        Picker.touch(dialog, chosen.x1, chosen.y1 or chosen.y); equal(dialog.stage, 3)
        Picker.render(dialog, 40, 10, clients)
        chosen = nil
        for _, hit in ipairs(dialog.hits) do if hit.action == "select" and hit.value.value == "1,0,0" then chosen = hit end end
        assert(chosen, "Localized reactor must remain selectable by its RawName identity")
        Picker.touch(dialog, chosen.x1, chosen.y1 or chosen.y)
        equal(dialog.chosen.targetType, "Reaktor")
        assert(central.server.api.watchSensor("regression", dialog.chosen)); bus.advance(3)
        local reading = central.server.api.getSensorReading(dialog.chosen)
        equal(reading.status, "ok"); equal(reading.reactor.heat, 48036)
        assert(table.concat(central.server.command("sensors sensor_20020"), "\n"):find("targets=62 reactors=1", 1, true))
    end
end

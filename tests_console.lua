-- Execute the real OS console while connection logs, timers and edits interleave.
return function(tests, newBus, monitor, serialize, unserialize, equal)
    local function event(bus, computer, name, value)
        bus.queue(computer, {name, value}); bus.pump()
    end

    function tests.console_async_logs_preserve_bottom_prompt_and_insertion_cursor()
        local bus = newBus()
        local screen = monitor(24, 8)
        local central = bus.computer(10, "server", {terminal = screen})
        central.env.read = function() error("The live console must not use read's fixed cursor row") end
        central:start()
        event(bus, central, "char", "clints")
        for _ = 1, 3 do event(bus, central, "key", 203) end
        equal(central.console.cursor, 3)
        local bridge = bus.computer(11, "io"):start()
        assert(bridge.client.connected)
        for index = 1, 12 do central.server.api.log("Async message " .. index) end
        equal(central.console.text, "clints"); equal(central.console.cursor, 3)
        equal(screen.lines[8], "> clints" .. string.rep(" ", 16))
        equal(screen.x, 6); equal(screen.y, 8); equal(screen.blink, true)
        assert(screen.lines[7]:find("Async message 12", 1, true))
        event(bus, central, "char", "e")
        equal(central.console.text, "clients")
        event(bus, central, "key", 28)
        equal(central.console.text, "")
        equal(screen.lines[8], "> " .. string.rep(" ", 22))
        assert(central.console.lines[#central.console.lines]:find("io_11 io ONLINE", 1, true))
        equal(screen.x, 3); equal(screen.y, 8)
    end

    function tests.console_clear_keeps_app_state_windows_outputs_and_network_alive()
        local bus = newBus()
        local file = assert(io.open("apps_coffee.lua", "r")); local coffee = file:read("*a"); file:close()
        local central = bus.computer(10, "server", {apps = {["apps_coffee.lua"] = coffee}}):start()
        local bridge = bus.computer(11, "io"):start()
        bus.computer(13, "monitor", {monitors = {top = monitor(60, 24)}}):start()
        local id = assert(central.server.api.openApp("coffee", "monitor_13:top"))
        assert(central.server.api.layoutWindow(id, "right"))
        assert(central.server.api.mapOutput("lamp", "io_11", "left", nil))
        assert(central.server.api.setOutput("lamp", true)); bus.pump(); bus.advance(1)
        local state, saved = serialize(central.server.state), central.disk.files["configs_os_state.txt"]
        bus.command(central, "clear")
        equal(serialize(central.server.state), state); equal(central.disk.files["configs_os_state.txt"], saved)
        equal(#central.console.lines, 0)
        for y = 1, central.terminal.height - 1 do equal(central.terminal.lines[y], string.rep(" ", central.terminal.width)) end
        equal(central.terminal.lines[central.terminal.height], "> " .. string.rep(" ", central.terminal.width - 2))
        equal(central.server.state.windows[id].layout, "right"); equal(central.server.running.coffee, true)
        equal(bridge.digital.left, true)
        bus.advance(1); equal(central.server.lastTick, bus.now); equal(bridge.client.connected, true)
        bus.command(central, "help")
        assert(table.concat(central.console.lines, "\n"):find("clear | save | quit", 1, true))
    end

    function tests.console_editing_history_and_clear_preserve_an_unsubmitted_draft()
        local computer = newBus().computer(10, "server")
        local screen = monitor(15, 5)
        local console = computer.env.dofile("lib_console.lua").new(screen)
        console.handle("paste", "abcdef")
        console.handle("key", 199); console.handle("key", 211); console.handle("char", "X")
        console.handle("key", 207); console.handle("key", 14); console.handle("key", 203); console.handle("key", 211)
        equal(console.text, "Xbcd")
        equal(console.handle("key", 28), "Xbcd")
        console.handle("paste", "value"); equal(console.handle("key", 156), "value")
        console.handle("char", "half")
        console.handle("key", 200); equal(console.text, "value")
        console.handle("key", 200); equal(console.text, "Xbcd")
        console.handle("key", 208); equal(console.text, "value")
        console.handle("key", 208); equal(console.text, "half")
        console.clear(); equal(console.text, "half"); equal(#console.history, 2)
        assert(screen.lines[5]:find("> half", 1, true))
        console.handle("paste", "\nquit\n")
        equal(console.text, "half quit ", "Pasted newlines must not submit a hidden command")
    end

    function tests.console_long_lines_wrap_without_losing_input_through_terminal_resize()
        local computer = newBus().computer(10, "server")
        local screen = monitor(10, 4)
        local console = computer.env.dofile("lib_console.lua").new(screen)
        local draft = string.rep("abcdef", 10)
        console.handle("paste", draft)
        console.log("A long message that wraps into multiple rows", "and more", 123)
        for _, size in ipairs({{10, 4}, {19, 9}, {40, 6}, {3, 2}, {51, 19}}) do
            screen.width, screen.height = size[1], size[2]
            console.handle("term_resize")
            equal(console.text, draft); equal(console.cursor, #draft)
            assert(screen.x >= 1 and screen.x <= screen.width); equal(screen.y, screen.height)
            for y = 1, screen.height do equal(#screen.lines[y], screen.width) end
            equal(screen.lines[screen.height]:sub(1, 2), "> ")
        end
        equal(console.handle("key", 28), draft)
    end

    function tests.console_quit_saves_and_returns_a_clean_cursor_to_craftos()
        local bus = newBus()
        local central = bus.computer(10, "server"):start()
        local nativePrint = central.env.print
        bus.command(central, "quit")
        equal(central.active, false)
        assert(unserialize(central.disk.files["configs_os_state.txt"]))
        equal(central.env.print, nativePrint, "Console logging must not replace global print")
        equal(central.terminal.x, 1); equal(central.terminal.y, central.terminal.height)
        equal(central.terminal.blink, false)
        equal(central.terminal.lines[central.terminal.height], string.rep(" ", central.terminal.width))
    end
end

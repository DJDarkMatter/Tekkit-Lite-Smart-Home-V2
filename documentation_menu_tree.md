# SmartHome OS menu tree

This is the editable source for the [portrait PDF](documentation_menu_tree.pdf). Brackets mark entries that depend on the installed apps, configured devices, or screen size.

Review these paths against the Lua menus whenever the UI changes. Each pair of spaces makes a child path. Named anchors and Markdown links connect reusable dialogs and related pages. Screensaver rows are generated from the Lua catalog in the order listed under [designs and credits](documentation_screensaver.md).

Build with `python3 -m pip install reportlab==4.4.9` followed by `python3 tools_build_menu_tree.py`. Run `python3 tools_build_menu_tree.py --check` before releasing. The check uses the Python standard library and flags changes to the documented sources, app coverage, names, OS version, or builder. Rebuilding records that the written paths have been reviewed. Render and inspect every PDF page after changes.

## OS

### Desktop & windows

Launcher, taskbar, title-bar controls and window placement.

**Path** Monitor desktop

**Source** [lib_desktop.lua](lib_desktop.lua), [lib_server.lua](lib_server.lua), [lib_monitor.lua](lib_monitor.lua), [documentation_desktop.md](documentation_desktop.md)

- Taskbar
  - Start [+] — Lists Settings and compatible enabled apps alphabetically. A star marks a running app.
    - [Settings](#settings) — Opens the built-in Settings window.
    - [App] — Opens the app or focuses its existing window on this monitor.
    - [Alert inbox](#alert-inbox) — Launcher entry on monitors without the clock shortcut.
  - [Window tab] — Focus, minimize the focused window, or restore a minimized one.
  - ‹ / › — Scroll through the window tabs when they overflow.
  - [[Clock / alert badge]](#alert-inbox) — Opens or closes the Alert inbox where the clock fits.
- Window title bar
  - Minimize [-] — Restore from the taskbar.
  - X Close — Closes the window on this monitor.
  - [[Title area]](#desktop--windows-move) — Starts the Move workflow.
  - Layout [#]
    - 1×1 — Applies immediately. Uses the desktop area and keeps the taskbar.
    - 2×1 / 1×2 / 2×2 — Pick a numbered pane on the next screen.
      - [Position] — Positions that cannot fit the app are disabled.
    - 3×1 / 1×3 / 3×2 / 2×3 / 3×3 — More numbered panes.
      - [Position] — Positions that cannot fit the app are disabled.
    - Restore — Returns to the normal layout when a preset is active.
    - Fullscreen — Uses all monitor cells.
      - [Top-right cell] — Restores ordinary windows. Screensaver handles the corner itself.
    - Resize
      - First corner — Touch to select. Arrows nudge, Place repicks and OK accepts the corner.
        - Other corner — Touch, nudge or repick. OK applies if the window fits.
    - <a name="desktop--windows-move"></a> Move
      - Pick position — Touch, nudge or use Place to repick. OK applies and Cancel exits.
    - Cancel — Closes the layout menu.
- [Monitor-client calibration] — Run clients_monitor_client.lua calibrate [side].
  - [Measure nine points] — Touch the centers from the usual viewing position.
  - [Test preview] — The --test flag starts here. Arrows adjust the offset.
    - Save / Reset / Cancel — Save the offset, preview the stock offset or exit.
    - Remeasure — R on the client keyboard repeats the measurement.
  - [Retry screen] — Appears when samples disagree. Retry, Reset or Cancel.

### Settings

Appearance, system diagnostics, client names and saved app data.

**Path** Desktop → Start → Settings

**Source** [lib_settings.lua](lib_settings.lua), [lib_system.lua](lib_system.lua), [lib_server.lua](lib_server.lua)

- Appearance
  - [Background](#shared-dialogs-os-color-palette) — Choose a desktop background color.
  - [Window border / Borders](#shared-dialogs-os-color-palette) — Choose a frame color.
  - [Taskbar](#shared-dialogs-os-color-palette) — Choose a taskbar color.
- System overview
  - Central computer — IDs, channels, uptime, last checkpoint, world clock and player status.
  - Clients — Announced clients and online/offline status.
    - <a name="settings-client"></a> [Client] / Client details — Role-specific monitor, IO, sensor or relay data.
      - Targets — Sensor clients only.
        - [Sensor target] — Catalog metadata and cached readings.
    - Filter — Cycles all, IO, monitor, sensor and relay.
  - Sensors — Opens the Sensor clients list.
    - [[Sensor client]](#settings-client) — Open details, then Targets.
    - Filter — Same control as on the Clients page.
  - Outputs — Mapped outputs with their requested ON/OFF states.
    - [Mapped output] — Route, desired value, online status and acknowledgment.
  - Apps — Enabled apps and running/background status.
  - Windows — Saved windows by monitor with geometry and state.
  - Uptime history — Observed OS and client online/offline events.
  - Relay map
    - [Client route] / Observed path — OS, relay hops and endpoint. Relay details also list downstream devices.
      - [Details](#settings-client) — Opens the selected client's details.
  - Overview options
    - Client filter — Cycles all, IO, monitor, sensor and relay.
    - About — Explains the live registry and last-observed paths.
- Client names
  - [Client] / Client name — Friendly label and stable ID.
    - [Rename](#shared-dialogs-touch-keyboard) — Set saves the label. Back returns to the selected client.
    - Reset — Clears the friendly label and restores the ID.
- Screensavers — Read-only numbered list from the installed Screensaver app.
  - [[Design names in cycle order]](#screensaver-design-rotation) — To run or cycle them, open Screensaver from Start.
- App data
  - Backup & restore
    - Create backup
      - [Entire OS / OS settings / app] — Creates a backup immediately when none exists.
        - Replace backup? — Replace or Cancel if a backup already exists.
    - Restore backup
      - [Existing backup]
        - Restore data? — Restore or Cancel.
  - Reset data
    - Entire OS
      - Are you sure? — Continue or Cancel.
        - Are you really sure? — Erase all or Cancel.
    - OS settings
      - Are you sure? — Delete data or Cancel. Clears desktop layout, appearance and OS routes.
    - [App]
      - Are you sure? — Delete data or Cancel. Clears app data, routes and layouts.
  - Delete apps
    - [Installed app]
      - Delete app? — Uninstall or Cancel. Saved settings are kept.
- Close — Closes this monitor's Settings window.

### Alert inbox

Recent alert history and the separate acknowledgment popup.

**Path** Desktop → Clock / alert badge or Start → Alert inbox

**Source** [lib_alert_inbox.lua](lib_alert_inbox.lua), [lib_server.lua](lib_server.lua)

- Alert list — Newest first. Active alerts are marked with an asterisk.
  - [Alert] / Details — Time, message and Active or Closed status. Back returns to the list.
  - Back — Closes the inbox.
- [Active popup] — Separate modal shown above the desktop and fullscreen apps.
  - OK — Acknowledges through the originating app. Clock and Level emitter can also use a configured dismiss input.

### Shared dialogs

Reusable picker and editor flows linked from their calling menus.

**Path** Opened by an app action

**Source** [lib_io_picker.lua](lib_io_picker.lua), [lib_sensor_picker.lua](lib_sensor_picker.lua), [lib_gui.lua](lib_gui.lua), [lib_server.lua](lib_server.lua)

- <a name="shared-dialogs-redstone-picker"></a> Redstone picker
  - Select IO
    - Select side — Uses the selected IO client.
      - Select wire — Digital or one of 16 bundled colors. Roomy screens show the selected client and side.
        - Use this input? — Shows ON, OFF or Unknown when the input can be read.
          - Use — Passes the selected input to the app.
        - Use this output?
          - Test — Briefly tests the output from the confirmation screen.
          - Use — Passes the selected output to the app.
- <a name="shared-dialogs-sensor-picker"></a> Sensor picker
  - Sensor client
    - Sensor side — Filtered pickers require a compatible card.
      - Select target — The selected card supplies the catalog. Roomy screens show the path so far.
        - Use sensor?
          - Use — Passes the selected sensor address to the app.
- <a name="shared-dialogs-os-color-palette"></a> OS color palette
  - [Color swatch] — Standard OS palette applies on selection. Some apps have their own Apply preview.
  - Back — Returns to the calling screen.
- <a name="shared-dialogs-touch-keyboard"></a> Touch keyboard
  - [QWERTY keys] — Three letter rows. Compact keyboards page the rows when needed.
  - ABC / 123 / abc — The mode key shows the next bank. Uppercase resets after one letter.
  - Space / Sp and Del — Insert a space or delete the last character.
  - Set / Save / Find — Apply the draft using the calling screen's action.
  - Clr / Back — Clear the draft or return.
- <a name="shared-dialogs-number-pad"></a> Number pad
  - [Digits / Clr / Del] — Enter a whole number. Clock's world-time editor uses HHMM.
  - Set / Back — Apply the draft or return. The caller validates the value.
- <a name="shared-dialogs-decimal-pad"></a> Decimal number pad
  - [Digits / . / Del] — Enter decimal seconds for a Switchboard button or Logic Sandbox Wait.
  - Set / Back — Apply the draft or return. The caller checks precision and range.

## Automation

### Clock

World-time alarms, timers, a stopwatch and optional redstone signals.

**Path** Desktop → Start → Clock

**Source** [apps_clock.lua](apps_clock.lua), [documentation_clock.md](documentation_clock.md)

- Alarms — Opens World-time alarms.
  - [+ Add alarm](#clock-edit-alarm) — Opens a blank alarm editor.
  - [Alarm] / Details
    - Enabled / Disabled — Toggle the alarm.
    - Dismiss / OK — Appears while the alert is pending.
    - Output / signal details — Route, timing, dismiss input and wire acknowledgment.
    - <a name="clock-edit-alarm"></a> Edit / Alarm settings
      - [Name](#shared-dialogs-touch-keyboard) — Touch keyboard.
      - [Time](#shared-dialogs-number-pad) — Minecraft world time in HHMM.
      - Repeat — Daily or Once.
      - Enabled — Yes or No.
      - [Select output](#shared-dialogs-redstone-picker) — Optional redstone output.
      - Disconnect output — Available after assigning an output.
      - [Select dismiss input](#shared-dialogs-redstone-picker) — Optional fresh input press to acknowledge.
      - Clear dismiss input — Available after assigning an input.
      - Signal — Cycles Constant and Pattern.
      - [Length](#shared-dialogs-number-pad) — Constant only. Zero means Until OK.
      - [ON / OFF / Total](#shared-dialogs-number-pad) — Pattern only. Total zero means Until OK.
      - Save / Cancel — Save the alarm or discard the draft.
    - Delete
      - Delete alarm? — Delete or Cancel.
- Timers — Opens Timers / recent.
  - [+ Add timer](#clock-edit-timer) — Opens a blank timer editor. Use Start to save and run it.
  - [Timer] / Details
    - Pause / Resume / Restart — Depends on the current timer state.
    - Cancel timer — Available when running or paused.
    - Dismiss / OK — Appears while the alert is pending.
    - Output / signal details — Route, signal timing, dismiss input and acknowledgment.
    - <a name="clock-edit-timer"></a> Edit / Timer settings — Available while the timer is not running and has no pending alert.
      - [Name](#shared-dialogs-touch-keyboard) — Touch keyboard.
      - [Time](#shared-dialogs-number-pad) — Enter the duration in seconds.
      - Clock — Real time or Game time.
      - [Select output](#shared-dialogs-redstone-picker) — Optional redstone output.
      - Disconnect output — Available after assigning an output.
      - [Select dismiss input](#shared-dialogs-redstone-picker) — Optional fresh input press to acknowledge.
      - Clear dismiss input — Available after assigning an input.
      - Signal — Cycles Constant and Pattern.
      - [Length](#shared-dialogs-number-pad) — Constant only. Zero means Until OK.
      - [ON / OFF / Total](#shared-dialogs-number-pad) — Pattern only. Total zero means Until OK.
      - Start / Save / Cancel — Start a new timer, save edits or discard the draft.
    - Delete
      - Delete timer? — Delete or Cancel.
- Stopwatch
  - Start / Stop — Runs or stops the elapsed clock.
  - Lap — Adds a split while running. The lap list can page.
  - Reset — Clears elapsed time and lap history.
  - Real / Game — Change the time base when stopped and reset. Real shows tenths. Game shows days and HH:MM:SS.
- Settings
  - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - Timer history — Cycles 10, 20 and 50 retained results.
  - <a name="clock-clock-status"></a> Clock status — World time, source health and errors.
  - About / restart rules — Explains trigger, timing and restart behavior.
- [Status](#clock-clock-status) — Home shortcut to Clock status.
- [[Alarm / timer popup]](#alert-inbox) — OK or the configured dismiss input acknowledges it.

### Coffee

Harvest countdown, player input, output routing and counters.

**Path** Desktop → Start → Coffee

**Source** [apps_coffee.lua](apps_coffee.lua), [documentation_coffee.md](documentation_coffee.md)

- Pause / Resume — Toggles the current countdown or harvest.
- Harvest now — Forces a harvest when an online output is configured.
- Menu
  - Settings
    - [Player input / Player IO](#shared-dialogs-redstone-picker) — Assign the player-presence input.
    - [Harvest output / Harvest IO](#shared-dialogs-redstone-picker) — Assign the harvest output.
    - Countdown
      - Step / - / + — 1, 10, 60, 600 or 3600 second adjustments.
      - Save (next) / Cancel — Applies the new duration to the next cycle.
    - Harvest time
      - Step / - / + — 1, 10, 60, 600 or 3600 second adjustments.
      - Save (next) / Cancel — Applies the new duration to the next cycle.
    - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - Stats / Harvest counts — Shows total and trip counts.
    - Reset trip — Zeros the trip counter.
  - Maintenance
    - Reset timer
      - Reset timer? — Confirm or Cancel. Confirm starts a fresh countdown.
    - Import save
      - Import save? — Confirm or Cancel. Reads countdown_state.txt and imports paused.

### Level emitter

Item-count rules with hold, rearm and optional signal outputs.

**Path** Desktop → Start → Level emitter

**Source** [apps_level_emitter.lua](apps_level_emitter.lua), [documentation_level_emitter.md](documentation_level_emitter.md)

- + Add — Select an AE sensor, then choose an item.
  - [[AE sensor picker]](#shared-dialogs-sensor-picker) — Select a sensor client, AE card side and target.
    - [Select item](#level-emitter-item) — After accepting the sensor.
      - [Level rule](#level-emitter-edit-rule) — After choosing an item.
- [Rule]
  - Enable / Disable — Toggles evaluation of the rule.
  - <a name="level-emitter-edit-rule"></a> Edit rule / Level rule — Editing is unavailable while its alert is pending.
    - [Name](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - <a name="level-emitter-item"></a> Item / Select item
      - [Item] — Uses the selected identity and returns to the rule editor.
      - Find / Item list
        - [Search](#shared-dialogs-touch-keyboard) — Touch keyboard.
        - Sort / Order — Name or amount, ascending or descending.
        - Refresh — Rebuilds the item list.
        - Manual item / Register absent item
          - [Name / RawName](#shared-dialogs-touch-keyboard) — Enter the display name and exact raw item name.
          - [Damage](#shared-dialogs-number-pad) — Enter the item's damage value.
          - Use item — Uses the manual identity.
    - [ME / Select ME](#shared-dialogs-sensor-picker) — Changes the rule's AE sensor.
    - Condition / Compare item count
      - Under (<)
      - Over (>)
      - Exactly (=) — Rearms when the count differs.
    - [Level](#shared-dialogs-number-pad) — Target item count.
    - [Hold](#shared-dialogs-number-pad) — Required matching duration in seconds.
    - Enabled — Yes or No.
    - [Rearm](#shared-dialogs-number-pad) — Count at which an Under/Over rule can rearm.
    - [Select output (optional)](#shared-dialogs-redstone-picker) — Bind a redstone output.
    - [Select dismiss input](#shared-dialogs-redstone-picker) — Bind an acknowledgment input.
    - Signal — Cycles Constant and Pattern.
    - [Length](#shared-dialogs-number-pad) — Constant only. Zero means Until OK.
    - [On / Off / Total](#shared-dialogs-number-pad) — Pattern only. Total zero means Until OK.
    - Disconnect output — Clears the draft's existing output.
    - Clear dismiss input — Clears the draft's existing input.
    - Save / Cancel — Save the rule or discard the draft.
  - Item and IO details — Identity, sensor, thresholds, routes and source status.
  - Delete rule
    - Delete level rule? — Delete or Cancel.
- Menu
  - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - About / alarm behavior — Threshold, signal, latching and acknowledgment rules.
  - Imported Solar rules — Read-only migration count.
- [[Rule alert popup]](#alert-inbox) — OK or the configured dismiss input acknowledges it.

### Logic Sandbox

Build circuits from redstone and ME stock, then connect gates, delays and reusable actions.

**Path** Desktop → Start → Logic Sandbox

**Source** [apps_logic_sandbox.lua](apps_logic_sandbox.lua), [documentation_logic_sandbox.md](documentation_logic_sandbox.md)

- [+ New circuit](#shared-dialogs-touch-keyboard) — Enter a name. Set opens a new, disabled circuit.
- [Circuit]
  - OFF - Enable / ON - Disable — Toggles the circuit's background evaluation.
  - <a name="logic-sandbox-setup-tips"></a> Setup tips — Appears when block connections need attention.
    - [Tip] — Explains the missing step for that block.
      - Edit / Back — Opens the block editor or returns to the tips.
  - + Add / Add logic node
    - [Redstone input / Input](#logic-sandbox-routing) — Reads a redstone wire.
    - [Item amount](#logic-sandbox-stock) — Compares an item count from the selected ME network.
    - [AND / OR / NOT / XOR](#logic-sandbox-gates) — Combines or inverts signals.
    - [Delay](#logic-sandbox-delay) — Waits for a source to stay on.
    - [If / Then](#logic-sandbox-rule) — Runs action blocks in order on a rising condition.
    - [Redstone output / Output](#logic-sandbox-output) — Routes a signal to a wire.
    - [Wait / Set output / Alarm](#logic-sandbox-actions) — Reusable blocks for rules.
    - [Output target](#logic-sandbox-target) — A named wire destination for Set output blocks.
  - <a name="logic-sandbox-flow"></a> Flow / Circuit flow — Paged text view of conditions, routes and actions. Back returns to the circuit.
  - Menu
    - [View flow](#logic-sandbox-flow) — Available here when Flow does not fit the circuit footer.
    - Enable circuit / Disable circuit — Turns background evaluation on or off.
    - [Check setup](#logic-sandbox-setup-tips) — Checks connections and explains missing steps.
    - [Rename circuit](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - Delete circuit
      - Delete? — Delete or Cancel.
  - [Node] — Numbered rows identify blocks. Roomy windows show ON, OFF, Waiting, Running, Ready, Action or Alert separately.
    - <a name="logic-sandbox-routing"></a> [Select redstone](#shared-dialogs-redstone-picker) — Input, Output and Output target. A saved route shows its address.
    - Clear routing — Available when one of those nodes has an assigned route.
    - <a name="logic-sandbox-stock"></a> Set item count / Edit count — Item amount only. Visible saved counts stay live while the circuit is disabled. Source errors explain an unavailable count.
      - [ME / Select ME](#shared-dialogs-sensor-picker) — Select an AE sensor, side and target.
      - Select item — Live item names and amounts. Select a row to use its identity.
        - Find / Find item
          - [Search](#shared-dialogs-touch-keyboard) — Filter by item name or RawName.
          - Refresh — Rebuilds the item list.
          - Manual item — Register an item that is absent from the network.
            - [Name / RawName](#shared-dialogs-touch-keyboard) — Enter display and exact raw names.
            - [Damage](#shared-dialogs-number-pad) — Enter the item's damage value.
            - Use / Back — Use the identity or return to Find item.
      - Compare / Compare count
        - Under (<) / Over (>) / Exactly (=) — Choose the comparison.
      - [Level](#shared-dialogs-number-pad) — Enter the item count to compare against.
      - Save / Cancel — Commit the stock condition or discard the draft.
    - <a name="logic-sandbox-gates"></a> A / B — A for all gates. B for AND, OR and XOR. Pick Unwired or a compatible source node.
    - <a name="logic-sandbox-output"></a> From — The source for a Redstone output. Choose Unwired or a compatible node.
    - <a name="logic-sandbox-delay"></a> Delay editor
      - When — Choose the signal that must stay on.
      - [Wait](#shared-dialogs-decimal-pad) — Set seconds with up to two decimal places.
      - [+ Link output](#shared-dialogs-redstone-picker) — Creates and routes an Output fed by this Delay.
    - <a name="logic-sandbox-rule"></a> If / Then editor
      - When — Pick the triggering node. The rule's signal is on while it runs.
      - Then blocks — View the ordered steps for this rule.
        - + Block / Then add block
          - [+ Wait / + Set output / + Alarm](#logic-sandbox-actions) — Create and edit a reusable block.
          - [Existing block] — Reuse a named block here or in another rule.
        - [Step]
          - [Edit block](#logic-sandbox-actions) — Edit the shared block. Rule returns to the steps.
          - Move earlier / Move later — Reorder this occurrence.
          - Remove step / Remove from rule? — Remove this occurrence or Cancel.
    - <a name="logic-sandbox-actions"></a> Action block editors
      - [Wait](#shared-dialogs-decimal-pad) — Pause this rule for the entered decimal seconds.
      - Set output
        - Choose target / Target — Pick an existing named Output target.
          - [+ New target](#logic-sandbox-target) — Creates a target and opens the redstone picker.
        - Set ON / Set OFF — Changes the value this block sends.
        - [Select redstone / saved route](#shared-dialogs-redstone-picker) — Sets or changes the chosen target's wire.
      - Alarm — Runs as an action in If / Then. Popup title is Alarm.
        - [Name](#shared-dialogs-touch-keyboard) — Enter the popup cause. An empty name uses the circuit name.
    - <a name="logic-sandbox-target"></a> Output target editor — Choose or clear a wire using the routing controls above.
    - Popup ON / OFF — Optional alert for other signal nodes. Item amount uses an If / Then Alarm action.
    - [Rename node](#shared-dialogs-touch-keyboard) — Other nodes. Alarm uses its Name control above.
    - [Setup tip](#logic-sandbox-setup-tips) — Item amount or Alarm editors with a missing connection.
    - Delete node
      - Delete? — Delete or Cancel.
- [[Node / Alarm block popup]](#alert-inbox) — OK acknowledges the alert.
- Close — Closes the current window.

### Switchboard

IO side presets, timed buttons, custom switch grids and scenes.

**Path** Desktop → Start → Switchboard

**Source** [apps_switchboard.lua](apps_switchboard.lua), [documentation_switchboard.md](documentation_switchboard.md)

- + Add view / New view
  - + Empty view
    - Empty view — Set Cols and Rows with the +/- controls.
      - Create / Cancel — Create adds an unwired grid.
  - [IO client]
    - Select side
      - [Available side]
        - 16 switches
          - Create — Adds a 4×4 view with one switch per bundled wire color.
- [View] / Switch grid
  - [Routed tile] — Toggles a switch or starts a timed button press. Tapping a timed button again restarts its timer.
  - [[Unwired / invalid tile]](#switchboard-switch) — Opens that switch's editor.
  - Edit / View settings
    - [Rename view](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - Edit switches
      - <a name="switchboard-switch"></a> [Switch] — The editor retains the original route and wire color.
        - [Rename / Name](#shared-dialogs-touch-keyboard) — Touch keyboard.
        - Color / Button color
          - [Swatch] / IO default / By state — Pick a fixed color, use the wire color or use the state color.
          - Apply / Cancel — Save or discard the color draft.
        - State colors / States
          - Active / Inactive / Pending — Pick a swatch or Inherit from the view. Apply to save.
        - [Routing / Route](#shared-dialogs-redstone-picker) — Assign an IO client, side and Digital or bundled color.
        - Behavior / Mode — Opens Switch mode.
          - Switch — Tap the tile to toggle a steady output.
          - Button — Tap for a timed press. The IO client ends the press locally.
            - [Time](#shared-dialogs-decimal-pad) — Enter seconds with up to two decimal places. The mode screen shows the client's minimum.
        - Disconnect
          - Disconnect? — Confirm or Cancel.
    - State colors / View state colors
      - Active / Inactive / Pending — Pick a swatch or Inherit from app settings. Apply to save.
    - Grid size
      - Cols / Rows — Adjust the grid.
      - Save grid
        - Remove cells? — Confirm or Cancel if the grid is shrinking.
    - All OFF
      - All OFF? — Confirm or Cancel for this view.
    - Move earlier / Move later — Reorders the view on the home page.
    - Delete view
      - Delete view? — Confirm or Cancel.
- Scenes
  - [Scene] — Tapping a scene reapplies saved ordinary switch states to matching routes.
  - + New scene / Capture scene
    - [All views](#shared-dialogs-touch-keyboard) — Captures routed ordinary switches from all views after naming the scene.
    - [[One view]](#shared-dialogs-touch-keyboard) — Captures routed ordinary switches from the selected view after naming it.
  - Edit
    - [Scene]
      - [Rename](#shared-dialogs-touch-keyboard) — Touch keyboard.
      - Delete
        - Delete scene? — Delete or Cancel.
- Settings / App settings
  - UI color — Preview a swatch, then Apply or Cancel.
  - Background — Preview a swatch, then Apply or Cancel.
  - Button borders — Preview a swatch, then Apply or Cancel.
  - Unwired tiles — Preview a swatch, then Apply or Cancel.
  - Active color — Preview a swatch, then Apply or Cancel.
  - Inactive color — Preview a swatch, then Apply or Cancel.
  - Pending color — Preview a swatch, then Apply or Cancel.
  - Density — Cycles roomy and compact.
  - All switches OFF
    - All OFF? — Confirm or Cancel for all views.

## ME & Machines

### ME monitors

Saved grid and list views for live ME item counts.

**Path** Desktop → Start → ME monitors

**Source** [apps_me_monitor.lua](apps_me_monitor.lua), [documentation_me_monitor.md](documentation_me_monitor.md)

- + Add view
  - [[AE sensor picker]](#shared-dialogs-sensor-picker) — Select a client, AE card side and ME target.
    - New view layout — Opens after accepting the sensor.
      - List / Grid — Toggle the layout.
      - Items / Cols / Rows — Adjust list size or grid dimensions.
      - Create / Cancel — Create opens the new view.
- [View] — Item tiles in a grid or a paged list.
  - [[+ Item / Empty tile]](#me-monitors-item) — Opens the item picker.
  - [Assigned tile] / Item monitor
    - <a name="me-monitors-item"></a> Item / Select item
      - Name / Amount — Sort by item name or stored count.
      - A-Z / Z-A / Low-Hi / Hi-Low — Reverse the current sort.
      - [Search / Find](#shared-dialogs-touch-keyboard) — Search display names and raw names.
      - Refresh / Sync — Refresh the picker rows.
      - [Item] — Assigns this item to the chosen tile.
    - Color
      - [Color swatch] — Pick a custom grid tile or list row color.
      - Apply / Auto / Back — Auto restores default colors. Apply saves the preview.
    - Clear — Removes the item assignment.
  - Edit / View settings
    - Change rates / Rates — Toggles signed 5-minute change and net hourly rate.
    - [Rename view](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - Edit items / Choose a tile
      - [[Tile]](#me-monitors-item) — Opens the picker directly.
    - Layout / size
      - List / Grid — Toggle the layout.
      - Items / Cols / Rows — Adjust list size or grid dimensions.
      - Save grid
        - Remove last tiles? — Confirm or Cancel when shrinking.
    - [AE source](#shared-dialogs-sensor-picker) — Changes the view's sensor binding.
    - Source information — Client, side, target, status and age.
    - Delete view
      - Delete view? — Confirm or Cancel.
- Settings / Monitor settings
  - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - Density — Cycles roomy and compact.
  - About — Setup, sensor reads and count formatting.

### ME storage

Storage dashboards, exact counters and optional drive surveys.

**Path** Desktop → Start → ME storage

**Source** [apps_me_storage.lua](apps_me_storage.lua), [documentation_me_storage.md](documentation_me_storage.md)

- [+ Add system](#shared-dialogs-sensor-picker) — Choose an AE source. Accepting it opens the new dashboard.
- [ME system] / Dashboard — Bytes, items and types from the bound ME network.
  - <a name="me-storage-cells"></a> Cells / Cell / Drive inventories
    - Cell / drive totals — Cell survey totals across the selected live drive inventories.
    - [+ Add drive](#shared-dialogs-sensor-picker) — Uses an Inventory Card target for the drive or chest.
    - [Drive] / Drive slots
      - [Cell slot] — Item name, count and size when identifiable.
      - Source — Sensor binding, status and age.
      - Remove
        - Remove drive? — Confirm or Cancel.
  - Edit / System settings
    - [Rename](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - [Change AE sensor](#shared-dialogs-sensor-picker) — Changing the binding clears the old drive selection.
    - Source / exact figures — Binding, status, byte/item/type counts and headroom.
    - [Drive inventories](#me-storage-cells) — Alternate path to the Cells screen.
    - Remove system
      - Remove system? — Confirm or Cancel.
- Settings / ME settings
  - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - About / setup — AE1 card setup and limits of the available readings.

### Reactors

Reactor sensor readings and separate redstone control per reactor.

**Path** Desktop → Start → Reactors

**Source** [apps_reactors.lua](apps_reactors.lua), [documentation_reactors.md](documentation_reactors.md)

- [+ Add reactor](#shared-dialogs-sensor-picker) — Select a compatible sensor target. Use opens the new reactor.
- [Reactor card] — The header shows measured activity. The switch shows requested output.
  - [Set IO](#shared-dialogs-redstone-picker) — Shown if the control output is unassigned.
  - ON / OFF — Toggles a mapped output.
  - [Card body] / Reactor details — Heat, EU readings and extra fields when reported.
    - Set IO / ON / OFF — Same output control as the home card.
    - Edit / Reactor settings
      - [Rename](#shared-dialogs-touch-keyboard) — Touch keyboard.
      - [Sensor target](#shared-dialogs-sensor-picker) — Changes the monitored reactor target.
      - [Control output](#shared-dialogs-redstone-picker) — Assigns or changes the separate redstone output.
      - Raw readings / Sensor fields — Paged sensor data, including flattened nested fields.
      - Delete reactor
        - Delete reactor? — Confirm or Cancel.
- Settings / App settings
  - UI color — Preview a swatch, then Apply or Cancel.
  - Panel color — Preview a swatch, then Apply or Cancel.
  - About readings — Explains heat thresholds, EU counters and sensor limitations.

### Solar farm

Farm stock and net rates, main-ME HV tracking and item pins.

**Path** Desktop → Start → Solar farm

**Source** [apps_solar_farm.lua](apps_solar_farm.lua), [documentation_solar_farm.md](documentation_solar_farm.md)

- [Item / Amount header] — Where visible, touch to sort. Touch again to reverse.
- [Item row] / Item overview — Amount, learned average, recent change, valid time and ignored withdrawals.
  - Pin item / Edit pin
    - [Name](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - Stick — Keeps the pinned row above the sorted list.
    - Item color — Pick a swatch to apply.
    - [Drop minimum / Drop percent](#shared-dialogs-number-pad) — Override the global withdrawal filter for this item.
    - Use default filter — Clears the item-specific overrides.
    - [Select HV item](#solar-farm-hv-panel-type) — HV pin only.
    - Unpin item — Removes the pin.
- Pin item / Pin overview item — Opens the item picker.
  - [Farm ME item] — Pins the selected farm item.
  - [HV solar / main ME] — Pins the main-ME HV row.
  - [Find](#solar-farm-find) — Opens the same filters as the HV picker.
- Menu / Solar farm menu
  - ME sources
    - [Select farm ME](#shared-dialogs-sensor-picker) — Supplies the overview's farm inventory.
    - [Select main ME (HV)](#shared-dialogs-sensor-picker) — Supplies the HV output row.
  - <a name="solar-farm-hv-panel-type"></a> HV panel type / detection — Opens the Main ME item list.
    - [HV item] — Chooses the exact panel identity.
    - Auto — Restores automatic HV identification.
    - <a name="solar-farm-find"></a> Find / Find item
      - [Search](#shared-dialogs-touch-keyboard) — Touch keyboard.
      - Sort / Order — Name or amount, ascending or descending.
      - Refresh list — Rebuilds the picker list.
      - Register absent item / Absent item identity
        - [Name / RawName](#shared-dialogs-touch-keyboard) — Display name and exact raw name.
        - [Damage](#shared-dialogs-number-pad) — Enter the item's damage value.
        - Use item — Uses the registered identity.
  - Graph/change — Cycles 5, 15 and 60 minutes.
  - Rate unit — Cycles per hour, per minute and per second.
  - List sorting / Overview order
    - Pinned first (default)
    - Item A-Z / Item Z-A
    - Amount high-low / Amount low-high
  - Reset rate learning / Restart learned rates
    - Main / HV only
      - Reset rate learning? — Reset or Cancel. Keeps sources and pins.
    - Farm only
      - Reset rate learning? — Reset or Cancel. Keeps sources and pins.
    - Both ME sources
      - Reset rate learning? — Reset or Cancel. Keeps sources and pins.
  - Withdrawal filter / Ignore big withdrawals
    - [Minimum](#shared-dialogs-number-pad) — Global item-count threshold.
    - [Percent](#shared-dialogs-number-pad) — Global percentage threshold.
  - [UI color](#shared-dialogs-os-color-palette) — Standard OS palette.
  - Source status — Farm/Main health, age, learning time and HV selection.
  - About net rates — Explains stock changes, averages and sampling.

## Utilities

### IO Scope

Browse IO history and save traces for selected wires.

**Path** Desktop → Start → IO Scope

**Source** [apps_io_scope.lua](apps_io_scope.lua)

- [Used by apps](#io-scope-saved-view) — Opens a trace of wires bound by apps.
- Client side
  - [IO client]
    - [Side] / Wires
      - [Outputs](#io-scope-saved-view) — Trace output lanes on this side.
      - [Inputs](#io-scope-saved-view) — Trace input lanes on this side.
- [+ New view](#shared-dialogs-touch-keyboard) — Name a blank saved view. Set opens its trace.
- <a name="io-scope-saved-view"></a> [Saved view] / Trace — The same trace screen is also opened by live discovery views.
  - [Wire lane] / Wire details — Shows binding, current state and apps using the wire.
    - Remove — Removes the lane from a saved view.
  - ‹ Earlier / Later › — Scrolls the time window.
  - Hold / Live — Freezes the trace or follows the present.
  - Menu / … — Opens Scope menu.
    - Range — Cycles 10, 30, 60 and 120 seconds.
    - All views — Returns to the Scope home screen.
    - [Add output](#shared-dialogs-redstone-picker) — Saved view only.
    - [Add input](#shared-dialogs-redstone-picker) — Saved view only.
    - [Rename view](#shared-dialogs-touch-keyboard) — Saved view only.
    - Delete view — Saved view only.
      - Delete view? — Delete or Cancel.
    - [Save as view](#shared-dialogs-touch-keyboard) — Discovery views only. Name a snapshot of the current lane selection.
- Close — Closes the current window.

### Notes

Notes, interactive checklists and Markdown export.

**Path** Desktop → Start → Notes

**Source** [apps_notes.lua](apps_notes.lua)

- [+ New note](#shared-dialogs-touch-keyboard) — Enter a title. Set opens a new note.
- [Note]
  - [[Text line]](#notes-line-details) — Tap to open line details.
  - [[Checkbox]](#notes-line-details) — Tap to toggle it. In Edit lines mode, tap to open its details.
  - <a name="notes-line-details"></a> [Line details] — Shows the text of the selected line or checkbox.
    - [Edit](#shared-dialogs-touch-keyboard) — Modify the text with the touch keyboard.
    - Delete
      - Delete? — Delete or Cancel.
  - + Add / Add to note
    - [Text line](#shared-dialogs-touch-keyboard) — Type a line and Set to add it.
    - [Checkbox](#shared-dialogs-touch-keyboard) — Type a checklist item and Set to add it.
  - Menu / Note menu
    - Edit lines / Done editing — Controls what tapping a checkbox does.
    - [Rename note](#shared-dialogs-touch-keyboard) — Touch keyboard.
    - Export Markdown — Writes notes_export_ID.md on the OS computer.
    - Delete note
      - Delete? — Delete or Cancel.
- Close — Closes the current window.

### Screensaver

Fullscreen animations with invisible corner controls and a saved rotation.

**Path** Desktop → Start → Screensaver

**Source** [apps_screensaver.lua](apps_screensaver.lua), [lib_settings.lua](lib_settings.lua), [documentation_screensaver.md](documentation_screensaver.md)

- [Top-left 2×2 area] — Previous design, wrapping from first to last.
- [Top-right 2×2 area] — Next design, wrapping from last to first.
- [Any other touch] — Closes the fullscreen window. Active alert popups take touch priority.
- <a name="screensaver-design-rotation"></a> Design rotation — Each opening advances the design. Settings lists the same names in order.
  <!-- screensaver designs -->

### Window Presets

Capture, reassign and restore monitor window layouts.

**Path** Desktop → Start → Window Presets

**Source** [apps_window_presets.lua](apps_window_presets.lua), [documentation_desktop.md](documentation_desktop.md)

- + Save layout
  - [This monitor](#shared-dialogs-touch-keyboard) — Name and save the current monitor's layout.
  - [All online monitors](#shared-dialogs-touch-keyboard) — Name and save the layout across online monitors.
- [Preset] / Preview
  - [Monitor slot] / Monitor preview — Shows source, target and which windows can be restored.
    - Assign / Assign monitor
      - Original — Use the slot's original monitor.
      - Skip this slot
      - [Online monitor] — Assign the saved slot to that monitor.
  - [Rename preset](#shared-dialogs-touch-keyboard) — Touch keyboard.
  - Delete preset
    - Delete preset? — Delete or Cancel.
  - Apply
    - Replace layouts? — Shows open, minimized and unavailable counts.
      - Apply / Cancel — Applies the previewed layouts and keeps app data.
- Close — Closes the current window.

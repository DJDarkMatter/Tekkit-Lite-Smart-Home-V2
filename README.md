# SmartHome OS for Tekkit Lite

Repository: [DJDarkMatter/Tekkit-Lite-Smart-Home-V2](https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2). Every distributed file lives in the root; see the [complete filename map](documentation_file_map.md).

A central ComputerCraft computer owns apps, saved state and output decisions. Remote computers are reusable IO, monitor, sensor or wireless relay clients. See [the target design](documentation_design.md), [the review](documentation_review.md) and [the app/protocol reference](documentation_api.md).

This repair targets Lua 5.1 and the channel-based modem API available in ComputerCraft 1.5. It uses serialized **strings** on the wire and no CC:Tweaked-only APIs. It has been tested with simulated ComputerCraft APIs, **not inside the Minecraft server**.

## Updating to v36

V36 repairs a startup/event-loop stall introduced in v35. A lost private wake-up event could leave the worker waiting indefinitely; during saved-state startup this could happen before the modem opened. The central OS now uses one serial event loop, buffers input during cooperative pauses and uses a native timer fallback if a yield marker is lost. Startup shows its progress, opens the modem before restoring app state, and prints a caught failure's stage and message.

Upload the complete package root to the V2 repository. Replace your one installer Pastebin with this version's `install.lua` and download a fresh `inst` (banner **bundled-v36**). On the **central OS computer**, hold Ctrl+T to leave the stalled OS, run `cd /`, then `inst server` and `reboot`.

**From v35: no app or remote-client reinstall is needed.** From v33/v34, also update `solar_farm` if installed. From v32 or earlier, also update your installed v33 apps: `clock`, `coffee`, `level_emitter`, `me_monitor`, `me_storage`, `reactors`, `screensaver`, `solar_farm`, `switchboard` and `system`. Use `inst app NAME` only for apps you already use. Existing saved settings, routing, counters, learned rates and layouts are retained.

See [the v36 recovery instructions and exact changed filenames](documentation_update_v36.md). The [v33/v34/v35 reinstall checklist](documentation_update_v35.md), [v34 confirmation fix](documentation_update_v34.md) and [v33 UI changes](documentation_update_v33.md) are included.

Caught OS errors are saved in `diagnostics_os_error.txt`; type `errorlog` in the OS console after restarting, or `edit diagnostics_os_error.txt` in CraftOS. Logging is best effort; a forced shutdown may prevent a report. The original blank startup's exact server-side trigger is not confirmed. Regression tests reproduce v35's stall by dropping a wake-up event from a full simulated queue and verify recovery in v36.

## First working IO connection

Use two computers with wireless modems, initially near each other in loaded chunks in the same dimension. The OS modem can be on any side. The IO modem can also be on any side, but that side cannot be used for a cable.

### Install (one Pastebin upload)

`install.lua` is a self-contained installer containing all twenty-two runtime source files and **no user apps**. Upload its complete contents as **one** Pastebin paste, or replace the contents of your existing installer paste. It prints `SmartHome installer: bundled-v36`; OS/client installation makes no HTTP requests. Role files are extracted directly into the computer root with `lib_` and `clients_` filename prefixes. OS settings is built-in system UI. User apps are downloaded from GitHub only when requested; no separate app paste is needed and none are enabled by default.

On a computer, run:

```text
cd /
pastebin get YOUR_PASTE_ID inst
inst server --startup
reboot
```

Use `inst io --startup`, `inst monitor --startup`, `inst sensor --startup`, or `inst relay --startup` on the other computers, with the same paste ID. To replace an older downloaded installer, delete only that copy with `delete inst` before downloading the updated paste again. If it still says `Downloading lib_storage.lua`, the old HTTP installer is still being run.

The installer checks and stages all selected Lua files before replacing programs, preserves existing configuration and saved data, and backs up replaced program files as `.pre_update`. `--startup` explicitly configures the role's boot script and backs up an existing one. Omit the flag to preserve `startup`.

Downloading the installer itself through Pastebin still requires access to Pastebin, but extracting and running the bundled programs requires no GitHub access, Java HTTPS compatibility, or matching GitHub folder layout.

For an existing installation, run the new `inst server --startup`, `inst io --startup`, or `inst monitor --startup` for that computer's role. The installer imports old `Configs` settings, saved OS/app/window state, and explicitly enabled old `Apps` into the new root filenames. It keeps the old files as recovery copies and never overwrites newer flat data with an old copy. Use `--startup` so the boot script points to the renamed client. Keep the legacy saved files until the migration succeeds.

Filename prefixes replace folders: `apps_coffee.lua`, `clients_io_client.lua`, `lib_server.lua`, `documentation_design.md`, `tools_build_installer.py`, and `tests_run.lua`. App files follow `apps_NAME.lua`; the enabled app name remains `NAME`. `main_os.lua`, `install.lua`, `startup`, and `README.md` retain their established root names. Runtime data includes `configs_network.txt`, `configs_transport.txt`, `configs_io.txt`, `configs_monitor.txt`, `configs_sensor.txt`, `configs_relay.txt`, `configs_os.txt`, and `configs_os_state.txt`.


For direct file copying instead, preserve these paths:

| Role | Required files |
| --- | --- |
| All roles | `lib_work.lua`, `lib_network.lua`, `lib_storage.lua` |
| Central OS | Also `main_os.lua`, `lib_me.lua`, `lib_server.lua`, `lib_console.lua`, `lib_io_picker.lua`, `lib_desktop.lua`, `lib_settings.lua`, `lib_sensor_data.lua`, `lib_sensor_server.lua`, `lib_sensor_picker.lua` |
| IO client | Also `clients_io_client.lua`, `lib_io.lua` |
| Monitor client | Also `clients_monitor_client.lua`, `lib_monitor.lua` |
| Sensor client | Also `clients_sensor_client.lua`, `lib_sensor.lua`, `lib_sensor_data.lua` |
| Relay client | Also `clients_relay_client.lua`, `lib_relay.lua` |

Both the OS and monitor roles also require `lib_gui.lua` for color surfaces and drawing.

For maintainers: edit the normal source files, then run `python3 tools_build_installer.py` to rebuild `install.lua`. `python3 tools_build_installer.py --check` checks that it matches those sources. The previous GitHub-downloading installer is retained at `tools_install_github.lua` as an optional alternative; it is not needed by the bundled installer or installed computers.

### Installing a user app later

The same installer has an explicit app mode. On the **central OS computer**, quit to the CraftOS shell, then use one of:

```text
inst app APP_NAME
inst app APP_NAME --ref BRANCH_OR_COMMIT
inst app APP_NAME PASTE_ID
inst app APP_NAME --file /path/to/app.lua
```

`inst app APP_NAME` fetches the root file `apps_APP_NAME.lua` from the V2 repository's `main` branch, using `https://api.github.com/repos/DJDarkMatter/Tekkit-Lite-Smart-Home-V2/contents/apps_APP_NAME.lua?ref=main`. The GitHub API is the confirmed working route on the target server, so bundled-v10 uses it first. Use `--ref` to select a different branch or commit. Keep the current app file on GitHub; only the installer needs a Pastebin paste. This mode requires working HTTP access to GitHub from the server. The optional Pastebin mode uses the built-in `pastebin get` program; the file mode needs no network.

The installer decodes the API's base64 content using Lua 5.1, checks the filename and decoded byte count, and compiles the recovered source without running it. If the API request fails or returns an invalid file, it tries `raw.githubusercontent.com` as a fallback. This uses only GitHub hosts and needs no token or newer JSON API. If both routes fail, the console prints separate `Raw:` and `API:` reasons. Failed downloads leave the installed app and settings intact.

These commands install your chosen file as `apps_APP_NAME.lua` and enable only that app in `configs_os.txt`. Syntax is checked without executing the app during installation. Failed downloads, HTTP errors, empty responses and invalid Lua leave installed code/settings untouched. Existing app code and OS settings are backed up as `.pre_update`; other settings, app data and `startup` are preserved. Restart the OS to load the app. OS/IO/monitor installation never fetches apps.

Optional apps are [Coffee](documentation_coffee.md), [Switchboard](documentation_switchboard.md), and [Reactors](documentation_reactors.md). Use `inst app coffee`, `inst app switchboard` or `inst app reactors` on the OS computer to fetch one from GitHub. Coffee starts automatically without a window and offers IO, durations and color settings. Switchboard offers saved views, sixteen-color side presets, custom grids/routing, touch naming and appearance settings. Reactors selects sensor targets and separate IO switches; see [sensor setup](documentation_sensors.md) and [the reactor guide](documentation_reactors.md), including card-dependent remaining-time data. All three app sources stay unchanged in bundled-v16. Update the OS and endpoint roles to use [wireless relays](documentation_relay.md); existing direct clients remain compatible. Apps, calibration and desktop geometry need no changes for relaying.

### Version 32: learned rates, sortable tables and a finer curve

Solar farm starts directly with the Live indicators; the blue overview/navigation header is removed. Average rates now use all accepted net changes and valid observed time, saved across restarts. Retained v31 history seeds the initial estimate. Production measured in batches settles as observation grows rather than repeatedly losing old data at a rolling-window boundary. The recent graph/change period remains independent, and Menu can explicitly restart learning after a production change.

Click **Item** or **Amount** in the table header to sort; click again to reverse. Sticky items stay above the sorted rows. Small screens offer the same choices under Menu → List sorting. The three-row HV curve uses `.` and `|` for six height levels and one time column per character, with native sensor samples retained at finer intervals. Split time counters and decimal strings for large totals avoid legacy checkpoint rounding.

Upload the full v32 contents to GitHub. From v31, use the existing bundled-v31 installer on the central computer:

```text
cd /
inst app solar_farm
reboot
```

No new installer paste or core/client reinstall is needed from v31. The full release retains all **75 flat root files**; the installer remains bundled-v31 with 21 core sources and no apps. Older installations must first follow the v31 core update below.

### Version 31: Solar farm repair for legacy LuaJ and a live dashboard

Fixes the HV detector crash in LuaJ 2.0.3 that stopped processing the farm ME and also broke the HV item picker. The detector now uses safe plain word matching. One bad source no longer blocks the other source, and picker searches no longer filter the overview accidentally.

The overview includes source-health indicators and clearer unknown/empty states. Medium windows add HV output and farm stock/type/byte summaries. Larger windows add farm movement counts, selected-window item changes and a signed HV trend chart. Every farm item remains eligible for the list; if HV panels exist in the farm too, that farm stock/rate is separate from the main-ME output row. Pin/Stick controls and existing source selections are preserved. HV panel type / detection explains the main-ME binding and offers Auto.

Upload the full v31 ZIP contents to GitHub and replace/download the one installer paste with this release's **bundled-v31** `install.lua`. On the central OS, stop with Ctrl+T and run:

```text
cd /
inst server
inst app solar_farm
reboot
```

The central core update is required because the faulty matcher was in `lib_me.lua`. Existing clients, Level emitter and Screensaver need no reinstall when upgrading from v30. The complete release has **75 flat root files**, 21 bundled core sources and no bundled apps. Validation includes native Lua 5.1 and focused LuaJ 2.0.3 checks; see documentation_review.md.

### Version 30: combined Solar overview, Level emitter and Screensaver (superseded by v31)

[Solar farm](documentation_solar_farm.md) now shows farm amounts and farm net rates together in one paginated list. Only HV solar uses the main ME. It starts pinned with Stick enabled; every pin can toggle Stick or be unpinned. Pin item and Menu share the footer with page arrows when needed. The menu contains the ME sources and rate/display settings.

Item alarms are now the separate [Level emitter](documentation_level_emitter.md) app: select any ME item, Under/Over/Exactly, a level and optional hold/reset, then popup/output/dismiss-input settings. Existing Solar rules, pending alerts and output routes migrate automatically. The manual [Screensaver](documentation_screensaver.md) app offers fifteen animated designs, always fullscreen: top-left selects the previous design, top-right the next, and every other touch closes it. Alarm popups stay above it. It rotates designs on each opening and never auto-opens after reboot. Start sorts apps and OS settings alphabetically by their displayed names.

Upload the full v30 package to GitHub and replace/download your single installer paste with the new `install.lua` (**bundled-v30**). Stop the central OS with Ctrl+T and run:

```text
cd /
inst server
inst app level_emitter
inst app solar_farm
inst app screensaver
reboot
```

Install all three apps before rebooting so saved alarms can migrate before Solar farm changes schema. No endpoint client update is needed. Core role installation still contains **no apps**; these are explicit GitHub downloads. The complete release has 74 flat root files. See the guides for saved-data details and net-rate limitations.

### Version 29: Solar farm overview (superseded by v30)

The optional [Solar farm overview](documentation_solar_farm.md) replaces the planned SMF production dashboard. Select the main and farm ME targets independently, browse all farm items and main-ME net rates, and pin useful items with saved history and per-item colors. Large downward changes are treated as player withdrawals through an adjustable count/percentage filter. Rates are stock-based estimates; farm operating conditions remain external. Item buildup alarms work on either ME with saved OK popups, selectable IO output/dismiss input, Constant/Pattern signals and zero-duration indefinite operation.

Upload this complete package to GitHub. On the central OS, stop its program with Ctrl+T, then run `cd /`, `inst app solar_farm`, and `reboot`. Use Start → Solar farm to select the two sources and pin items. The existing bundled-v28 installer works unchanged: there is no new installer paste or client/core update. This app is explicitly installed and then starts its background tracking/alarms at OS boot without opening a window. The complete v29 archive contains all 66 flat root files.

### Version 28: sensor report saving on legacy CraftOS

Fixes the inspection crash `textutils:148: Cannot serialize table with recursive entries` after the first Sample line. The report reused target metadata in both its catalog and samples, and older CraftOS rejects repeated table references. Each sample now gets an independent copy, including its position. Native readings with shared sub-tables remain fully copied; genuinely cyclic readings retain bounded scalar counters with an explicit Partial status.

Replace/download the one bundled-v28 installer and run `inst sensor` on the sensor computer, then retry `clients_sensor_client.lua inspect`. After it reports Saved, run `pastebin put diagnostics_sensor.txt` and reboot to resume its normal service. Existing peripheral/card placement can stay as detected. Only this sensor role needs reinstalling for the repair. The full package includes all 63 files and retains v27 fullscreen/corner controls.

### Version 27: corner nudges and fullscreen

The title-bar layout control is `#` again. Resize now confirms each corner separately: tap a point, adjust it with the one-cell arrow pad, OK; then repeat for the opposite corner. The second OK applies the window. Place repicks the current corner; Cancel keeps the previous window.

The layout menu adds **Fullscreen** on its first screen. The app uses every monitor cell, including the former frame and taskbar. Tap the very top-right cell to restore the previous window; the app's own content remains visible in that cell. Fullscreen and its previous layout/navigation survive restarts, resolution changes and reconnection. Alarm popups remain modal above fullscreen. Coffee uses extra rows for counters on 1×1 screens and can show its graphical clock on shorter windows when all important information fits.

Upload this full package to GitHub and replace/download the single bundled-v27 installer. On the central OS, stop it with Ctrl+T, then run `cd /`, `inst server`, `inst app coffee`, and `reboot`. Existing monitor/IO/relay clients can keep their current versions. The v26 sensor inspection command below remains included; use `inst sensor` on the SMF sensor computer before collecting the report.

### Version 26: SMF inspection and responsive Reactor details

The existing sensor client gains `clients_sensor_client.lua inspect`. It records attached peripheral types/method names, sensor cards/targets and two timestamped native detail samples for detected Mass Fabricators in `diagnostics_sensor.txt`. The report is local; it changes no startup/configuration, sends no network messages and issues no redstone or machine-control commands. It handles legacy queued/yielding OCS getters through the existing request queue. Large/failed readings are explicitly marked; default inspection covers at most 32 matched targets per run.

After uploading this complete package to GitHub and updating/downloading the one bundled-v26 installer, stop the sensor client with Ctrl+T on a computer whose IndustrialCraft sensor card can see the SMFs. Run:

```text
cd /
inst sensor
clients_sensor_client.lua inspect
pastebin put diagnostics_sensor.txt
reboot
```

Reactors also removes Remaining from every operational view and adds available extra sensor fields/headroom on roomy cards and paged details. Upload the updated apps_reactors.lua, run `inst app reactors` on the central OS and reboot it; the display change does not require updating the server role.

Share the report paste ID for analysis. Normal sensor service is paused during inspection and resumes on reboot through its existing startup. Only the inspected sensor role and Reactors app changed at runtime; other roles/apps need no update. No extra program or app Pastebin is needed. See [inspection options](documentation_sensors.md).

The remaining SMF/HV work is now one planned Production overview app. It will observe SMF output, farm-made solar panels from UU, final HV output and network stocks as separate stages. Its item buildup alarms must work on either ME and accept remembered/manually registered items even when absent. Farm switches, transfer thresholds, bus modes and buffer-control rules remain external. This version supplies the investigation tool; the production app is not installed or implemented yet.

### Version 25: Clock popups and manual dismissal

Clock alarms/timers now display an **OK** popup on every monitor. OK on any monitor stops that occurrence and closes its popup everywhere; several alerts queue. **Pulse** is renamed **Constant**. Constant length **0** or Pattern total **0** runs until dismissed, either by OK or a fresh press on an independently selected **dismiss input** (IO client/side/color or Digital). Finite signals still expire normally while their popup awaits acknowledgement. Pending popups and indefinite progress survive restarts. Existing Pulse settings migrate without resetting timers or routes.

Upload the complete v25 archive's root files to GitHub and replace the single installer paste with the new `install.lua`. Download a fresh bundled-v25 `inst` on the central OS, quit the OS, run `inst server` and `inst app clock`, then reboot. Existing startup/settings remain. Client programs and other app sources do not change. See [Clock setup and dismissal behaviour](documentation_clock.md).

### Version 24: ME layouts, diagnostics and clocks

ME storage shows the six main counters in compact/medium windows and adds all three reported totals when nine cards fit. ME monitors removes the inner grey tile rim and adds Grid/List layouts plus saved per-item colors. Every title bar has a leading space. Sensor selections, routes, settings, layouts and open app pages remain checkpointed; live sensor observations still refresh after boot.

New optional apps are [CC system](documentation_system.md), a read-only client/card/route/output/app/window overview, and [Clock](documentation_clock.md), a background service for multiple world-time alarms, real/game timers with pulse/pattern IO outputs, and a saved stopwatch with laps. Apps are downloaded only when explicitly requested.

After uploading this package's root files to GitHub and replacing the one installer paste, download a fresh bundled-v24 `inst` on the central computer. Quit the OS, then run:

```text
cd /
inst server
inst app me_storage
inst app me_monitor
inst app system
inst app clock
reboot
```

Existing startup and saved settings are retained. No client updates are required for v24; Coffee, Switchboard and Reactors stay installed. Clock starts at OS boot without a window. Clocks resume from saved progress, exclude downtime and skip missed alarms; see its guide for world-time jumps, offline signals and shared routes. The full v24 archive includes every root file, not just changes.

### Confirm connection and test a wire

The IO computer prints its ID, e.g. `io_11`, then `Connected to OS computer 10`. The OS prints `io connected: io_11`. Either computer may start first; retries happen every five seconds.

The startup messages show each computer's **listening** channel, so different numbers are expected. The OS listens on `45231`; an IO computer with ID `19621` listens for replies on `20621` and sends requests to `45231`. The OS's computer ID is a separate identifier, not its channel. Keep the shared `channel` setting in `configs_network.txt` the same on both computers.

For distant devices, put wireless relay computers along a path and install `inst relay --startup`. Chains have no fixed software hop-count limit. Update the OS and endpoints that will use relays to bundled-v16; apps stay installed. The OS `clients` list shows every relay and each original device separately, with a `via=relay_...` path. See [relay setup, upgrades and range](documentation_relay.md).

Bundled-v17 fixes a sensor-catalog failure where one empty machine name could make the OS reject the whole side after a sensor connected. Native OCS `Name`/`RawName` fields are retained, including raw reactor identities when display names are localized. Update the OS and sensor roles; relays and apps need no update. The sensor picker shows waiting/rejection information and known incompatible sides as disabled. Run `sensors` or `sensors sensor_ID` on the OS to inspect received sides, target/reactor counts, missing catalog parts and the last validation error.

Bundled-v18 updates the server role and optional Reactors app: output buttons read ON/OFF; detail views show heat headroom, supplied energy counters and source information, with two columns on wide windows and paged/wrapped fields on small ones. Raw readings expand nested fields. More explicit time aliases are recognized, but the stock old IC2 card supplies no fuel lifetime/inventory, even on the core, so Remaining stays unavailable for that card. No chamber targets are added automatically. Upload the new app, run `inst server --startup`, `inst app reactors`, then reboot the OS. Other roles need no update. Monitor scale stays at its configured value (default 0.5); see [scale and individual element sizing](documentation_desktop.md).

Bundled-v19 fixes the OS crash `lib_sensor_server.lua:199: invalid key to 'next'` after closing Reactors. Sensor cleanup now traverses saved key lists before deleting readings, expired subscriptions or incomplete packets. With a fresh v19 installer, run `inst server --startup` and reboot only the central OS. Existing apps and clients need no update; saved settings, bindings and output intent are retained. The full package includes every root file.

Version 20 is an app-only Switchboard update. Each switch's editor adds a Color palette with an optional saved tile color and Auto to restore the routed wire color. Actual routing remains visible, and appearance edits leave routing and output state alone. Upload `apps_switchboard.lua` to GitHub, quit the central OS, run `inst app switchboard` with your existing installer, then reboot. No installer paste replacement or client/core update is needed. The full v20 package includes every root file and the unchanged bundled-v19 installer.

Bundled-v21 adds the optional [ME storage overview](documentation_me_storage.md), using an explicitly selected AE1 sensor/access-point source. It shows native bytes, item counts and type-slot data, with optional inventory-card drive/cell surveys. No ME app is bundled automatically. It also saves per-window app navigation (including each monitor's Switchboard view/page), adds Coffee's clock side clearance and hides its compact Player line. Update the central OS and the sensor role serving ME, then explicitly install `coffee` and `me_storage` with the fresh v21 installer. Relays, IO/monitor clients and existing Switchboard/Reactors app files need no update. The ME guide explains version-specific limits and the measurement plan for the next three independent apps.

Bundled-v22 adds independent [ME item monitors](documentation_me_monitor.md): saved views, arbitrary 1–16 by 1–16 grids, per-tile item selection, Name/Amount sorting in both directions, search and live plain-number counts. The new compact item feed shares one sensor poll with capacity views and supports bounded larger catalogs. Update the OS and affected ME sensor roles, then explicitly install `me_monitor`. Coffee's compact player line is restored; clock side clearance now matches its selected background color. The capacity dashboard removes Cells surveyed and uses plain decimal counters/one-decimal percentages without scientific notation or letter suffixes. Update `coffee` and `me_storage` too. The full package includes all fifty-seven flat root files.

Version 23 changes the ME capacity heading from Live to Usage, preserving connection/power/error messages. Drive inventories are an optional inventory-card survey of installed cells, separate from AE network totals. Update only `me_storage` using the existing installer; all core/client files and the bundled-v22 installer are unchanged. The full v23 package still includes every root file.

On the **OS console**, substitute the IO computer's actual client ID:

```text
clients
inputs io_11
map test io_11 left white
set test on
outputs
set test off
```

Connect a bundled cable on the IO computer's **left** side, and observe its white channel. `outputs` should show `confirmed` after the IO client acknowledges each state. `inputs io_11` displays bundled masks and ordinary redstone, including zero/false readings. For ordinary redstone, use `map lamp io_11 front digital`.

The OS owns the complete output mask of every mapped cable side: unmapped colors on that side are OFF. Do not drive the same side with a second program. Multiple logical names can reference the same physical wire and share its desired state. Toggling any copy updates them all. Adding a reference adopts an existing wire's current state; removing/rerouting a reference clears its old wire only when no references remain. A newly bound, previously unused wire starts with the requested initial intent. A logical output is independent of the IO computer's identity and physical wire address.

The OS console keeps its command prompt on the bottom row and displays messages above it. Connection/status messages preserve your current draft and insertion cursor. Left/Right, Home/End, Backspace/Delete and Up/Down command history are supported. Long input scrolls horizontally. Type `clear` to clear the console messages; apps, outputs, monitor windows and saved state keep running. `quit` saves and returns to CraftOS. App code should use `api.log(...)` for messages instead of writing to the local terminal directly.

To configure autorun during installation, use `install server --startup`, `install io --startup`, or `install monitor --startup`. If you downloaded the installer as `inst`, use `inst` instead of `install`. An existing boot script is backed up as `startup.pre_update` before replacement. Autorun runs when the ComputerCraft computer boots; the program does not execute while its chunk is unloaded. A Lua program error without a reboot does not rerun `startup` automatically.

Alternatively edit `startup` manually and add `shell.run("main_os.lua")` on the OS, `shell.run("clients_io_client.lua")` on an IO computer, or `shell.run("clients_monitor_client.lua")` on a monitor computer. Add the line to any existing script deliberately.

### Connection settings

The first run creates `configs_network.txt`:

```lua
{
  networkId = "home",
  channel = 45231
}
```

Choose your own `networkId` and use the same value and channel on all your computers. On clients, add `serverId = 10` with your central computer's actual ID if you want to pin them to it. Restart the program after editing settings. Relaying is enabled by default; `relayEnabled = false` selects direct-only operation on an endpoint. Keep automatically maintained `configs_transport.txt` so packet IDs remain distinct across restarts.

IO settings are in `configs_io.txt`: `clientId`, enabled `sides`, `announceInterval`, `timeout`, and `safeOff`. By default the client clears outputs at startup and switches them OFF if it loses the OS for 15 seconds. When it reconnects, the OS restores the saved desired state. `safeOff = false` keeps the last commanded outputs during a network timeout instead; startup still clears them. An enabled side is a side the client may read and drive.

IO output writes share a per-side cooldown across bundled and ordinary redstone, respecting the public server's `[IDT-Fix]` requirement of at least 0.5 seconds between writes. `outputInterval` defaults to 0.6 seconds and must be at least 0.5. Unchanged outputs are not rewritten; rapid commands coalesce to the latest desired state. A timer applies pending writes while the client continues receiving network and input events. Each output retains its own confirmation until its bundled color or digital value changes. Only changed wires lose confirmation while waiting for the full snapshot ACK; unrelated switches keep their known state. Shared aliases follow their physical wire. A real IO reconnect/restart invalidates every wire until a fresh snapshot is acknowledged. Startup and safe-off also use this queue, so clearing both output types on a side can take two intervals; restoration waits for clearing to finish.

For a replacement computer, give it the old logical `clientId` to reuse mappings. Shut down the old computer first; a duplicate active ID is rejected until the old connection times out.

This is a public-server wireless protocol, **not authentication or encryption**. Network names, IDs and channels prevent accidental cross-talk, but another player can sniff/spoof them. There is no password transmitted as a pretend security feature. Use server protections where necessary.

If no acknowledgement arrives, check: matching program versions and network settings; the pinned server ID; modem presence; wireless range/dimension; both chunks loaded. The programs keep retrying and accept late modem attachment.

## Monitors

Install a third computer with a wireless modem and one or more attached monitors:

```text
inst monitor --startup
reboot
```

For touch input, use advanced monitors. All attached monitors become independent desktops, e.g. `monitor_13:top` and `monitor_13:left`. A replacement monitor on the same side keeps that desktop's identity. Adjust `textScale` in `configs_monitor.txt` if needed.

The desktop initially has no user apps. `[+]` always offers **OS settings**, where Background, Window border and Taskbar colors can be selected and saved for all monitors. There is no branding text on the background. The optional Screensaver app is explicitly opened from Start; it is separate from the static background preference. Finish the console-based IO connection test before installing user-specific apps. Role installation never installs a switchboard or coffee timer; `inst app NAME` is an explicit opt-in. The OS loads a user app only when its name is explicitly set to `true` in `enabledApps` in `configs_os.txt`; an old auto-populated app registry does not enable it. The switchboard test fixture is `tests_fixtures_switchboard.lua` and is not installed.

The taskbar's clock reads Minecraft world time from the OS computer's built-in `os.time()`; no time sensor or extra computer is required. This is the in-game day/night clock, not real-world local time. If that API is unavailable, an online sensor's `gameTime` value remains a fallback. The original `?:??` appeared because the earlier OS waited exclusively for that unimplemented sensor source.

Every monitor has a bottom taskbar with `[+]`, local window buttons, overflow arrows and a clock when space permits. The title is at the far left on the selected window-border color, with contrasting text; controls are at the far right: `-` minimize, `#` layouts, red `X` close this view. A normal app stops after its last view closes across all monitors; Coffee is a background service and keeps running. The layout flyout first offers grid diagrams (1×1 through 3×3), then a separate position screen. Fullscreen, Restore, Resize, Move and Cancel stay on the first level. Fullscreen hides the frame/taskbar until the very top-right cell is tapped. Click title text for Move, choose a coarse position, then use one-cell arrows on the green preview. Arrows disappear at workspace boundaries. Place picks another coarse position; OK commits and Cancel discards. See [desktop controls](documentation_desktop.md).

Coffee's Pause/Resume, Harvest now and Menu controls remain available at every supported size. Menu has Settings, Stats and Maintenance without duplicate routes. Wide windows put the main controls in one row; roomy windows add a graphical timer. The main view shows player presence and harvest counts; timing configuration and wiring stay in Settings. Each app should offer UI color in its Settings; the OS supplies a reusable palette and saves one shared accent per app. Coffee uses it for its heading, timer and primary control.

Advanced monitors now draw a colored desktop, filled title bars/panels/buttons and wire-color swatches. Drawing uses CC 1.5 foreground/background colors on character cells; it needs no `blit` or pixel API. Incoming modem/touch events are buffered while peripheral drawing waits. Frame ordering prevents a delayed frame from restoring an older page; touches retain the revision of the screen seen when they arrived, so duplicate/stale taps cannot apply an action twice. Clock-only repaints do not invalidate otherwise-current taps.

If physical touches still appear offset, stop the monitor client with Ctrl+T, run `cd /`, then `clients_monitor_client.lua calibrate [side]`. Include `.lua`; with one monitor, omit the side. Bundled-v12 measures **nine circle centres** distributed across the screen, prints averages/agreement and proposes a correction for a live test. Use your usual viewing position. A nonzero correction needs at least 7/9 matching measurements on its axis; mixed readings start that axis at zero and are flagged. Test before saving: tap the white targets, use arrow buttons/keys to adjust, `0` for stock, `S` to save or `C` to cancel. More targets reduce individual-tap influence, but touch coordinates are whole character cells, so no true half-cell correction is available. Previous offsets remain saved until you choose Save.

To reset an overcorrection immediately, use `clients_monitor_client.lua calibrate right --reset` (substitute the monitor side), then reboot. To test/adjust the current offset without repeating measurement, use `clients_monitor_client.lua calibrate right --test`. Reset is also available on-screen during sampling and testing; this proposes zero and needs Save. See the [calibration guide](documentation_desktop.md). Taskbar size, position and text placement are unchanged.

The OS resolves touches from coordinates and stacking order. Clients do not invent window IDs. From the OS console you can also use:

```text
apps
open YOUR_APP monitor_13:top
resize 1 24 8
move 1 1 3
close 1
save
quit
```

Window sizes in these commands include the frame. `move` and `resize` clamp to the monitor and app limits and return fullscreen windows to framed mode. Framed layouts reserve the taskbar's last row; fullscreen uses it for the app. Layouts and free rectangles adapt to each monitor's resolution. Window layouts and app state restore after restarting; window IDs are recovered without overwriting restored windows.

## What is implemented

- Acknowledged, addressed OS/IO connections; retries, reconnects and client timeouts.
- Full desired output snapshots, acknowledgements and periodic resynchronization; late/duplicate commands are idempotent.
- Bundled/ordinary output mappings and input reporting; the central OS never accesses redstone.
- Multiple generic monitor desktops; rendering, touch routing, launcher, focus, minimize/restore/close, console positioning/resizing, and app size checks.
- Single-file apps with shared persistent data: ordinary apps run while views exist; declared background services run independently of windows.
- Checkpoints in `configs_os_state.txt` with temporary/backup recovery. Logical output changes and mappings save before hardware commands. App data and window layouts checkpoint every second while the OS runs, including with older 30-second settings; open/close, focus, minimize, move and resize changes also save immediately.
- A shared touch IO picker, per-window app view context, built-in Minecraft clock, and optional persistent coffee app with settings and legacy-state import.
- An app-free role installer and Lua 5.1 integration tests.

## Still to build from the design

Production measurement/averages and the ME overview app are not implemented. The generic OpenCCSensors bridge supports IC2 and dedicated Applied Energistics card discovery/selected raw readings; Reactors provides the first sensor app. Coffee, Switchboard and Reactors are optional and separate from the OS installer. The original coffee/switchboard programs are the root `oldfiles_*.lua` archives; the OS does not load them. Character resolution is measured from the monitor API; physical block dimensions are not guessed from that resolution.

Periodic checkpoints can lose progress since the last successful checkpoint on a crash (normally up to one second). Important app transitions call `api.save()` or save with the output intent before hardware commands. No program runs while its own computer is unloaded. Network confirmations report that the IO computer applied an output, not that an external machine physically responded. Disconnect detection still uses the configured client timeout; external-machine feedback requires a real input.

## Tests

From the repository root:

```sh
lua5.1 tests_run.lua
```

The tests include installing and booting all five roles with HTTP absent, plus exercising the optional GitHub installer. App-install tests cover GitHub downloads that yield like CC 1.5 HTTP, optional older response handles without status methods, branch/commit selection, failed/invalid responses, preservation of saved progress, and deferred execution until boot. They run the actual entry points as separate computers with independent disks and event queues, using string-only virtual modems and three-dimensional radio distance. Every simulated output write enforces a shared 0.5-second per-side cooldown, including unchanged values and cooldowns across program restarts. They cover startup order, reply-channel collisions, dropped traffic, sessions/restarts, safe-off, modem relocation, remapping, zero inputs, touch/layout restoration, interrupted checkpoints, failed saves, malformed packets, sensor isolation and background timing. Relay coverage includes the 120-block vertical gap, 16/17-relay chains, overlapping paths without repeated actions, independent client listings, alternate routes, outages/recovery, large packets and legacy direct compatibility. The root `github_workflows_lua.yml` is an optional workflow template; GitHub requires workflows in `.github/workflows/`, so run the root test/build commands locally for this flat package.

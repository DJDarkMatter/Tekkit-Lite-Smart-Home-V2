# SmartHome OS for Tekkit Lite

Repository: [DJDarkMatter/Tekkit-Lite-Smart-Home-V2](https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2). Every distributed file lives in the root; see the [complete filename map](documentation_file_map.md).

A central ComputerCraft computer owns apps, saved state and output decisions. Remote computers are reusable IO, monitor, sensor or wireless relay clients. See [the target design](documentation_design.md), [the review](documentation_review.md) and [the app/protocol reference](documentation_api.md).

This repair targets Lua 5.1 and the channel-based modem API available in ComputerCraft 1.5. It uses serialized **strings** on the wire and no CC:Tweaked-only APIs. It has been tested with simulated ComputerCraft APIs, **not inside the Minecraft server**.

## First working IO connection

Use two computers with wireless modems, initially near each other in loaded chunks in the same dimension. The OS modem can be on any side. The IO modem can also be on any side, but that side cannot be used for a cable.

### Install (one Pastebin upload)

`install.lua` is a self-contained installer containing all twenty runtime source files and **no user apps**. Upload its complete contents as **one** Pastebin paste, or replace the contents of your existing installer paste. It prints `SmartHome installer: bundled-v16`; OS/client installation makes no HTTP requests. Role files are extracted directly into the computer root with `lib_` and `clients_` filename prefixes. OS settings is built-in system UI. User apps are downloaded from GitHub only when requested; no separate app paste is needed and none are enabled by default.

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
| All roles | `lib_network.lua`, `lib_storage.lua` |
| Central OS | Also `main_os.lua`, `lib_server.lua`, `lib_console.lua`, `lib_io_picker.lua`, `lib_desktop.lua`, `lib_settings.lua`, `lib_sensor_data.lua`, `lib_sensor_server.lua`, `lib_sensor_picker.lua` |
| IO client | Also `clients_io_client.lua`, `lib_io.lua` |
| Monitor client | Also `clients_monitor_client.lua`, `lib_monitor.lua` |
| Sensor client | Also `clients_sensor_client.lua`, `lib_sensor.lua`, `lib_sensor_data.lua` |
| Relay client | Also `clients_relay_client.lua`, `lib_relay.lua` |

Both the OS and monitor roles also require `lib_gui.lua` for colour surfaces and drawing.

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

Optional apps are [Coffee](documentation_coffee.md), [Switchboard](documentation_switchboard.md), and [Reactors](documentation_reactors.md). Use `inst app coffee`, `inst app switchboard` or `inst app reactors` on the OS computer to fetch one from GitHub. Coffee starts automatically without a window and offers IO, durations and colour settings. Switchboard offers saved views, sixteen-colour side presets, custom grids/routing, touch naming and appearance settings. Reactors selects sensor targets and separate IO switches; see [sensor setup](documentation_sensors.md) and [the reactor guide](documentation_reactors.md), including card-dependent remaining-time data. All three app sources stay unchanged in bundled-v16. Update the OS and endpoint roles to use [wireless relays](documentation_relay.md); existing direct clients remain compatible. Apps, calibration and desktop geometry need no changes for relaying.

### Confirm connection and test a wire

The IO computer prints its ID, e.g. `io_11`, then `Connected to OS computer 10`. The OS prints `io connected: io_11`. Either computer may start first; retries happen every five seconds.

The startup messages show each computer's **listening** channel, so different numbers are expected. The OS listens on `45231`; an IO computer with ID `19621` listens for replies on `20621` and sends requests to `45231`. The OS's computer ID is a separate identifier, not its channel. Keep the shared `channel` setting in `configs_network.txt` the same on both computers.

For distant devices, put wireless relay computers along a path and install `inst relay --startup`. Chains have no fixed software hop-count limit. Update the OS and endpoints that will use relays to bundled-v16; apps stay installed. The OS `clients` list shows every relay and each original device separately, with a `via=relay_...` path. See [relay setup, upgrades and range](documentation_relay.md).

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

The OS owns the complete output mask of every mapped cable side: unmapped colours on that side are OFF. Do not drive the same side with a second program. Multiple logical names can reference the same physical wire and share its desired state. Toggling any copy updates them all. Adding a reference adopts an existing wire's current state; removing/rerouting a reference clears its old wire only when no references remain. A newly bound, previously unused wire starts with the requested initial intent. A logical output is independent of the IO computer's identity and physical wire address.

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

IO output writes share a per-side cooldown across bundled and ordinary redstone, respecting the public server's `[IDT-Fix]` requirement of at least 0.5 seconds between writes. `outputInterval` defaults to 0.6 seconds and must be at least 0.5. Unchanged outputs are not rewritten; rapid commands coalesce to the latest desired state. A timer applies pending writes while the client continues receiving network and input events. `confirmed` appears only after the whole latest snapshot has been applied. Startup and safe-off also use this queue, so clearing both output types on a side can take two intervals; restoration waits for clearing to finish.

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

The desktop initially has no user apps. `[+]` always offers **OS settings**, where Background, Window border and Taskbar colours can be selected and saved for all monitors. There is no branding text on the background. Graphical screensavers are a future extension; no unimplemented screensaver option is shown. Finish the console-based IO connection test before installing user-specific apps. Role installation never installs a switchboard or coffee timer; `inst app NAME` is an explicit opt-in. The OS loads a user app only when its name is explicitly set to `true` in `enabledApps` in `configs_os.txt`; an old auto-populated app registry does not enable it. The switchboard test fixture is `tests_fixtures_switchboard.lua` and is not installed.

The taskbar's clock reads Minecraft world time from the OS computer's built-in `os.time()`; no time sensor or extra computer is required. This is the in-game day/night clock, not real-world local time. If that API is unavailable, an online sensor's `gameTime` value remains a fallback. The original `?:??` appeared because the earlier OS waited exclusively for that unimplemented sensor source.

Every monitor has a bottom taskbar with `[+]`, local window buttons, overflow arrows and a clock when space permits. The title is at the far left on the selected window-border colour, with contrasting text; controls are at the far right: `-` minimize, `+` layouts, red `X` close this view. A normal app stops after its last view closes across all monitors; Coffee is a background service and keeps running. The layout flyout first offers grid diagrams (1×1 through 3×3), then a separate position screen. Restore, Resize, Move and Cancel stay on the first level. Click title text for Move, choose a coarse position, then use one-cell arrows on the green preview. Arrows disappear at workspace boundaries. Place picks another coarse position; OK commits and Cancel discards. See [desktop controls](documentation_desktop.md).

Coffee's Pause/Resume, Harvest now and Menu controls remain available at every supported size. Menu has Settings, Stats and Maintenance without duplicate routes. Wide windows put the main controls in one row; roomy windows add a graphical timer. The main view shows player presence and harvest counts; timing configuration and wiring stay in Settings. Each app should offer UI colour in its Settings; the OS supplies a reusable palette and saves one shared accent per app. Coffee uses it for its heading, timer and primary control.

Advanced monitors now draw a coloured desktop, filled title bars/panels/buttons and wire-colour swatches. Drawing uses CC 1.5 foreground/background colours on character cells; it needs no `blit` or pixel API. Incoming modem/touch events are buffered while peripheral drawing waits. Frame ordering prevents a delayed frame from restoring an older page; touches retain the revision of the screen seen when they arrived, so duplicate/stale taps cannot apply an action twice. Clock-only repaints do not invalidate otherwise-current taps.

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

Window sizes in these commands include the frame. `move` and `resize` clamp to the monitor and app limits. The taskbar reserves the last row. Layouts and free rectangles adapt to each monitor's resolution. Window layouts and app state restore after restarting; window IDs are recovered without overwriting restored windows.

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

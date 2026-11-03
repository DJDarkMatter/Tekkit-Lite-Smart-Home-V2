# Version 33 — complete update

This archive contains all project root files. Nothing has been pushed to your GitHub repository automatically.

## Install on an existing setup

1. Upload all archive root files to the V2 repository.
2. Replace the contents of your existing installer Pastebin with the new `install.lua`, and replace the central computer's `inst` with that version. Its banner must say **bundled-v33**.
3. Quit the OS on the **central computer** and run:

```text
cd /
inst server
inst app clock
inst app switchboard
inst app screensaver
```

Also reinstall any of these apps you already use, with `inst app NAME`: **me_storage**, **me_monitor**, **reactors**, **solar_farm**, **level_emitter** (shared one-letter Shift and selection context), **coffee** and **system** (English wording). Apps remain optional; install only the ones you use. Then run `reboot`.

No remote monitor, IO, sensor or relay reinstall is needed. Existing configurations, routes, app state and desktop layouts remain in place. The installer still bundles no user apps, and physical redstone writes retain their existing per-side cooldown.

## Behavior

- The 1x1 layout tile applies immediately; other grids still ask for position.
- Real stopwatch uses elapsed uptime anchors, samples Start/Stop/Lap between OS ticks and retains time through unrelated failed alarm-save attempts. Game stopwatch and laps show days and whole seconds, without subseconds. As before, OS downtime is excluded; old ComputerCraft's uptime clock can still slow under server lag, so this is not a separate UTC wall clock.
- Every touch keyboard returns to lower case after one accepted capital letter.
- Alarm popups are red with white text and a white OK strip.
- Switchboard Active, Inactive and Pending each resolve **button → view → app**. Inherit/Base removes only that local override. Button Color also offers IO default, By state, or a fixed swatch. Appearance changes preserve real routing and output state; saved old fills remain valid.
- Screensaver top-left goes backward; top-right goes forward; every other touch exits that monitor's screensaver. Modal alarms still capture input first. The exit touch does not activate a control underneath.
- Dense Matrix fills every physical character column. Fifteen designs now include Nyan Cat, Starflight, Northern lights, Lava lamp, Neon tunnel, Fireworks and Spiral ribbons. The twelve cropped Nyan animation frames credit K. Lange and retain his permission notice; see `documentation_screensaver.md` for sources. Other added patterns use new renderers. No text-scale or custom-palette changes.
- Completed IO/sensor selections and ME item sources appear above the next selection where at least 24x8 content cells fit. Small windows keep their usable list space.
- User-facing English text says **color**. Existing saved keys, protocol fields and compatibility APIs keep their original names to preserve old data and apps.

## Validation

308 native Lua 5.1 integration checks passed. Focused LuaJ 2.0.3 checks cover Clock, Switchboard, all screensavers, Solar farm, direct 1x1 selection, one-letter Shift and routing breadcrumbs. All Lua files compile and the embedded installer matches its 21 current core source files. Every design is tested at tiny through 256x128 sizes against the legacy modem packet budget. Twenty-two simulated monitor screens were rendered and visually reviewed. This has not been run inside the public Minecraft server.

## Exact changed filenames (from v32)

- `README.md`
- `apps_clock.lua`
- `apps_coffee.lua`
- `apps_level_emitter.lua`
- `apps_me_monitor.lua`
- `apps_me_storage.lua`
- `apps_reactors.lua`
- `apps_screensaver.lua`
- `apps_solar_farm.lua`
- `apps_switchboard.lua`
- `apps_system.lua`
- `documentation_api.md`
- `documentation_clock.md`
- `documentation_coffee.md`
- `documentation_design.md`
- `documentation_desktop.md`
- `documentation_file_map.md`
- `documentation_level_emitter.md`
- `documentation_me_monitor.md`
- `documentation_me_storage.md`
- `documentation_reactors.md`
- `documentation_review.md`
- `documentation_screensaver.md`
- `documentation_solar_farm.md`
- `documentation_switchboard.md`
- `documentation_system.md`
- `documentation_update_v33.md`
- `install.lua`
- `lib_desktop.lua`
- `lib_gui.lua`
- `lib_io_picker.lua`
- `lib_sensor_picker.lua`
- `lib_server.lua`
- `tests_app_helpers.lua`
- `tests_appearance.lua`
- `tests_clock.lua`
- `tests_coffee.lua`
- `tests_desktop.lua`
- `tests_run.lua`
- `tests_screensaver.lua`
- `tests_switchboard.lua`
- `tools_build_installer.py`

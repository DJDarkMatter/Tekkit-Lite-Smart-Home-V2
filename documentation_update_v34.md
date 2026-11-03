# Version 34 — independent output confirmation

The complete archive includes the v33 UI/app work and this confirmation fix. No changes have been pushed to GitHub automatically.

## Install this fix

Upload the package root to the V2 repository. Replace your existing installer Pastebin contents with this `install.lua` and replace the central computer's `inst` with that version; its banner is **bundled-v34**. Quit the OS on the **central computer**, then run:

```text
cd /
inst server
reboot
```

For **v33 → v34**, no app or remote IO/monitor/sensor/relay reinstall is needed. If updating from v32 or earlier, apply the optional app updates described in `documentation_update_v33.md` too, using this newer installer. Existing app selections, routes, saved states and monitor layouts remain intact.

## What caused the orange board

The apps read cached desired output state and confirmation; they do not query all physical switches after a toggle. The IO client already skips unchanged hardware values. The fault was the central API's confirmation calculation: every output depended on the IO computer's latest revision being acknowledged, so changing one output made that computer's entire board appear pending. Reactors used the same API.

Confirmation is now tracked per **IO client / side / bundled color or Digital**. Only changed wires lose confirmation; unchanged colors on the same cable, Digital, and other sides retain theirs. Buttons in other views/monitors that share the exact changed wire correctly show pending together. Rapid ON/OFF reversals stay pending until the newest applicable snapshot is acknowledged, even when the desired value matches its earlier value. Failed saves cannot advance confirmation metadata or actuate new output intent.

Complete desired-state snapshots remain for retry/reconnect recovery. They contain the OS's intended masks and do not request sensor polling or rewrite every physical output. A real IO restart/reconnect/capability change still invalidates all its outputs and requires a fresh revision acknowledgement. The existing shared per-side redstone cooldown is unchanged.

## Verification

312 native Lua 5.1 integration checks pass. Focused LuaJ 2.0.3 checks cover all Switchboard cases, the independent Reactor controls, and packet-loss/reconnect recovery. Regression cases include all sixteen rendered button fills, shared aliases, bundled/Digital outputs on one side, other sides, failed saves, rapid reversals, lost/stale acknowledgements, and real client restart. The Reactors check confirms a toggle does not re-query its sensor targets. The installer matches its twenty-one core source files. In-game verification remains necessary for this public server.

## Exact combined changed filenames — v33 and v34 (since v32)

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
- `documentation_update_v34.md`
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
- `tests_sensors.lua`
- `tests_switchboard.lua`
- `tools_build_installer.py`

## Files changed in v34 alone

- `README.md`
- `documentation_api.md`
- `documentation_file_map.md`
- `documentation_reactors.md`
- `documentation_review.md`
- `documentation_switchboard.md`
- `documentation_update_v34.md`
- `install.lua`
- `lib_server.lua`
- `tests_run.lua`
- `tests_sensors.lua`
- `tests_switchboard.lua`
- `tools_build_installer.py`

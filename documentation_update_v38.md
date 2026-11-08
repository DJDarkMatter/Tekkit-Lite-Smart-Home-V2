# Version 38

ME monitors displays the signed net change over five minutes and an hourly rate. Open a tile to see both figures. **Edit → Change rates** saves the on/off preference for that view. Rates use complete sensor readings and start from a fresh baseline after a power loss, stale data or a sensor restart.

In **OS settings → Reset data**, the first two rows are Entire OS and OS settings. Apps follow in alphabetical order, including installed apps and saved data left by removed apps.

| Scope | What it clears |
| --- | --- |
| Entire OS | Every app's saved data and routes, all window layouts, and OS appearance preferences |
| OS settings | OS appearance preferences, desktop layouts and routes owned by the OS |
| An app | Its saved settings, windows, color preference, alerts and owned routes |

Entire OS requires **Continue**, then **Erase all** on a second screen. Each other scope asks once. The two desktop scopes close the windows whose layouts they clear. App resets reload the selected app so its private runtime starts fresh. A shared wire keeps the state requested by its surviving route. Released wires receive an OFF snapshot when their IO client is available.

The reset scope is the central OS's managed state file and its recovery copies. Program files, installation choices and network configuration are separate. Legacy custom routes with no known app owner appear under OS settings. A failed checkpoint leaves the original state available and the reset confirmation can be retried.

## Install from v37

Upload all root files from the ZIP to the V2 repository. Replace your installer paste with `install.lua` from this release and download a fresh `inst` showing **bundled-v38**. On the central computer, quit to CraftOS and run:

```text
cd /
inst server
inst app me_monitor
reboot
```

These are the central OS and ME Monitor updates. The bundled installer includes all 22 core sources. This release requires no remote-client reinstalls.

## Checks

343 Lua 5.1 integration checks and 59 focused LuaJ 2.0.3 checks cover rate display, saved toggles, sensor power loss, slow polls, reset ordering, both confirmations, legacy route ownership, shared wires, offline IO recovery and failed checkpoint replacement. The generated installer matches its source files.

## Exact changed files

- `README.md`
- `apps_me_monitor.lua`
- `documentation_api.md`
- `documentation_me_monitor.md`
- `documentation_update_v38.md`
- `install.lua`
- `lib_me.lua`
- `lib_sensor_server.lua`
- `lib_server.lua`
- `lib_settings.lua`
- `lib_storage.lua`
- `main_os.lua`
- `tests_appearance.lua`
- `tests_me_monitor.lua`
- `tests_run.lua`
- `tests_work.lua`
- `tools_build_installer.py`

# Version 35 — cooperative OS work and saved errors

This full release includes v33, v34 and v35. The error reported by the user was approximate and no traceback was captured. It may have been ComputerCraft's "Too long without yielding" watchdog, but that is not confirmed. V33/v34 did not specifically address that kind of timeout. V35 hardens plausible heavy-work paths and improves diagnosis; it does not establish the exact cause of the earlier incident.

## Exact reinstall checklist for v33, v34 and v35

All changes below run on the **central OS computer**. Update only apps you already use. No optional app is bundled or installed by default.

| Version | Central OS | Apps to reinstall | Remote clients to reinstall |
| --- | --- | --- | --- |
| v33 | `inst server` with its new installer | `clock`, `switchboard`, `screensaver`, `me_storage`, `me_monitor`, `reactors`, `solar_farm`, `level_emitter`; also `coffee` and `system` for wording updates | None: IO, monitor, sensor and relay programs remain compatible |
| v34 | `inst server` with its new installer | None beyond the v33 app updates | None |
| v35 | `inst server` with bundled-v35 | `solar_farm` if installed | None |

### Jump directly from v32 to v35

Do not install each intermediate version. Upload all files from this ZIP to the V2 GitHub repository. Replace the contents of your existing installer Pastebin with this release's **install.lua**, then replace the central computer's **inst** with that version. Verify its banner says **bundled-v35**. Quit the OS on the central computer, then run:

```text
cd /
inst server
```

Run the following **only for apps you currently use**, then reboot once. If you use all ten, this is the complete list:

```text
inst app clock
inst app coffee
inst app level_emitter
inst app me_monitor
inst app me_storage
inst app reactors
inst app screensaver
inst app solar_farm
inst app switchboard
inst app system
reboot
```

If already on v33 or v34 with their app updates installed, v35 only needs:

```text
cd /
inst server
inst app solar_farm
reboot
```

Omit `inst app solar_farm` if you do not use it. Existing client IDs, network settings, app selections, routing, counters/learned rates and window layouts remain in place. Keep your existing startup script; no remote computer needs reinstalling. Fresh role installs include the new helper automatically. The installer embeds **22 core files and no apps**.

## What v35 changes

- The central OS buffers incoming modem/peripheral events and complete console commands while one worker performs state changes. Commands cannot interrupt a partially saved transaction. Monitor taps and IO messages are retained during cooperative work pauses.
- Large GUI drawing/packing, shared ME copies/catalog parsing, state copying and plain-data serialization give control back in bounded batches. Background app callbacks and monitor frames have boundaries too. Yield-safe protected calls preserve legacy Lua 5.1/LuaJ behavior and Solar source isolation.
- Routine IO/sensor/relay announcements no longer trigger full desktop redraws. A monitor announcement resynchronizes only that monitor; normal periodic/touch/animation refresh continues.
- The storage writer avoids reparsing the same validated old state on every checkpoint, while still detecting external corruption before rotating a backup. Checkpoint-before-output ordering and the existing redstone cooldown remain unchanged.
- Catchable errors save their message and last operation to **diagnostics_os_error.txt**. Yielding-timeout errors are recorded even when an inner protected call handles them. The OS does not enter an automatic reboot loop. A forced shutdown, native abort or unavailable filesystem can prevent a report; this is best-effort capture.

## Reading the next error

If the OS is running, type this into its console:

```text
errorlog
```

After an error/reboot, startup announces that a report exists. If the OS cannot stay running, use CraftOS:

```text
edit diagnostics_os_error.txt
```

The report is the latest captured error, not proof of a new crash on every boot. Keep its exact text and stage for diagnosis. Ordinary Ctrl+T is not recorded as a crash.

## Verification

**325 native Lua 5.1 integration checks pass**, with **117 distinct focused LuaJ 2.0.3 checks** across cooperative work/event buffering, Solar, Switchboard and Clock. All Lua files compile and the installer matches its 22 embedded core sources. Stress cases cover a 1,500-item live ME catalog, every screensaver at 256x128 through the real central worker and modem-size limit, IO/touches/console input during paused work, large checkpoints, corrupted/failed saves, nested coroutine forwarding and persistent error reports. These simulations do not reproduce the public server's actual watchdog timing or guarantee that every possible native operation/third-party app loop can be preempted.

## Exact files changed in v35

- `README.md`
- `apps_solar_farm.lua`
- `documentation_api.md`
- `documentation_file_map.md`
- `documentation_review.md`
- `documentation_solar_farm.md`
- `documentation_update_v35.md`
- `install.lua`
- `lib_gui.lua`
- `lib_me.lua`
- `lib_network.lua`
- `lib_server.lua`
- `lib_storage.lua`
- `lib_work.lua`
- `main_os.lua`
- `tests_console.lua`
- `tests_run.lua`
- `tests_work.lua`
- `tools_build_installer.py`

## Combined changed filenames across v33, v34 and v35 (since v32)

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
- `documentation_update_v35.md`
- `install.lua`
- `lib_desktop.lua`
- `lib_gui.lua`
- `lib_io_picker.lua`
- `lib_me.lua`
- `lib_network.lua`
- `lib_sensor_picker.lua`
- `lib_server.lua`
- `lib_storage.lua`
- `lib_work.lua`
- `main_os.lua`
- `tests_app_helpers.lua`
- `tests_appearance.lua`
- `tests_clock.lua`
- `tests_coffee.lua`
- `tests_console.lua`
- `tests_desktop.lua`
- `tests_run.lua`
- `tests_screensaver.lua`
- `tests_sensors.lua`
- `tests_switchboard.lua`
- `tests_work.lua`
- `tools_build_installer.py`

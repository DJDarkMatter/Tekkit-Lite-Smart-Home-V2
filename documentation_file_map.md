# Flat-root filename map

Repository: https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2

All distributed files have unique filenames and live in the repository root. Runtime-created configuration, state, app and startup files also live in the computer root.

The [menu tree PDF](documentation_menu_tree.pdf), [editable menu source](documentation_menu_tree.md), and `tools_build_menu_tree.py` also live in the root. Full releases include all three. The PDF contains the menu hub, a complete overview, and linked detail pages. System overview is a Settings submenu.

See [v46 files and deletions](documentation_update_v46.md) for the compact Solar Farm, shared keypads and Level Emitter retirement.

| Previous path | New root filename |
| --- | --- |
| `main_os.lua` | `main_os.lua` |
| `Lib/server.lua` | `lib_server.lua` |
| `Lib/network.lua` | `lib_network.lua` |
| `Lib/storage.lua` | `lib_storage.lua` |
| `Lib/io.lua` | `lib_io.lua` |
| `Lib/monitor.lua` | `lib_monitor.lua` |
| `Lib/io_picker.lua` | `lib_io_picker.lua` |
| `Clients/io_client.lua` | `clients_io_client.lua` |
| `Clients/monitor_client.lua` | `clients_monitor_client.lua` |
| `Apps/coffee.lua` | `apps_coffee.lua` |
| `install.lua` | `install.lua` |
| `tools/build_installer.py` | `tools_build_installer.py` |
| `tools/install-github.lua` | `tools_install_github.lua` |
| `tests/run.lua` | `tests_run.lua` |
| `tests/coffee.lua` | `tests_coffee.lua` |
| `tests/fixtures/switchboard.lua` | `tests_fixtures_switchboard.lua` |
| `DOCUMENTATION/API.md` | `documentation_api.md` |
| `DOCUMENTATION/COFFEE.md` | `documentation_coffee.md` |
| `DOCUMENTATION/DESIGN.md` | `documentation_design.md` |
| `DOCUMENTATION/REVIEW.md` | `documentation_review.md` |
| `OLDFILES/CofeeTimer/timer.lua` | `oldfiles_coffee_timer.lua` |
| `OLDFILES/SwitchBoard/buttons.lua` | `oldfiles_switchboard_buttons.lua` |
| `OLDFILES/SwitchBoard/screensaver.lua` | `oldfiles_switchboard_screensaver.lua` |
| `.github/workflows/lua.yml` | `github_workflows_lua.yml` |

`README.md` and the repository ignore file keep their standard root names. This map is new as `documentation_file_map.md`.

## In-game configuration and saved data

| Previous path | New root filename |
| --- | --- |
| `Configs/network.txt` | `configs_network.txt` |
| `Configs/io.txt` | `configs_io.txt` |
| `Configs/monitor.txt` | `configs_monitor.txt` |
| `Configs/os_state.txt` | `configs_os_state.txt` |
| `Configs/os.txt` | `configs_os.txt` |

The bundled installer migrates existing settings, state and explicitly enabled apps. Existing data is never replaced by defaults. Legacy source files are retained as recovery copies; active programs use only the new root paths.

User apps are named `apps_NAME.lua`, keeping app files distinct from core, test and archived scripts. The application name in saved state and settings stays `NAME`, so coffee stays `coffee`.

`github_workflows_lua.yml` is an optional workflow template at the root. GitHub only activates workflows under its reserved `.github/workflows/` location; this strictly flat package does not enable it automatically. Run the root test/build commands locally instead.

## Window-manager update (bundled-v5)

New flat files: `lib_desktop.lua`, `tests_desktop.lua`, and `documentation_desktop.md`. Updated runtime: `lib_server.lua`, `lib_monitor.lua`, `apps_coffee.lua`, and generated `install.lua`; builder: `tools_build_installer.py`; existing tests: `tests_run.lua` and `tests_coffee.lua`; guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. No folder names or runtime data filenames change in this update.

## GitHub app installer update (bundled-v6)

`inst app NAME` now downloads `apps_NAME.lua` from the V2 repository's `main` branch; `--ref` selects a branch or commit. Only the installer needs a Pastebin upload. No new files: changed files are `tools_build_installer.py`, generated `install.lua`, `tests_run.lua`, `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, and this map. The runtime/app sources and saved data formats are unchanged from bundled-v5.

## GitHub download compatibility update (bundled-v7)

The installer now tries GitHub's contents API after a failed raw download and reports both failure reasons. No new files: changed files are `tools_build_installer.py`, generated `install.lua`, `tests_run.lua`, `README.md`, `documentation_api.md`, `documentation_coffee.md`, and this map. Runtime/app sources and saved formats are unchanged. Updating the installer paste is sufficient for this app-download change.

## Color GUI and input update (bundled-v8)

New file: `lib_gui.lua`, installed on OS and monitor roles. Updated source/build: `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `lib_desktop.lua`, `lib_io_picker.lua`, `apps_coffee.lua`, `tools_build_installer.py`, and generated `install.lua`. Updated tests: `tests_run.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. All files remain in the root. Reinstall both OS and monitor roles; update the Coffee source on GitHub before running `inst app coffee`. App/window state is preserved, and measured touch offsets use the existing `configs_monitor.txt`.

## Appearance, snap cards and app navigation (bundled-v9)

New files: `lib_settings.lua` (built-in OS settings) and `tests_appearance.lua`. Updated source/build: `lib_server.lua`, `lib_gui.lua`, `lib_desktop.lua`, `lib_io_picker.lua`, `apps_coffee.lua`, `tools_build_installer.py`, and generated `install.lua`. Updated existing tests: `tests_run.lua`, `tests_coffee.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. Update the server role and Coffee; existing bundled-v8 monitor and IO programs remain compatible. No directories or new configuration files are introduced; appearance is in `configs_os_state.txt`.

## Grid submenus and Coffee presentation (bundled-v10)

No new files. Updated source/build: `apps_coffee.lua`, `lib_desktop.lua`, `lib_server.lua`, `lib_gui.lua`, `tools_build_installer.py`, `install.lua`. Updated tests: `tests_run.lua`, `tests_coffee.lua`, `tests_desktop.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. The clock retains its original size/scaling with its colors swapped; Coffee has a cleaner main view. Layouts use a grid screen followed by a position screen, including 3×3; Resize/Move remain at the first level. App downloads now try the confirmed working GitHub API first. Update the server role and Coffee; existing bundled-v8 monitor and IO programs remain compatible. Saved timer/settings data is preserved.

## Console and calibration repairs (bundled-v11)

New files: `lib_console.lua`, `tests_console.lua`. Updated source/build: `main_os.lua`, `lib_network.lua`, `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `tools_build_installer.py`, `install.lua`. Updated existing tests: `tests_run.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_review.md`, and this map. The installer contains thirteen core sources and no apps. Update the server role for the bottom-row console/clear command and the monitor role for tolerant calibration with Retry/Cancel. Use the full filename `clients_monitor_client.lua calibrate [side]`. Coffee, desktop geometry, saved data formats and the IO client are unchanged.

## Global colors and calibration testing (bundled-v12)

No new files. Updated source/build: `lib_settings.lua`, `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `tools_build_installer.py`, `install.lua`. Updated tests: `tests_run.lua`, `tests_desktop.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_desktop.md`, `documentation_review.md`, and this map. OS settings adds global Window border and Taskbar palettes. Monitor calibration uses nine circles, agreement reporting, a live test, manual nudges and stock reset (`--reset` or the on-screen Reset followed by Save). Update the server and monitor roles; Coffee, IO, window resizing, taskbar dimensions/coordinates and file layout are unchanged.

## Switchboard (bundled-v13)

New files: `apps_switchboard.lua`, `tests_switchboard.lua`, `documentation_switchboard.md`. Updated source/build: `lib_server.lua`, `tools_build_installer.py`, `install.lua`. Updated existing tests: `tests_run.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. All files remain flat at the root. Update only the central server role, then install `switchboard` using the same installer. The app is optional, fetched from GitHub and never embedded or enabled by a core install. No new configuration files are introduced. Coffee, monitor/IO clients, calibration, window/taskbar geometry and the shared IO cooldown are unchanged. Original switchboard archives and the test fixture remain unchanged.

## Shared Switchboard routes, steady ACK status and palette previews (bundled-v14)

No new files. Updated runtime/build: `lib_server.lua`, `apps_switchboard.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_run.lua`, `tests_switchboard.lua`, `tests_coffee.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_switchboard.md`, `documentation_review.md`, and this map. Update the central server role and Switchboard; clients need no update. Duplicate routes now share a physical state, ordinary announcements preserve earned confirmation, and every Switchboard color picker has draft previews on larger windows plus Apply/Cancel. Active/inactive status colors are configurable. Existing state migrates without resetting views or outputs; no new data files or folders. Coffee runtime, calibration, client code, IO cooldown and window/taskbar geometry are unchanged.

## Generic sensor client and Reactors (bundled-v15)

New runtime/app files: `clients_sensor_client.lua`, `lib_sensor.lua`, `lib_sensor_data.lua`, `lib_sensor_server.lua`, `lib_sensor_picker.lua`, `apps_reactors.lua`. New test: `tests_sensors.lua`. New guides: `documentation_sensors.md`, `documentation_reactors.md`. Changed runtime/build: `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`, optional `tools_install_github.lua`. Changed existing test: `tests_run.lua`. Changed existing guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_switchboard.md`, `documentation_design.md`, `documentation_review.md`, and this map. The installer now contains eighteen core sources, adds the offline `sensor` role, and still includes no apps. Install Reactors explicitly using `inst app reactors`. Runtime sensor settings use `configs_sensor.txt`; reactor bindings/configuration use existing `configs_os_state.txt`. Update the central OS and install the sensor role on sensor computers; existing IO/monitor clients, Coffee, Switchboard, calibration, desktop geometry and IO cooldown are unchanged. All files remain unique root filenames.

## Chained wireless relays (bundled-v16)

New runtime files: `clients_relay_client.lua`, `lib_relay.lua`. New test: `tests_relay.lua`. New guide: `documentation_relay.md`. Updated runtime/build: `lib_network.lua`, `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`, optional `tools_install_github.lua`. Updated existing test: `tests_run.lua`. Updated existing guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_switchboard.md`, `documentation_sensors.md`, `documentation_reactors.md`, `documentation_design.md`, `documentation_review.md`, and this map. All files remain flat. The installer has twenty core sources and no apps. Update the OS and each endpoint that will use relays, then install `inst relay --startup` on any number of relay computers. New runtime settings are `configs_relay.txt` and the automatically maintained per-computer `configs_transport.txt`; other IDs, settings and app data are retained. There is no fixed software hop-count cutoff. Apps, calibration, desktop geometry and IO cooldown code are unchanged. Direct older clients remain compatible.

## Sensor names, sides and catalog diagnostics (bundled-v17)

No new files. Updated runtime/build: `lib_sensor_data.lua`, `lib_sensor_server.lua`, `lib_sensor_picker.lua`, `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_run.lua`, `tests_sensors.lua`, `tests_relay.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_switchboard.md`, `documentation_sensors.md`, `documentation_reactors.md`, `documentation_relay.md`, `documentation_review.md`, and this map. Empty names no longer invalidate a whole side; native raw identities remain available for localized reactor selection. Picker/console diagnostics distinguish waiting, rejected and incomplete catalogs. Update the OS and sensor roles, with no app downloads. Relays, network transport, IO, calibration, desktop geometry and saved data filenames remain unchanged. All fifty-one distributed files stay in the root; the installer still contains twenty core sources and no apps.

## Reactor details, time aliases and ON/OFF controls (bundled-v18)

No new files. Updated app/runtime/build: `apps_reactors.lua`, `lib_sensor_data.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_run.lua`, `tests_sensors.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_switchboard.md`, `documentation_sensors.md`, `documentation_reactors.md`, `documentation_relay.md`, `documentation_desktop.md`, `documentation_review.md`, and this map. Update the central server role and explicitly download the Reactors app after uploading it to GitHub. Sensor/relay/IO/monitor programs, calibration, global text scale and desktop geometry are unchanged. Extra detail fields and nested raw-data pages require no chamber subscriptions or new saved-state files. The stock IC2 card still supplies no fuel lifetime; additional aliases only interpret time that another adapter actually reports. All fifty-one root files are included in the full package; twenty core sources and no apps are embedded in the installer.

## Sensor cleanup crash (bundled-v19)

No new files. Updated runtime/build: `lib_sensor_server.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_run.lua`, `tests_sensors.lua`. Updated guides: `README.md`, `documentation_coffee.md`, `documentation_switchboard.md`, `documentation_sensors.md`, `documentation_reactors.md`, `documentation_relay.md`, `documentation_review.md`, and this map. Sensor cleanup uses key snapshots to avoid `invalid key to 'next'` when closing Reactors or expiring runtime data. Update only the central server role; no app downloads or client updates are needed. All fifty-one root files are included in the full package, and the installer still embeds twenty core sources without apps. Saved settings and output intent are retained.

## Switchboard button appearance (v20 app update)

No new files. Updated app: `apps_switchboard.lua`. Updated test: `tests_switchboard.lua`. Updated guides: `README.md`, `documentation_switchboard.md`, `documentation_review.md`, and this map. Per-switch appearance palettes add an optional saved `displayColour` without changing the real route or wire state. Missing overrides preserve automatic wire-color behavior. Update only Switchboard using the existing installer; `install.lua`, its builder, all core/client programs and other apps are byte-identical to v19. The full v20 package retains all fifty-one flat root files and the bundled-v19 installer.


## ME storage, window navigation and Coffee spacing (bundled-v21)

New app/test/guide: `apps_me_storage.lua`, `tests_me_storage.lua`, `documentation_me_storage.md`. Updated app/runtime/build: `apps_coffee.lua`, `lib_server.lua`, `lib_sensor.lua`, `lib_sensor_data.lua`, `lib_sensor_server.lua`, `tools_build_installer.py`, generated `install.lua`. Updated existing tests: `tests_run.lua`, `tests_coffee.lua`, `tests_desktop.lua`, `tests_switchboard.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_desktop.md`, `documentation_reactors.md`, `documentation_relay.md`, `documentation_review.md`, `documentation_sensors.md`, `documentation_switchboard.md`, and this map. All fifty-four files remain flat at the root; the installer embeds the same twenty core sources and no apps.

Install the fresh v21 server role on the central OS, update sensor roles serving ME, and explicitly download `coffee` and `me_storage`. Relays, IO/monitor clients and Switchboard/Reactors app sources do not change. Saved window geometry is retained and per-window navigation is now checkpointed in each window's viewState. Coffee gains digit gutters/compact spacing. The first independent ME app reads native network counts and optional drive inventories; later stock/SMF/solar apps are a documented plan, not downloaded or implemented here. No new runtime configuration/state filenames are introduced.


## ME item monitors and display corrections (bundled-v22)

New files: `apps_me_monitor.lua`, `tests_me_monitor.lua`, `documentation_me_monitor.md`. Updated app/runtime/build: `apps_coffee.lua`, `apps_me_storage.lua`, `lib_sensor.lua`, `lib_sensor_data.lua`, `lib_sensor_server.lua`, `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`. Updated existing tests: `tests_run.lua`, `tests_coffee.lua`, `tests_me_storage.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_desktop.md`, `documentation_me_storage.md`, `documentation_reactors.md`, `documentation_relay.md`, `documentation_review.md`, `documentation_sensors.md`, `documentation_switchboard.md`, and this map. All fifty-seven distributed files remain in the root. The installer embeds twenty core sources and no apps.

Update the central OS and affected ME sensor roles using a fresh bundled-v22 installer; explicitly install `coffee`, `me_storage` and `me_monitor`. Relays, IO/monitor clients, Switchboard and Reactors app sources are unchanged. The item-monitor app has independent saved views, grids, source bindings and item identities, sharing physical reads through a bounded compact item profile. Coffee restores compact player presence and matches clock-edge clearance to the chosen background. Capacity counters/percentages use plain decimal formatting and the dashboard omits Cells surveyed. Existing runtime state filenames and the saved window-navigation mechanism are unchanged.

## ME usage label and drive-survey explanation (v23 app update)

No new files. Updated app: `apps_me_storage.lua`. Updated guides: `README.md`, `documentation_me_storage.md`, `documentation_review.md`, and this map. The percentage heading says Usage instead of Live when data is available; error/offline states are retained. The guide explains optional Inventory Card drive surveys and their cell-count versus per-cell-fill limits. Update only the ME capacity app. All fifty-seven root files remain in the complete package, and the installer remains bundled-v22 without changes.

## ME layouts, Clock and CC system (bundled-v24)

New app/test/guide files: `apps_clock.lua`, `tests_clock.lua`, `documentation_clock.md`, `apps_system.lua`, `tests_system.lua`, `documentation_system.md`.

Updated runtime/build: `apps_me_monitor.lua`, `apps_me_storage.lua`, `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`.

Updated existing tests: `tests_run.lua`, `tests_desktop.lua`, `tests_me_monitor.lua`, `tests_me_storage.lua`.

Updated existing guides: `README.md`, `documentation_api.md`, `documentation_desktop.md`, `documentation_me_monitor.md`, `documentation_me_storage.md`, `documentation_review.md`, and this map.

All sixty-three root files are included in the complete package. The installer retains twenty core sources and no apps. Update only the central server role and explicitly install `me_storage`, `me_monitor`, `system` and `clock`. No client, Coffee, Switchboard or Reactors files change. Existing configs and state filenames remain unchanged; the optional new apps add independent appStates entries. ME selections, colors, clocks, routes and per-window navigation are checkpointed centrally; live telemetry remains runtime-only.

## Clock popups and indefinite signals (bundled-v25)

No new files. Updated runtime/build: `apps_clock.lua`, `lib_server.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_clock.lua`, `tests_run.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_clock.md`, `documentation_desktop.md`, `documentation_review.md`, and this map.

The complete archive still includes all sixty-three flat root files. The installer retains twenty core sources and no apps. Update only the central server role and explicitly install `clock`. All client programs and other app sources are unchanged. Clock's schema migrates v24 Pulse to Constant and adds persisted per-occurrence alerts plus selectable dismiss inputs. Runtime popup mirrors require no new state/config file. Existing durations, routes, stopwatch/laps, app/window settings and the IO cooldown are retained.

## SMF inspection, Reactor metrics and revised production plan (bundled-v26)

No new distributed files. Updated runtime/build: clients_sensor_client.lua, lib_sensor.lua, apps_reactors.lua, tools_build_installer.py, generated install.lua. Updated tests: tests_sensors.lua, tests_run.lua. Updated guides: README.md, documentation_api.md, documentation_design.md, documentation_me_storage.md, documentation_sensors.md, documentation_reactors.md, documentation_review.md, and this map.

The archive still includes all sixty-three unique root files; twenty core sources and no apps are embedded in the installer. Update the sensor role being inspected, and explicitly install reactors on the central OS for the display correction. Other client roles, the central OS core and other app sources are unchanged. The standalone command creates diagnostics_sensor.txt locally, plus its existing storage writer's temporary/backup files, and does not alter saved settings/startup/IDs or operate machine outputs. The Production overview is documented as one future app; it is not included as a new runtime app in this version.

## Corner nudges and fullscreen (bundled-v27)

No new distributed files. Updated runtime/build: `lib_desktop.lua`, `lib_server.lua`, `apps_coffee.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_desktop.lua`, `tests_appearance.lua`, `tests_run.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map.

The full archive retains sixty-three unique root files and twenty embedded core sources without apps. Update the central server role and explicitly install Coffee for its compact counters/shorter graphical clock layouts. Client programs are compatible without reinstallation. The sensor role retains the v26 inspection command for the upcoming SMF report. Fullscreen adds a saved flag inside existing window records, keeping the framed layout/restore targets and view navigation. The frame/taskbar stay hidden until a top-right exit tap; notifications remain modal. Each custom corner is picked, nudged and confirmed separately, with the second confirmation committing the window.

## Legacy sensor report saving (bundled-v28)

No new distributed files. Updated runtime/build: `lib_sensor.lua`, `tools_build_installer.py`, generated `install.lua`. Updated tests: `tests_sensors.lua`, `tests_run.lua`. Updated guides: `README.md`, `documentation_sensors.md`, `documentation_review.md`, and this map.

The full archive retains all sixty-three flat root files and the installer contains twenty core sources without apps. Reinstall only the inspected sensor role using a fresh v28 installer. Each report sample now owns independent target metadata, including nested position fields, so legacy CraftOS can serialize the complete report. The test harness now rejects every repeated table reference, matching old serialization behavior across all roles. Existing fullscreen, app sources, saved settings/startup and report timing/bounds remain intact.

## Solar farm overview (v29 app release)

New files: `apps_solar_farm.lua`, `tests_solar_farm.lua`, `documentation_solar_farm.md`. Updated tests: `tests_run.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_design.md`, `documentation_me_storage.md`, `documentation_review.md`, and this map.

The complete archive now has 66 unique root files. `install.lua` and its twenty embedded core sources remain unchanged at bundled-v28; the existing installer downloads the explicitly requested `solar_farm` app from GitHub. Update no OS/client roles for this release. The optional app uses a separate `appStates.solar_farm` record inside the existing central checkpoint for its selected main/farm sources, pins, identities, filter settings, history and alarms. Current ME inventories/baselines stay runtime-only. It replaces the planned SMF production app with farm inventory and filtered main-ME net stock-rate estimates; machinery control stays external.

## Solar overview, Level emitter and Screensaver (v30)

The complete release contains **74 unique root files**. The single `install.lua` is now **bundled-v30**, with 21 embedded core sources and **no apps**. Update only the central server role, then explicitly download the three apps before reboot. Existing monitor, IO, sensor and relay roles need no update for this release. See [Solar farm update commands](documentation_solar_farm.md).

New files:

- `apps_level_emitter.lua`
- `apps_screensaver.lua`
- `lib_me.lua`
- `tests_app_helpers.lua`
- `tests_level_emitter.lua`
- `tests_screensaver.lua`
- `documentation_level_emitter.md`
- `documentation_screensaver.md`

Changed files:

- `apps_solar_farm.lua`
- `lib_server.lua`
- `lib_desktop.lua`
- `lib_gui.lua`
- `main_os.lua`
- `install.lua`
- `tools_build_installer.py`
- `tests_run.lua`
- `tests_solar_farm.lua`
- `README.md`
- `documentation_api.md`
- `documentation_design.md`
- `documentation_desktop.md`
- `documentation_me_storage.md`
- `documentation_solar_farm.md`
- `documentation_review.md`
- `documentation_file_map.md`

Solar farm state is now schema 2. Level emitter owns `appStates.level_emitter`, including imported Solar alarms, exact ME/item/IO bindings and pending signals. It preserves legacy logical output names during the atomic migration. Solar farm keeps selected sources, farm pins, per-pin Stick preferences, HV pin/Stick preference, withdrawal settings and sparse history. Screensaver keeps only its next-design rotation in `appStates.screensaver`; its windows never restore automatically. Normal app windows and other app namespaces remain in the existing central checkpoint.

## Solar farm legacy compatibility and dashboard (v31)

The complete release has **75 unique root files**. The installer is **bundled-v31** with 21 core sources and no user apps. Update the central server role and `solar_farm`; existing clients and other apps need no reinstall from v30.

New: `tests_me.lua`.

Changed: `apps_solar_farm.lua`, `lib_me.lua`, `install.lua`, `tools_build_installer.py`, `tests_run.lua`, `tests_solar_farm.lua`, `README.md`, `documentation_api.md`, `documentation_design.md`, `documentation_solar_farm.md`, `documentation_review.md`, `documentation_file_map.md`.

`lib_me.lua` removes the LuaJ frontier-pattern crash and contains reader/parser failures. Solar farm retains schema 2 with an optional auto/manual HV-selection flag, existing sources and pin/Stick state. The overview gains source-health indicators, adaptive stock/capacity/movement summaries, selected-window changes and a signed HV history plot. The full farm list is independent of picker searches; farm HV and main output retain separate origins. No IO/client protocol or hardware behavior changes.

## Solar farm learned rates, sorting and curve (v32 app-only release)

The full archive retains **75 unique root files**. `install.lua` and all 21 embedded core sources are unchanged at **bundled-v31**. Upload the full release and run `inst app solar_farm` on an existing v31 central OS, then reboot; no new installer paste or role/client reinstall is needed.

Changed files: `apps_solar_farm.lua`, `tests_solar_farm.lua`, `README.md`, `documentation_solar_farm.md`, `documentation_design.md`, `documentation_api.md`, `documentation_review.md`, `documentation_file_map.md`.

Solar's saved schema-2 namespace gains bounded cumulative ledgers and a fine HV curve, while each window saves its sorting preference. Source bindings, HV identity, pins, Stick flags, colors and compatible recent history remain intact. The overview starts with Live indicators, headers sort/reverse, and the three-row graph uses six glyph-height steps. No new files or other app/core changes are introduced.


`documentation_update_v33.md` records the v33 installation steps, behavior changes and exact changed filenames. The complete v33 archive includes every root file, not just updates.

`documentation_update_v34.md` explains the per-wire confirmation fix and lists the exact combined changes across v33 and v34 (since v32).


V35 adds `lib_work.lua` (bounded cooperative work and protected calls), `tests_work.lua` (runtime/queue/checkpoint stress checks), and `documentation_update_v35.md` (v33/v34/v35 reinstall checklist and exact filenames). Runtime errors may create `diagnostics_os_error.txt` and its temporary write file in the computer root.


`documentation_update_v36.md` records the startup recovery, exact v36 changed files and cumulative v33–v36 reinstall checklist. V36 changes the central `main_os.lua` and its bundled installer; existing app and remote-client program files are unchanged.


`documentation_update_v37.md` records the Screensaver-only update, including 2×2 navigation, reference Matrix motion/trails and exact changed filenames. V37 retains every v36 core/installer/client source unchanged; the full package's installer still says bundled-v36.


## Version 39

`apps_system.lua` became `lib_system.lua`, a built-in Settings page. `lib_alert_inbox.lua` and `lib_io_history.lua` are also central OS files. The optional apps `apps_io_scope.lua`, `apps_logic_sandbox.lua`, `apps_notes.lua` and `apps_window_presets.lua` stay at the root. See [version 39](documentation_update_v39.md) for install commands and the exact file list.

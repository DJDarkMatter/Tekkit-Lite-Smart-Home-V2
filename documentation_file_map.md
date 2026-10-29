# Flat-root filename map

Repository: https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2

All distributed files have unique filenames and live in the repository root. Runtime-created configuration, state, app and startup files also live in the computer root.

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

## Colour GUI and input update (bundled-v8)

New file: `lib_gui.lua`, installed on OS and monitor roles. Updated source/build: `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `lib_desktop.lua`, `lib_io_picker.lua`, `apps_coffee.lua`, `tools_build_installer.py`, and generated `install.lua`. Updated tests: `tests_run.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. All files remain in the root. Reinstall both OS and monitor roles; update the Coffee source on GitHub before running `inst app coffee`. App/window state is preserved, and measured touch offsets use the existing `configs_monitor.txt`.

## Appearance, snap cards and app navigation (bundled-v9)

New files: `lib_settings.lua` (built-in OS settings) and `tests_appearance.lua`. Updated source/build: `lib_server.lua`, `lib_gui.lua`, `lib_desktop.lua`, `lib_io_picker.lua`, `apps_coffee.lua`, `tools_build_installer.py`, and generated `install.lua`. Updated existing tests: `tests_run.lua`, `tests_coffee.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. Update the server role and Coffee; existing bundled-v8 monitor and IO programs remain compatible. No directories or new configuration files are introduced; appearance is in `configs_os_state.txt`.

## Grid submenus and Coffee presentation (bundled-v10)

No new files. Updated source/build: `apps_coffee.lua`, `lib_desktop.lua`, `lib_server.lua`, `lib_gui.lua`, `tools_build_installer.py`, `install.lua`. Updated tests: `tests_run.lua`, `tests_coffee.lua`, `tests_desktop.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_design.md`, `documentation_review.md`, and this map. The clock retains its original size/scaling with its colours swapped; Coffee has a cleaner main view. Layouts use a grid screen followed by a position screen, including 3×3; Resize/Move remain at the first level. App downloads now try the confirmed working GitHub API first. Update the server role and Coffee; existing bundled-v8 monitor and IO programs remain compatible. Saved timer/settings data is preserved.

## Console and calibration repairs (bundled-v11)

New files: `lib_console.lua`, `tests_console.lua`. Updated source/build: `main_os.lua`, `lib_network.lua`, `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `tools_build_installer.py`, `install.lua`. Updated existing tests: `tests_run.lua`, `tests_desktop.lua`. Updated guides: `README.md`, `documentation_desktop.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_review.md`, and this map. The installer contains thirteen core sources and no apps. Update the server role for the bottom-row console/clear command and the monitor role for tolerant calibration with Retry/Cancel. Use the full filename `clients_monitor_client.lua calibrate [side]`. Coffee, desktop geometry, saved data formats and the IO client are unchanged.

## Global colours and calibration testing (bundled-v12)

No new files. Updated source/build: `lib_settings.lua`, `lib_server.lua`, `lib_monitor.lua`, `clients_monitor_client.lua`, `tools_build_installer.py`, `install.lua`. Updated tests: `tests_run.lua`, `tests_desktop.lua`, `tests_appearance.lua`. Updated guides: `README.md`, `documentation_api.md`, `documentation_coffee.md`, `documentation_desktop.md`, `documentation_review.md`, and this map. OS settings adds global Window border and Taskbar palettes. Monitor calibration uses nine circles, agreement reporting, a live test, manual nudges and stock reset (`--reset` or the on-screen Reset followed by Save). Update the server and monitor roles; Coffee, IO, window resizing, taskbar dimensions/coordinates and file layout are unchanged.

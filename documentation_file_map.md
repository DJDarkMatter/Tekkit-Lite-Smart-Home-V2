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

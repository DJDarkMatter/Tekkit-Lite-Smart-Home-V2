# Version 50

App menus use inset dark panels, accent markers on section headers and smaller footer controls. Short sets of actions can sit side by side on wider windows. Lists of saved items stay in order and remain paginated on smaller windows. Clock has a live time header and four main tools. Switchboard keeps the configured switch and state colors, and ME storage, Reactors and Solar Farm use clearer metric groups. IO Scope centers each trace inside its lane.

## Update

Upload the flat contents of the full ZIP to the V2 GitHub repository. Replace your installer paste with v50 `install.lua` and download it as `inst`. On the central OS computer, run these commands from CraftOS.

```text
cd /
inst server
```

Run `inst apps` to install and enable all twelve release apps. To update only selected apps, run `inst app NAME` for each one you use. Then run `reboot`. The app identifiers are in the table below without the `apps_` prefix and `.lua` suffix.

From v49, the current clients already support the central update. From v48 or older, update each client with its v50 role and let it reconnect before making a new full backup that includes its configuration. See [Entire OS backup and restore](documentation_update_v49.md).

Restoring a full backup also restores the app versions saved inside it. Run the app update after restoring a snapshot made with earlier app versions if you want the refreshed screens.

## Changed and added files since v49

| Area | Files |
| --- | --- |
| Core and installer | `lib_gui.lua`, `main_os.lua`, `install.lua`, `tools_build_installer.py` |
| Apps | `apps_clock.lua`, `apps_coffee.lua`, `apps_io_scope.lua`, `apps_logic_sandbox.lua`, `apps_me_monitor.lua`, `apps_me_storage.lua`, `apps_notes.lua`, `apps_reactors.lua`, `apps_solar_farm.lua`, `apps_switchboard.lua`, `apps_window_presets.lua` |
| Tests | `tests_clock.lua`, `tests_run.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_clock.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v50.md` |

# Version 48

App content and desktop menus adapt to the available character cells. Short windows keep compact controls and paging. Where space permits, menus, pickers, keyboards, forms, and the alarm OK button provide taller touch areas. Padding inside a control is part of its touch area. Long labels can wrap within taller buttons.

Coffee and Clock use larger readouts where they fit. Reactor cards, ME storage metrics, ME monitor and Switchboard views, IO Scope lanes, and Solar Farm charts use more of their window. The layout picker and placement arrows use larger targets. Adjacent controls use contrasting fills, visible separators, or gaps.

The compact Nyan Cat layout fits more of the original sprite rows and preserves the eyes, cheeks, smile, and chin across all twelve frames.

## Install

Upload the flat root contents of the full ZIP to the V2 GitHub repository. Update your installer paste with v48 `install.lua` and download it as `inst` on the central computer. From CraftOS, run the server update and the commands for the optional apps you use. Reboot after the installs finish.

```text
cd /
inst server
inst app clock
inst app coffee
inst app io_scope
inst app logic_sandbox
inst app me_monitor
inst app me_storage
inst app notes
inst app reactors
inst app screensaver
inst app solar_farm
inst app switchboard
inst app window_presets
reboot
```

Settings, routes, app data, and layouts are loaded from the existing saves. The server update includes Settings and the desktop. All these commands run on the central computer.

## Changed and added files

| Area | Files |
| --- | --- |
| OS and shared UI | `main_os.lua`, `lib_alert_inbox.lua`, `lib_desktop.lua`, `lib_gui.lua`, `lib_io_picker.lua`, `lib_sensor_picker.lua`, `lib_server.lua`, `lib_settings.lua`, `lib_system.lua` |
| Apps | `apps_clock.lua`, `apps_coffee.lua`, `apps_io_scope.lua`, `apps_logic_sandbox.lua`, `apps_me_monitor.lua`, `apps_me_storage.lua`, `apps_notes.lua`, `apps_reactors.lua`, `apps_screensaver.lua`, `apps_solar_farm.lua`, `apps_switchboard.lua`, `apps_window_presets.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_appearance.lua`, `tests_me_monitor.lua`, `tests_run.lua`, `tests_screensaver.lua`, `tests_solar_farm.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_desktop.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_screensaver.md`, `documentation_update_v48.md` |

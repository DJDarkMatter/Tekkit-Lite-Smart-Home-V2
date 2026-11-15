# Version 51

- Switchboard groups Rename, Color, Routing, Behavior, State colors and Disconnect into matching buttons. Color has a small swatch where space permits.
- Shared client, side, wire and sensor choices use consistent rows. A shorter last page keeps the same row size. Color palettes use matching swatches.
- Keyboard letter keys use equal sizes and stay within their own rows. Back, Menu and other secondary actions can use smaller controls.
- Start uses a single column. Its entries are two rows tall on monitors with at least 17 desktop rows and one on smaller monitors.

## Update from v50

Upload the flat contents of the full ZIP to the V2 GitHub repository. Replace your installer paste with v51 `install.lua` and download it as `inst`. On the central OS computer, run these commands for the apps you use.

```text
cd /
inst server
inst app switchboard
inst app clock
inst app me_monitor
inst app me_storage
reboot
```

`inst apps` installs and enables all 12 apps if you want the full catalog. See [backup and restore](documentation_update_v49.md) for backups and role updates from older versions.

## Changed files since v50

| Area | Files |
| --- | --- |
| Core and installer | `lib_desktop.lua`, `lib_gui.lua`, `lib_io_picker.lua`, `lib_sensor_picker.lua`, `main_os.lua`, `install.lua`, `tools_build_installer.py` |
| Apps | `apps_clock.lua`, `apps_me_monitor.lua`, `apps_me_storage.lua`, `apps_switchboard.lua` |
| Tests | `tests_appearance.lua`, `tests_run.lua`, `tests_switchboard.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_desktop.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_switchboard.md`, `documentation_update_v51.md` |

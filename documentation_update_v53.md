# Version 53

## Update from v50

Upload the full ZIP's root files to the V2 GitHub repository. Use `tools_install_github.lua` as the contents of your installer paste. This script is about 2 KB and runs the full `install.lua` from memory. If GitHub's raw downloads are unavailable on your ComputerCraft server, `install.lua` is the self-contained installer when you have room to copy it to the computer.

At the CraftOS prompt on the central computer, remove the old `inst` file if it is still present. Download the new paste and install the server role.

```text
cd /
pastebin get YOUR_PASTE_ID inst
inst server
reboot
```

The v50 clients can connect to the v53 central OS. The v52 Solar Farm fix is in `apps_solar_farm.lua`. Run `inst app solar_farm` before rebooting to get it from v50. The [v51 update guide](documentation_update_v51.md) lists the app files for the previous layout fixes. Use `inst app NAME` for the apps you want to update. `inst apps` installs and enables the entire release catalog.

## Disk usage and recovery

- `inst space` reports free disk bytes and how much is occupied by old program copies that the installer can remove.
- Updates reclaim `.pre_update` and abandoned staging files for programs with a readable installed version. They verify the new programs, check space and write one file at a time. Existing configuration, app data, routes, layouts and backup archives carry over.
- If an update is interrupted, run the same installer command again. Keep `install_pending.txt` and `install_plan.txt` together while resuming. If GitHub `main` has advanced, use `inst --installer-ref REF` with the original release branch or commit, followed by the original command arguments.
- Startup uses the network boot record instead of requiring a full state save. The regular checkpoint writes directly, keeps one verified recovery copy, and compresses larger snapshots when it saves space. v53 reads older state and backup files. Use v53 to read compact live state. The one-file **Entire OS** backup remains compatible with v52.

## Changed files since v52

| Area | Files |
| --- | --- |
| Core | `lib_backup.lua`, `lib_codec.lua`, `lib_network.lua`, `lib_server.lua`, `lib_storage.lua`, `main_os.lua` |
| Installer | `install.lua`, `tools_build_installer.py`, `tools_install_github.lua`, `tools_install_update.lua` |
| Tests | `tests_appearance.lua`, `tests_clock.lua`, `tests_coffee.lua`, `tests_console.lua`, `tests_desktop.lua`, `tests_me_monitor.lua`, `tests_me_storage.lua`, `tests_run.lua`, `tests_screensaver.lua`, `tests_sensors.lua`, `tests_switchboard.lua`, `tests_system.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_file_map.md`, `documentation_menu_tree.pdf`, `documentation_update_v53.md` |

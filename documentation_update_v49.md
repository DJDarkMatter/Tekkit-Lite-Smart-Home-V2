# Version 49

## Full backup and restore

**Settings → App data → Backup & restore → Create backup → Entire OS** writes one `backup_os_all.txt` on the main computer. A v49 backup includes installed app programs and their enabled settings, app data and selections, window layouts and open views, client names, appearance, network settings, redstone routes and saved output states, and startup when present. It also includes each client's latest reported role settings, such as monitor calibration and scale or enabled IO sides.

Update each client with its v49 role and let it reconnect once before creating the backup. The main computer retains the last settings reported by each updated client, including clients that later go offline. The restore preview shows app, client and window counts.

- **Running OS** — Copy the file to the main computer's root. Choose **Restore backup → Entire OS** and confirm. The OS restarts with the saved programs and state.
- **Fresh main computer** — Install the v49 server role, put the backup in the root and run `inst restore`, then `reboot`. The backup supplies its app files and enabled list. Use `inst restore PATH` to read it from another location.
- **Rebuilt client** — Use the same backup file on that computer. After installing its role, run `inst restore monitor monitor_13` for a monitor with that saved client ID, then reboot. Substitute `io`, `sensor`, or `relay` and the saved client ID for other roles. For a monitor, use the computer's client ID without the attached side. Layouts match the saved monitor ID and physical side.

The restore stages the new files together and rolls back an interrupted replacement. Replaced files are retained with a `.before_restore` suffix. The previous full backup is retained as `backup_os_all.txt.bak` when replacing a readable snapshot.

A legacy backup can restore the app data and windows actually stored in it. Its preview displays the number of saved apps and windows. Install missing apps with `inst apps` or `inst app NAME`. For an older backup that lacks app data, recovery requires an earlier backup or a copy of the original `configs_os_state.txt` or its `.bak`. Keep those copies before making a new backup.

## Desktop and apps

- Start uses a compact single column on all monitor sizes.
- **Settings → Appearance → Taskbar → Position** places the taskbar at the top or bottom across all monitors. Windows and snap layouts follow the available desktop area.
- **Clock → World time** shows Minecraft time and the world day when available.
- Secondary controls such as Settings, Edit, Menu and Back use a compact, dark strip. Primary controls retain larger touch areas when space permits.

## Update

Upload the flat root contents of the full ZIP to the V2 GitHub repository. Update your single installer paste with v49 `install.lua` and download it as `inst`. Run these commands from CraftOS on the central computer.

```text
cd /
inst server
inst apps
reboot
```

`inst apps` installs and enables the twelve release apps. It stages the whole set before replacing programs. To update only installed apps with changes in v49, use `inst app clock`, `inst app coffee`, `inst app logic_sandbox`, `inst app me_monitor`, `inst app reactors` and `inst app switchboard` as applicable. The updated core supplies the shared button styles for the other apps.

On each client, run `inst io`, `inst monitor`, `inst sensor` or `inst relay` for its existing role, then reboot. Role updates preserve local configuration.

## Changed and added files

| Area | Files |
| --- | --- |
| OS and libraries | `main_os.lua`, `lib_alert_inbox.lua`, `lib_backup.lua`, `lib_desktop.lua`, `lib_gui.lua`, `lib_network.lua`, `lib_server.lua`, `lib_settings.lua` |
| Clients | `clients_io_client.lua`, `clients_monitor_client.lua`, `clients_relay_client.lua`, `clients_sensor_client.lua` |
| Apps | `apps_clock.lua`, `apps_coffee.lua`, `apps_logic_sandbox.lua`, `apps_me_monitor.lua`, `apps_reactors.lua`, `apps_switchboard.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_appearance.lua`, `tests_clock.lua`, `tests_run.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_clock.md`, `documentation_desktop.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v49.md` |

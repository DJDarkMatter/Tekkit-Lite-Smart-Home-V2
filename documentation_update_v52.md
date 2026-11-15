# Version 52

Entire OS creates a compact `backup_os_all.txt` containing installed app programs, app data and selections, window layouts, OS settings and the latest client configurations reported to the OS. Settings prompts for **Replace** when there is a readable completed backup. A failed first save offers **Create** to retry. A readable temporary backup from an older failed save can still be recovered. An interrupted replacement retains a readable prior snapshot.

Solar Farm holds the last good farm reading through a five-second retry window. **Menu → Source status** shows the error detail while it retries. A sustained error appears on the overview. Recovery starts a fresh baseline for farm and combined rates.

## Update from v49

Upload the flat contents of the full v52 ZIP to the V2 GitHub repository. Replace your installer paste with v52 `install.lua` and download it as `inst`. Run these commands from CraftOS on the central computer for the backup and Solar Farm fixes.

```text
cd /
inst server
inst app solar_farm
reboot
```

To get the v50 and v51 layout changes as well, run `inst app NAME` for each of your installed apps in the [v50 update list](documentation_update_v50.md). `inst apps` installs and enables all twelve release apps in one command. The v49 clients support the v52 central OS.

## Create and restore a full backup

Open **Settings → App data → Backup & restore → Create backup → Entire OS**. Copy `backup_os_all.txt` from the central computer's root for safekeeping. For a failed v49 save, you can leave `backup_os_all.txt.tmp` in place while upgrading. v52 can read it if the file contains a complete backup.

Use the v52 installer or OS to restore a compact v52 backup. v52 also reads the previous backup formats. See [the v49 guide](documentation_update_v49.md) for the central OS and individual client restore commands. Use the v52 installer in those steps.

## Changed files since v51

| Area | Files |
| --- | --- |
| Core and installer | `lib_backup.lua`, `lib_server.lua`, `lib_settings.lua`, `lib_storage.lua`, `main_os.lua`, `install.lua`, `tools_build_installer.py` |
| App | `apps_solar_farm.lua` |
| Tests | `tests_run.lua`, `tests_solar_farm.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_solar_farm.md`, `documentation_update_v52.md` |

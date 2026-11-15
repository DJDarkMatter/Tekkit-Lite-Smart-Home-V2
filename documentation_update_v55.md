# Version 55

The installer now checks the raw file when CraftOS 1.5 text readback changes line endings. It still rejects truncated or damaged files. File Explorer uses `pastebin put` and shows the paste ID and URL after you confirm **Send**.

## Resume the central computer upgrade

Upload the full release to the V2 GitHub repository. Use `tools_install_github.lua` as your installer paste. This small launcher runs the bundled installer in memory. At the CraftOS prompt, replace your old downloaded `inst` and run the update over your existing files.

```text
cd /
delete inst
pastebin get YOUR_PASTE_ID inst
inst server --startup
inst app file_explorer
```

The install should show `SmartHome installer: bundled-v55`. Your app data, routes, client selections and layouts carry over. If you are coming from v50 or the failed v54 install, also update the apps you use from the [v50 app list](documentation_update_v54.md#upgrade-directly-from-v50). `inst apps` installs and enables all 13 optional apps.

Run `reboot` after the updates finish. Existing IO, monitor, relay and sensor clients can stay on their current version.

## Changed files since v54

| Area | Files |
| --- | --- |
| Core and installer | `main_os.lua`, `lib_server.lua`, `lib_storage.lua`, `install.lua`, `tools_build_installer.py` |
| App | `apps_file_explorer.lua` |
| Tests | `tests_file_explorer.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_file_explorer.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v55.md` |

# Version 54

Coffee's countdown header fills the row from edge to edge. The shared heading fix applies across apps, and the Coffee, Logic Sandbox, ME storage, Reactors and Solar Farm panels have matching fixes for their own custom headers. File Explorer adds central filesystem browsing, file and folder creation, copy, move and Pastebin transfers.

## Upgrade directly from v50

Upload the full ZIP contents to the V2 GitHub repository. Use v54 `tools_install_github.lua` as the contents of your installer paste. It is about 2 KB and loads the full installer in memory. Keep your existing live configuration and saved-state files on the central computer. If an older `inst` is present, remove that downloaded installer before getting the new paste.

Run these commands at the central CraftOS prompt.

```text
cd /
pastebin get YOUR_PASTE_ID inst
inst server
inst app file_explorer
```

Update each of these apps that you use to get its latest changes since v50.

```text
inst app clock
inst app coffee
inst app logic_sandbox
inst app me_monitor
inst app me_storage
inst app reactors
inst app solar_farm
inst app switchboard
```

Run `reboot` after installing the apps. Your v50 IO, monitor, sensor and relay clients work with the v54 central OS. `inst apps` installs and enables all 13 release apps as an alternative to the app commands. `inst space` shows the remaining disk space.

The server update includes the low-space startup, updater and backup fixes from v52–v53. Use **Start → File Explorer** to open the new app. Pastebin uploads use a developer key. [File Explorer controls](documentation_file_explorer.md)

## Changed files since v53

| Area | Files |
| --- | --- |
| Core and installer | `main_os.lua`, `lib_gui.lua`, `lib_server.lua`, `install.lua`, `tools_build_installer.py` |
| Apps | `apps_coffee.lua`, `apps_file_explorer.lua`, `apps_logic_sandbox.lua`, `apps_me_storage.lua`, `apps_reactors.lua`, `apps_solar_farm.lua` |
| Tests | `tests_desktop.lua`, `tests_file_explorer.lua`, `tests_run.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_file_explorer.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v54.md` |

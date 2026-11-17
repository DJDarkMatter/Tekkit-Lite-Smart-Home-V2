# Version 57

The taskbar's right border uses the theme's window border color, with a contrasting color when it matches the taskbar. The Alert inbox has a left border in both sidebar and compact views. The clock still opens the inbox when tapped at the right edge.

File Explorer sends each HTTP result back to the installed Pastebin command. This fixes the “Pastebin command paused unexpectedly” error when older CraftOS waits for a request event.

## Update the central computer

Upload the full release to the V2 GitHub repository. On the central computer, use the small launcher from `tools_install_github.lua` as `inst`. It downloads the latest bundled installer from GitHub. Run the update over your existing setup.

```text
cd /
inst server --startup
inst app file_explorer
reboot
```

Check for `bundled-v57` in the installer output. Run the File Explorer app command if you use that app.

## Changed files since v56

| Area | Files |
| --- | --- |
| Core and installer | `main_os.lua`, `lib_server.lua`, `lib_desktop.lua`, `lib_alert_inbox.lua`, `install.lua`, `tools_build_installer.py` |
| App | `apps_file_explorer.lua` |
| Tests | `tests_appearance.lua`, `tests_desktop.lua`, `tests_file_explorer.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_desktop.md`, `documentation_file_explorer.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v57.md` |

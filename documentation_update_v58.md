# Version 58

The Start menu has a right border using the window border color. The taskbar clock reaches the screen's right edge again. The notification center has its left border.

File Explorer preserves the installed Pastebin command's upload URL, body and headers. Earlier versions appended a query parameter and could add a Content-Type header. The comparison test now runs the same program manually and through File Explorer and checks that the requests match.

The backup upload that also fails through the manual command still needs verification on the Minecraft server. V58 provides the correction to File Explorer's request handling.

## Update the existing central computer

Upload the full release to the V2 GitHub repository. Use the small `tools_install_github.lua` launcher as `inst`, then run the update on the existing computer.

```text
cd /
inst server --startup
inst app file_explorer
reboot
```

Check for `SmartHome installer: bundled-v58`. The update carries the saved app configuration, selections, routes and layouts forward.

## Changed files since v57

| Area | Files |
| --- | --- |
| Core and installer | `main_os.lua`, `lib_server.lua`, `lib_desktop.lua`, `install.lua`, `tools_build_installer.py` |
| App | `apps_file_explorer.lua` |
| Tests | `tests_appearance.lua`, `tests_desktop.lua`, `tests_file_explorer.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_desktop.md`, `documentation_file_explorer.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v58.md` |

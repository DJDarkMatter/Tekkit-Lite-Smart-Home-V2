# Version 56

The installer reads back the actual bytes of its recovery plan, empty update marker, installed programs and startup file. Older ComputerCraft can include disk quota overhead in its reported file sizes. V56 uses quota figures for space checks and verifies the data directly. Truncated files still fail verification.

## Retry the central computer upgrade

Upload the full release to the V2 GitHub repository. If your `inst` already contains the small launcher from `tools_install_github.lua`, it will download the v56 bundle from the repository. If you used the full bundled paste, replace `inst` with a paste containing the small launcher to reclaim disk space.

```text
cd /
delete inst
pastebin get YOUR_LAUNCHER_PASTE_ID inst
```

Run the upgrade on the central computer over the existing files.

```text
cd /
inst server --startup
```

Check for `SmartHome installer: bundled-v56`. The v55 error on `install_plan.txt` happened before replacing any installed programs. Keep your saved settings, routes, app files and backups on disk.

If you already installed the v55 app updates, run `reboot`. If you are still on v50, update the apps you use from the [v50 app list](documentation_update_v54.md#upgrade-directly-from-v50) before rebooting. Run `inst app file_explorer` if you want File Explorer. Existing clients can stay on their current versions.

## Changed files since v55

| Area | Files |
| --- | --- |
| Core and installer | `lib_storage.lua`, `main_os.lua`, `install.lua`, `tools_build_installer.py`, `tools_install_update.lua` |
| Tests | `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_update_v56.md`, `documentation_menu_tree.pdf` |

# Version 47

Nyan Cat preserves the face and right outline as its twelve frames scale down. Tetris Rain keeps whole colored tetrominoes inside the play area on compact displays. Calibrated taps that cross the screen boundary are clipped to the edge cell, including taps in the two 2×2 screensaver corners.

## Install

Upload the v47 release to the GitHub repo. On the central computer, update Screensaver.

```text
cd /
inst app screensaver
reboot
```

Replace the installer on the monitor computer with v47 `install.lua`. Reinstall the monitor role to pick up the corner fix.

```text
cd /
inst monitor
reboot
```

## Changed and added files

| Area | Files |
| --- | --- |
| Runtime | `apps_screensaver.lua`, `lib_monitor.lua`, `main_os.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_screensaver.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_desktop.md`, `documentation_screensaver.md`, `documentation_menu_tree.pdf`, `documentation_update_v47.md` |

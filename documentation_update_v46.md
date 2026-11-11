# Version 46

## Solar Farm

Windows with at least 22 content columns fit the item, quantity and rate on one row. The name uses the space left by the numeric columns. Counts use a high-contrast foreground. On dark rows, positive changes are bright lime and negative changes are pink. The item detail view shows the full values.

## Number pads

Whole-number and decimal keys fill the available rows between the draft and the footer. Each tile is tappable across its entire area. Clock uses the shared keypad for time and duration fields. Logic Sandbox, Solar Farm and Switchboard get the layout through the core update.

## Level Emitter

Level Emitter leaves the launcher and the installer rejects it. On the first v46 boot, the OS closes old windows and archives the app's routes. Its exclusive outputs turn off and saved rules remain in the checkpoint. A local copy of the old app can be removed under **Settings → App data → Delete apps**. Set up any item alarms you still need in Logic Sandbox.

Delete these files from the GitHub repository root when uploading the full release.

- `apps_level_emitter.lua`
- `documentation_level_emitter.md`
- `tests_level_emitter.lua`

## Install from v45

Replace your installer with the v46 `install.lua`. After uploading the release to GitHub and removing the three files above, run these commands on the central computer.

```text
cd /
inst server
inst app clock
inst app solar_farm
reboot
```

## Changed and added files

| Area | Files |
| --- | --- |
| Apps | `apps_clock.lua`, `apps_solar_farm.lua` |
| OS and installer | `lib_gui.lua`, `lib_server.lua`, `main_os.lua`, `tools_build_installer.py`, `install.lua` |
| Tests | `tests_app_helpers.lua`, `tests_appearance.lua`, `tests_clock.lua`, `tests_run.lua`, `tests_screensaver.lua`, `tests_solar_farm.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_design.md`, `documentation_file_map.md`, `documentation_me_storage.md`, `documentation_solar_farm.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v46.md` |

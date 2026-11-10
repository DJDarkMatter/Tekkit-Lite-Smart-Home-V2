# Version 41

## What changed

- **Settings** keeps the selected client when you back out of Rename and discards the draft. It also recovers a saved window left on the broken rename screen.
- The shared keyboard uses QWERTY with three letter rows. Compact windows page across those rows. The mode key shows **ABC**, **123** or **abc** for the mode it will open. Typing an uppercase letter returns to lowercase.
- Window Presets preserves the selected monitor when backing out of Assign. Relay Map preserves the selected path when returning from Details. Clock returns to its list if another monitor deletes the alarm or timer whose output details are open.
- Logic Sandbox accepts **Item amount** as an input. Select an AE target and item, then compare the live count against a level. See [the node guide and example circuits](documentation_logic_sandbox.md).
- Nyan Cat keeps its full right outline in all twelve frames. The five new screensavers are DVD Bounce, Pac-Man Chase, Tetris Rain, Rainbow Road and Among Us Drift. The existing designs retain their numbers.
- Legacy runtime fixes cover modem relocation, monitor detach, desktop startup with invalid saved entries, and Reactor save rollback and decimal display.

## Install

Upload the full flat-root release to GitHub. Replace the existing installer paste with this release's `install.lua`. Download it as `inst` and look for **bundled-v41**.

On the central computer, stop the OS and run `cd /` followed by `inst server`. Reinstall the apps below that you use. Each app command pulls its file from your GitHub repository.

```text
inst app clock
inst app level_emitter
inst app logic_sandbox
inst app me_monitor
inst app me_storage
inst app reactors
inst app screensaver
inst app solar_farm
inst app switchboard
inst app window_presets
```

Reboot the central computer. On IO clients, use the new installer to run `inst io` and reboot. On monitor clients, run `inst monitor` and reboot. The installer retains saved configuration and existing startup scripts.

## Changed files

| Area | Files |
| --- | --- |
| Central OS | `main_os.lua`, `lib_server.lua`, `lib_settings.lua`, `lib_system.lua`, `lib_gui.lua` |
| Client libraries | `lib_io.lua`, `lib_monitor.lua` |
| Apps | `apps_clock.lua`, `apps_level_emitter.lua`, `apps_logic_sandbox.lua`, `apps_me_monitor.lua`, `apps_me_storage.lua`, `apps_reactors.lua`, `apps_screensaver.lua`, `apps_solar_farm.lua`, `apps_switchboard.lua`, `apps_window_presets.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_appearance.lua`, `tests_clock.lua`, `tests_run.lua`, `tests_screensaver.lua`, `tests_switchboard.lua`, `tests_v39.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_logic_sandbox.md`, `documentation_screensaver.md`, `documentation_update_v41.md` |

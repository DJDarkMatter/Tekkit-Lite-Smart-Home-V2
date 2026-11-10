# Version 43

## Central OS watchdog recovery

The reported failure is `main_os.lua:67: Too long without yielding`, accompanied by a failed checkpoint and `OS stopped at: Receiving modem message`.

The cooperative pause previously called `os.queueEvent` before yielding and waited for its own wake marker. The OS now arms a native fallback timer before expensive work. If the legacy watchdog rejects the software wake call, the pause still reaches `os.pullEvent`. Any delivered event completes that work slice, and the collector retains application and console events for ordered processing after the current transaction.

Work slices use a smaller budget. A pending wake marker is reused during traffic bursts. A stale fallback timer is renewed after incoming events. The OS receive buffer has limits of 256 packets and one MiB while long work is in progress. Excess modem packets produce one warning per overflow period. Console commands, peripheral changes and the background timer retain their queue positions.

The cooperative serializer also saves numbers at full round-trip precision. Legacy LuaJ's default number conversion could truncate relative window sizes and restore a window one cell smaller after a reboot and monitor resize. The same fix preserves fractional app state and large counters when checkpointed.

## Install from v42

Upload the full release root to GitHub and replace your installer paste with this release's `install.lua`. Download a fresh `inst` showing **bundled-v43** on the central computer. From the CraftOS root, run the following commands.

```text
inst server
reboot
```

The startup banner is **SmartHome OS v43**. If upgrading from v41 or earlier, follow the [v42 app and IO update instructions](documentation_update_v42.md) as well.

## Maintained menu tree

The root now includes the [clickable portrait menu tree](documentation_menu_tree.pdf), its [editable menu source and maintenance instructions](documentation_menu_tree.md), and `tools_build_menu_tree.py`. It covers the current 13 optional apps, Settings, desktop controls, shared dialogs, and all 25 screensaver designs. System overview is under Settings.

The builder reads the version, app titles and screensaver catalog from Lua. Its freshness check flags changes to the documented source files and requires a rebuilt PDF. Review menu paths against the changed Lua before rebuilding. Repository maintenance instructions and the optional root workflow include that check.

## Verification

All 380 integration tests pass on Lua 5.1 and LuaJ 2.0.3. Regression tests reproduce the screenshot's wake-call error during a modem-triggered checkpoint and during decoding, then verify continued IO and valid saved state. Another test floods a checkpoint with large packets and checks the buffer limit, console responsiveness and save integrity. The suite also covers lost wake events, large sensor catalogs, fullscreen rendering, layouts, routing and existing app behavior. Test snapshots now use a stable key order, and the calibration assertion follows the runtime's number formatting. Tests simulate ComputerCraft. LycoDon's IDT-Fixed runtime needs an in-game run.

The menu PDF has 19 portrait pages and 809 verified link destinations. Every page was rendered and visually checked. Its builder produces byte-identical output, and the freshness check rejects source edits and newly added apps until the documentation is reviewed and rebuilt.

## Changed files

| Area | Files |
| --- | --- |
| Central OS | `main_os.lua`, `lib_work.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_run.lua`, `tests_work.lua`, `tests_desktop.lua` |
| Menu tree | `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `tools_build_menu_tree.py` |
| Documentation and maintenance | `README.md`, `documentation_file_map.md`, `documentation_update_v43.md`, `AGENTS.md`, `github_workflows_lua.yml` |

# Version 36 — recover blank central OS startup

The central startup/event loop changed in v35. It could wait indefinitely if a private wake-up event was discarded. During a large saved-state checkpoint, that wait could occur before modem discovery or normal startup logs. A regression test reproduces this failure with the original v35 entry point. The exact trigger on the public Minecraft server has not been captured, so event loss there remains an inference.

V36 uses a single serial event loop and no private event to wake queued work. Cooperative pauses have a native timer fallback, while keeping incoming modem events, monitor touches and console commands buffered until the current operation finishes. Native configuration/modem bootstrap runs on the program's original thread. The console shows startup progress immediately, opens the modem before saved app-state restoration, and prints the stage/message of a caught failure. The bounded-work checks and error reports added in v35 remain enabled.

## Install this complete release

This ZIP contains the entire project. Upload its root files to the V2 GitHub repository, including **install.lua**. Replace your existing installer Pastebin with the full contents of this release's **install.lua**. No files have been published to GitHub by this repair session.

On the **central OS computer**, hold **Ctrl+T** to leave the stalled program. Replace the downloaded `inst` with the updated installer from your usual Pastebin, then run:

```text
cd /
inst server
reboot
```

The installer must say **SmartHome installer: bundled-v36**. If it still says v35 or an earlier version, delete only the downloaded **inst**, then download your updated paste again. You do not need to change your existing startup script. Do not delete your configuration/state files.

**From v35, no apps or remote clients need reinstalling.** Existing routes, source selections, app settings, counters, production history and layouts remain in their saved files. The installer continues to embed 22 core sources and no user apps.

## Cumulative reinstall checklist

Do not install each intermediate version. Use v36 once and update only the optional apps you already have installed.

| Version containing the change | Central OS | Apps to reinstall | Remote clients to reinstall |
| --- | --- | --- | --- |
| v33 | Included in `inst server` with bundled-v36 | `clock`, `coffee`, `level_emitter`, `me_monitor`, `me_storage`, `reactors`, `screensaver`, `solar_farm`, `switchboard`, `system`, only if installed | None |
| v34 | Included in `inst server` | None beyond v33 | None |
| v35 | Included in `inst server` | `solar_farm`, if installed | None |
| v36 | `inst server` with bundled-v36 | None | None |

From v32, update all your installed apps with `inst app NAME` before rebooting. From v33/v34 with those app updates already installed, only `inst app solar_farm` is additionally needed if you use it. From v35, update only the central OS.

## If startup still stops

Startup now displays **SmartHome OS v36: starting**, modem information, **Loading saved OS state...** and **Starting enabled apps...**. The last visible stage narrows down any remaining failure.

A caught failure prints **OS stopped at:** and its error, and attempts to save **diagnostics_os_error.txt**. Read the report in CraftOS with:

```text
edit diagnostics_os_error.txt
```

Or use `errorlog` once the OS is running. A hard shutdown/native abort may prevent error reporting; the report is the latest caught error and can refer to an earlier boot. Ordinary Ctrl+T does not overwrite it.

## Verification

- **329 Lua 5.1 integration tests pass**; all project Lua files compile.
- **120 distinct focused standalone LuaJ 2.0.3 tests pass**, covering cooperative startup/work, Clock, Switchboard and Solar farm.
- The new full-queue startup regression fails against the original v35 entry point and passes in v36, preserving 1,600 saved entries.
- Recovery checks also cover lost software wake-ups while running, all four client roles, visible configuration errors and a single shared fallback timer during many fast pauses.
- Existing checks retain transactional save/IO ordering, buffered touches/console input, large ME catalogs, large screensaver frames and saved diagnostics.
- The generated installer matches its 22 embedded sources. These are simulated ComputerCraft APIs and standalone LuaJ tests; the public server itself has not been run here.

## Exact files changed from v35

- `README.md`
- `documentation_api.md`
- `documentation_file_map.md`
- `documentation_review.md`
- `documentation_update_v36.md`
- `install.lua`
- `main_os.lua`
- `tests_run.lua`
- `tests_work.lua`
- `tools_build_installer.py`

The only changed installed runtime file is **main_os.lua**; **install.lua** embeds it and updates the version banner. No app or remote client source changes in v36. The complete v33/v34/v35 changed-file list remains in **documentation_update_v35.md**.

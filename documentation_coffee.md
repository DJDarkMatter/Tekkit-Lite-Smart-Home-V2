# Coffee timer

This optional, single-file app adapts `oldfiles_coffee_timer.lua`. It runs on the central OS and uses generic IO clients for its player-presence input and harvest output. It is not bundled with the base OS installer. Its root filename is `apps_coffee.lua`; the app name remains `coffee`.

## Install on the central computer

Upload the complete new `install.lua` as your single installer Pastebin paste. Keep the current `apps_coffee.lua` in the root of `DJDarkMatter/Tekkit-Lite-Smart-Home-V2` on GitHub's `main` branch; no app paste is needed. If the OS console is running, type `quit` to return to CraftOS. Then:

```text
cd /
delete inst
pastebin get INSTALLER_PASTE_ID inst
inst server --startup
inst app coffee
reboot
```

The installer banner must say `bundled-v6`. `inst app coffee` downloads only `apps_coffee.lua` from GitHub and enables it in `configs_os.txt`; rerunning the command updates code while preserving saved timer/settings state. The current Coffee file declares `backgroundService = true` and requires the bundled-v5 app API or newer. Every OS boot starts its background service without opening a window. Its saved state schema and the network protocol are unchanged, so existing IO and monitor clients remain compatible. To migrate their files into the root too, run the new installer there with their role and `--startup`. The central computer must stay loaded for any code to run.

The GitHub download requires HTTP access from ComputerCraft to `raw.githubusercontent.com`. A missing file, network/HTTP error, empty response or Lua syntax error stops installation before replacing the installed app or OS settings. Check that GitHub has the latest app file before testing. You can optionally select a known branch/commit with `inst app coffee --ref REF`; Pastebin-ID and `--file PATH` modes remain available for other app sources.

## Configure wiring by touch

On an advanced monitor, touch bottom-left `[+]`, then `coffee`. Choose `Settings`, or `Menu` then `Settings` in a compact window:

1. **Player IO:** select the IO computer, the physical side carrying the presence signal, and `Digital` for ordinary redstone or the bundled wire colour. Review and touch `Use`.
2. **Harvest IO:** select the output client, side and Digital/colour the same way.

The modem side is excluded. `+` beside an IO client means online; `-` means offline. Lists have `Prev`/`Next` buttons on small windows. The app does not assume the original left input/right output; select your actual wiring.

After both bindings are configured, an online player signal starts the countdown. With no valid input/output or with a disconnected client, it waits for configuration/reconnection. Selecting a wire already owned by another logical output is rejected. Rewiring an active harvest switches its old output OFF and pauses the app; use `Resume` to run on the new output.

The picker belongs to the OS and can be used by future switchboard/other apps as well. It is not coffee-specific.

## Behavior and controls

- **Defaults:** 14,400 seconds (four hours) between harvests, and a 60-second harvest. Seconds use computer uptime, not Minecraft clock hours; changing world time does not advance the coffee timer.
- **Original player behavior:** countdown pauses when the presence signal is OFF. During an automatic harvest, an absent player pauses the harvest timer while leaving the harvest output ON, as the original did. Unknown/disconnected input data causes the app to turn the harvest intent OFF until it can resume.
- **Pause/Resume:** preserves remaining time. Manual Pause turns the harvest output OFF even during a harvest; Resume continues the remaining duration.
- **Harvest now:** starts a harvest immediately, including when the player input is OFF or not configured. It still requires a configured online output. Repeated taps during a harvest do not restart or extend it. The normal presence rule returns after that harvest.
- **Countdown / Harvest time settings:** touch the Step row to cycle 1 s, 10 s, 60 s, 600 s and 3,600 s; use minus/plus, then Save. Durations can be 1 second to 7 days. Changes apply to the next phase and preserve the current remaining time.
- **Reset:** explicitly starts a fresh countdown using the configured duration, stopping an active harvest if necessary. It asks for confirmation.
- **Stats:** completed harvest total and resettable trip counter. Closing/minimizing a window never stops or duplicates the background service.

The smallest supported content area is 12×6 characters (14×9 including the bottom taskbar and window frame). Compact windows show the overview and a Menu button; larger windows expose controls, counts, durations and wiring details. The top-left `[#]` button opens snap/maximize/custom layout options. See [desktop controls](documentation_desktop.md). Multiple windows use independent settings pages/drafts while sharing one timer and applied configuration.

## Restarts and saves

The OS saves all app states and window layouts every second while running; coffee also checkpoints every second and saves important phase/control/configuration transitions immediately. It stores phase, remaining countdown, remaining harvest time, durations, IO bindings, pause/manual-harvest state and counts in `configs_os_state.txt`. Installed/enabled apps are recorded in `configs_os.txt`.

Temporary/backup files support interrupted-write recovery. A restart restores saved remaining time instead of starting over or counting unloaded time. Output intents are checkpointed before commands are sent. A failed save blocks starting a new harvest until saving recovers. An IO client reconnect restores the current desired output; timer progress waits for its acknowledgement.

A crash can still lose progress since the last successful checkpoint, normally up to one second. Client loss is detected using the network timeout, not instantly. Confirmation proves the IO computer applied its output; it is not feedback from the physical farm.

## Import the original standalone timer's progress

Copy the original `countdown_state.txt` to the central OS computer's root. In Coffee Settings, choose `Import`, then confirm. The app validates and copies the original remaining countdown, harvest-active flag and remaining harvest duration; it leaves the old file untouched.

Imported state starts **paused**. Configure the IO addresses, inspect the remaining time, then press Resume. Importing is explicit so a stale original file cannot overwrite an existing new-app countdown on each boot.

## Minecraft taskbar clock

The bundled-v5 OS reads `os.time()` on the central computer and formats a 24-hour Minecraft clock. It needs no additional IO, app or sensor. `?:??` remains only if neither that API nor a sensor fallback is available. This clock is separate from coffee's real-second countdown.

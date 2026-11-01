# Clock: alarms, timers and stopwatch (v24)

`apps_clock.lua` runs on the central OS. It is an optional background service: after explicit installation it starts at every OS boot, even without a window. Closing its windows leaves clocks and output signals running.

## Install or update

Upload the complete v24 package's root files to the V2 GitHub repository. Replace the single installer paste with the supplied `install.lua` (banner `bundled-v24`), download a fresh `inst` on the central computer, quit the OS and run:

```text
cd /
inst server
inst app clock
reboot
```

Keep the existing startup script. Use `inst server --startup` if configuring startup for the first time. IO/monitor/sensor/relay clients do not change for v24. The installer includes no apps; `inst app clock` fetches this app through GitHub's contents API, with the existing raw-download fallback. No extra Pastebin file is needed.

## Alarms

Open **Clock → Alarms → + Add alarm**. Name it with the touch keyboard, set its world time as four HHMM digits (for example 0715), choose Daily or Once, enable it, and select an output. Output selection uses the normal **IO client → side → bundled colour / Digital → Use** picker. Save applies everything together. Selecting a route in the picker edits the draft; Cancel discards it.

Each saved alarm remains in the list. Touch it to enable/disable it, inspect routing and signal details, edit or delete it. Once disables after its first trigger; Daily can trigger once per world day. Changing the scheduled time explicitly starts a new schedule. Output-free entries are allowed, but actuate nothing. Disable prevents future triggers; **Stop output signal** ends an already running signal.

All schedules use the OS computer's numeric Minecraft world clock, with `os.day()` when supplied by the installed runtime. A display-only legacy sensor clock is insufficient. Without numeric world time, alarms wait and game clocks pause; real clocks continue. Midnight rollover and Minecraft's 06:00 day-counter boundary are handled separately. Without `os.day`, the app tracks observed midnights.

## Timers

**Timers → + Add timer** configures a name, duration in whole seconds, Real/Game clock and the same output options. **Start** saves and starts the new timer. The list shows running/paused timers plus recent finished/cancelled ones, newest first. Touch an entry for Pause/Resume, Cancel, Restart, output details or Delete. Pause a running timer before editing it. Changing duration or clock mode resets a paused timer to the new duration; an unchanged duration/mode preserves its remaining progress.

Real uses elapsed `os.clock()` computer uptime. Game uses actual sampled world-clock seconds: an ordinary 24-game-hour day normally passes in 20 real minutes. Game timers are not estimated from a fixed multiplier when the world clock is missing. The legacy APIs cannot provide a reliable UTC wall-clock deadline across unloads/restarts; lag and server pauses can also affect uptime clocks. There is no HTTP time dependency.

Settings retains **10, 20 or 50** completed/cancelled timers, with paging to fit each window. Running/paused timers and unfinished signals are not discarded for history space. Up to 64 list entries can be created; delete old entries if full. Clock supports 64 alarms separately.

## Output options

| Mode | Fields | Behaviour |
| --- | --- | --- |
| Pulse | ON seconds | One ON interval, then OFF |
| Pattern | ON seconds, OFF seconds, Total seconds | Starts ON, repeats ON/OFF, ends OFF at the total duration |

Signal durations always use real computer uptime, independently of the timer's clock mode. All fields accept whole seconds. ON/OFF are at least one second, keeping transitions compatible with the existing per-side IO write cooldown. Late OS ticks go directly to the current phase instead of emitting a burst of missed edges. The normal IO queue can delay hardware changes; desired state and ACK status are visible in Output details.

Each entry has its own saved logical output. Shared routes are allowed. Overlapping Clock signals on the same wire are OR-combined, so finishing one does not interrupt another active Clock signal. Other apps share that physical wire too: a deliberate Clock ON/OFF changes shared intent just like Switchboard. Binding an idle clock entry adopts an already mapped wire's intent; deleting an idle reference preserves other references. Deleting/stopping an active signal removes that signal's contribution.

An offline IO client receives only current desired state on reconnect. Expired pulses and missed pattern edges are never replayed.

## Stopwatch

Choose Real or Game while reset/stopped. **Start/Stop**, **Lap** and **Reset** operate on one stopwatch shared by its windows. Reset also stops it. Up to 50 recent laps are saved; compact screens show lap duration, and wide screens also show cumulative elapsed time. Lap pages and the selected Clock page are independent per window.

## Saved state and restarts

Alarms, enabled/repeat flags, exact IO addresses, signals, timer progress/history, stopwatch/laps and settings live in `appStates.clock` inside `configs_os_state.txt`. The OS also checkpoints each window's navigation/drafts/geometry. No new runtime data files are needed.

Trigger markers, completed timers and output changes commit in the same central checkpoint **before** hardware sync. Save failure sends no new output and the transition is retried. The persisted alarm day prevents duplicate firing after reboot or a backwards world-clock adjustment. Concurrent editors reject a configuration changed in another window or an alarm that fired while being edited.

Countdowns, stopwatch and active patterns resume from their last checkpoint. **Downtime is not counted**, and an active pulse can therefore remain pending across a restart, just like Coffee's saved phase. Time spent while the OS is absent is not recoverable as real elapsed time. Alarms missed during downtime are skipped. Large forward/backward world-clock changes, such as sleep/time-set jumps, establish a new baseline without catching up skipped schedules or game durations. Very small clock adjustments are indistinguishable from ordinary sampled progress. The status screen reports missing/rebased clocks and pending save errors.

The OS saves normal progress within one second; important transitions save immediately. This is checkpoint recovery, not a physical transaction with Minecraft hardware. In-game testing remains necessary for the public server's exact timing.

Legacy API references: [os.time](https://computercraft.info/wiki/Os.time), [os.day](https://computercraft.info/wiki/Os.day), [os.clock](https://computercraft.info/wiki/Os.clock).

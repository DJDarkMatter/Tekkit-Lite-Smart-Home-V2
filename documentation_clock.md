# Clock

`apps_clock.lua` runs on the central OS. It is an optional background service: after explicit installation it starts at every OS boot, even without a window. Closing its windows leaves clocks and output signals running.

## Install or update

Install the v50 server role on the central computer. Run `inst app clock` to install Clock by itself or `inst apps` to install the whole release catalog. See [the v50 update instructions](documentation_update_v50.md).

## World time

Clock shows the current Minecraft time on its home screen. Wider windows use a two-column grid for Alarms, Timers, Stopwatch and World time. Settings and Status are in the footer. On narrow windows Settings is labeled **Setup**.

Open **Clock → World time** for a larger readout and the world day when available.

## Alarms

Open **Clock → Alarms → + Add alarm**. Name it with the touch keyboard, set its world time as four HHMM digits (for example 0715), choose Daily or Once, enable it, and select an output. Output selection uses the normal **IO client → side → bundled color / Digital → Use** picker. Save applies everything together. Selecting a route in the picker edits the draft; Cancel discards it.

Each saved alarm remains in the list. Touch it to enable/disable it, inspect routing and signal details, edit or delete it. Once disables after its first trigger; Daily can trigger once per world day. Changing the scheduled time explicitly starts a new schedule. Output-free entries still show the popup, without actuating a wire. Disable prevents future triggers; **Dismiss / OK** ends an already running signal.

All schedules use the OS computer's numeric Minecraft world clock, with `os.day()` when supplied by the installed runtime. A display-only legacy sensor clock is insufficient. Without numeric world time, alarms wait and game clocks pause; real clocks continue. Midnight rollover and Minecraft's 06:00 day-counter boundary are handled separately. Without `os.day`, the app tracks observed midnights.

## Timers

**Timers → + Add timer** configures a name, duration in whole seconds, Real/Game clock and the same output options. **Start** saves and starts the new timer. The list shows running/paused timers plus recent finished/cancelled ones, newest first. Touch an entry for Pause/Resume, Cancel, Restart, output details or Delete. Pause a running timer before editing it. Changing duration or clock mode resets a paused timer to the new duration; an unchanged duration/mode preserves its remaining progress.

Real uses elapsed `os.clock()` computer uptime. Game uses actual sampled world-clock seconds: an ordinary 24-game-hour day normally passes in 20 real minutes. Game timers are not estimated from a fixed multiplier when the world clock is missing. The legacy APIs cannot provide a reliable UTC wall-clock deadline across unloads/restarts; lag and server pauses can also affect uptime clocks. There is no HTTP time dependency.

Settings retains **10, 20 or 50** completed/cancelled timers, with paging to fit each window. Running/paused timers, unfinished signals and unacknowledged popups are not discarded for history space. Up to 64 list entries can be created; delete old entries if full. Clock supports 64 alarms separately.

## Output options

| Mode | Fields | Behaviour |
| --- | --- | --- |
| Constant | Length seconds | ON for this long, then OFF; 0 holds ON until dismissed |
| Pattern | ON seconds, OFF seconds, Total seconds | Repeats ON/OFF; ends OFF at Total, or continues until dismissed when Total is 0 |

Signal durations always use real computer uptime, independently of the timer's clock mode. All fields accept whole seconds. Pattern ON/OFF phases are at least one second; Constant length and Pattern total may be zero for indefinite operation, keeping transitions compatible with the existing per-side IO write cooldown. Late OS ticks go directly to the current phase instead of emitting a burst of missed edges. The normal IO queue can delay hardware changes; desired state and ACK status are visible in Output details.

Each entry has its own saved logical output. Shared routes are allowed. Overlapping Clock signals on the same wire are OR-combined, so finishing one does not interrupt another active Clock signal. Other apps share that physical wire too: a deliberate Clock ON/OFF changes shared intent just like Switchboard. Binding an idle clock entry adopts an already mapped wire's intent; deleting an idle reference preserves other references. Deleting/stopping an active signal removes that signal's contribution.

An offline IO client receives only current desired state on reconnect. Expired finite signals and missed pattern edges are never replayed.

## Popup and redstone dismissal

Every alarm/timer trigger creates a **red panel with white text and a white OK strip**, independent of desktop/window/app colors. It creates a small modal window showing its type/name and one **OK** button on **every connected monitor**, even when Clock has no open windows and no output is selected. OK on any monitor acknowledges that occurrence, stops its signal and closes its popup everywhere. Finite signals stop at their configured length/total, but their popup remains until acknowledged. Constant length **0** and Pattern total **0** continue until acknowledged.

If several entries trigger, popups queue in trigger order. Acknowledging one does not dismiss another or interrupt another active Clock signal on a shared wire. There is at most one outstanding popup per alarm/timer; an already pending daily alarm is not restarted by its next scheduled occurrence. Pending popups appear again after OS/monitor restart and reach monitors connected later. They overlay the desktop without creating, moving or replacing saved app windows. Clicks do not pass through a popup to the desktop underneath, and queued stale OK taps cannot dismiss the following entry.

Each alarm/timer editor offers **Select dismiss input** (or **Dismiss: client**) using **IO client → side → Digital/bundled color → Use**. Apply it with Save, just like the output. **Clear dismiss input** removes it. A fresh LOW→HIGH press after the trigger has the same effect as OK, closing the popup everywhere. A line already HIGH when the alarm starts must go LOW before another HIGH acknowledges it. After an OS restart or the input going offline, a fresh observed LOW is required again; reconnecting HIGH cannot silently acknowledge an alarm. Multiple entries may share an input, in which case that press acknowledges all pending entries configured for it.

Acknowledgement and desired output changes checkpoint together before sync; if saving fails, the popup and output intent remain and can be retried. Redstone acknowledgement retries while the pressed input remains HIGH. Existing IO cooldown and confirmation behaviour still apply to physical writes.

The former **Pulse** name is now **Constant**. Saved v24 Pulse configurations automatically migrate to Constant with the same duration, routes, progress and IDs. Only a still-active old signal receives a restored popup; already finished v24 timer history does not generate old notifications. Per-entry dismiss inputs and pending occurrences are part of saved Clock state, without extra runtime files.

## Stopwatch

Real timing now uses a runtime start anchor plus saved elapsed time rather than summing background ticks. The display and Start/Stop/Lap sample `os.clock()` directly, including fractions between callbacks. Delayed callbacks and unrelated alarm-save retries do not silently discard that time. Stop/resume/reboot establish new anchors; offline time remains excluded. Game mode shows **days HH:MM:SS**, without subsecond digits, in the main readout and laps. Real mode retains tenths. Legacy ComputerCraft exposes computer uptime, not an independent real-world wall clock: server lag can still slow that clock, which this change cannot infer or correct.


Choose Real or Game while reset/stopped. **Start/Stop**, **Lap** and **Reset** operate on one stopwatch shared by its windows. Reset also stops it. Up to 50 recent laps are saved; compact screens show lap duration, and wide screens also show cumulative elapsed time. Lap pages and the selected Clock page are independent per window.

## Saved state and restarts

Alarms, enabled/repeat flags, exact IO addresses, signals, timer progress/history, stopwatch/laps and settings live in `appStates.clock` inside `configs_os_state.txt`. The OS also checkpoints each window's navigation/drafts/geometry. No new runtime data files are needed.

Trigger markers, completed timers and output changes commit in the same central checkpoint **before** hardware sync. Save failure sends no new output and the transition is retried. The persisted alarm day prevents duplicate firing after reboot or a backwards world-clock adjustment. Concurrent editors reject a configuration changed in another window or an alarm that fired while being edited.

Countdowns, stopwatch and active patterns resume from their last checkpoint. **Downtime is not counted**, and an active signal can therefore remain pending across a restart, just like Coffee's saved phase. Time spent while the OS is absent is not recoverable as real elapsed time. Alarms missed during downtime are skipped. Large forward/backward world-clock changes, such as sleep/time-set jumps, establish a new baseline without catching up skipped schedules or game durations. Very small clock adjustments are indistinguishable from ordinary sampled progress. The status screen reports missing/rebased clocks and pending save errors.

The OS saves normal progress within one second; important transitions save immediately. This is checkpoint recovery, not a physical transaction with Minecraft hardware. In-game testing remains necessary for the public server's exact timing.

Legacy API references: [os.time](https://computercraft.info/wiki/Os.time), [os.day](https://computercraft.info/wiki/Os.day), [os.clock](https://computercraft.info/wiki/Os.clock).

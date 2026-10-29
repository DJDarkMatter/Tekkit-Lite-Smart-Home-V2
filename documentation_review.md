# Review of the original implementation

Reviewed baseline: `4cd4d8b629cd15d02c41f634ad3ac6a910bf6dae` (the original `main` commit).

The design describes a useful architecture: one computer runs the logic, and reusable clients bridge displays, redstone and sensors. The original repository contains a partly written OS, one non-working IO client, and standalone archived programs. The written design describes considerably more than the original code implements.

## Defects preventing the first IO connection

| Original code | Effect | Repair |
| --- | --- | --- |
| OS listens on `100`; IO client uses `45231` | They cannot receive each other's packets | Shared configuration and transport |
| `local modem` exists only inside each `mainLoop` | Helper functions see a nonexistent global `modem` | Transport object passed explicitly |
| OS calls `modem.send` | Raw modems expose `transmit`, not `send` | One shared transmit implementation |
| Table sent directly to an old modem API | Compatibility depends on the installed CC version | Serialize every wire packet to a string |
| Server assumes its modem is on `back` | A different placement fails | Detect/recover a modem on any side |
| IO client announces once and has no welcome handling | No confirmed connection or recovery if OS starts later | Nonce-echoed welcome and periodic announcements |
| `sleep` after handling events | ComputerCraft's filtered sleep consumes unrelated events | Timer-driven unfiltered event loops; parallel console |

The modem API signature and event arguments are documented in the [ComputerCraft modem API](https://computercraft.info/wiki/Modem_(API)); the event-discarding behavior is documented in [os.pullEvent](https://computercraft.info/wiki/Os.pullEvent). String payloads also avoid relying on newer modem table support (see the [historical 1.5 channel tutorial](https://ccf.squiddev.cc/forums2/index.php?/topic/10343-15-modems-and-channels/)).

## Other broken behavior

- IO capability discovery checked attached peripherals for redstone methods. Bundled redstone belongs to the computer's `redstone` API, not to a cable peripheral.
- `readInputs` was never called. The event loop filtered out redstone events, and the OS had no input handler.
- The old OFF calculation OR-ed the current mask with an inverted colour mask. This could turn unrelated wires ON. The repaired OS computes a complete desired mask from logical boolean outputs; the client applies it directly.
- Output commands confused the client address (`io_main`) with the physical address (`left:16384`). These are now separate fields in OS-owned mappings.
- All commands used a shared channel with no recipient filtering. Packets now carry protocol, household network ID and recipient computer/client IDs.
- `sendToIO` and `handleTaskbarTouch` were referenced before their local declarations, resolving to nonexistent globals. Both paths are now real methods in the server module.
- `p5` was passed without being captured from `os.pullEvent`. Event fields are now captured deliberately; unused distance is not required by routing.
- The OS trusted `message.type` on arbitrary public-server traffic. Both transport and message handlers now validate their inputs.
- Sensor packets could overwrite arbitrary top-level state, including `windows`, via `state[message.varName]`. Raw sensor values now live under their registered sensor client; only typed `playerOnline` and `gameTime` update system indicators.
- Save directories were not created, file-open failures were unchecked, and only windows/registry were saved. Checkpoints now include app state, logical mappings/outputs and boot generations, with recovery and visible failures.
- Restored windows could be overwritten because `nextWindowId` reset to 1. IDs are now derived from restored windows.
- Rendering ignored window coordinates, failed to clip to the screen, and had an incorrect title/close-button width. Touch offsets did not match rendered content. Central composition and hit testing now share the same geometry.
- The taskbar handler was empty. There was no app API for opening windows or generic monitor client. A launcher, window controls, app lifecycle/API and generic monitor client now support the architecture. Apps are user-specific and opt-in; no app is bundled or enabled by default. The switchboard used to exercise window/IO behavior is a test fixture only.
- Background jobs and saves depended on the arrival/count of unrelated events. Dedicated timers now drive background elapsed time and checkpoint intervals.

## Design decisions that need to remain explicit

1. **Saved intent versus observed hardware:** ON means the OS's desired state; confirmed means the IO computer applied it. External machine feedback requires a real input/sensor.
2. **Connection loss:** default clients switch outputs OFF after a 15-second timeout and restore saved intent on reconnect. This policy is configurable; it is transport behavior, not farm logic.
3. **Durability:** all app data and window layouts checkpoint every second; important counters/transitions checkpoint immediately. Coffee saves its active phase and remaining duration, with no downtime catch-up. Checkpoints are not an exact transaction with an external machine, so the repair does not claim to recover unsaved sub-second elapsed time or prove a physical harvest happened exactly once.
4. **App/view sizing:** actual character capacity from `monitor.getSize()` is authoritative for fit checks. A physical `5x4` classification requires separate metadata if still useful; it cannot safely be inferred from arbitrary text scale/resolution.
5. **Desktop ergonomics:** the coloured bottom taskbar and top-right controls offer two-step graphical grid/position selection through 3×3, two-corner custom sizing and coarse placement with one-cell move arrows that disappear at boundaries. Resize and Move remain on the first level. The title stays at the left on contrasting neutral chrome. OS settings is in Start; app accents use a shared palette. The console controls remain available.
6. **Public-server trust:** packet IDs and a pinned OS ID filter accidental traffic. They are not cryptographic authentication. Wireless sniffing/spoofing remains possible.
7. **App state:** all views share app data; normal apps run until their last view closes, while declared services such as Coffee keep running with zero views. All app hooks run centrally, must return promptly without sleeping/yielding, and should store serializable data only.
8. **Settings UI:** menus/drafts are per window; applied configuration is persistent shared app state. The OS's reusable IO picker supplies client, side and Digital/bundled-colour choices. Output binding can checkpoint an initial OFF intent atomically with the mapping.
9. **Clock:** the earlier implementation waited for a sensor even though ComputerCraft's built-in `os.time()` exposes Minecraft time. The taskbar now uses that API and retains sensor fallback when it is unavailable.

## Validation limits

The Lua 5.1 test harness executes the real server, IO and monitor entry points against simulated APIs, including string-only modems and independent event queues/filesystems. It does not emulate the Minecraft world, Java/TLS support, a server's ComputerCraft configuration, wireless range or mod-specific sensor peripherals. Follow the README's one-wire test on the actual server before attaching production automation.

After the in-game UI report, tests now record actual foreground/background writes, reorder frames, replay/burst touches, drop render replies, exercise paging across announcements and suspend native drawing while a touch arrives. These reproduce missing transport/input safeguards and verify the new buffer/revision checks; they do not prove which condition caused every observed in-game click. A guided three-point calibration test also runs the real monitor entry point, saves an offset and verifies corrected coordinates after reboot. Physical hitbox alignment on the user's monitor still needs in-game measurement.

The subsequent calibration screenshot showed the old exact-match check exiting on a differing second tap. Bundled-v11 collects three samples and tolerates at most one cell of residual per axis around their median, keeping the ±3-cell correction limit. Tests cover the second differing tap reaching target three, ignored old-target repeats, Retry after disagreement, Cancel without replacing the previous offset, and failed-save recovery. Native expected/received coordinates are printed for further diagnosis.

Console tests execute the real main OS with cursor-recording terminals: connection logs arrive while editing a command in its middle, long drafts survive resizing, editing/history preserve drafts, clear keeps Coffee/window/output state and networking active, and quit saves and returns a clean cursor. The new editor reserves the bottom row instead of sharing a `read()` cursor with asynchronous messages. These checks run against simulated CC APIs, not the live Minecraft server.

Appearance/navigation tests run the real Start → OS settings → palette flow without enabling user apps, recover appearance and settings windows after reboot, roll back failed cosmetic saves, click diagram panes below their first row, and exercise move arrows/Place/OK at every boundary. A matrix of 512 Coffee page/size combinations checks row/style bounds, non-overlapping controls, unique menu paths and parent Back/Cancel navigation, including three-digit hours in the graphical clock. Another matrix checks 420 monitor/grid combinations and every popup page; 3×3 panes cover odd-sized workspaces exactly and restore across resolution changes/reboots. A raster check verifies swapped clock colours, unchanged double-size pixels and clearing old digit shapes through the real bridge. The user confirmed that the earlier countdown was correct; the clock change is visual only. This does not substitute for an in-game visual/input check.

After an in-game screenshot exposed the public server's `[IDT-Fix]` 0.5-second redstone limit, the harness gained a shared per-port write cooldown that reproduces that startup failure. IO now skips unchanged writes and queues changes with a default 0.6-second interval, acknowledging only fully applied snapshots. This tests the observed rule, not the complete server modification.

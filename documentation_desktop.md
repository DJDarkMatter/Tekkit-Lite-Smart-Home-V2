# Monitor desktops and windows

The main OS owns all window positions, taskbars, menus and hit testing. Monitor clients relay touches and render addressed colour frames. Each monitor has an independent desktop and a taskbar on its bottom row. Advanced monitors show filled panels, coloured title bars/buttons and wire swatches through CC 1.5's character-cell foreground/background API. Standard monitors receive a monochrome fallback.

For this bundled-v8 UI, install the new `server` and `monitor` roles using the same installer paste. Update Coffee from its current GitHub file too. A successful OS role install extracts embedded files and does not test GitHub connectivity; app installation makes a separate GitHub request.

## Taskbar

- `[+]` opens the app launcher. It shows only apps whose smallest layout fits this monitor. A `*` beside an app means it is running.
- Each local window has a taskbar button. Clicking it restores/focuses that view; clicking the already-active view minimizes it.
- `<` and `>` scroll through overflowing buttons. Button order follows window creation, so focusing does not shuffle them. Scroll position is saved per monitor.
- The Minecraft clock appears on the right when space permits. Narrow monitors prioritize accessible window buttons.
- Minimizing leaves the view open and its app running.

## Three title-bar buttons

The title begins at the far left. The buttons are at the far right: `-`, `+`, `X`.

| Control | Behavior |
| --- | --- |
| `-` | Minimize this view. Restore it through its taskbar button. |
| `+` | Open the layout menu beside the controls: Maximize, Restore, halves, quarters, Custom area, Move and Cancel. |
| Red `X` | Close only this view. Ordinary apps stop when their last view closes, across all monitors. Background services such as Coffee keep running with zero views. |

The launcher focuses an existing view on this monitor if one is already open. Other monitors' views are unaffected. Closing a switchboard-like UI retains existing logical output states; an app's optional shutdown hook can define additional behavior.

## Layout presets

Presets divide this monitor's usable character area, excluding its taskbar. They are not fixed pixel/block sizes. Odd dimensions are divided without gaps, with the extra row/column in the bottom/right half.

The menu marks incompatible presets with `-`; selecting them does not alter the window. App minimum/maximum content sizes are respected. Apps that support full maximization should use preferred sizes rather than a restrictive maximum. Coffee has a preferred initial size and can fill larger screens.

Restore returns to the previous layout/free rectangle. Repeating the current preset does not overwrite the restore target.

## Custom size and position

1. Open the title-bar `+` and select `Custom area`.
2. Click one corner of the desired window, then its opposite corner.
3. Inspect the outline and size. Click `[OK]` on the bottom row to apply, or `[Cancel]` to keep the old layout.

An undersized selection is rejected. You can choose a different second corner before applying. These touches are captured by the OS and do not activate app buttons underneath. App background work continues throughout placement.

For moving without resizing, choose `Move`, or click the title text at the left. Click the destination for its top-left corner, then OK. The window is constrained to the desktop and cannot cover the taskbar.

## Different monitor/window sizes

Apps receive their current content width/height and render the appropriate layout. Coffee uses:

| View | Content |
| --- | --- |
| Compact: width below 24 or height below 9 | Countdown, status and Menu. Menu provides Pause/Resume, Harvest now, Settings and Stats. |
| Standard | Adds directly visible controls, player status and harvest counts. |
| Detailed: width at least 36 and height at least 11 | Adds configured durations and wiring summaries as space permits. |

All views of Coffee share one timer. Resizing, hiding, moving, closing or reopening a view does not reset it. Each view has independent temporary menus/settings drafts.

Snap modes are recalculated after resolution/text-scale changes. Free rectangles retain relative coordinates, with app size limits applied. The bridge polls resolution once a second so older CC versions do not need `monitor_resize` events.

## Touch reliability and calibration

The renderer and hit tester use the same title-button rectangles. App content starts at `(window.x + 1, window.y + 1)`, and both drawing and touches use that origin. Coloured button backgrounds show the full clickable character cell, including padding.

Each new frame has an increasing ID. A monitor discards older frames; an input revision prevents an old/duplicate tap from advancing a page twice or activating a control on a changed screen. Stale touches request a fresh frame so a lost reply does not leave the UI waiting for the next announcement. The monitor buffers input/modem events during yielding peripheral operations, retaining the revision visible when each touch arrived.

For a physical/native coordinate offset, stop the bridge with Ctrl+T and run `clients_monitor_client calibrate [side]`. With one monitor, omit the side. Tap the centre of each of three white `+` targets and reboot. All three must agree on the same offset (at most three cells); otherwise nothing is saved. Offsets are per monitor side in `configs_monitor.txt` under `touchOffsets`, and are applied before forwarding coordinates. Repeat after a text-scale change if necessary. Calibration does not alter app state or window positions.

## Persistence and app lifecycle

Window geometry, snap mode, restore target, ordering, minimized state, and per-monitor taskbar scroll are saved. Successful layout actions commit immediately; the OS also checkpoints all app/window state at least once a second while running. Placement previews and unapplied settings drafts are transient.

Old top-taskbar window positions are migrated once to the new workspace origin. Restored ordinary-app views start their app once at OS boot; an ordinary app with no saved views stays stopped until opened. `backgroundService = true` apps, and apps without any render hook, start automatically when explicitly enabled. Coffee declares this flag.

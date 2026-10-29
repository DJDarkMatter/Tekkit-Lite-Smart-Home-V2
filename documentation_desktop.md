# Monitor desktops and windows

The main OS owns all window positions, taskbars, menus and hit testing. Monitor clients relay touches and render addressed character frames. Each monitor has an independent desktop and a taskbar on its bottom row.

## Taskbar

- `[+]` opens the app launcher. It shows only apps whose smallest layout fits this monitor. A `*` beside an app means it is running.
- Each local window has a taskbar button. Clicking it restores/focuses that view; clicking the already-active view minimizes it.
- `<` and `>` scroll through overflowing buttons. Button order follows window creation, so focusing does not shuffle them. Scroll position is saved per monitor.
- The Minecraft clock appears on the right when space permits. Narrow monitors prioritize accessible window buttons.
- Minimizing leaves the view open and its app running.

## Three title-bar buttons

The buttons are at the top left: `[X][#][_]`.

| Control | Behavior |
| --- | --- |
| `[X]` | Close only this view. Ordinary apps stop when their last view closes, across all monitors. Background services such as Coffee keep running with zero views. |
| `[#]` | Open the layout menu: Maximize, Restore, halves, quarters, Custom area, Move and Cancel. |
| `[_]` | Minimize this view. Restore it through its taskbar button. |

The launcher focuses an existing view on this monitor if one is already open. Other monitors' views are unaffected. Closing a switchboard-like UI retains existing logical output states; an app's optional shutdown hook can define additional behavior.

## Layout presets

Presets divide this monitor's usable character area, excluding its taskbar. They are not fixed pixel/block sizes. Odd dimensions are divided without gaps, with the extra row/column in the bottom/right half.

The menu marks incompatible presets with `-`; selecting them does not alter the window. App minimum/maximum content sizes are respected. Apps that support full maximization should use preferred sizes rather than a restrictive maximum. Coffee has a preferred initial size and can fill larger screens.

Restore returns to the previous layout/free rectangle. Repeating the current preset does not overwrite the restore target.

## Custom size and position

1. Open `[#]` and select `Custom area`.
2. Click one corner of the desired window, then its opposite corner.
3. Inspect the outline and size. Click `[OK]` on the bottom row to apply, or `[Cancel]` to keep the old layout.

An undersized selection is rejected. You can choose a different second corner before applying. These touches are captured by the OS and do not activate app buttons underneath. App background work continues throughout placement.

For moving without resizing, choose `Move`, or click the title text after the three buttons. Click the destination for its top-left corner, then OK. The window is constrained to the desktop and cannot cover the taskbar.

## Different monitor/window sizes

Apps receive their current content width/height and render the appropriate layout. Coffee uses:

| View | Content |
| --- | --- |
| Compact: width below 24 or height below 9 | Countdown, status and Menu. Menu provides Pause/Resume, Harvest now, Settings and Stats. |
| Standard | Adds directly visible controls, player status and harvest counts. |
| Detailed: width at least 36 and height at least 11 | Adds configured durations and wiring summaries as space permits. |

All views of Coffee share one timer. Resizing, hiding, moving, closing or reopening a view does not reset it. Each view has independent temporary menus/settings drafts.

Snap modes are recalculated after resolution/text-scale changes. Free rectangles retain relative coordinates, with app size limits applied. The bridge polls resolution once a second so older CC versions do not need `monitor_resize` events.

## Persistence and app lifecycle

Window geometry, snap mode, restore target, ordering, minimized state, and per-monitor taskbar scroll are saved. Successful layout actions commit immediately; the OS also checkpoints all app/window state at least once a second while running. Placement previews and unapplied settings drafts are transient.

Old top-taskbar window positions are migrated once to the new workspace origin. Restored ordinary-app views start their app once at OS boot; an ordinary app with no saved views stays stopped until opened. `backgroundService = true` apps, and apps without any render hook, start automatically when explicitly enabled. Coffee declares this flag.

# Monitor desktops and windows

The main OS owns all window positions, taskbars, menus and hit testing. Monitor clients relay touches and render addressed colour frames. Each monitor has an independent desktop and a taskbar on its bottom row. Advanced monitors show filled panels, coloured title bars/buttons and wire swatches through CC 1.5's character-cell foreground/background API. Standard monitors receive a monochrome fallback.

For this bundled-v10 UI, update the `server` role and Coffee using the same installer paste. Existing bundled-v8 monitor bridges remain compatible. A successful OS role install extracts embedded files and does not test GitHub connectivity; app installation makes a separate GitHub request, using the confirmed working API route first.

## Desktop appearance and OS settings

The background contains no branding text. `[+]` → **OS settings** opens the built-in Appearance window, including before any user apps are installed. Choose Background, then a swatch to save a static colour for all monitor desktops. A graphical screensaver is a future extension. Appearance preferences are checkpointed centrally; they do not alter app timers, IO wiring or enabled-app choices.

Window title bars use neutral colours and remain distinct from the desktop, including when the user selects gray. App accents are independent of the desktop and window chrome. Coffee offers **Menu → Settings → UI colour**; future apps should use the same OS-owned palette.

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
| `+` | Open graphical grid choices, then select a position. Restore, Resize, Move and Cancel stay on the first screen. |
| Red `X` | Close only this view. Ordinary apps stop when their last view closes, across all monitors. Background services such as Coffee keep running with zero views. |

The launcher focuses an existing view on this monitor if one is already open. Other monitors' views are unaffected. Closing a switchboard-like UI retains existing logical output states; an app's optional shutdown hook can define additional behavior.

## Layout presets

Presets divide this monitor's usable character area, excluding its taskbar. First choose a graphical **1×1**, **2×1**, **1×2**, **2×2**, **3×1**, **1×3**, **3×2**, **2×3** or **3×3** grid (columns × rows). This opens a separate diagram with numbered panes; tap the position you want. Choosing the grid alone never moves/resizes the window. Back returns to the grid choices; Cancel dismisses the flyout.

Incompatible panes are gray; selecting them does not alter the window. Grids with no compatible position are disabled. Narrow/short screens paginate cards; very short screens use a compact text list. Odd dimensions are partitioned using shared boundaries, so panes cover the usable area without gaps or overlap. App minimum/maximum content sizes are respected, including for every 3×3 pane. Coffee has a preferred initial size and can fill larger screens.

Restore returns to the previous layout/free rectangle. Repeating the current preset does not overwrite the restore target.

## Custom size and position

1. Open the title-bar `+` and select `Resize` on its first screen.
2. Click one corner of the desired window, then its opposite corner.
3. Inspect the outline and size. Click `[OK]` on the bottom row to apply, or `[Cancel]` to keep the old layout.

An undersized selection is rejected. You can choose a different second corner before applying. These touches are captured by the OS and do not activate app buttons underneath. App background work continues throughout placement.

For moving without resizing, choose `Move`, or click the title text at the left. Click a coarse destination for the top-left corner. The green preview then has one-cell arrow controls on its sides. Each arrow disappears when its side touches the workspace boundary; the bottom taskbar is excluded. Once placed, other desktop clicks do not jump the preview. Use **Place** at the top right to pick another coarse position. **OK** commits the preview; **Cancel** keeps the old window. Moving never changes size.

## Different monitor/window sizes

Apps receive their current content width/height and render the appropriate layout. Coffee uses:

| View | Content |
| --- | --- |
| Every supported size, starting at 12×6 content | Phase heading, remaining time, status, Pause/Resume, Harvest now and Menu. |
| Width at least 36, height at least 8 | Places the three main controls in a single bottom row; narrower windows use three rows. |
| Width at least 32, height at least 14 | Keeps the original graphical clock font, dimensions and scaling, with its two colours swapped: light digits on the app accent (white on blue by default). Doubles scale at height 20+ when the complete time fits at double width. |
| Remaining information area | Shows player presence and harvest counts, side by side when space permits. Wiring and configured durations stay in Settings. |

Coffee uses a dark content panel with a distinct accent header and spaced controls. Menu has exactly three destinations: **Settings**, **Stats**, **Maintenance**. Settings has player input, harvest output, countdown, harvest time and UI colour; wide settings menus show configured durations in their labels. Stats owns the trip reset. Maintenance owns timer reset and legacy import, with confirmation. Each submenu's Back/Cancel returns to its parent. Pagination is shown only when needed; changing width/height never resets progress or applies an unsaved duration draft.

All views of Coffee share one timer. Resizing, hiding, moving, closing or reopening a view does not reset it. Each view has independent temporary menus/settings drafts.

Snap modes are recalculated after resolution/text-scale changes. Free rectangles retain relative coordinates, with app size limits applied. The bridge polls resolution once a second so older CC versions do not need `monitor_resize` events.

## Touch reliability and calibration

The renderer and hit tester use the same title-button rectangles. App content starts at `(window.x + 1, window.y + 1)`, and both drawing and touches use that origin. Coloured button backgrounds show the full clickable character cell, including padding.

Each new frame has an increasing ID. A monitor discards older frames; an input revision prevents an old/duplicate tap from advancing a page twice or activating a control on a changed screen. Stale touches request a fresh frame so a lost reply does not leave the UI waiting for the next announcement. The monitor buffers input/modem events during yielding peripheral operations, retaining the revision visible when each touch arrived.

For a physical/native coordinate offset, stop the bridge with Ctrl+T and run `clients_monitor_client calibrate [side]`. With one monitor, omit the side. Tap the centre of each of three white `+` targets and reboot. All three must agree on the same offset (at most three cells); otherwise nothing is saved. Offsets are per monitor side in `configs_monitor.txt` under `touchOffsets`, and are applied before forwarding coordinates. Repeat after a text-scale change if necessary. Calibration does not alter app state or window positions.

## Persistence and app lifecycle

Window geometry, snap mode, restore target, ordering, minimized state, and per-monitor taskbar scroll are saved. Successful layout actions commit immediately; the OS also checkpoints all app/window state at least once a second while running. Placement previews and unapplied settings drafts are transient.

Old top-taskbar window positions are migrated once to the new workspace origin. Restored ordinary-app views start their app once at OS boot; an ordinary app with no saved views stays stopped until opened. `backgroundService = true` apps, and apps without any render hook, start automatically when explicitly enabled. Coffee declares this flag.

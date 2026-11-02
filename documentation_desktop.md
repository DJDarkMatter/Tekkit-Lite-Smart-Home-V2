# Monitor desktops and windows

The main OS owns all window positions, taskbars, menus and hit testing. Monitor clients relay touches and render addressed colour frames. Each monitor has an independent desktop and a taskbar on its bottom row while using framed windows. Advanced monitors show filled panels, coloured title bars/buttons and wire swatches through CC 1.5's character-cell foreground/background API. Standard monitors receive a monochrome fallback.

Bundled-v27 updates the `server` role for the `#` control, per-corner nudges and fullscreen. Update Coffee separately for its denser compact view. Existing monitor bridges remain compatible with the display frames. Role installation extracts embedded files without GitHub requests; optional app installation uses the confirmed working API route first.

## Desktop appearance and OS settings

The background contains no branding text. `[+]` → **OS settings** opens the built-in Appearance window, including before any user apps are installed. It contains **Background**, **Window border** and **Taskbar** colour controls. Choose one, then a swatch to save its colour across every monitor. Window border colours the complete frame and title bar of every window, including OS settings; Close remains red. A graphical screensaver is a future extension. Appearance preferences are checkpointed centrally; they do not alter app timers, IO wiring or enabled-app choices.

Window borders and the taskbar default to gray. Text switches between white and black for contrast; the selected taskbar button and open launcher use an inverted highlight. A selected border colour is honoured even if it matches the desktop. App accents remain independent: Coffee offers **Menu → Settings → UI colour**, and future apps should use the same OS-owned palette. The taskbar remains exactly one row high, with its text and hit regions at their previous positions; no row padding or vertical shift is applied.

## Taskbar

- `[+]` opens the app launcher. It shows only apps whose smallest layout fits this monitor. A `*` beside an app means it is running.
- Each local window has a taskbar button. Clicking it restores/focuses that view; clicking the already-active view minimizes it.
- `<` and `>` scroll through overflowing buttons. Button order follows window creation, so focusing does not shuffle them. Scroll position is saved per monitor.
- The Minecraft clock appears on the right when space permits. Narrow monitors prioritize accessible window buttons.
- Minimizing leaves the view open and its app running.

## Three title-bar buttons

The title begins at the far left. The buttons are at the far right: `-`, `#`, `X`.

| Control | Behavior |
| --- | --- |
| `-` | Minimize this view. Restore it through its taskbar button. |
| `#` | Open graphical grid choices, then select a position. Fullscreen, Restore, Resize, Move and Cancel stay on the first screen. |
| Red `X` | Close only this view. Ordinary apps stop when their last view closes, across all monitors. Background services such as Coffee keep running with zero views. |

The launcher focuses an existing view on this monitor if one is already open. Other monitors' views are unaffected. Closing a switchboard-like UI retains existing logical output states; an app's optional shutdown hook can define additional behavior.

## Layout presets

Presets divide this monitor's usable character area, excluding its taskbar. First choose a graphical **1×1**, **2×1**, **1×2**, **2×2**, **3×1**, **1×3**, **3×2**, **2×3** or **3×3** grid (columns × rows). This opens a separate diagram with numbered panes; tap the position you want. Choosing the grid alone never moves/resizes the window. Back returns to the grid choices; Cancel dismisses the flyout.

Incompatible panes are gray; selecting them does not alter the window. Grids with no compatible position are disabled. Narrow/short screens paginate cards; very short screens use a compact text list. Odd dimensions are partitioned using shared boundaries, so panes cover the usable area without gaps or overlap. App minimum/maximum content sizes are respected, including for every 3×3 pane. Coffee has a preferred initial size and can fill larger screens.

Restore returns to the previous layout/free rectangle. Repeating the current preset does not overwrite the restore target.

### Fullscreen (v27)

Choose **Fullscreen** on the layout menu's first screen. The app fills all character cells with its content; its title, frame and taskbar are hidden. Tap the very top-right character cell to restore the previous window. There is no exit button drawn over that cell. The tap is consumed by the OS, while other edge cells and the bottom row act as ordinary app content.

Each monitor keeps its own fullscreen selection. Other windows keep running behind it. Fullscreen, the previous snap/free layout and its restore target, and the app's selected page are saved centrally. Resolution changes recompute the full content size. If a monitor becomes too small for the app, an error view retains the top-right exit; the framed window becomes available again when the monitor is large enough. A failed exit checkpoint keeps fullscreen for retry. Alarm/timer popups retain priority over the exit tap until dismissed.

## Custom size and position

1. Open the title-bar `#` and select `Resize` on its first screen.
2. Tap the first corner. Use the arrow pad to nudge it one character at a time; `[OK]` fixes this corner.
3. Tap the opposite corner, nudge it with the same arrows, then `[OK]` applies the window.

The top line reports the active corner's coordinates; `+` marks each picked point. Arrows disappear at the monitor/workspace edges. The arrow pad stays put while a point is being nudged. **Place** repicks the current corner. An undersized selection is red and cannot be applied; adjust or repick the second corner. `[Cancel]` at either stage keeps the old window. The first confirmation never changes the live window. These touches are captured by the OS and do not activate app buttons underneath. App background work continues throughout placement.

For moving without resizing, choose `Move`, or click the title text at the left. Click a coarse destination for the top-left corner. The green preview then has one-cell arrow controls on its sides. Each arrow disappears when its side touches the workspace boundary; the bottom taskbar is excluded. Once placed, other desktop clicks do not jump the preview. Use **Place** at the top right to pick another coarse position. **OK** commits the preview; **Cancel** keeps the old window. Moving never changes size.

## Different monitor/window sizes

Apps receive their current content width/height and render the appropriate layout. Coffee uses:

| View | Content |
| --- | --- |
| Every supported size, starting at 12×6 content | Phase heading, remaining time, status, Pause/Resume, Harvest now and Menu. |
| Width at least 36, height at least 8 | Places the three main controls in a single bottom row; narrower windows use three rows. |
| At least nine rows before the bottom controls, and complete clock width plus four cells fits | Graphical clock with extra clock-background space beside its strokes, matching the chosen UI colour through both edges. Doubles scale at height 20+ only when that complete clock plus clearance fits; long hour counts can use the smaller size or normal text. |
| Remaining information area | Shows player presence and harvest counts when space permits. The compact Player: on/off line is included again in v22. Wiring and configured durations stay in Settings. |

Coffee uses a dark content panel with a distinct accent header and spaced controls. Menu has exactly three destinations: **Settings**, **Stats**, **Maintenance**. Settings has player input, harvest output, countdown, harvest time and UI colour; wide settings menus show configured durations in their labels. Stats owns the trip reset. Maintenance owns timer reset and legacy import, with confirmation. Each submenu's Back/Cancel returns to its parent. Pagination is shown only when needed; changing width/height never resets progress or applies an unsaved duration draft.

All views of Coffee share one timer. Resizing, hiding, moving, closing or reopening a view does not reset it. Each view has independent menus/settings drafts. The v21 OS checkpoints that per-window navigation, including Switchboard's selected board/page, alongside geometry, z order and minimized state. Temporary client loss/rejoin does not delete windows; an OS reboot restores the last successful checkpoint. After upgrading from an older version, select the desired board once so it can be saved. Selector overlays and live telemetry are rebuilt rather than treated as saved observations.

Snap modes are recalculated after resolution/text-scale changes. Free rectangles retain relative coordinates, with app size limits applied. The bridge polls resolution once a second so older CC versions do not need `monitor_resize` events.

## Text scale and individual elements

The monitor client defaults to `textScale = 0.5` in `configs_monitor.txt`; an existing configuration takes precedence. This setting applies to every monitor attached to that client. Increasing it by 0.5 would change the default from 0.5 to 1.0, roughly doubling character width and height, halving columns/rows and leaving about one quarter of the logical cells. Borders and rounding affect the exact dimensions. Apps would reflow/page more often and some small windows or grid positions would no longer fit. Larger physical cells/buttons may be easier to touch, but this cannot guarantee a repair for the observed player-position-dependent native hitbox offset. Saved calibration offsets are measured in cells and would need reassessing at a different scale.

Individual buttons, cards, bars and clocks can instead occupy more cells while the monitor scale stays fixed. Drawing and hit regions must use the same geometry. Native text has one scale for the entire monitor; differently sized text within one area needs custom glyphs drawn over multiple cells, as with Coffee's clock. Keeping ordinary text consistent and enlarging selected controls is possible without giving each element a different font. No text-scale, monitor, calibration or taskbar-coordinate changes are made in bundled-v18.

V21 keeps that scale/calibration behavior. The supplied 1×1 Coffee screenshot has roughly 13 content columns. Doubling the width of all eight HH:MM:SS characters would need at least 16, and the existing graphical font needs still more cells. The compact Player line is retained; removing it would not supply the missing columns. This update therefore retains the full readable text clock on that monitor; it does not enlarge the whole display or silently drop seconds.

## Touch reliability and calibration

The renderer and hit tester use the same title-button rectangles. Framed app content starts at `(window.x + 1, window.y + 1)`; fullscreen starts at monitor cell `(1,1)`. Drawing, styles, app touches and IO/sensor/colour pickers use the same content rectangle in either mode. Coloured button backgrounds show the full clickable character cell, including padding.

Each new frame has an increasing ID. A monitor discards older frames; an input revision prevents an old/duplicate tap from advancing a page twice or activating a control on a changed screen. Stale touches request a fresh frame so a lost reply does not leave the UI waiting for the next announcement. The monitor buffers input/modem events during yielding peripheral operations, retaining the revision visible when each touch arrived.

For a physical/native coordinate offset, stop the bridge with Ctrl+T, run `cd /`, then `clients_monitor_client.lua calibrate [side]`. Include `.lua`; with one monitor, omit the side. Tap the centre of all **nine circle targets**, distributed over three rows and three columns. A median is usable only when every sample is within one cell of it on each axis, and all measured corrections are within three cells. A nonzero proposal additionally needs at least 7/9 readings to agree on that axis; otherwise that axis starts at zero and the test screen flags mixed readings. The computer reports the fractional average as diagnostic information, not as a fractional correction. More samples reduce the influence of individual taps. Measure from your usual viewing position; if readings change with viewing position, one fixed correction may not suit every position.

Bundled-v12 then opens **Test before saving**. Tap the white targets: a green `X` shows a corrected hit on a target; a red `X` shows a miss. Use the on-screen arrows or the computer's arrow keys to adjust X/Y by one character cell. **Reset** (or `0`) proposes stock `X:0 Y:0`; **Save** (or `S`) applies it. `R` repeats measurement; Cancel/`C` preserves the previous offset. Touch events provide character coordinates, so fractional-pixel correction is not available through this interface.

To undo an overcorrection immediately, run `clients_monitor_client.lua calibrate right --reset`, substituting your monitor side. This explicitly saves zero without sampling. `clients_monitor_client.lua calibrate right --test` opens the live test with the current offset, without measuring again. Reset is also available during sampling or after rejected samples and takes you to the zero-offset test screen, where Save is required. Reboot after saving/resetting to resume the bridge.

If samples differ too much, Retry/Reset/Cancel appear on the monitor and the old offset remains unchanged. Taps far from the current target do not advance it. The computer prints each expected/received coordinate and correction. Save failures are reported without discarding the previous offset. Offsets are per monitor side in `configs_monitor.txt` under `touchOffsets`, and are applied before forwarding coordinates. Repeat after a text-scale change if necessary. Calibration does not alter app state or window positions.

## Persistence and app lifecycle

Window geometry, snap mode, restore target, fullscreen, ordering, minimized state, and per-monitor taskbar scroll are saved. Successful layout actions commit immediately; the OS also checkpoints all app/window state at least once a second while running. Corner/move placement previews are transient; app drafts follow the bounded per-window navigation checkpoint.

Old top-taskbar window positions are migrated once to the new workspace origin. Restored ordinary-app views start their app once at OS boot; an ordinary app with no saved views stays stopped until opened. `backgroundService = true` apps, and apps without any render hook, start automatically when explicitly enabled. Coffee declares this flag.

## Title spacing (v24)

Every window title begins one character to the right of the outer left edge. The right-hand Minimize, Layout and Close controls retain their positions; the title clips before them. This applies to user apps and built-in OS settings. Global text scale, calibration, taskbar rows and window geometry are unchanged.

## Alarm/timer popups (v25)

App notifications overlay a centred OK window on every monitor, above normal windows, menus and move/resize previews. Touches are modal and do not pass through to those surfaces. OK on one monitor acknowledges that occurrence for all monitors; the next queued occurrence, if any, then appears. Input revisions reject delayed taps from the old popup. Redstone dismissal closes it through the same saved Clock state transition. Popup rendering follows monitor size and does not modify saved desktop geometry, taskbar positions, global text scale or calibration.

# Switchboard

`apps_switchboard.lua` is an optional, single-file app for the central OS. The old standalone files are references only; their UI and local redstone loop are not used.

## Install

Put the current app and core files on the V2 repository's `main` branch. Replace your one installer paste with the current `install.lua` (banner **bundled-v18**), then download that paste again as `inst` on the **central OS computer**. Quit the running OS first. From the CraftOS shell:

```text
cd /
inst server --startup
inst app switchboard
reboot
```

The first command updates the central routing API. The second downloads only `apps_switchboard.lua` through the GitHub API, validates it and enables it. No separate app paste, monitor update or IO-client update is needed. Existing configuration and app/window state are preserved. An old downloaded `inst` must be replaced before running these commands.

Open **Switchboard** from the monitor's `[+]` launcher. It starts when opened; restored OS windows start it again after reboot. Closing one monitor's window leaves the others running. Closing the last window stops the UI; the OS keeps applying saved switch positions with no window open.

## Selection and adding views

Home contains saved view cards, one **+ Add view** control, and **Settings** at the bottom. With no views, a large Add tile takes their place. Cards page when needed and show their name and desired ON count. A newly created view is shown on the selection page containing it.

**+ Add view** offers **+ Empty view** alongside known IO clients. `+` before a client ID means online; `-` means offline. Choose a client, then an available computer-relative side. The modem side and disabled ports are excluded. Confirm creation to get all sixteen bundled colours in a 4×4 view. Previously unused wires start OFF. Already mapped wires adopt their current shared state, including wires referenced by other views, Coffee or console mappings. The entire preset is checked and saved as one operation; adding another view never resets an existing wire.

**Empty view** opens the grid editor. Adjust columns and rows independently from **1 through 16**: all 256 combinations, up to 256 switches per view. There can be up to 64 views. The miniature preview approximates very dense grids at character resolution. Empty switches have no route and cannot energize a wire.

## Switching and paging

Inside a view, coloured tiles fill the content area above **Back / Edit**. Bundled tiles retain their wire colour in both states. Their status strips show:

| Status | Meaning |
| --- | --- |
| ON / OFF | Desired state acknowledged by the IO client |
| ON ... / OFF ... | Saved intent awaiting acknowledgement |
| ON offline / OFF offline | Saved intent while the IO client is unavailable |
| SET IO | No route; touch to open this switch's editor |
| ROUTE! | Mapping missing or changed outside the app; reconnect through Routing |

Long labels shorten to fit, retaining the desired ON/OFF prefix. Acknowledgement confirms the IO computer's snapshot, not the connected machine's response.

Small content areas show fewer switches with **<**, page number and **>** navigation. A 13×7 content area displays a 2×2 page for a standard board; smaller supported areas can show fewer. The same rules apply to small physical monitors and resized OS windows. Preferred grid dimensions limit the visible columns/rows; pages follow saved row-major switch order. Every switch remains reachable, and resizing the OS window never deletes or rebinds anything.

Navigation and unfinished drafts are independent per OS window. Saved names, routes, order, colours and positions are shared. On restart, OS windows restore their geometry and Switchboard opens its selection screen.

## View settings

**Edit** offers:

- **Rename view**: touch keyboard, 32-character limit.
- **Edit switches**: paged grid in edit mode; selecting a tile opens Rename, Routing and Disconnect. Editing never toggles it. Switch names allow 24 characters.
- **Grid size**: preserves existing switch order, IDs, names and routes. New trailing cells are unbound. Shrinking requires confirmation and removes trailing references in one saved operation. An old wire turns OFF only if its last reference was removed. Changing shape while retaining cell count preserves every switch.
- **All OFF**: confirmed group action for this view.
- **Move earlier / Move later**: changes home-card order.
- **Delete view**: confirmed removal of its mappings. Shared switches in other views remain connected and retain their state; unused old wires turn OFF.

Routing uses **IO client → side → colour → Use** in the shared OS selector. Custom switches also support Digital/ordinary redstone, using the unwired tile colour. Changing a route removes this reference from the old wire, which clears only when its final reference is gone. The new route adopts the state of an existing wire, or starts OFF if unused. Re-selecting an unchanged valid route preserves its state. Disconnect requires confirmation. User labels survive rerouting; default labels follow the selected colour.

Duplicate routing is allowed: all references to the same client/side/colour share one desired state. A toggle or All OFF action updates every copy, including those on other monitors. An automated app such as Coffee can also change that shared wire during its normal operation. Open selectors detect switches changed/removed by another monitor; stale name/grid edits are rejected if their targets changed.

## Touch keyboard

Draft text appears above the keys and scrolls to the end. Large windows use spaced, staggered QWERTY rows. Small windows use paged letter tiles; tap **1/2** to change pages when present. **ABC → 123 → abc** cycles upper case, digits/punctuation and lower case. **Space**, **Del**, **Clear** (or **Clr**), **Save**, and **Cancel** (or **Back**) are separate controls. Blank/all-space names cannot be saved. Cancel retains the previous name. Input is through monitor touches, not typing at the monitor client's computer.

## App settings

Home → **Settings** offers **UI colour**, **Background**, **Button borders**, **Unwired tiles**, **Active colour**, **Inactive colour**, **Density** (Roomy/Compact), and confirmed **All switches OFF** across this app's views. Active/inactive colours control the status strips, preserving bundled tile identity. All OFF changes only wires referenced by these views; every other reference to those same wires updates too. Unrelated outputs remain untouched. Compact removes gaps and uses narrower tiles where space permits. App border colour affects internal controls, independently of OS window frames. Bundled switch fills always follow their wire colour. Text contrast adapts, and settings are shared/persistent. Every colour setting uses a draft palette with Apply/Cancel. At 24×15 content characters or larger, a sample panel appears below the swatches: its heading, background, borders, bundled ON tile and Digital OFF tile show all six settings. Selecting a swatch updates only this preview until Apply. Smaller windows keep the full palette and Apply/Cancel without the preview. Existing v13 settings gain active/inactive defaults without resetting views, routing or switch state.

## Persistence and IO timing

Views, grids, names, routes, order and app style live in `appStates.switchboard` inside `configs_os_state.txt`. Stable `switchboard_switch_ID` mappings and desired states live in the OS's `outputMap` and `outputs`. Removed IDs are not reused. Important edits and output intent save before any hardware command; failed saves roll back the complete edit. Aliases share state in the same checkpoint; removing a view is independent of turning a shared switch OFF. No legacy `redstoneState` data is imported automatically.

The app never writes redstone or drives monitor peripherals. It uses the existing client's 0.6-second per-side queue, shared Digital/bundled cooldown, unchanged-value suppression, coalescing, retries and acknowledgement. Offline touches still change saved intent; reconnection applies the latest value. Startup/timeout clearing follows existing `safeOff` settings. No code runs while its computer is unloaded.

Tests use simulated ComputerCraft Lua 5.1 with real app/OS/client entry points. They cover paging, both keyboards, cross-client routing, shared references with Coffee, restarts, failed saves and simultaneous windows. Tests also record intermediate repaints through routine announcements with deliberately lost health ACKs: known confirmation remains stable, while actual unacknowledged changes and real client restarts still show pending. In-game visual/touch behaviour still needs testing on the server. Coffee, calibration, desktop/taskbar geometry and client programs are unchanged in this update.

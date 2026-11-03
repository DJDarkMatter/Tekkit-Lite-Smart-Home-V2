# Switchboard

`apps_switchboard.lua` is an optional, single-file app for the central OS. The old standalone files are references only; their UI and local redstone loop are not used.

## Install

For the v33 app update on a bundled-v33 OS, put `apps_switchboard.lua` on the V2 repository's `main` branch. Quit the running OS on the **central computer**, then use your existing installer from CraftOS:

```text
cd /
inst app switchboard
reboot
```

This downloads only `apps_switchboard.lua` through the GitHub API, validates it and enables it. The v20 appearance feature needs no installer change. For v21 navigation restoration, update the central server role with a fresh bundled-v22 installer; the Switchboard app file itself is unchanged. Existing configuration and app/window state are preserved. A first installation needs the [current OS](README.md) and GitHub-capable `inst`; Switchboard requires the shared routing/UI APIs from bundled-v14 or newer.

Open **Switchboard** from the monitor's `[+]` launcher. It starts when opened; restored OS windows start it again after reboot. Closing one monitor's window leaves the others running. Closing the last window stops the UI; the OS keeps applying saved switch positions with no window open.

## Selection and adding views

Home contains saved view cards, one **+ Add view** control, and **Settings** at the bottom. With no views, a large Add tile takes their place. Cards page when needed and show their name and desired ON count. A newly created view is shown on the selection page containing it.

**+ Add view** offers **+ Empty view** alongside known IO clients. `+` before a client ID means online; `-` means offline. Choose a client, then an available computer-relative side. The modem side and disabled ports are excluded. Confirm creation to get all sixteen bundled colors in a 4×4 view. Previously unused wires start OFF. Already mapped wires adopt their current shared state, including wires referenced by other views, Coffee or console mappings. The entire preset is checked and saved as one operation; adding another view never resets an existing wire.

**Empty view** opens the grid editor. Adjust columns and rows independently from **1 through 16**: all 256 combinations, up to 256 switches per view. There can be up to 64 views. The miniature preview approximates very dense grids at character resolution. Empty switches have no route and cannot energize a wire.

## Switching and paging

Inside a view, colored tiles fill the content area above **Back / Edit**. Bundled tiles use their wire color in both states by default; each switch can optionally have its own appearance color. Their status strips show:

| Status | Meaning |
| --- | --- |
| ON / OFF | Desired state acknowledged by the IO client |
| ON ... / OFF ... | Saved intent awaiting acknowledgement |
| ON offline / OFF offline | Saved intent while the IO client is unavailable |
| SET IO | No route; touch to open this switch's editor |
| ROUTE! | Mapping missing or changed outside the app; reconnect through Routing |

Long labels shorten to fit, retaining the desired ON/OFF prefix. Acknowledgement confirms the IO computer's snapshot, not the connected machine's response.

Small content areas show fewer switches with **<**, page number and **>** navigation. A 13×7 content area displays a 2×2 page for a standard board; smaller supported areas can show fewer. The same rules apply to small physical monitors and resized OS windows. Preferred grid dimensions limit the visible columns/rows; pages follow saved row-major switch order. Every switch remains reachable, and resizing the OS window never deletes or rebinds anything.

Navigation and unfinished drafts are independent per OS window. Saved names, routes, order, colors and positions are shared. The v21 OS saves each window's selected view, page and navigation with its geometry. OS/monitor restarts, temporary disconnections and rejoining do not reset a saved board to the general overview. Select a board once after upgrading from older versions that did not save navigation; subsequent checkpoints restore it. Live IO state still comes from the clients.

## View settings

**Edit** offers:

- **Rename view**: touch keyboard, 32-character limit.
- **Edit switches**: paged grid in edit mode; selecting a tile opens Rename, Color, Routing and Disconnect. Editing never toggles it. Switch names allow 24 characters.
- **Grid size**: preserves existing switch order, IDs, names and routes. New trailing cells are unbound. Shrinking requires confirmation and removes trailing references in one saved operation. An old wire turns OFF only if its last reference was removed. Changing shape while retaining cell count preserves every switch.
- **All OFF**: confirmed group action for this view.
- **Move earlier / Move later**: changes home-card order.
- **Delete view**: confirmed removal of its mappings. Shared switches in other views remain connected and retain their state; unused old wires turn OFF.

Routing uses **IO client → side → color → Use** in the shared OS selector. Custom switches also support Digital/ordinary redstone, using the unwired tile color by default. Changing a route removes this reference from the old wire, which clears only when its final reference is gone. The new route adopts the state of an existing wire, or starts OFF if unused. Re-selecting an unchanged valid route preserves its state. Disconnect requires confirmation. User labels survive rerouting; default labels follow the selected color.

**Color** (or **Button color** in wide windows) opens a palette for that switch's tile fill. Select one of the sixteen colors, then **Apply** (**Save** on tiny windows). **Auto** (**IO default** on wide windows), followed by Apply, removes the override: bundled tiles follow their routed wire color; Digital and unconnected tiles follow the app's unwired color. Cancel/Back discards the draft. A sample of the actual switch appears below the swatches when at least 24×15 content characters fit. Active/inactive status strips keep their existing meanings and colors.

The editor continues to display the actual IO client, side and routed wire color, independently of the appearance selection. Changing appearance does not rename, reroute or toggle anything. Overrides survive rerouting, disconnecting, grid changes and restarts. They belong to each saved switch: two views can show the same wire in different colors, while every monitor displaying the same view sees its saved appearance. Concurrent color changes are checked before saving, and a stale draft cannot overwrite a newer selection from another window.

Duplicate routing is allowed: all references to the same client/side/color share one desired state. A toggle or All OFF action updates every copy, including those on other monitors. An automated app such as Coffee can also change that shared wire during its normal operation. Open selectors detect switches changed/removed by another monitor; stale name/grid edits are rejected if their targets changed.

## State colors and fill mode (v33)

Each **Active**, **Inactive** and **Pending** color resolves independently: **button override → view override → app setting**. App defaults are Lime, Gray and Orange. View settings → **State colors**, and an individual button’s **States** control, open the corresponding palettes. **Inherit** (or **Base** on small windows) removes only that field’s override, so future changes to its parent apply immediately. Pending also covers an offline/unconfirmed routed switch; the label still identifies offline or routing errors.

A button’s **Color** palette offers **IO default**, **By state**, or any fixed swatch. **By state** colors the whole tile according to its effective active/inactive/pending color. IO default keeps following the routed bundled color (or the unwired app color for Digital); fixed colors remain appearance-only. Status strips always use the effective state colors. All choices are drafts until Apply. The routing editor still shows the actual client, side and bundled wire color independently. Colors never change routes or outputs. Existing fixed fills and all routes migrate without being reset.

Large palettes preview ON, OFF and Pending states. Small windows retain all settings through paging. Concurrent changes to the same local field are rejected; failed saves restore the prior field and saved configuration.

## Touch keyboard

Draft text appears above the keys and scrolls to the end. Large windows use spaced, staggered QWERTY rows. Small windows use paged letter tiles; tap **1/2** to change pages when present. **ABC → 123 → abc** cycles upper case, digits/punctuation and lower case. Upper case is a one-letter Shift: after a capital letter is accepted, the keyboard returns to lower case. Spaces, digits and rejected input at the length limit do not consume Shift. **Space**, **Del**, **Clear** (or **Clr**), **Save**, and **Cancel** (or **Back**) are separate controls. Blank/all-space names cannot be saved. Cancel retains the previous name. Input is through monitor touches, not typing at the monitor client's computer.

## App settings

Home → **Settings** offers **UI color**, **Background**, **Button borders**, **Unwired tiles**, **Active color**, **Inactive color**, **Pending color**, **Density** (Roomy/Compact), and confirmed **All switches OFF** across this app's views. Active/inactive/pending colors provide the inherited defaults for status strips and By state fills. All OFF changes only wires referenced by these views; every other reference to those same wires updates too. Unrelated outputs remain untouched. Compact removes gaps and uses narrower tiles where space permits. App border color affects internal controls, independently of OS window frames. Bundled switch fills follow their wire color unless overridden in that switch's editor. Text contrast adapts, and settings are shared/persistent. Every color setting uses a draft palette with Apply/Cancel. At 24×15 content characters or larger, a sample panel below the swatches previews heading/background/borders and ON, OFF and Pending states. Selecting a swatch updates only this preview until Apply. Smaller windows keep the full palette and Apply/Cancel without the preview. Existing v13 settings gain active/inactive defaults without resetting views, routing or switch state.

## Persistence and IO timing

Views, grids, names, routes, order and app style live in `appStates.switchboard` inside `configs_os_state.txt`. A switch's optional `displayColour` is its fixed fill override; `fillMode="state"` selects state coloring. An absent fillMode/displayColour follows IO. Optional `stateColors` tables on buttons and views hold the three inherited fields. Saved legacy field names remain unchanged. Stable `switchboard_switch_ID` mappings and desired states live in the OS's `outputMap` and `outputs`. Removed IDs are not reused. Important edits and output intent save before any hardware command; failed saves roll back the complete edit. Aliases share state in the same checkpoint; removing a view is independent of turning a shared switch OFF. No legacy `redstoneState` data is imported automatically.

The app never writes redstone or drives monitor peripherals. It uses the existing client's 0.6-second per-side queue, shared Digital/bundled cooldown, unchanged-value suppression, coalescing, retries and acknowledgement. Offline touches still change saved intent; reconnection applies the latest value. Startup/timeout clearing follows existing `safeOff` settings. No code runs while its computer is unloaded.

Tests use simulated ComputerCraft Lua 5.1 with real app/OS/client entry points. They cover paging, both keyboards, cross-client routing, shared references with Coffee, restarts, failed saves and simultaneous windows. Tests also record intermediate repaints through routine announcements with deliberately lost health ACKs: known confirmation remains stable, while actual unacknowledged changes and real client restarts still show pending. In-game visual/touch behaviour still needs testing on the server. Hardware routing/cooldowns, monitor text scale and calibration are unaffected by these appearance choices.


## Confirmation behavior (v34 core update)

Toggling one switch marks only that physical IO client/side/color (or Digital) pending. Other switches keep their known status, including other colors on the same bundled cable. Copies sharing that exact route show pending together. A client restart/reconnect can still make all of its controls pending while restoration is acknowledged. This is provided by the central `lib_server.lua` update; this app file and the remote IO client are unchanged from v33. Full desired snapshots remain for recovery, but unchanged hardware values are not rewritten.

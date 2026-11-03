# ME item monitors (AE1, v24)

`apps_me_monitor.lua` is the second independent ME app. It displays live amounts for selected items in saved grids or lists, similar to clusters of AE storage monitors. It does not move items, craft, toggle redstone or depend on the capacity app's configuration.

## Install v24

Upload the complete v24 package's flat root files to GitHub, replace the one installer paste with the supplied bundled-v24 `install.lua`, download a fresh `inst` on the central OS, quit the OS and run:

```text
cd /
inst server
inst app me_storage
inst app me_monitor
reboot
```

This preserves startup, settings and saved views. v24 does not change any clients. AE sensor computers need v22 or newer for compact catalogs; when upgrading one older than v22, run `inst sensor --startup` and reboot it. Apps remain explicit GitHub downloads and are never bundled or enabled by a core role installation.

## Create a view

Open **ME monitors** from Start. Home shows saved view cards and **+ Add view**, with Settings at the bottom. With no views, one large Add tile is shown.

1. Choose **+ Add view**.
2. Select **AE sensor client → peripheral side → ME Wireless Access Point → Use**. You can reuse the same target already selected in ME storage, or select another ME network.
3. Touch **Grid / List** to choose the layout. Grid sets columns and rows independently from **1 to 16** (default 4×4); List sets **1–256 entries**. Then choose **Create**.
4. Touch an empty **+ Item** tile and choose the item to monitor.

Up to 64 named views can be saved. Each view has its own source, layout and item selections. **Edit → Rename view** uses a touch keyboard. The physical sensor computer can serve multiple apps/views; the OS deduplicates reads of the same client/side/target.

## Select and sort items

The picker shows both item names and current amounts. Wide windows put the amount at the right of each row; compact windows use a separate quantity row. All item quantities use complete decimal digits with spaces between thousands when they fit. There are no k/M/G suffixes or scientific notation.

- **Name / Amount** switches the sort key.
- **A-Z / Z-A** or **Low-Hi / Hi-Low** reverses the direction.
- **Search / Find** opens a paged touch keyboard and filters display names and raw item names. Apply an empty search to show all items again.
- **Refresh / Sync** rebuilds the current sorted/filtered list.
- Arrows page through results; Back preserves the existing tile selection.

Picker order is a snapshot taken when it opens or when Sort, Direction, Search or Refresh is used. Quantities keep updating, but changing stock cannot slide a different item under your tap. Newly appearing items are included after Refresh. The current search/sort/page are independent per OS window and are checkpointed by the OS. A restored picker keeps its page while waiting for the sensor catalog to return.

Bindings use the card's **raw item name and DamageValue**, not row positions or display names. Items with the same display name but different damage/metadata are shown with a `[damage]` suffix in the picker. The old card does not expose NBT: entries with identical exposed identity are combined, and the item details say when multiple variants were combined. The app cannot distinguish hidden NBT variants that the sensor does not identify.

## Viewing and editing tiles

Each tile shows its selected item name and amount. Names can wrap over two lines on roomy tiles; very long quantities wrap as plain digits when needed. Small windows page through a subset of the saved grid. Growing or resizing a window does not alter the grid or bindings. A complete live catalog in which an item is absent means **0**; unpowered/offline/waiting/stale/invalid data shows **--**, not zero. The heading also changes color when the source is unavailable.

Touch a configured tile for its full name, count, status, raw identity, damage and source. **Item** changes its selection, **Clear** unassigns it, and **Color** edits the tile/row appearance, and **Back** returns to the board. The palette has Apply, Auto and Back with a preview on larger windows. Auto restores the default grid fill or alternating list rows. Cosmetic changes preserve the real item identity and source. **Edit → Edit items** makes each tile open its picker directly for assigning several tiles. Repeating the same item in multiple tiles/views is allowed.

View settings also include **Layout / size**, **AE source**, **Source information** and confirmed **Delete view**. Changing a grid preserves existing tile IDs/order/selections; expanding adds unassigned tiles. Shrinking asks for confirmation before removing trailing tiles. IDs are never reused. Switching Grid/List retains tile IDs, bindings and colors. A list whose length does not exactly fit a rectangular grid expands with empty tiles; shrinking always confirms removal. Source changes preserve item identities and read their amounts from the newly selected network. Deleting views or clearing tiles removes only saved display bindings.

App Settings offers **UI color**, Roomy/Compact density and About. Colors use the shared OS palette. Input rectangles and rendering share geometry, and structural edits invalidate stale touches on other monitors.

## Shared sensor data and bounds

The v22 `ae_items` subscription projects the native item maps to a compact representation, preserving RawName, DamageValue, Name and Size. Native network capacity counters accompany it so the first ME app can share that physical target. Default raw readers still take priority, followed by item readers, then storage-only readers. Closing the last item-monitor window releases its watches; a capacity window on the same source continues using its summary subscription.

Item catalogs are normally polled about every two seconds. Identical snapshots use the existing exact-base heartbeat mechanism. Full catalogs have at most **8,192 entries**, **60,000 cleaned values**, and **64 × 12,000-character chunks**. Legacy/default and storage-only readings retain their smaller limits. Oversized/invalid readings report an error rather than silently dropping rows. The hub assembles complete snapshots and validates their profile/sequence; lost chunks cannot publish a partial item list as missing stock or zero. Relay frames retain their existing per-packet limit, so relay firmware is unchanged.

The capacity app requests only summary fields from the hub even when an item subscriber is present; it need not copy the whole catalog just to show byte totals. Other apps keep independent saved configuration and can reuse these clients without being merged.

## Persistence and restart behavior

Views, grid/list shapes, per-item colors, source addresses, names and item identities are saved in `appStates.me_monitor` inside `configs_os_state.txt`. Quantities and catalogs remain runtime-only. Existing per-window OS checkpoints restore the selected view/page, search/sort and small UI drafts after reboot. Fresh data must arrive again before a quantity is shown as live. Save failures roll back edits; deleting an entry from another monitor safely closes its stale editor. Minimized/covered windows keep the app running; closing its last window stops its subscriptions.

V22 also restores Coffee's compact player line, keeps its digit clearance in the selected clock background color, removes Cells surveyed from the capacity dashboard, and formats capacity counters/percentages without legacy floating-point formatting. The optional drive survey remains available under Cells.

Tests exercise the real app/OS/sensor/monitor entry points with simulated Lua 5.1, including a 4,000-entry catalog, dropped fragments, shared subscriptions, failed saves, both sort directions, search, stable taps, variant identity, window restoration and a grid/list/color screen-size matrix. Minecraft's actual graphics/touch behavior still needs in-game use.

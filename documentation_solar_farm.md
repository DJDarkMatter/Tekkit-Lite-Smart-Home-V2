# Solar farm overview

`apps_solar_farm.lua` is the optional `solar_farm` app. Its overview combines farm-ME amounts with **farm-ME net stock-change rates**. Only **HV solar** uses main-ME stock/rate data; it starts pinned with **Stick** enabled. You can turn Stick off or unpin it. No other main-ME item is listed. If HV panels are also in the farm, their farm amount/rate is a separate row labelled `(farm)`; it is not replaced by the main output amount. Machinery control, recipes and direct SMF output measurement remain external.

## Update from v31

Upload the complete v32 ZIP contents to GitHub, then stop the central OS and run `cd /`, `inst app solar_farm`, `reboot` with the existing bundled-v31 installer. This is an app-only update: no new Pastebin paste, core/client or other app update is needed. All 75 root files remain in the full release. Earlier installations still need the v31 shared-helper repair below.

## Update from v30

The v31 release fixes a LuaJ 2.0.3 frontier-pattern crash in the HV detector. Because Main was checked before Farm, it could stop all farm reads and crash the HV picker even with correct source selections. Native Lua 5.1 did not expose that interpreter-specific bug. The matcher now avoids frontier patterns, sources fail independently, and errors are visible.

Upload the full v31 package to GitHub, replace/download the one installer paste with bundled-v31, then stop the central OS and run `cd /`, `inst server`, `inst app solar_farm`, `reboot`. Updating only the app leaves the old shared helper installed; the app now detects that and requests the core update clearly. Existing clients and other apps need no reinstall from v30. Sources, pins, Stick preferences and compatible history are retained.

## First installation / update from v29

Upload the **complete v31 package** to the V2 GitHub repository and replace/download your single Pastebin installer with this package's `install.lua` (banner **bundled-v31**). On the central computer, stop the OS with Ctrl+T, then install everything before rebooting:

```text
cd /
inst server
inst app level_emitter
inst app solar_farm
inst app screensaver
reboot
```

Existing monitor, IO, sensor and relay clients need no update for v31. `inst server` preserves the existing startup; add `--startup` if you need to create it. Role installation still bundles no user apps. Apps are explicit GitHub downloads through the contents API, with raw download as a fallback.

Old Solar farm alarms move automatically into **Level emitter**, with selected ME targets, item identities, names, signal/dismiss routes, pending popups and signal progress. Level emitter keeps each original logical output name so the upgrade does not disconnect an active signal. Both app namespaces checkpoint together; a failed migration save retains the old records. Rebooting again does not import duplicates. Solar farm refuses to replace a v29 state that still contains alarms until Level emitter is installed. Do not uninstall/disable Level emitter while it owns alarms you need.

The main/farm source selections and pin appearance/filter settings survive. Existing HV pins become the fixed HV row. Other old pins become farm pins when the item is observed in the farm; main-only pins remain hidden. Old main-based histories are reset because they no longer measure the same source. The separate Level emitter catalog retains registered absent identities where capacity permits.

## Overview and menu

Choose **Menu → ME sources**, then select each sensor client → peripheral side → AE Wireless Access Point target → Use. Sources can share a sensor computer/card with each other and the other ME apps. Selections are saved centrally.

The overview shows an amount and signed net rate for each farm item. The overview starts with Farm/Main status indicators, without the old blue navigation row. Compact windows abbreviate them as F/M. The indicators are read-only; use Menu → Source status for the exact selected addresses, counts, reading age and any error. A failed Main feed leaves Farm observations running, and vice versa. Known empty inventories and unknown/offline data are distinct. Larger windows use aligned Item / Amount / Avg rate columns; narrow windows use two rows per item. Default order puts pins first, then other items alphabetically. Click **Item** for A–Z or **Amount** for high-to-low; clicking the same heading again reverses it. Explicit column sorting orders all scrolling rows, including ordinary pins, while Stick keeps its chosen group above that order. Unknown amounts sort last. Names use displayed pin labels. Live amount sorting rebuilds touch revisions when row order changes. Menu → List sorting offers all directions and the default pinned order on small screens. Sorting is saved per window/monitor. Each pin has a **Stick: On/Off** setting. Sticky items stay above the scrolling rows; other pins scroll normally. HV starts pinned with Stick on and can be edited or unpinned just like the others. If a sticky group fills a small window, the group pages first so every item remains reachable. The footer has **Pin item / Menu**, or **previous / next / Pin item / Menu** when pagination is required. Quantities update live; amount-sorted views also reorder as their amounts change. Newly appearing item identities update the overview automatically.

Use **Pin item** on the overview or tap an item and choose Pin item. Up to 64 pins can have custom names, colors and withdrawal filters. Pinned/registered farm items remain visible when absent, showing zero only from a fresh complete farm inventory. **Find** searches names/RawNames, sorts Name/Amount both ways, refreshes the selector or registers an absent identity with RawName, damage and display name.

The menu contains ME sources, HV item selection, graph/change period, rate unit, list sorting, reset rate learning, withdrawal filter, UI color, source status and an explanation. Alarm controls live entirely in Level emitter. Picker search/sort state is isolated from the overview, which always includes the complete available farm list plus configured pins.

Medium windows add two summary cards: main-ME HV stock/net change and farm item totals/type counts, plus byte usage when the sensor provides it. Larger windows add rising/falling item counts over the selected window, a Change column and an HV net-rate history plot. Lime bars are positive, orange negative, light-gray bars observed zero, and dark portions have no measured interval. These are past net observations; no crafting/transport conditions or gross SMF production are inferred. Tiny windows prioritise the item list.

HV solar is selected automatically when exactly one current main-ME item clearly identifies itself as HV/high-voltage solar. If it is absent, ambiguous or named differently, use **Menu → HV panel type / detection** and select/register its precise identity. The picker explains that this is the main-ME output item, offers **Auto**, and accepts exact manual registration under Find. Explicit selections are saved; Auto keeps an already identified type through temporary absence. Older saved selections are preserved rather than guessed again. HV setup can change its name, color, withdrawal filter and Stick preference. Unpinning returns it to the ordinary list; Pin item can pin it again. Its amount/rate still comes from the main ME.

## What rates measure

**Avg rate is the cumulative learned net rate:** total accepted signed stock change divided by total accepted observed seconds, converted to per second/minute/hour. Data keeps contributing across restarts; it no longer falls out of a 15-minute window. With stationary production arriving in batches, endpoint/batch noise becomes smaller relative to the growing observation period. The HV card shows the learned duration. v31's retained history seeds the initial cumulative ledger; older measurements that v31 already discarded cannot be reconstructed.

This converges to the **observed average net inflow**, not an unknowable gross production count. Consumption, transfers, player deposits or real production changes affect stock. Missing intervals cannot be reconstructed. A long-term estimate adapts more slowly after a real production change; use **Menu → Reset rate learning** to restart Main/HV, Farm or both. The action asks for confirmation and keeps source bindings, pins, colors and recent change history. Reselecting/rescanning the same HV identity preserves learning. A different source or HV identity starts a separate baseline.

The **Graph/change** period selects 5/15/60 minutes for the recent change column, movement counts and graph span. It never resets or truncates learned rates. Item details show both the long-term estimate/duration and the recent-window change/rate/duration.

A downward movement is excluded only if it meets **both** the minimum count (default 64) and percentage of preceding stock (default 5%). That item receives neither the interval's delta nor its time; the new quantity immediately becomes its next baseline. Other items keep their valid coverage. This is the configured player-withdrawal assumption, not proof of who moved items.

A missing item in a fresh complete powered inventory is zero. Offline, unpowered, partial and malformed readings are unknown. Cached duplicates add no deltas or time. Sensor reboots, outages, gaps over ten seconds and OS restarts rebase the first reading without inventing the stock jump through the gap. Learned totals persist; live readings/baselines are runtime-only. The observation clock excludes OS downtime.

The learned ledger is sparse and bounded per source. It splits whole/fractional time and stores large whole-number totals as decimal strings beyond the old integer range, preventing LuaJ's number-to-string precision from repeatedly rounding a growing counter. If its budget fills, untracked changes become unknown rather than fabricated zero rates; Source status explains the limit. Main/HV uses one item counter. Recent deltas retain the existing bounded minute history.

## Finer HV curve

The large-screen graph stays **three character rows tall**, with **six logical height steps**: `.` is a half step and `|` is a full step. It plots saved cumulative HV estimates, auto-scaled to the displayed value range. The range is labelled where width permits. Positive values are lime, negative orange and observed zero gray; missing samples leave gaps.

Each character column is its own time bin instead of a one-minute-wide block. The heading reports seconds per column and the observed sample interval. Fresh native readings are typically two seconds apart; the renderer cannot create faster independent measurements. Recent points keep native sample spacing for 15 minutes, older points thin to ten-second spacing, and the saved curve is bounded to 1,024 points / one observed hour. Outages add gap markers rather than invented measurements. Graph resolution and sensor sampling are separate from the continuously accumulating learned duration.

Identity remains RawName plus DamageValue. Legacy AE1 does not expose NBT discrimination.

## Background operation

After explicit installation, tracking starts at OS boot without opening a window. Closing every Solar farm window leaves measurements running. Sources, pins, identities, settings, rate history and normal window navigation are checkpointed in `configs_os_state.txt`. All item alarms now belong to Level emitter. Solar farm makes **no output writes** and contains no machinery-control conditions.

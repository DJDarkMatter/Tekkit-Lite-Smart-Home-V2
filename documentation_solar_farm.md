# Solar farm overview

`apps_solar_farm.lua` is the optional `solar_farm` app. Its overview combines farm-ME amounts with **farm-ME net stock-change rates**. Only **HV solar** uses main-ME stock/rate data; it starts pinned with **Stick** enabled. You can turn Stick off or unpin it. No other main-ME item is listed. If HV panels are also in the farm, their farm amount/rate is a separate row labelled `(farm)`; it is not replaced by the main output amount. Machinery control, recipes and direct SMF output measurement remain external.

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

The overview shows an amount and signed net rate for each farm item. Source health is shown directly: compact windows use the header for a failed feed, and wider windows show Farm/Main status bars. Tap the header/status to inspect the exact selected addresses, counts, reading age and any error. A failed Main feed leaves Farm observations running, and vice versa. Known empty inventories and unknown/offline data are distinct. Larger windows use aligned Item / Amount / Net rate columns; narrow windows use two rows per item. Pinned items come first, then other items alphabetically. Each pin has a **Stick: On/Off** setting. Sticky items stay above the scrolling rows; other pins scroll normally. HV starts pinned with Stick on and can be edited or unpinned just like the others. If a sticky group fills a small window, the group pages first so every item remains reachable. The footer has **Pin item / Menu**, or **previous / next / Pin item / Menu** when pagination is required. Quantities update without reordering rows by changing amounts. Newly appearing item identities update the overview automatically.

Use **Pin item** on the overview or tap an item and choose Pin item. Up to 64 pins can have custom names, colours and withdrawal filters. Pinned/registered farm items remain visible when absent, showing zero only from a fresh complete farm inventory. **Find** searches names/RawNames, sorts Name/Amount both ways, refreshes the selector or registers an absent identity with RawName, damage and display name.

The menu contains ME sources, HV item selection, average window, rate unit, withdrawal filter, UI colour, source status and an explanation. Alarm controls live entirely in Level emitter. Picker search/sort state is isolated from the overview, which always includes the complete available farm list plus configured pins.

Medium windows add two summary cards: main-ME HV stock/net change and farm item totals/type counts, plus byte usage when the sensor provides it. Larger windows add rising/falling item counts over the selected window, a Change column and an HV net-rate history plot. Lime bars are positive, orange negative, light-gray bars observed zero, and dark portions have no measured interval. These are past net observations; no crafting/transport conditions or gross SMF production are inferred. Tiny windows prioritise the item list.

HV solar is selected automatically when exactly one current main-ME item clearly identifies itself as HV/high-voltage solar. If it is absent, ambiguous or named differently, use **Menu → HV panel type / detection** and select/register its precise identity. The picker explains that this is the main-ME output item, offers **Auto**, and accepts exact manual registration under Find. Explicit selections are saved; Auto keeps an already identified type through temporary absence. Older saved selections are preserved rather than guessed again. HV setup can change its name, colour, withdrawal filter and Stick preference. Unpinning returns it to the ordinary list; Pin item can pin it again. Its amount/rate still comes from the main ME.

## What rates measure

The default is a **15-minute observed-time average per real hour**; choose 5/15/60 minutes and per second/minute/hour in Menu. Each rate is accepted signed stock change divided by accepted sampled seconds, converted to the selected unit. Minute bucket boundaries make the rolling window approximate. Details report the observed seconds and excluded withdrawals. These are net inventory rates: simultaneous arrivals and consumption can cancel, and a player deposit can raise an estimate. They do not claim gross crafting throughput or convert intermediate items into recipe equivalents.

A downward movement is ignored only if it meets **both** the minimum item count (default 64) and percentage of preceding stock (default 5%). The next quantity becomes the baseline immediately, avoiding a false recovery spike. An excluded interval contributes neither delta nor sampled duration for that item. Unchanged fresh heartbeats contribute observed zero changes. Other items in that complete snapshot retain their valid coverage.

A missing item in a complete powered inventory is zero. Offline, unpowered, partial or malformed inventories are unknown. Duplicate cached samples add no time or stock changes. Sensor reboots, outages, gaps over ten seconds and OS restarts rebase the first fresh reading without counting the unobserved stock jump. Source changes reset that source's history. Inventories and comparison baselines are runtime-only; saved history is never treated as a fresh sensor reading.

History retains at most 60 minute buckets per ME, with a sparse item-key index and a conservative memory budget. Busy inventories shorten history when necessary; an overlarge interval is dropped rather than invented as zero. Source status reports a shortened history. Identity is RawName plus DamageValue; legacy AE1 does not expose NBT discrimination.

## Background operation

After explicit installation, tracking starts at OS boot without opening a window. Closing every Solar farm window leaves measurements running. Sources, pins, identities, settings, rate history and normal window navigation are checkpointed in `configs_os_state.txt`. All item alarms now belong to Level emitter. Solar farm makes **no output writes** and contains no machinery-control conditions.

# ME storage overview (AE1, Minecraft 1.4.7)

`apps_me_storage.lua` is the first of four independent ME apps. It reads storage capacity; it neither crafts nor changes items or outputs. The generic sensor clients can be shared by every app, with independent saved source selections. No ME app is installed by the OS role automatically.

## Install v24

Upload the complete package's root files to GitHub, replace the single installer paste with the supplied bundled-v24 `install.lua`, download a fresh `inst` on the central computer, quit the OS and run:

```text
cd /
inst server
inst app me_storage
reboot
```

Existing startup, settings and sources are retained. v24 requires no client updates. AE sensors must already have v21 or newer for summary counters, or v22 for shared ME item catalogs. Apps are still separate explicit downloads through the same installer.

## Required AE source

Attach a sensor peripheral with the **Applied Energistics Sensor Card** to a generic sensor client. Put it within the card's scan range of a powered **ME Wireless Access Point** connected to the ME network you want to inspect. This is AE1's access point, not an AE2 controller or a ComputerCraft wireless modem. The historical AE sensor discovers access points; pointing it only at a drive does not substitute for one.

Open **ME storage** from Start. Choose **+ Add system**, then **sensor client → peripheral side → access-point target → Use**. Nothing is selected automatically. Up to sixteen systems can be saved, including a separate solar ME network. Each entry has its own source and optional drive survey. Edit offers Rename, Change AE sensor, Source / exact figures, Drive inventories and confirmed removal. Names use a paged touch keyboard.

## Dashboard and exact counters

The dashboard uses two columns on wide windows, three on very wide windows, and paged cards on small ones.

The percentage heading reads **Usage 85.6%**, meaning the percentage of reported bytes in use. Connection/power/error messages replace Usage when the source is unavailable. The Usage label was introduced in v23; v24 adds the responsive totals below.

| Readout | Meaning |
| --- | --- |
| Bytes used | Native `UsedBytes` |
| Bytes free | Native `FreeBytes` |
| Total bytes / bar | Used + free; percentage of those reported bytes |
| Items stored | Native `UsedCount`, individual items rather than stacks |
| Item room* | Native `FreeCount`; reported room, not a guarantee for arbitrary new types |
| Item types | Native `UsedTypes`; unique available item identities |
| Free type slots | Native `FreeTypes`; remaining type slots reported by the storage array |

Eight items use one data byte, and item-type/cell overhead also consumes bytes. Consequently item counts and byte counts are different measurements. Unique network item types are not interchangeable with occupied per-cell type slots. The app does not invent a fixed maximum item count or deduce cell sizes from aggregate bytes. Native counters are Java integers; negative/invalid values are reported as unsupported data, not interpreted as zero capacity.

Counters use complete plain decimal digits, with spaces between thousands when they fit. Spaces are removed when needed; letter suffixes and scientific notation are never used. Percentages round to one decimal without legacy floating-point formatting. **Edit → Source / exact figures** wraps/pages the complete numbers, source address, status and sample age. Unpowered, waiting, stale, missing and offline readings are distinct; old samples are not marked live. An empty powered network can legitimately report zero. A missing counter remains Unavailable.

## Optional drive/cell survey

The native AE card reports network totals and item contents, but not a list of installed storage cells or their individual NBT fill data. For physical cell counts and kinds, add a separate **Inventory Sensor Card** in another sensor peripheral near the relevant ME drives/chests. It can share the same computer with the AE sensor, or use another sensor client. One inventory card may discover several nearby drives.

Inside the selected ME system choose **Cells → + Add drive**, then select its inventory client/side/drive target. Add each physical inventory once; duplicate addresses within the same survey are rejected. You select membership: this old API does not identify whether an inventory belongs to the same ME grid. Changing an entry to a different AE source clears its previous drive bindings to avoid silently assigning them to the new system.

This feature is optional. If you only want network used/free storage, keep using the existing AE source and leave the drive list empty. For a survey, use an additional sensor peripheral containing an Inventory Sensor Card; do not replace the AE card supplying the network totals. Both peripherals can attach to the same sensor computer, and one inventory card can discover several nearby drives. Select the side of that inventory peripheral in the app, followed by each drive target.

The survey counts recognizable standard **1k / 4k / 16k / 64k** cell items, their surveyed capacity, occupied/empty slots, unidentified items and live versus selected drive inventories. Standard sizes are recognized from reported item names/raw names. Unrecognized items remain unknown; localized/custom cell names may need a later adapter once their raw identifiers are available. Counts cover only the selected live inventories, not every drive automatically. Network capacity can include other storage that is outside the survey.

Select a drive, then a slot, for its item name, raw identity, count, identified tier and any explicitly supplied per-cell counters. **Native Inventory Cards do not report per-cell used/free bytes, item counts or type fill**, so these stay Unavailable. The app does not infer them from the item's damage/metadata. Empty cells still count as installed cells. Remove bindings through a confirmation screen; no items move and no physical drive is altered.

## Persistence and subscriptions

Systems, names, source addresses and drive bindings live in `appStates.me_storage` in `configs_os_state.txt`. The v21 OS additionally saves each window's navigation, selection, page and draft UI data. Restored windows keep their monitor, position, size and minimized state. After upgrading from a version that never saved navigation, select a desired view once; future checkpoints can then restore it.

Live sensor readings remain runtime-only and must arrive again after an OS/sensor restart. A normal ME storage app watches sources while at least one window exists, including minimized or covered windows. Closing its last window releases its own subscriptions. Other apps subscribed to the same target continue receiving it. A sensor has a bounded 128-target watch list; spread unusually large installations over multiple clients as needed.

`watchSensor(key, address, {profile="ae_storage"})` requests only native AE storage counters and identity/power fields. The sensor projects before cleaning/serializing, avoiding huge item tables. `ItemsOmitted=true` identifies these projected readings. A concurrent default/full subscriber upgrades the shared target to a full read; removing that subscriber returns to the summary profile. Each target is still polled once. A future stock-monitor app can therefore request the full item list without duplicating sensor computers or hard-wiring another app's configuration. Full item lists remain subject to the documented bounded reading size.

## Other ME apps: item monitors and Solar farm overview

The independent [ME monitors app](documentation_me_monitor.md) is implemented. V29 adds a separate [Solar farm overview](documentation_solar_farm.md), replacing the planned combined SMF/HV dashboard. It selects main and farm ME networks independently and shares their `ae_items` feeds with the existing apps. SMF-specific production measurement is outside its scope.

All farm items can be browsed, searched and sorted, and all main-ME items have stock-change speed estimates. Pin selected identities for saved history and responsive dashboard cards. Quantities are ordinary decimal numbers. Raw-name/damage bindings support arbitrary UU, solar tiers, minium or other items rather than a fixed product list; Manual item registers currently absent identities. Practical ComputerCraft memory/network/polling bounds still apply.

Rates use signed observed main-ME stock changes. Large downward jumps are treated as player withdrawals through adjustable absolute/percentage rules, excluded from the rate, and followed by a new baseline. The default requires both 64 items and 5 percent; individual pins may override it. Other changes are net additions/consumption. Opposing flows, player deposits and production hidden by withdrawals can affect estimates, so the UI does not call them gross production or per-SMF counts.

The all-item Main list uses a 30-second smoother. Pinned items retain bounded minute buckets and 5/15/60-minute observed-time averages, including accepted sampled duration and excluded-drop counts. Missing, incomplete or unpowered sources stay unknown; a missing item in a complete fresh catalog is zero. Repeated cache reads add no measured time, and boot/outage/sensor-session changes rebase without catching up through unobserved periods. Saved history is retained independently of live telemetry.

Existing Solar farm, HV farm and Use minium switches, the main-ME UU reserve threshold, formatted 1k cell limits, transport bus modes and every other operating condition remain outside the app. It observes items moving or remaining stationary. Absence of flow, a zero ingredient count or an intentional full buffer is not itself an error.

Buildup alarms are independently enabled per selected item and selected ME network, covering both main and farm. Item choice must support current items, previously learned identities and registering a sample/manual raw-name plus damage identity; an item need not currently be present. Persist identities/names without restoring historical quantities as live. A missing item in a valid complete live catalog means zero; unavailable/stale data stays unknown. Never-seen items require a supplied/learned identity rather than an invented full Minecraft item registry.

Alarms use configurable high thresholds, hold intervals and reset/hysteresis thresholds. They reuse Clock-style Constant/Pattern outputs (zero Constant length or Pattern total waits for dismissal), selected IO outputs and fresh-press dismissal inputs, durable queued OK popups and save-before-sync behaviour. Acknowledging an above-threshold episode must not immediately retrigger until the reset condition rearms it. No recipe/switch/control configuration is required for item threshold alarms.

The earlier SMF investigation is retained in the standalone sensor inspection command. Its basic IC2 energy/progress values and GUI/TAB nominal rates are not used by Solar farm. The current app writes only explicitly selected alarm outputs; it adds no SMF instrumentation or transfer-chest requirement.

## Primary version sources

- [OpenCCSensors 1.4.7 AE target discovery](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/AppliedEnergisticsSensor.java)
- [Native AE access-point counters and item fields](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/targets/appliedenergistics/WirelessTarget.java)
- [Native inventory slot fields; NBT disabled](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/helper/InventoryHelper.java)
- [Native IC2 mass-fabricator fields](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/targets/industrialcraft/MassFabTarget.java)

These are the pre-Minecraft-1.5 sources, not modern AE2 or CC:Tweaked APIs. Automated checks use simulated ComputerCraft Lua 5.1; live server sensor output, graphics and touch alignment still need in-game verification.

## Responsive counters and totals (v24)

Medium/compact windows show **Bytes used, Bytes free, Items stored, Item room, Item types, Free type slots**, with paging only if needed. This removes the old total card that pushed the final counter onto another page. A large window whose card capacity is at least nine adds **Total bytes**, **Total item storage*** and **Total types***. Very wide windows use three columns. The choice follows content width/height rather than physical monitor block count.

Total bytes is UsedBytes + FreeBytes. Total item storage is UsedCount + FreeCount, meaning currently stored items plus the card's reported headroom. New item types consume metadata overhead, so this is not a guaranteed arbitrary-item capacity. Total types is UsedTypes + FreeTypes: **unique stored identities plus reported free per-cell type slots**. The native counters do not expose occupied per-cell slots across duplicated item types, so this combined indicator is not the actual sum of every cell's physical type capacity. The asterisks refer to this distinction; **Edit → Source / exact figures** explains it in the app. Missing or overflowing terms make the derived total unavailable instead of inventing a number. All values use plain decimal digits.

Sensor and drive addresses are saved immediately when applied; app/window checkpoints retain them through restarts. Received counters and item catalogs are runtime observations and must be refreshed after boot.

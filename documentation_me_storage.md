# ME storage overview (AE1, Minecraft 1.4.7)

`apps_me_storage.lua` is the first of four independent ME apps. It reads storage capacity; it neither crafts nor changes items or outputs. The generic sensor clients can be shared by every app, with independent saved source selections. No ME app is installed by the OS role automatically.

## Install v22

Upload this package's flat root files to the V2 GitHub repository. Replace the one installer paste with `install.lua` (banner `bundled-v22`) and download a fresh `inst` on the computers being updated.

Quit the central OS to CraftOS, then run:

```text
cd /
inst server --startup
inst app coffee
inst app me_storage
reboot
```

Update only the sensor computer(s) serving these ME sources with the same fresh installer:

```text
inst sensor --startup
reboot
```

The sensor update adds a compact storage-summary profile, so a huge ME item list does not exceed the existing bounded reading/network limits. Other sensors, relays, IO and monitor clients remain compatible. Existing Switchboard and Reactors app files need no update for window navigation restoration. Saved IDs, bindings, timers and layouts are retained.

## Required AE source

Attach a sensor peripheral with the **Applied Energistics Sensor Card** to a generic sensor client. Put it within the card's scan range of a powered **ME Wireless Access Point** connected to the ME network you want to inspect. This is AE1's access point, not an AE2 controller or a ComputerCraft wireless modem. The historical AE sensor discovers access points; pointing it only at a drive does not substitute for one.

Open **ME storage** from Start. Choose **+ Add system**, then **sensor client → peripheral side → access-point target → Use**. Nothing is selected automatically. Up to sixteen systems can be saved, including a separate solar ME network. Each entry has its own source and optional drive survey. Edit offers Rename, Change AE sensor, Source / exact figures, Drive inventories and confirmed removal. Names use a paged touch keyboard.

## Dashboard and exact counters

The dashboard uses two columns on wide windows and paged cards on small ones.

The percentage heading reads **Usage 85.6%**, meaning the percentage of reported bytes in use. Connection/power/error messages replace Usage when the source is unavailable. This v23 label update needs only `inst app me_storage` and an OS restart; the bundled-v22 installer and all clients remain compatible.

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

## Other ME apps: item monitors implemented, production planned

1. **Item stock monitors:** implemented as the independent [ME monitors app](documentation_me_monitor.md) in v22, with saved grids, per-tile selection, four sort modes and search. It shares this app's sensor target while keeping separate configuration. A stock value remains a snapshot, not a production counter.
2. **SMF production:** a separate app with an entry per mass fabricator/product. The old IC2 card exposes native Energy, MaxEnergy and Progress; it does not expose your server plugin's levels, upgrades or cumulative custom products. Fast extraction can happen entirely between samples. Reliable per-machine rates need a cumulative plugin/peripheral counter or a measured output path; watching its output slot or subtracting ME stock snapshots can miss production and consumption. A deliberately measured batch transfer is another possible source. We must inspect the custom interface before choosing the adapter.
3. **HV solar production:** a separate app selecting the solar ME network for stock/buffer levels, plus a measured HV-output count for an actual per-hour rate. Inventory change alone is net stock change. Alerts should combine sustained excess UU/solar buffers with stalled expected output and an observation interval; a zero ingredient stock is often normal during continuous crafting. Offline/restart gaps must remain unknown instead of creating false rates/alarms. Recipe-specific shortage diagnosis needs requirements or crafting progress, not just a snapshot showing zero resources.

All four apps stay separate. Source clients/ports/targets are selected inside each app; the shared OS sensor hub owns deduplication, freshness, sessions and transport. Reusing a sensor does not require coupling app state or merging the apps.

## Primary version sources

- [OpenCCSensors 1.4.7 AE target discovery](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/AppliedEnergisticsSensor.java)
- [Native AE access-point counters and item fields](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/targets/appliedenergistics/WirelessTarget.java)
- [Native inventory slot fields; NBT disabled](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/helper/InventoryHelper.java)
- [Native IC2 mass-fabricator fields](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/sensors/targets/industrialcraft/MassFabTarget.java)

These are the pre-Minecraft-1.5 sources, not modern AE2 or CC:Tweaked APIs. Automated checks use simulated ComputerCraft Lua 5.1; live server sensor output, graphics and touch alignment still need in-game verification.

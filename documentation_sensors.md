# Generic sensor client

Bundled-v15 adds the `sensor` role. One client detects OpenCCSensors peripherals on every computer side, identifies their inserted cards, discovers targets and returns selected readings. The wireless modem is found automatically. Different cards use the same program, including the **dedicated Applied Energistics card** in the user's Minecraft 1.4.7 installation; it is not treated as an inventory card.

## Install

Replace your installer paste with the current `install.lua` and download a fresh `inst`. On the sensor computer:

```text
cd /
inst sensor --startup
reboot
```

Attach a wireless modem and an OpenCCSensors Sensor Peripheral on any free side. Reactors need OpenCCSensors' **IndustrialCraft 2 Sensor Card**, not Nuclear Control's **Reactor Sensor Location Card**, and must be within its detection range. Additional sensor peripherals/cards can share this computer on other sides. A single suitable card can detect several reactors.

Use the same `networkId`/`channel` in `configs_network.txt` as the central OS. Optional `serverId` pins the OS computer. The client prints its logical ID, modem location/channel, detected sensor sides, card names, target counts and connection status. Existing monitor/IO programs do not need updating. Update the **server** role to v15 before using the new sensor picker/app.

Bundled-v16 adds [wireless relays](documentation_relay.md). For a distant sensor, update the OS and sensor role to v16, then put `inst relay --startup` computers along a path. Chains have no fixed software hop-count limit. The sensor stays separately listed in OS `clients` and remains selectable by its original ID. Other endpoints need the new network library only when they will also use relays; app code and sensor-card adapters are unchanged. Preserve automatically maintained `configs_transport.txt` on every updated role.

## Connected sensor but no available side

Bundled-v17 fixes a reproduced failure: a sensor discovered 62 targets before a five-relay path connected, but one blank machine name caused the OS to reject its entire catalog and offer no sides. Empty names now fall back to the native OCS `RawName`, or `Unknown`; raw identities also identify reactors behind localized display names. Native OCS tile targets normally supply `Name`, `RawName` and `Position`, rather than the `Type` field used by some adapters. The hub retains raw identities and accepts blank types from older catalogs without discarding the whole side. This reproduces the reported symptom; the user's exact native metadata has not been captured.

Update the **OS and sensor roles** with the bundled-v17 installer, then reboot both. Relays and app files need no update. The picker now says `Waiting for catalog`, `Catalog rejected` or `Sensor client offline` as appropriate, and shows known but unusable sides as disabled instead of hiding them.

Run `sensors` or `sensors sensor_20020` on the OS console to inspect protocol/boot, card name, side status, accepted target/reactor counts, incomplete catalog parts and validation errors. This distinguishes a missing catalog from a rejected one without assuming that wireless connection alone proves telemetry arrived. If a side is visible but a target is absent, check card range and the returned names/raw identities.

## Configuration

`configs_sensor.txt` preserves:

| Setting | Default | Meaning |
| --- | --- | --- |
| `clientId` | `sensor_COMPUTER_ID` | Stable ID used by saved app bindings |
| `announceInterval` | 5 seconds | Network handshake/heartbeat |
| `timeout` | 15 seconds | OS disconnection detection |
| `discoveryInterval` | 5 seconds | Card identification and target discovery |
| `pollInterval` | 1 second | Minimum interval per subscribed target |
| `requestTimeout` | 4 seconds | Limit for one peripheral request |
| `bootCounter` | maintained automatically | Reject old data after client restart |

Discovery timing depends on the number of attached peripherals and pending reads; requested intervals are not a hard real-time guarantee. Calls are serialized across sensors because old OpenCCSensors uses small per-peripheral queue IDs without an event-side field. Native `ocs_success`/`ocs_error` replies, immediate-return implementations and yielding calls are supported without yielding through Lua 5.1 `pcall`. A timed-out response ID is quarantined for that program session, preventing a late reply from being used for another sensor. Repeated failures are reported as unavailable data while networking continues.

Cards are identified by the actual `getSensorName` result. Card changes, removal, detached peripherals, missing targets and read errors remain distinct from a valid zero/false reading. Bindings include client ID, peripheral side, target key, expected card and target type. They identify a location/target exposed by the mod, not a unique physical-machine UUID: replacing a reactor with the same type at that same target address is not distinguishable.

## Data and future apps

The client publishes bounded target catalogs; apps subscribe to particular targets through the central OS. Shared addresses are polled once for all app/monitor views. Reactor telemetry is normalized centrally, and generic nested readings remain available for a future ME app. There is no ME app in this update.

The old IC2 card reports heat/output/activity but not fuel lifetime or fuel inventory, for both core and chamber targets. Bundled-v18 adds more explicit remaining-time aliases for adapters that do provide them, plus normalized heat margins and native energy counters. It does not make missing lifetime available on a stock card or add chamber subscriptions. Update the OS role and Reactors app for these display/adapter improvements; the sensor and relay roles need no update. [The reactor guide](documentation_reactors.md) explains the fields and expanded raw-data browser.

Bundled-v19 fixes a legacy-runtime OS crash during subscription cleanup, observed as `lib_sensor_server.lua:199: invalid key to 'next'` after Reactors closes. Cached readings, expired watch entries and incomplete packet assemblies are pruned using key snapshots. Update only the central server role with a fresh v19 installer and reboot it. Sensor/relay firmware and app files are unchanged; saved configuration and manual output intent are preserved.

Samples use changed full snapshots or compact unchanged heartbeats. Heartbeats identify the exact full snapshot they confirm, so losing a changed snapshot cannot keep older data falsely fresh. Full snapshots repeat at least every five seconds of successful polling. Catalogs repeat on discovery for recovery. Catalogs are paged (up to 4,096 targets per side); readings use up to sixteen 12,000-character chunks. Partial/out-of-order data is assembled before publication, and old sessions/sequences are rejected. Oversized/unsupported/cyclic values produce an explicit read error. No arbitrary returned table is merged into OS state.

The default freshness limit is ten seconds, increasing to three polling intervals for configured slower polling. Client loss is separately detected by the OS's client timeout. Live readings are never restored from disk as fresh after a reboot. Removing the last active subscription stops detailed polling; basic card/target discovery continues. All relevant computers/chunks must remain loaded for live readings.

The sensor role never writes redstone. Reactor switches use independently selected **IO clients**, with the existing cooldown/ACK system. The installer embeds client/core files offline and no apps. No extra Pastebin paste, OCS Lua API installation or HTTP request is needed to extract the sensor role; the peripheral mod itself must be installed on the server.

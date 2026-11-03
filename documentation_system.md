# CC system overview (v24)

`apps_system.lua` is an optional read-only app on the central computer. It gathers the OS's current client registry, catalogs and output confirmations; it does not discover unannounced computers or poll every machine automatically.

Upload the complete package's flat files to GitHub, use the new single `install.lua` paste (banner `bundled-v24`), quit the central OS and run:

```text
cd /
inst server
inst app system
reboot
```

Existing startup, settings and other apps are retained. No client update or extra Pastebin app file is needed. The app's name in Start is **CC system**.

## Pages

| Page | Information |
| --- | --- |
| Central computer | Computer/network/session IDs, modem side, server/relay channels, uptime, checkpoint age, clock source/day and player indicator |
| Clients | Every announced IO, monitor, sensor and relay separately; online/offline, computer/reply channel, last-seen age and relay path |
| IO client | Available sides, input masks/digital state, desired output revision and acknowledged revision |
| Monitor client | Character dimensions, input-revision protocol and saved-window count |
| Relay client | Observed relay path/hops and last announced forwarded-packet count |
| Sensor client | Peripheral sides, actual card identities/statuses, target counts, protocol/boot generation, catalog errors and incomplete parts |
| Sensor targets | Name, raw identity, exact target key, kind/position when reported and any already cached sample; no additional subscriptions |
| Outputs | Logical names, exact IO routing/color, desired ON/OFF, online and ACK state |
| Apps | Enabled apps, running/stopped and background-service status |
| Windows | Saved app/monitor, geometry, layout and minimized status |

Lists and wrapped details page on small windows. Sensor target sample fields are informational; only a currently valid cached observation is shown as data. AE target details request the existing capacity projection so opening diagnostics does not repeatedly copy a large item catalog.

Settings offers UI color and a client-role filter (All, IO, Monitor, Sensor, Relay). The filter and each window's page/selection are checkpointed. Live device/sensor data is rebuilt after restart; an old client detail page can therefore say it is waiting for an announcement. Offline clients stay visible during the current OS session. Distance, chunk load status and unreported machine fields are not inferred.

The overview cannot change outputs, rename devices or delete app state. It opens no sensor watches, so viewing catalogs does not add peripheral polling load. Source selections continue to belong to each app; identical targets can be reused across apps and monitors.

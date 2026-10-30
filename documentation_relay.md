# Wireless relay client

Bundled-v16 adds `inst relay --startup`. A relay computer needs one wireless modem on any side. It carries SmartHome traffic in both directions for sensors, IO clients, monitors and other relays. Relays discover paths automatically; no parent, child or per-device routing configuration is needed.

Chains may contain as many relays as the installation needs: OS → relay → relay → … → device. There is **no fixed software hop-count limit**. Every radio hop must remain within the server's wireless range, in the same dimension, with all participating chunks loaded. Chunk loading across a tall vertical area does not extend modem range. The user observed a practical vertical range of about **30 blocks** on this server; use roughly **20–25 blocks per hop** for margin. The 120-block gap therefore needs a chain, rather than assuming the stock range.

## Install or upgrade

Upload this package's root files to the V2 repository and replace the one installer paste with bundled-v18 `install.lua`. Download a fresh `inst` on each computer being updated. Quit its running program to CraftOS first. Existing v16 relays need no update for v17's sensor-catalog fix; update the OS and affected sensor roles instead.

On the central OS:

```text
cd /
inst server --startup
reboot
```

On every new relay computer:

```text
cd /
inst relay --startup
reboot
```

Update each endpoint that should use relays by reinstalling its existing role: `inst sensor --startup`, `inst io --startup` or `inst monitor --startup`, followed by `reboot`. Directly connected older clients still work, but old network libraries cannot use the new relay transport. Apps need no update or reinstall. The role installer includes all twenty core sources, extracts only the selected role's dependencies, contains no apps and needs no HTTP for extraction.

Use matching `networkId` and `channel` settings in `configs_network.txt` on the OS, relays and endpoints. Optional `serverId` pins the OS ID and is enforced when forwarding as well as receiving. `relayEnabled` defaults to true; explicitly setting it false makes an endpoint direct-only. Relay computers require it enabled. The modem side and listening/reply channel are detected normally; the separate relay channel is automatic.

## OS client list

Run `clients` on the OS console. A relay appears as its own `relay` client, with ONLINE/offline status and a forwarding count. Every sensor, IO client and monitor behind it also appears independently, retaining its original logical and computer IDs. Sensor and IO pickers therefore continue to offer the actual devices.

Example console entries:

```text
relay_30 relay ONLINE computer=30 direct forwarded=123
relay_31 relay ONLINE computer=31 via=relay_30 forwarded=98
sensor_20020 sensor ONLINE computer=20020 via=relay_31>relay_30
io_11 io ONLINE computer=11 via=relay_31>relay_30
```

`via` runs from the device towards the OS. `direct` means no relay appeared in the accepted announcement. On overlapping paths, the first valid copy wins; direct copies are sent first. Paths refresh with normal announcements and can change automatically after a relay is lost. The list is not a manually configured or permanently reserved route. The API exposes `via`, `hops`, structured `route` and relay `forwarded` count through `api.getClients()`.

Losing a relay causes each unreachable endpoint to time out independently and remain listed as offline. Other available paths can continue carrying traffic. Restoring a relay, OS or endpoint re-establishes the normal handshake and saved output intent without changing app bindings. An IO client's existing timeout/safe-off and write cooldown still apply; the relay never reads or drives redstone. Forwarding operates even before the relay itself receives an OS welcome. Modem removal/reattachment is detected without a manual program restart.

## Saved settings and protocol

`configs_relay.txt` defaults to `{clientId = "relay_COMPUTER_ID", announceInterval = 5, timeout = 15}`. Keep its ID stable. Every updated role also creates `configs_transport.txt`, containing an automatically maintained boot counter. Preserve that file along with the other configurations. It distinguishes fresh packet IDs after a computer reboot; installation does not replace it. Networking does not start if its boot checkpoint cannot be written.

Updated endpoints keep the original direct channel and also listen on channel `65533`. Each new send has a persisted boot generation and increasing sequence number; it is sent on its direct destination channel and on the relay channel. Original sender, recipient, reply channel, OS session and application payload are preserved. Copies share one ID and are suppressed before app/handshake handling. Relays forward only valid SmartHome packets for their configured network, on the relay channel, and append their ID to the visited route. A relay never forwards a packet that has already visited it. This prevents cycles without a fixed TTL/hop cutoff. A bounded 4,096-packet/60-second cache additionally suppresses overlapping copies, while actual retries get fresh IDs.

ComputerCraft's encoded modem-message limit still applies: 65,536 characters per transmitted packet. Sources leave 4,096 characters of headroom for route metadata; relays check the size again after appending their route. There is no promise of an infinite physical network or unlimited payload size. Extra relays add forwarding traffic and latency. Normal announcement/retry/session, sensor multipart/freshness and IO acknowledgement rules remain unchanged. This transport does not add authentication or encryption.

The tests run the actual relay, server and endpoint programs with three-dimensional radio distance, including the 120-block vertical gap, 16- and 17-relay chains, overlapping/direct paths, large payloads, lost packets, restarts and unplugged modems. They simulate ComputerCraft Lua 5.1, not the user's live Minecraft server.

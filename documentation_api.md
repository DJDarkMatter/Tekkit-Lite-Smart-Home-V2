# App and network reference

## Single-file apps

The installer contains no apps. A user app is a Lua file returning an app table, stored as `apps_NAME.lua` in the OS computer root. It executes only if `enabledApps[APP_NAME] = true` in `configs_os.txt`; restart the OS after changing this setting. The default is an empty table. The saved legacy `appRegistry` does not enable execution. Enabled app definitions are registered at OS boot. Ordinary apps initialize when first opened (or when saved views restore), run while any view exists, and stop after their last view closes. Apps with `backgroundService = true`, and apps without a render hook, start at boot and continue with zero views. Optional apps are `apps_coffee.lua`, `apps_switchboard.lua`, `apps_reactors.lua`, `apps_me_storage.lua`, `apps_me_monitor.lua` and `apps_clock.lua`. The [v39 release notes](documentation_update_v39.md) list the newer optional apps.

Explicit installation uses the same installer: `inst app APP_NAME` downloads the root file `apps_APP_NAME.lua` from `DJDarkMatter/Tekkit-Lite-Smart-Home-V2` on GitHub (`main` branch). `inst app APP_NAME --ref BRANCH_OR_COMMIT` selects another ref. Apps therefore need no separate Pastebin upload. Optional alternatives remain `inst app APP_NAME PASTE_ID` or `inst app APP_NAME --file /path/to/app.lua`. The installer checks syntax, installs the file and enables that one app for the next OS start. It preserves existing settings, startup and saved app state, backing up replaced code/settings. It does not execute the app at install time. GitHub mode uses the CC 1.5 `http.get` API; role installation remains offline and app-free.

Bundled-v10 tries GitHub's contents API first (confirmed working on the target server), then the raw file if needed. The API response is decoded from base64 without `textutils.unserializeJSON`; it must describe the requested filename with a matching decoded size and valid Lua. Request exceptions are caught through a child coroutine so CC 1.5 HTTP can still yield; response handles are closed and termination aborts without retrying. Failures print separate raw/API reasons before any app/settings replacement. Server network restrictions and Java TLS failures require server-side investigation.

```lua
local app = {minWidth = 18, minHeight = 4, preferredWidth = 30, preferredHeight = 10}
-- Set backgroundService = true for always-on automation such as Coffee.

function app.init(state, api)
    -- init runs after restoring state: set defaults, do not erase saved values.
    if state.seconds == nil then state.seconds = 0 end
end

function app.background(dt, state, api)
    state.seconds = state.seconds + dt
end

function app.render(width, height, state, api)
    return {"Running: " .. math.floor(state.seconds) .. "s"}
end

function app.handleTouch(x, y, width, height, state, api)
    -- All coordinates here are 1-based within the content, excluding the frame.
    state.seconds = 0
    api.save()
    return true
end

return app
```

Size limits describe **content** character dimensions. The OS adds a one-character frame and reserves one bottom taskbar row. Preferred sizes set initial content dimensions; optional maximum sizes constrain presets too. Omit maxima for fully responsive applications. A background-only app can omit `render`. `shutdown(state, api, {appName})` is an optional hook called when the last ordinary-app view closes. Closing or minimizing one view never stops work shared by other views. App state is shared across the app's windows and background hook and is persisted separately from window geometry. `handleTouch` may optionally return `handled, replacementState`.

An app may attach `styles` to its returned array of text rows. Each style is `{x, y, width, height = 1, fg, bg}` in content coordinates, with numeric CC color constants. Styles affect foreground/background without replacing text and are clipped to the content area. For example, `return {"Settings", styles = {{x = 1, y = 1, width = width, fg = 1, bg = 2048}}}` paints a blue heading. Old plain-text apps remain supported. Coffee's button helper generates its text, color rectangle and hit rectangle from the same geometry. `lib_gui.lua` composes and encodes surfaces centrally; app code never draws on a peripheral.

Bundled-v9 adds optional `app.title` (1–64 characters) for launcher, taskbar and title-bar display; the filename/app identifier remains unchanged. **Every future app Settings menu should include UI color** and use `api.getAppColour(context.appName)` for its heading/primary controls. Call `api.pickColour(context.windowId)` from that setting; the OS handles the palette, validates/saves the accent and returns to the underlying page. No app-specific color callback or duplicate color state is needed. Switchboard instead composes `api.ui.palette` with a draft preview and Apply/Cancel, committing its accent through `api.setAppColour`; the shared saved accent remains OS-owned. Use `api.ui.contrast(accent)` for text on the accent.

`api.ui.content(width, height)` supplies `lines`, `hits`, `text`, `heading`, `style`, and `button`; the returned `lines.hits` aliases the same rectangles used for interaction. `api.ui.menu(width, height, title, items, page, backAction, accent)` returns `lines, hits, page, pages`, with pagination only when needed. Items use `{label, action, enabled}`. `api.ui.hit(hit, x, y)` supports both one-row and rectangular controls. These helpers are pure layout functions and do not touch peripherals. Coffee is the reference for responsive action placement and parent navigation.

Hooks must return promptly and must not call `sleep`, `read`, `os.pullEvent`, HTTP, or other yielding functions. Lua 5.1 hooks run under `pcall` for fault isolation. Apps are trusted code, not sandboxed plugins.

| API | Result |
| --- | --- |
| `api.mapOutput(name, clientId, side, color, initialValue)` | `ok, error`; nil color means ordinary/digital redstone; otherwise one CC color bit. Optional boolean sets initial intent for a previously unused wire; new references to an existing wire adopt its state. Rebinding an unchanged address with an explicit boolean sets shared intent |
| `api.setOutput(name, boolean)` | `ok, error`; saves the shared desired state for every reference to that wire before sending it |
| `api.updateOutputs(changes)` | `ok, error`; bundled-v13 atomic batch of mappings, removals and desired values; see below |
| `api.getOutput(name)` | Desired boolean; false if unknown |
| `api.getOutputs()` | Sorted array of `{name, clientId, side, color, value, online, confirmed}` |
| `api.getInput(clientId, side)` | `{value = bundledMask, digital = boolean}`, or nil if unknown/offline |
| `api.readInput(address)` | Boolean for one Digital/bundled input, or `nil, reason` if unconfigured/offline; address is `{clientId, side, color}` with nil color for Digital |
| `api.getIOClients()` | Sorted `{id, computerId, online, sides}` records; sides exclude the modem and unavailable/config-disabled ports |
| `api.pickIO(windowId, key, direction, currentAddress)` | Opens the reusable touch selector in this window; direction is `input` or `output`. Needs at least 12×6 content characters |
| `api.getSensor(clientId, name)` | Raw scalar reading, or nil if unknown/offline |
| `api.getSensorClients()` | Sorted sensor clients with ID, online status, computer ID and per-side card/type/target catalogs; also `sensorProtocol`, `bootId`, `catalogError`, `catalogRejected` and `pending = {{side, received, parts}}` diagnostics |
| `api.pickSensor(windowId, key, currentAddress, kind)` | Shared client/side/target picker; `kind = "reactor"` filters reactor targets, `"ae"` selects AE sources; callback below |
| `api.watchSensor(key, address, options)` | Keeps a selected target subscribed for ten seconds; optional v21 `{profile="ae_storage"}` requests AE counters without Items. Default is full data; duplicate addresses share one client poll |
| `api.unwatchSensor(key)` | Removes this subscription; shared addresses continue if other subscriptions exist |
| `api.getSensorReading(address)` | Structured status, raw `data`, age, error, target info and optional normalized `reactor` reading; never restores saved telemetry as live |
| `api.getSystem()` | Display clock/player status plus v24 numeric `worldTime`/optional `worldDay`, central computer/network/modem/channel/session, uptime and checkpoint age; unavailable numeric time is nil |
| `api.setNotifications(appName, entries)` | v25 bounded runtime list of `{key, title, message}`; shows queued OK popups on all monitors, owned/persisted by the app |
| `api.getDiagnostics()` | v24 fresh read-only snapshot `{system, clients, io, sensors, outputs, apps, windows}`; no subscriptions or output changes |
| `api.getClients()` | Sorted `{id, type, online, computerId, via, hops, route, forwarded}` records; includes relays and every original endpoint separately. `via` lists relay IDs from device towards OS; `route` also includes their computer IDs; relay-only `forwarded` is its last reported count |
| `api.openApp(name, monitorId, x, y, width, height)` | `windowId, error`; geometry optional, outer dimensions |
| `api.closeWindow(windowId)` | `ok, error`; closes only this view and stops a normal app after its last view |
| `api.placeWindow(windowId, x, y, width, height)` | `ok, error`; nil fields retain the old values |
| `api.layoutWindow(windowId, mode)` | `ok, error`; fullscreen, maximize, restore, left/right/top/bottom, top_left/top_right/bottom_left/bottom_right, or `grid_CxR_X_Y` for 1–3 columns/rows and a 1-based column/row position (e.g. `grid_3x3_2_3`) |
| `api.getAppColour(appName)` | Saved app accent, default blue; shared by all its views |
| `api.setAppColour(appName, color)` | `ok, error`; validates/saves or rolls back on failure |
| `api.pickColour(windowId)` | Opens the shared palette for this window's app; selection saves automatically |
| `api.getOSSettings()` | `{backgroundMode = "solid", backgroundColour, windowBorderColour, taskbarColour}` |
| `api.setBackgroundColour(color)` | `ok, error`; changes the static background on all desktops |
| `api.setWindowBorderColour(color)` | `ok, error`; saves one frame/title color for all windows; Close stays red |
| `api.setTaskbarColour(color)` | `ok, error`; saves the taskbar background across monitors; text/highlights adapt for contrast |
| `api.save()` | `ok, error`; checkpoints central state |
| `api.invalidateAppViews(appName)` | Advances input revisions for every monitor displaying this app after shared structural edits; normal telemetry/clock updates need no invalidation |

Physical sides use computer-relative names. Mappings are independent of apps and persisted centrally. All mapped sides are fully owned by the OS. Input/sensor values are live observations, not restored stale values. Losing a sensor client clears its supplied system indicators.

## Per-window settings and shared IO selector

`init` receives an optional third argument `{appName}`. `render` and `handleTouch` receive an optional final `context = {appName, windowId, monitorId, fullscreen, view}`. Since v27, `fullscreen` is a boolean; older apps can ignore it and use the supplied content dimensions as usual. `view` is this window's menus/drafts, checkpointed since v21; app `state` remains shared persistent business data. Closing a window discards its draft menus. Other views keep the app running; the last close stops an ordinary app, while a background service continues. Persist applied settings in `state` and checkpoint them.

An app can request `api.pickIO(context.windowId, "playerInput", "input", state.playerInput)`. The OS draws a paginated client → side → Digital/color menu, with an explicit Use/Cancel review. It offers all known IO clients, marks offline ones, and excludes unavailable sides. Selecting Use invokes:

```lua
function app.handleIOSelection(key, address, state, api, context)
    local previous = state[key]
    state[key] = address
    local ok, err = api.save()
    if not ok then state[key] = previous end
    return ok, err -- false,error leaves the dialog open with the error
end
```

The callback should validate/apply the change, roll back its own state on failed save/mapping, and return `true` or `false, error`. For outputs use `api.mapOutput` and a logical output name; apps never write redstone directly. The coffee callback demonstrates committing an OFF binding with its address. Switchboard reuses the same picker for each output, including detecting stale selections from another monitor.

OS checkpoints include all app states and window position/size/order/minimized status, snap/restore metadata and per-monitor taskbar scrolling at an interval no longer than one second, even when an older config still specifies 30 seconds. Important transitions and applied settings save immediately. This is checkpoint recovery, not an exact transaction with the external Minecraft machine.

`dt` is elapsed ComputerCraft `os.clock()` time between OS ticks. It is not reconstructed across program/server downtime. A real coffee app must define its own online/pause/harvest state transitions and explicitly save important counters.

## Atomic output groups (bundled-v13)

`api.updateOutputs(changes)` accepts a dense array of operations, each with a unique logical `name`:

```lua
api.updateOutputs({
    {name = "panel_1", clientId = "io_11", side = "left", color = 1, initialValue = false},
    {name = "panel_2", value = false}, -- Existing mapping, new desired value.
    {name = "old_panel_3", remove = true},
})
```

A mapping includes `clientId`, `side` and optional bundled `color`; nil color means Digital. Multiple logical names may reference one wire. An explicit boolean `value` sets the shared desired state for every reference, even names outside the batch. Mapping-only `initialValue` supplies an initial intent for a previously unused wire; it adopts the current state when linking an existing wire. Do not combine `value` and `initialValue`. If neither is supplied, existing physical state takes precedence, then previous logical intent (default OFF). Contradictory explicit values for one wire in one batch are rejected. Value-only operations need existing mappings. Removal clears only this reference and its named value. Empty arrays checkpoint caller app-state edits without changing IO. New mappings are checked against online client capabilities. Duplicate logical names in one batch remain invalid.

The group and caller's current app state save before hardware sync. Validation/save failure changes no mappings, intent or hardware; apps must restore their own edited state on failure, as Switchboard does. Released sides remain in the snapshots so unused old wires clear; shared wires remain driven by their surviving references. Physical snapshot changes receive one new revision per affected client after the checkpoint. Unchanged snapshots retain their revision and confirmation. Normal cooldown/retry/ACK semantics apply. Routine announcements preserve known ACKs; reconnects, restarted announcement counters and changed capabilities invalidate confirmation. Changed capabilities get a fresh revision so clients cannot acknowledge an obsolete snapshot. This is an atomic central checkpoint, not simultaneous switching across computers. Switchboard uses it for presets, route changes, grid shrink, disconnect/delete and All OFF. Existing `mapOutput`/`setOutput` remain compatible with Coffee.

## Selected sensor targets (bundled-v15)

Sensor addresses are `{clientId, side, target, card, targetType}`. The target is the exact key returned by OpenCCSensors, often relative coordinates. Card and target type protect against silent reassignment to incompatible devices. `pickSensor` calls the app's optional `handleSensorSelection(key, address, state, api, context)` hook. Return `true` after saving the binding, or `false, error` with rollback; it uses the same per-window overlay/callback pattern as IO. Multiple reactors/entries may share one card/client with different target keys, or share an identical address across monitors.

After shared structural configuration changes, Reactors calls `invalidateAppViews`. This rejects queued touches from old card/entry layouts on other monitors, including when deleting a reactor shifts another control into its former position. Ordinary sensor value updates do not invalidate input.

`apps_reactors.lua` is the reference: background renews every configured subscription, reads cached telemetry synchronously, and shutdown removes its watch keys while preserving manual output intent. The sensor client performs asynchronous peripheral work, so app hooks never wait for a sensor. A normal app with no remaining views stops its subscription renewals; services can renew at boot without windows. Live state is runtime-only. `getSensorReading` returns `unconfigured`, `waiting`, `offline`, `missing`, `card_changed`, `target_changed`, `no_card`, `detached`, `error`, `stale`, or `ok`, depending on source state. Only an `ok` result with a valid `reactor` record is a live reactor observation. Historical data may accompany an error/stale result; inspect status before using it.

The bridge announces `sensorProtocol = 1` and persisted `bootId`; every catalog/sample is bound to OS session, sender, client ID and boot ID. Catalogs contain at most 64 target summaries per part and 64 parts per port. `sensorWatch` supplies a deduplicated list of at most 128 targets per client and retries every three seconds. `sensorSample` carries at most sixteen 12,000-character chunks with increasing sequence IDs. The hub publishes only complete, validated tables; old/incomplete packets cannot partially overwrite a reading. Unchanged samples use a compact heartbeat naming the exact complete base snapshot. Missing that base cannot renew older data, and periodic full samples recover loss. Scalar `sensorData` stays separate for old adapters. Limits and physical setup are in [the sensor guide](documentation_sensors.md).

Bundled-v17 normalizes empty/control-only display names using a nonempty `Type`, `type`, `Name`, then `RawName`, finally `Unknown`. Catalog targets retain optional `rawName` (up to 128 characters); reactor classification uses both display and raw identity, matching OCS 1.4.7's native `Name`/`RawName` shape. The hub also tolerates blank/missing string types from older clients, while rejecting invalid addresses or structured/oversized type fields. This stops one unnamed machine invalidating an entire side. Names and kind are informational; valid reactor details still require actual Heat/MaxHeat data. The picker explains missing/rejected catalogs and leaves known incompatible/error sides visible but disabled. `sensors [client]` prints source protocol/boot, card/side status, target/reactor counts, incomplete part counts and the latest catalog rejection. These diagnostics are runtime-only and do not change saved bindings or output intent.

Bundled-v18's normalized `reactor` also includes signed `heatToMelting`/`heatToMax`, optional `energyEmitted`/`energySunken`, and `remainingField` when an explicit time field was recognized. Remaining seconds aliases include `TimeLeft`/`timeLeft` and explicit seconds names; explicit tick aliases are divided by 20. See [exact aliases and native-card limits](documentation_reactors.md). Missing lifetime stays nil; no prediction, inventory scan or chamber subscription is introduced. Reactors uses these fields in responsive details and expands nested raw data for inspection. Output buttons display current ON/OFF intent. Monitor text scale, input calibration, protocol and saved state schemas are unchanged.

Bundled-v21 exposes `api.sensorProfiles = true`. The optional AE storage profile projects native identity/power and storage counters before data cleaning/encoding; it adds `ItemsOmitted = true`. The hub chooses full data when any subscriber to an address requests the default profile. Profile changes force fresh full samples for that representation instead of reusing a heartbeat from the previous one. Watch renewal, sessions, card identity and network protocol 1 remain unchanged. Update the ME sensor role for projection; older sensor firmware ignores the optional field and remains compatible for bounded full readings. See [ME storage and the future independent apps](documentation_me_storage.md).

Bundled-v22 additionally exposes `api.aeItemProfiles = true` and `watchSensor(key, address, {profile="ae_items"})`. This produces native AE capacity/power fields plus `ItemsFormat="ae_compact_v1"` and compact `Items` rows `{RawName, DamageValue, Name, Size}`. Valid complete item tables carry `ItemsComplete=true`. The priority for a shared address is default/raw, then ae_items, then ae_storage; there is still only one poll. Typed item snapshots allow up to 8,192 rows, 60,000 cleaned values and 64 chunks; other profiles retain their 16-chunk/12,000-value limits. Profile metadata is validated across parts and unchanged-heartbeat bases. Item polling is at least two seconds. `getSensorReading(address, {profile="ae_storage"})` projects counters for a summary-only reader, even when a richer snapshot is cached. All catalogs are runtime-only. The new [ME monitors app](documentation_me_monitor.md) is the reference consumer; native/raw `Items` tables remain readable for compatibility.

## Persistent per-window UI (bundled-v21)

Render/touch/selection contexts include `{windowId, monitorId, appName, view}`. `state` is shared business configuration; `context.view` belongs to only this window. The OS now checkpoints each window's plain UI data as `windows[id].viewState` and restores it into `context.view`: selected switchboard/ME/reactor IDs, screen/page, pagination and drafts therefore survive an OS restart. Touch actions save immediately; periodic checkpoints also capture render-time navigation normalization. Existing saves without viewState restore empty navigation until the user selects a view once. Closing a window removes that window's UI state.

Use `view` only for small UI state, not live telemetry, peripherals or callbacks. Snapshot cleaning accepts finite scalar values and plain tables up to depth 8 / 2,048 visited values, with strings up to 4,096 characters; `hits`/`styles`, functions and cycles are omitted. Oversized snapshots fall back to empty navigation without blocking app/output checkpoints. Hit maps are rebuilt from the next frame. OS selector overlays themselves remain transient; their parent app window/navigation is retained. Sensor caches remain runtime-only and are not part of view restoration. Monitor disconnects keep their windows; actual resolution changes can still refit geometry to what fits.

## Transport

`lib_network.lua` handles modem detection, string encoding and envelope checks. Configuration is a serialized Lua table in `configs_network.txt`.

- Server listens on `channel` (default `45231`).
- Client listens on `1000 + (computerId % 40000)`, substituting `41001` if that equals the server channel.
- Clients announce to the server channel with their own channel as `replyChannel`.
- Server replies to that channel with its server channel as `replyChannel`.
- Every message is `textutils.serialize(packet)`; receivers use protected `textutils.unserialize`.
- Bundled-v16 also opens relay channel `65533` on updated roles by default. `relayEnabled = false` keeps an endpoint direct-only.

Every envelope has these fields:

```lua
{
  protocol = "SmartHomeOS/1",
  networkId = "home",
  sender = 11,           -- claimed ComputerCraft ID; not authentication
  recipient = 10,        -- may be absent for discovery to an unpinned server
  type = "announce",
  clientId = "io_11"     -- stable logical endpoint, distinct from computer ID
}
```

Multiple logical monitor endpoints can share a computer/reply channel. The recipient computer ID and the logical client ID are checked separately. Packets for another household, computer, channel, modem side, pinned OS ID or protocol are discarded. Packets are limited to 65536 encoded characters; monitor resolutions are bounded to 256x128 characters.

### Relay transport (bundled-v16)

Install the OS, participating endpoints and any number of relay computers with the current role installer. Full setup is in [the relay guide](documentation_relay.md). Relays are registered clients of type `relay`; they never replace IO/sensor/monitor identities or app bindings. The `clients` command includes their ONLINE/offline status and every endpoint's observed `via` path. Directly connected old clients remain compatible, but relaying requires the new endpoint network library.

New sends retain the normal envelope and attach `_transport = {version = 1, boot, sequence, serverChannel, channel, path = {}}`. The boot counter is checkpointed once per network start in `configs_transport.txt`, and the sequence increases per send. Each send goes to its normal destination channel and to `65533`; copies share `(sender, boot, sequence)`. `channel` names the original destination, not the relay channel. The physical modem reply channel always remains the original source's reply channel. Existing OS registration/session/recipient checks therefore still see the real endpoint.

Relays forward only valid packets on `65533`, append `{id, computerId}` to `path`, and never forward a packet containing their own computer ID. Repeated IDs and malformed/sparse paths are rejected. There is no fixed hop-count cutoff. A bounded 4096-packet/60-second FIFO additionally suppresses duplicates, and endpoints suppress copies before application/handshake handling. Fresh retries have new IDs. The received `_route` is produced by the network library from validated path records; the OS keeps it only in runtime client metadata. `via` follows the device-to-OS announcement path and updates on later announcements, rather than reserving a route.

Sources allow 61440 encoded characters to leave route headroom; forwards still must fit the modem's 65536-character wire limit. Every radio hop must be within range in loaded chunks of the same dimension. Relay chains add traffic/delay and do not bypass hardware packet limits. The relay's own handshake is independent of forwarding, so forwarding can recover an OS/endpoint before the relay is welcomed. Existing message sessions, revisions, sensor reassembly/freshness and IO cooldown/ACK rules remain in force.

## Handshake and output state

1. Client sends `announce` with `clientType` (`io`, `monitor`, `sensor`, `relay`), an increasing `nonce`, and capabilities/resolution. Relays include `relayProtocol = 1` and a bounded integer `forwarded` count.
2. OS registers the logical endpoint and returns `welcome`, echoing `nonce` and including its persisted per-boot `serverSession`.
3. Client accepts a welcome only for its current nonce. IO reports all inputs, including zero values.
4. OS sends the IO client `ioCommand`, with `command = "syncOutputs"`, `serverSession`, integer `revision`, and `outputs` indexed by physical side.
5. Client validates the complete snapshot, ignores earlier revisions/sessions and queues the latest accepted state. Changed outputs are written at least `outputInterval` seconds apart per side (default 0.6), sharing the cooldown between bundled and digital redstone for IDT-Fix servers. Network and input events continue during the wait. Only when every value in the latest snapshot has reached the hardware does the client send `ioAck` with that revision and session. Repeated applied snapshots are acknowledged without redundant writes.
6. OS retries unacknowledged state every two seconds. Announcements/full resynchronization also repeat every five seconds, recovering lost welcomes/acks/frames and OS/client restarts.

V42 IO clients advertise `buttonMinHundredths`, the shortest supported timed press in hundredths of a second. `api.pulseOutput(name, hundredths)` requests a timed high on a mapped wire whose steady state is off. `api.outputPulseMinimum(name)` reads the advertised minimum. The OS includes the press ID, `hundredths` and optional bundled color in `buttonPulses[side]` alongside the steady snapshot. The IO client starts its deadline when the line actually goes high and reports the same ID and completion state in `ioAck`. Repeated snapshots reuse that ID and leave the timer alone. Only the configured mode and length are saved. `api.getOutputs()` exposes the transient request as `pulse = true` while `value` remains the steady intent.

`api.wakeAt(uptime)` lets an app's background tick request an earlier next OS tick at an `os.clock()` deadline. Logic Sandbox uses it for Delay and Wait blocks.

Logic Sandbox retains live `ae_items` subscriptions for visible saved Item amount editors as well as enabled circuits. Its Item amount popup flags migrate into If / Then rules with Alarm actions. Alarm actions publish a fixed `Alarm` title and their optional `alarmName`, falling back to the circuit name. Pending migrated notifications retain their original keys until acknowledged.

An IO snapshot looks like:

```lua
{
  type = "ioCommand", clientId = "io_11", command = "syncOutputs",
  serverSession = "10:3", revision = 7,
  outputs = {
    left = {bundled = 16385, digital = false},
    front = {bundled = 0, digital = true}
  }
}
```

It sets a complete desired state instead of sending toggle commands, so a duplicate/retry cannot toggle twice. Boot sessions and increasing revisions prevent delayed commands from restoring obsolete outputs. This is convergence/acknowledgement, not an exactly-once guarantee for external machinery.

Input updates use `inputData` with `side`, `value` (bundled mask), `digital`, and `serverSession`. Monitor touches use `touch` with `x`, `y` and `serverSession`; the OS decides the window. Frames use `render` with `lines`, `width`, `height`, `monitorId` and `serverSession`.

Bundled-v8 monitors announce `touchProtocol = 1`. Render packets add `frameId`, `inputRevision`, `colourFormat = "rle1"`, and `foreground`/`background` row arrays. Each color row is run-length encoded as repeated two-hex-digit counts (1–255) plus one color digit (0–f, corresponding to `2^index`). The bridge validates full rows and draws contiguous spans with legacy color setters and `write`; `blit` is not required. Older frame IDs are discarded, and cache keys include colors as well as text.

New clients echo the displayed `inputRevision` with each touch. The OS advances it when interactions/layouts change and accepts only the current revision; stale touches trigger a replacement frame without applying an action. Background clock-only changes do not advance it. The bridge's event collector buffers modem/touch/timer events while its worker waits on peripheral calls, capturing each touch's revision at receipt. Old clients without the capability retain legacy input behavior. Install both new roles for the full color/input behavior.

Optional per-side `touchOffsets` in `configs_monitor.txt` are measured with `clients_monitor_client.lua calibrate [side]`. Bundled-v12 uses nine circle targets and requires a live-test Save before persisting a proposal. Per-axis medians must be within one cell of every sample, with every measured correction inside ±3. Nonzero proposals need at least 7/9 matches on their axis; lower agreement proposes zero and shows mixed readings. Diagnostic averages can be fractional, but persisted/applied offsets remain integer character cells because touch events have no sub-cell position. Arrow controls adjust a proposal; `0`/Reset restores a zero proposal, `S` saves, `R` remeasures and `C` cancels. `--test` starts from the current saved value without sampling. `--reset` explicitly saves `{x=0,y=0}` immediately for that side. Failed saves/cancellation preserve the previous correction and other sides. App content origin is `(win.x + 1, win.y + 1)`; forwarded local coordinates are `(touch.x - win.x, touch.y - win.y)`. No guessed global offset is applied by the OS.

## Local OS console

`lib_console.lua` owns the local terminal, with log output above a fixed bottom-row command editor. Server/network constructors accept an optional logger (`Server.new(net, storage, config, logger)`, `Network.new(config, isServer, logger)`); other callers retain normal `print` logging. `api.log(...)` routes app messages through that console, preserving a draft and its insertion cursor. Apps should not draw to the OS computer's terminal directly. `clear` is an OS command that clears only the console; it does not save/reset app state, clear outputs, close monitor windows or stop the server. Up/Down history is transient and bounded to 50 commands; message history is bounded to 200 logical lines. No `read`, terminal redirection or newer window API is used.

The bundled-v15 generic sensor adapter uses the existing announce/welcome/session process plus typed catalogs, selected subscriptions and bounded multipart samples; see [sensor setup and protocol](documentation_sensors.md). Legacy scalar `sensorData` remains supported with `varName`, scalar `value`, and `serverSession`: `playerOnline` must be boolean and `gameTime` a string, and values remain isolated under their client. New reactor/ME tables never overwrite OS state or system indicators.

The desktop stores normalized free rectangles and named snap zones, and reserves the bottom row for its taskbar in framed mode. Its two-step flyout first chooses a grid, then a pane; choosing the grid alone does not change saved geometry. Fullscreen, Resize and Move remain first-level actions. Each custom corner has tap/nudge/confirm stages. Each pane is partitioned from shared integer boundaries, including thirds. User layout menus and placement are OS overlays, so application hooks need no pointer-drag handling. See [desktop behavior](documentation_desktop.md).

### Fullscreen content (bundled-v27)

`api.layoutWindow(id,"fullscreen")` checkpoints `window.fullscreen = true` and retains the framed `layout`, normalized `relative` rectangle and `restore` target. Repeated fullscreen requests are idempotent. `restore` first leaves fullscreen without popping that saved layout's restore target; a subsequent Restore behaves normally. Diagnostics include each window's boolean `fullscreen` flag. Direct placement returns to framed mode.

Fullscreen rendering and pickers receive the monitor's entire width/height and start at `(1,1)`. Styles and touch coordinates share this origin, and the former taskbar row belongs to the app. This mode expands beyond framed maximum/preferred sizes; apps should lay out within the supplied dimensions. The OS consumes only `(monitor.width,1)` as the invisible exit, before calling app/picker touch handlers. Notification overlays remain modal above this exit. Apps may draw in the exit cell, but should keep critical touch actions elsewhere.

Fullscreen is independent on each monitor; the topmost visible fullscreen view covers its other windows. Geometry is recomputed after resize/reconnection. If its minimum content size no longer fits, a small error view retains exit access. Exiting still restores the desktop when the framed window cannot fit at that resolution; the saved rectangle can recover on a larger monitor. Failed checkpoints preserve the prior mode.

Built-in OS settings lives in `lib_settings.lua` and a private system-app registry, with saved window identifier `@settings`. It is always offered by Start and requires no `enabledApps` entry or app download. User-app registration/consent remains separate. The saved state's `appearance` table holds `backgroundColour`, `windowBorderColour`, `taskbarColour` and `appColours`; these are separate from business state in `appStates`. Border/taskbar defaults are gray. `api.pickColour(windowId, target)` supports the system-only targets `background`, `windowBorder` and `taskbar` in an `@settings` view; ordinary apps use the default app-accent target. System color choices affect every monitor and use automatic text contrast. Border color applies to title bars and frames, with a red Close control. Taskbar geometry and text coordinates are unchanged. Cosmetic changes checkpoint immediately and roll back on save failure. The optional Screensaver app is separate from static desktop appearance; it is explicitly opened and transient.

## Diagnostics and numeric world clocks (bundled-v24)

`api.getClients()` also supplies reply `channel`, last-seen `age`, monitor `width`/`height`/`touchProtocol` and output `revision`/`ackedRevision` when applicable. These are observed runtime metadata, not persisted online records. `getDiagnostics` composes existing queries with enabled app lifecycle records and safe window geometry; it does not expose raw app business state or create watches. `lib_system.lua` is the built-in System Overview.

`api.getSystem()` retains its existing fields and adds `worldTime` (numeric hours 0–24, exclusive of 24) and `worldDay` only after successful local clock calls. Legacy string sensor time remains display-only. Additional fields are `computerId`, `networkId`, `modemSide`, `channel`, optional `relayChannel`, `uptime`, `session`, `lastSaveAge`. `apps_clock.lua` is an optional background service using these numeric readings. The clock stores its own trigger cursor/last-fired markers as scheduling state and rebases after boot; saved observations never become a live system clock.

Clock settings/trigger transitions reuse atomic output groups and the established IO selector; signal patterns are scheduled on real uptime with minimum one-second phases. The app combines its own active signals for a shared wire before issuing output values. It does not change IO client write intervals. All apps still use one shared persistent app state and independently checkpointed per-window view state.

## App notification popups (bundled-v25)

`api.setNotifications(appName, entries)` replaces a running app's runtime notification list. Entries form a dense array of at most 128 records: unique nonempty key (up to 96 characters), title (64), message (128), with no control characters. Validation failure leaves the current queue unchanged. Contents are copied. Identical publication retains arrival order and input revisions. A new/changed list invalidates monitor input revisions so stale taps cannot acknowledge the next popup or pass into its underlying desktop.

The OS shows the oldest pending notification as a centred modal window on every monitor, including monitors with no app windows or insufficient space to open the app itself. There is one OK button, with no close/minimize/resize controls. Popup geometry follows the monitor's current size. The underlying app windows, taskbar/menu state and placement drafts are preserved. This overlay is not a saved ordinary app window.

OK invokes `app.handleNotification(key, state, api, {appName, monitorId})`. The app must acknowledge its business state and output changes durably, then republish its remaining list and return true. Return false,error on failure; the popup remains for retry. The OS does not remove a notification independently of the app or stop its outputs on its behalf.

Notification records are runtime mirrors, not a second persistent store. Background services such as Clock save pending occurrences in app state, publish them during init, and refresh the mirror after changes. Ordinary apps must publish their pending state again when they start; only running apps' notifications are shown. Clock uses opaque per-occurrence keys so one OK cannot clear a different or later event, and combines shared-wire intents before atomically stopping an acknowledged signal. Selected dismiss inputs use the existing IO picker/readInput API; unknown/offline is never interpreted as a LOW press.

## Local sensor inspection helpers (bundled-v26)

`Sensor.new(net, config, logger)` in lib_sensor.lua accepts an optional logger; ordinary clients retain their existing print messages. `client.inspectTarget(side, target, callback)` queues one local read-only getTargetDetails request through the bridge's existing serial coroutine/OCS-event/timeout engine. It returns ok,error and bounds the queued requests to sixteen. The callback receives value,error and must return without yielding. A changed sensor/card generation cannot publish an old inspection result. Inspection requests are not part of the network protocol and do not change app watch bindings or sample profiles.

`Sensor.inspect(side?, target?)`, invoked by `clients_sensor_client.lua inspect [all|SIDE [TARGET]]`, runs a standalone offline diagnostic with its own non-transmitting transport. It discovers sensors, captures two bounded native samples for selected targets and writes diagnostics_sensor.txt using the existing recoverable storage writer. It never constructs the normal network transport or reads/modifies role configuration. Normal client mode and remote sensor APIs are unchanged. The report's statuses, timestamps, partial flags and omissions must be inspected before interpreting a field as a production counter; nominal energy-derived rates are not cumulative output totals.


## v30 app lifecycle and shared ME support

Optional app-definition booleans `fullscreenOnly`, `transientWindow` and `hideTaskbar` are validated. `fullscreenOnly` opens directly using the entire monitor; layout/place requests cannot turn it into a framed window. A top-right touch closes that view, while ordinary app fullscreen keeps its existing restore behavior. `transientWindow` excludes those windows from saved/recovered desktops; business state still saves. `hideTaskbar` filters the app's windows from taskbar buttons. Screensaver uses all three and is not a background service.

`onOpen(state,api,context)` runs after app initialization for each explicit opening. It can return `false,error` to reject that new view; another existing view is retained. `onClose(state,api,context)` runs for the closing view after its window-removal checkpoint. `context.view` remains per-window. `api.fullscreenApps == true` advertises this support. Optional `animationInterval` is validated from 0.1 to 1 second; visible fullscreen apps can request a shorter server tick. Closing them restores the configured interval. Modal notifications retain first input/drawing priority.

`api.getAppData(name)` returns a detached copy, including for an installed but uninitialized app. `api.migrateAppState(from,to,transform)` passes detached app states to a synchronous transform that must return `true` (or `false,error`). It checkpoints both namespaces together, updates live app tables in place, rolls back on failed saves and invalidates affected views/old notification mirrors. It does not change IO maps. Level emitter uses it to import old Solar farm alarms before the Solar app changes schema. Imported signals preserve their original output names. No modern filesystem or serialization API is needed.

`lib_me.lua` shares legacy AE item normalization, RawName/damage identity, plain number formatting, powered/complete snapshot checks, boot-aware cache keys and sparse bounded minute history. `Me.snapshot(cache,api,address,boots?)` returns a mutable runtime snapshot; apps store separate previous time/sequence/items records rather than assuming that snapshot is immutable. Fresh heartbeats count zero changes; duplicate sequence/time reads do not. `Me.Rates.record/sum/valid` use shared observed-time coverage plus sparse per-item deltas/excluded withdrawals. These helpers are installed on the central OS and apps remain one-file downloads.

`api.ui.form(...)` adds common menus, wrapped details, paginated rows, number pad and touch keyboard to existing Gui surfaces. Drawing and hit regions use the same geometry. Existing app APIs, monitor text scale and hardware IO cooldown remain unchanged.


## v31 legacy ME compatibility

`Me.safePatterns == true` identifies the helper with a LuaJ-safe HV classifier. The old frontier matcher could raise a Java array-bound error at the start of a string in LuaJ 2.0.3; native Lua 5.1 allowed it. The replacement normalises camel-case/acronym boundaries and uses padded words/plain finds. Solar farm checks this capability before touching saved state, so an app-only update with an old helper requests the central core update explicitly.

`Me.snapshot` explicitly requests the item profile, contains reader/parser exceptions as an unknown/error snapshot, rejects `ItemsComplete == false`, and exposes distinct `types` alongside total count. Its inventories remain runtime-only. Solar farm isolates per-source work so HV detection/Main errors cannot prevent Farm sampling, and picker queries never filter the overview. Its optional saved `hv.selection` is `auto` or `manual`; existing selected identities migrate conservatively to manual. No app-state schema reset is needed.

The host test runner accepts a substring filter using the global `SMART_HOME_TEST_FILTER` or a host environment variable. For LuaJ 2.0.3, set the Lua global because its old `os.getenv` does not reliably expose host environment values. Normal `lua5.1 tests_run.lua` still runs the complete suite.


## v32 Solar farm app-owned analytics

No core API changes are required. Solar schema 2 adds optional `averages` ledgers and `hvTrace`. Each source ledger has shared whole/fractional observed time, sparse per-item accepted deltas/exclusions and a bounded cost. Large integer totals become decimal strings beyond the legacy integer range. Existing rolling history seeds the ledger once; live baselines stay runtime-only. Main's ledger records its HV identity so selecting the same item preserves learning and changing identity resets only that stream. The curve stores per-second average points and explicit gaps independently of display units/window. Per-view `overviewSort` is saved through ordinary window snapshots; `api.invalidateAppViews` protects touches when live amount ordering changes. The distributed app remains one GitHub download and the installer stays bundled-v31.


## v33 shared touch UI

`api.ui.typeKey(keyboard,key,limit)` appends accepted input and returns to the lower-case bank after one capital letter. It supports the numeric `0/1/2` and string `abc/ABC/123` bank conventions. Full fields and non-letter keys do not consume Shift. All app keyboards use it. `api.ui.breadcrumb(parts,width,height)` returns a compact completed-selection path at 24x8 or above, or nil for smaller areas; IO/sensor selectors and ME item pickers reserve its row and adjust their page capacity/hits together. The server role must be updated before installing the revised apps.

`api.fullscreenCornerNavigation == true` advertises the v33 corner handoff. Optional boolean `handlesFullscreenCorner` gives an app the very top-right touch, after modal notification handling. Screensaver sets it to navigate designs in both directions and closes its own transient window for every other touch. Its v37 app expands the invisible corner hit regions to 2×2 cells, clipped on tiny screens, and requests a 0.1-second animation interval; no core API change is needed. Normal apps retain the invisible top-right restore/exit behavior. This metadata does not change layout restoration or monitor text scale.

All user-facing English labels/messages use **color**. Legacy protocol keys, saved fields (`displayColour`, `appColours`, etc.) and compatibility APIs retain their names, so existing installations and user apps do not need a configuration conversion. No output timing or routing API changes.


## v34 per-wire IO confirmation

`api.getOutputs()` keeps its public fields and call shape. `confirmed` is now computed for each **client/side/bundled color or Digital**. The central server records the last desired snapshot and the last revision that changed each physical wire. An unchanged wire keeps its previous confirmation while another wire is awaiting ACK. Changing a wire back before ACK still requires the latest revision for that wire; matching an older value does not prove hardware application. Aliases of one physical wire naturally share confirmation. All metadata is runtime-only and bounded by the six sides and seventeen output channels per side.

The IO command/ACK protocol is unchanged. Complete idempotent snapshots continue to provide retry/reconnect convergence, and clients already skip unchanged hardware writes. Snapshot contents are desired masks, not requests to query switches or reactor sensors. A genuine IO reconnect, restart or capability change clears all per-wire confirmation and advances the revision, so an old acknowledgement cannot validate the new connection. Routine health announcements preserve known confirmations. Failed output checkpoints cannot advance per-wire revisions or send new hardware intent. Existing apps and remote clients need no reinstall for this fix; replace the installer with bundled-v34 and update the central server role.


## v35/v36 cooperative central work and diagnostics

`lib_work.lua` is a shared legacy-compatible helper; the installer now embeds 22 core files and installs the helper on fresh roles. Only the central OS enables its budget. Existing remote role installations stay compatible with the unchanged packet schema, channel/routing rules and RLE frames.

The central OS uses one serial event loop. During cooperative pauses it buffers modem/peripheral events, its own tick and complete console commands, while continuing the bottom-row editor. Buffered commands cannot interleave partial output/app-state checkpoints. A private yield marker is a fast path, with one reusable native timer as a fallback if the marker is lost; no private event is needed to wake queued work. Bootstrap opens the modem and shows progress before restoring saved app state. This replaces v35's parallel collector/worker handoff, which could wait indefinitely for a discarded wake-up event. Native Lua 5.1 and LuaJ are supported.

`api.cooperate(cost?)` accounts work and yields at budget boundaries inside the central worker; it is a no-op for unrelated callers. `api.protectedCall(fn,...)` returns protected-call results with portable coroutine/event forwarding, including nil results. Use it rather than native Lua 5.1 `pcall` around work that may cooperate. Existing app hook signatures are unchanged. GUI drawing/packing, central state copies, serialization and shared ME copies/catalog parsing account their work. Solar sampling uses the same yield-safe protected calls to retain per-source error isolation. App background hooks and monitor frames have boundaries between units. This is cooperative scheduling, not a preemptive interrupt for arbitrary app loops or one native operation.

The storage writer produces ordinary Lua table text accepted by legacy `textutils.unserialize`, preserving sparse keys and the old rejection of repeated references. Previously validated/written primary bytes avoid reparsing unchanged backups every checkpoint; external modifications still receive validation before backup rotation. Temporary-file/backup/checkpoint-before-IO ordering remains unchanged. No app schema migration/reset is required. Network snapshots still carry serialized strings.

A monitor announcement repaints only that monitor, while IO/sensor/relay announcements defer ordinary UI refresh to the normal tick. Touch handling, explicit forced repaint and periodic animation continue normally.

Caught hook/worker errors and caught yielding-timeout errors record a bounded `diagnostics_os_error.txt` containing the message and last operation. `errorlog` reads it; startup announces an existing report. Reporting failure cannot replace the original error, ordinary Ctrl+T is not logged as a crash, and there is no automatic restart loop. A hard external shutdown/native abort can prevent a report. The reported user error was not captured, so this hardening is not a confirmed diagnosis of that exact incident.


## v38 reset scopes and ME Monitor rates

New logical output mappings record the creating app in the optional `owner` field. Console-created mappings belong to `@settings`. Existing built-in names and saved Level emitter references identify legacy routes, including imports from Solar farm. Legacy custom mappings with no known owner belong to OS settings. The built-in Settings window has private callbacks for enumerating reset targets and clearing saved data. Resets use the normal output checkpoint, including shared-wire reconciliation and OFF snapshots for released sides. A confirmed reset replaces the active state and clears older recovery copies for that checkpoint. Restarted services initialize with fresh data for their selected reset scope.

Sensor reads expose `maxAge` so ME Monitor can use its sensor's valid polling interval. `Me.Rates.record` accepts an optional fifth argument for the largest accepted sample interval in seconds. Its default stays ten seconds for existing callers. ME Monitor keeps a bounded runtime history and saves only the per-view `showRates` preference.


## Desktop and wiring services (v39)

| API | Result |
| --- | --- |
| `api.clientName(id)` | Saved display name or the stable ID. Client lists expose it as `displayName`. |
| `api.getScreensavers()` | Ordered design names from the installed Screensaver's `screensavers` metadata and a boolean indicating whether the app file exists. |
| `api.getUsedIO()` | Physical input and output addresses with a direction and a list of owning app titles. Declare additional configured inputs with `app.ioRoutes(state)`, returning an array of `{clientId, side, color, direction}` entries. |
| `api.getIOTrace(address, finish, seconds, width)` | A row of `0`, `1`, `p`, `?` or `\|` columns, and the latest state. `finish` is in the OS computer's `os.clock()` units. Each column represents a time bin. `\|` marks a transition within that bin. |
| `api.captureWindowPreset(monitorId, allMonitors)` | Detached monitor slots containing saved geometry and app navigation state. |
| `api.previewWindowPreset(slots, assignments)` | Plan per slot, including missing, minimized and visible windows. Assignments map source monitor IDs to targets or `false` to skip. |
| `api.applyWindowPreset(slots, assignments)` | Saves the replacement layouts for the assigned monitors and starts restored views. |

IO Scope uses a bounded per-side event history in memory. It can show changes reported by the bridge between OS ticks. The shared IO picker tests outputs with a temporary snapshot override and restores the current desired state without changing the selected app's route. The server checkpoints any newly managed side before the test so its next boot can clear an interrupted test.

# App and network reference

## Single-file apps

The installer contains no apps. A user app is a Lua file returning an app table, stored as `apps_NAME.lua` in the OS computer root. It executes only if `enabledApps[APP_NAME] = true` in `configs_os.txt`; restart the OS after changing this setting. The default is an empty table. The saved legacy `appRegistry` does not enable execution. Enabled app definitions are registered at OS boot. Ordinary apps initialize when first opened (or when saved views restore), run while any view exists, and stop after their last view closes. Apps with `backgroundService = true`, and apps without a render hook, start at boot and continue with zero views. Optional apps are `apps_coffee.lua` and `apps_switchboard.lua`.

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

An app may attach `styles` to its returned array of text rows. Each style is `{x, y, width, height = 1, fg, bg}` in content coordinates, with numeric CC colour constants. Styles affect foreground/background without replacing text and are clipped to the content area. For example, `return {"Settings", styles = {{x = 1, y = 1, width = width, fg = 1, bg = 2048}}}` paints a blue heading. Old plain-text apps remain supported. Coffee's button helper generates its text, colour rectangle and hit rectangle from the same geometry. `lib_gui.lua` composes and encodes surfaces centrally; app code never draws on a peripheral.

Bundled-v9 adds optional `app.title` (1–64 characters) for launcher, taskbar and title-bar display; the filename/app identifier remains unchanged. **Every future app Settings menu should include UI colour** and use `api.getAppColour(context.appName)` for its heading/primary controls. Call `api.pickColour(context.windowId)` from that setting; the OS handles the palette, validates/saves the accent and returns to the underlying page. No app-specific colour callback or duplicate colour state is needed. Switchboard instead composes `api.ui.palette` with a draft preview and Apply/Cancel, committing its accent through `api.setAppColour`; the shared saved accent remains OS-owned. Use `api.ui.contrast(accent)` for text on the accent.

`api.ui.content(width, height)` supplies `lines`, `hits`, `text`, `heading`, `style`, and `button`; the returned `lines.hits` aliases the same rectangles used for interaction. `api.ui.menu(width, height, title, items, page, backAction, accent)` returns `lines, hits, page, pages`, with pagination only when needed. Items use `{label, action, enabled}`. `api.ui.hit(hit, x, y)` supports both one-row and rectangular controls. These helpers are pure layout functions and do not touch peripherals. Coffee is the reference for responsive action placement and parent navigation.

Hooks must return promptly and must not call `sleep`, `read`, `os.pullEvent`, HTTP, or other yielding functions. Lua 5.1 hooks run under `pcall` for fault isolation. Apps are trusted code, not sandboxed plugins.

| API | Result |
| --- | --- |
| `api.mapOutput(name, clientId, side, color, initialValue)` | `ok, error`; nil colour means ordinary/digital redstone; otherwise one CC colour bit. Optional boolean sets initial intent for a previously unused wire; new references to an existing wire adopt its state. Rebinding an unchanged address with an explicit boolean sets shared intent |
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
| `api.watchSensor(key, address)` | Keeps a selected target subscribed for ten seconds; call from background while needed. Duplicate addresses share one client poll |
| `api.unwatchSensor(key)` | Removes this subscription; shared addresses continue if other subscriptions exist |
| `api.getSensorReading(address)` | Structured status, raw `data`, age, error, target info and optional normalized `reactor` reading; never restores saved telemetry as live |
| `api.getSystem()` | `{gameTime, clockSource, playerOnline}`; Minecraft time is read locally through `os.time()`, with sensor fallback |
| `api.getClients()` | Sorted `{id, type, online, computerId, via, hops, route, forwarded}` records; includes relays and every original endpoint separately. `via` lists relay IDs from device towards OS; `route` also includes their computer IDs; relay-only `forwarded` is its last reported count |
| `api.openApp(name, monitorId, x, y, width, height)` | `windowId, error`; geometry optional, outer dimensions |
| `api.closeWindow(windowId)` | `ok, error`; closes only this view and stops a normal app after its last view |
| `api.placeWindow(windowId, x, y, width, height)` | `ok, error`; nil fields retain the old values |
| `api.layoutWindow(windowId, mode)` | `ok, error`; maximize, restore, left/right/top/bottom, top_left/top_right/bottom_left/bottom_right, or `grid_CxR_X_Y` for 1–3 columns/rows and a 1-based column/row position (e.g. `grid_3x3_2_3`) |
| `api.getAppColour(appName)` | Saved app accent, default blue; shared by all its views |
| `api.setAppColour(appName, colour)` | `ok, error`; validates/saves or rolls back on failure |
| `api.pickColour(windowId)` | Opens the shared palette for this window's app; selection saves automatically |
| `api.getOSSettings()` | `{backgroundMode = "solid", backgroundColour, windowBorderColour, taskbarColour}` |
| `api.setBackgroundColour(colour)` | `ok, error`; changes the static background on all desktops |
| `api.setWindowBorderColour(colour)` | `ok, error`; saves one frame/title colour for all windows; Close stays red |
| `api.setTaskbarColour(colour)` | `ok, error`; saves the taskbar background across monitors; text/highlights adapt for contrast |
| `api.save()` | `ok, error`; checkpoints central state |
| `api.invalidateAppViews(appName)` | Advances input revisions for every monitor displaying this app after shared structural edits; normal telemetry/clock updates need no invalidation |

Physical sides use computer-relative names. Mappings are independent of apps and persisted centrally. All mapped sides are fully owned by the OS. Input/sensor values are live observations, not restored stale values. Losing a sensor client clears its supplied system indicators.

## Per-window settings and shared IO selector

`init` receives an optional third argument `{appName}`. `render` and `handleTouch` receive an optional final `context = {appName, windowId, monitorId, view}`. Old apps can ignore these extra arguments. `view` is transient state for this particular window's menus/drafts; app `state` remains shared persistent business data. Closing a window discards its draft menus. Other views keep the app running; the last close stops an ordinary app, while a background service continues. Persist applied settings in `state` and checkpoint them.

An app can request `api.pickIO(context.windowId, "playerInput", "input", state.playerInput)`. The OS draws a paginated client → side → Digital/colour menu, with an explicit Use/Cancel review. It offers all known IO clients, marks offline ones, and excludes unavailable sides. Selecting Use invokes:

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

A mapping includes `clientId`, `side` and optional bundled `color`; nil colour means Digital. Multiple logical names may reference one wire. An explicit boolean `value` sets the shared desired state for every reference, even names outside the batch. Mapping-only `initialValue` supplies an initial intent for a previously unused wire; it adopts the current state when linking an existing wire. Do not combine `value` and `initialValue`. If neither is supplied, existing physical state takes precedence, then previous logical intent (default OFF). Contradictory explicit values for one wire in one batch are rejected. Value-only operations need existing mappings. Removal clears only this reference and its named value. Empty arrays checkpoint caller app-state edits without changing IO. New mappings are checked against online client capabilities. Duplicate logical names in one batch remain invalid.

The group and caller's current app state save before hardware sync. Validation/save failure changes no mappings, intent or hardware; apps must restore their own edited state on failure, as Switchboard does. Released sides remain in the snapshots so unused old wires clear; shared wires remain driven by their surviving references. Physical snapshot changes receive one new revision per affected client after the checkpoint. Unchanged snapshots retain their revision and confirmation. Normal cooldown/retry/ACK semantics apply. Routine announcements preserve known ACKs; reconnects, restarted announcement counters and changed capabilities invalidate confirmation. Changed capabilities get a fresh revision so clients cannot acknowledge an obsolete snapshot. This is an atomic central checkpoint, not simultaneous switching across computers. Switchboard uses it for presets, route changes, grid shrink, disconnect/delete and All OFF. Existing `mapOutput`/`setOutput` remain compatible with Coffee.

## Selected sensor targets (bundled-v15)

Sensor addresses are `{clientId, side, target, card, targetType}`. The target is the exact key returned by OpenCCSensors, often relative coordinates. Card and target type protect against silent reassignment to incompatible devices. `pickSensor` calls the app's optional `handleSensorSelection(key, address, state, api, context)` hook. Return `true` after saving the binding, or `false, error` with rollback; it uses the same per-window overlay/callback pattern as IO. Multiple reactors/entries may share one card/client with different target keys, or share an identical address across monitors.

After shared structural configuration changes, Reactors calls `invalidateAppViews`. This rejects queued touches from old card/entry layouts on other monitors, including when deleting a reactor shifts another control into its former position. Ordinary sensor value updates do not invalidate input.

`apps_reactors.lua` is the reference: background renews every configured subscription, reads cached telemetry synchronously, and shutdown removes its watch keys while preserving manual output intent. The sensor client performs asynchronous peripheral work, so app hooks never wait for a sensor. A normal app with no remaining views stops its subscription renewals; services can renew at boot without windows. Live state is runtime-only. `getSensorReading` returns `unconfigured`, `waiting`, `offline`, `missing`, `card_changed`, `target_changed`, `no_card`, `detached`, `error`, `stale`, or `ok`, depending on source state. Only an `ok` result with a valid `reactor` record is a live reactor observation. Historical data may accompany an error/stale result; inspect status before using it.

The bridge announces `sensorProtocol = 1` and persisted `bootId`; every catalog/sample is bound to OS session, sender, client ID and boot ID. Catalogs contain at most 64 target summaries per part and 64 parts per port. `sensorWatch` supplies a deduplicated list of at most 128 targets per client and retries every three seconds. `sensorSample` carries at most sixteen 12,000-character chunks with increasing sequence IDs. The hub publishes only complete, validated tables; old/incomplete packets cannot partially overwrite a reading. Unchanged samples use a compact heartbeat naming the exact complete base snapshot. Missing that base cannot renew older data, and periodic full samples recover loss. Scalar `sensorData` stays separate for old adapters. Limits and physical setup are in [the sensor guide](documentation_sensors.md).

Bundled-v17 normalizes empty/control-only display names using a nonempty `Type`, `type`, `Name`, then `RawName`, finally `Unknown`. Catalog targets retain optional `rawName` (up to 128 characters); reactor classification uses both display and raw identity, matching OCS 1.4.7's native `Name`/`RawName` shape. The hub also tolerates blank/missing string types from older clients, while rejecting invalid addresses or structured/oversized type fields. This stops one unnamed machine invalidating an entire side. Names and kind are informational; valid reactor details still require actual Heat/MaxHeat data. The picker explains missing/rejected catalogs and leaves known incompatible/error sides visible but disabled. `sensors [client]` prints source protocol/boot, card/side status, target/reactor counts, incomplete part counts and the latest catalog rejection. These diagnostics are runtime-only and do not change saved bindings or output intent.

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

Bundled-v8 monitors announce `touchProtocol = 1`. Render packets add `frameId`, `inputRevision`, `colourFormat = "rle1"`, and `foreground`/`background` row arrays. Each colour row is run-length encoded as repeated two-hex-digit counts (1–255) plus one colour digit (0–f, corresponding to `2^index`). The bridge validates full rows and draws contiguous spans with legacy colour setters and `write`; `blit` is not required. Older frame IDs are discarded, and cache keys include colours as well as text.

New clients echo the displayed `inputRevision` with each touch. The OS advances it when interactions/layouts change and accepts only the current revision; stale touches trigger a replacement frame without applying an action. Background clock-only changes do not advance it. The bridge's event collector buffers modem/touch/timer events while its worker waits on peripheral calls, capturing each touch's revision at receipt. Old clients without the capability retain legacy input behavior. Install both new roles for the full colour/input behavior.

Optional per-side `touchOffsets` in `configs_monitor.txt` are measured with `clients_monitor_client.lua calibrate [side]`. Bundled-v12 uses nine circle targets and requires a live-test Save before persisting a proposal. Per-axis medians must be within one cell of every sample, with every measured correction inside ±3. Nonzero proposals need at least 7/9 matches on their axis; lower agreement proposes zero and shows mixed readings. Diagnostic averages can be fractional, but persisted/applied offsets remain integer character cells because touch events have no sub-cell position. Arrow controls adjust a proposal; `0`/Reset restores a zero proposal, `S` saves, `R` remeasures and `C` cancels. `--test` starts from the current saved value without sampling. `--reset` explicitly saves `{x=0,y=0}` immediately for that side. Failed saves/cancellation preserve the previous correction and other sides. App content origin is `(win.x + 1, win.y + 1)`; forwarded local coordinates are `(touch.x - win.x, touch.y - win.y)`. No guessed global offset is applied by the OS.

## Local OS console

`lib_console.lua` owns the local terminal, with log output above a fixed bottom-row command editor. Server/network constructors accept an optional logger (`Server.new(net, storage, config, logger)`, `Network.new(config, isServer, logger)`); other callers retain normal `print` logging. `api.log(...)` routes app messages through that console, preserving a draft and its insertion cursor. Apps should not draw to the OS computer's terminal directly. `clear` is an OS command that clears only the console; it does not save/reset app state, clear outputs, close monitor windows or stop the server. Up/Down history is transient and bounded to 50 commands; message history is bounded to 200 logical lines. No `read`, terminal redirection or newer window API is used.

The bundled-v15 generic sensor adapter uses the existing announce/welcome/session process plus typed catalogs, selected subscriptions and bounded multipart samples; see [sensor setup and protocol](documentation_sensors.md). Legacy scalar `sensorData` remains supported with `varName`, scalar `value`, and `serverSession`: `playerOnline` must be boolean and `gameTime` a string, and values remain isolated under their client. New reactor/ME tables never overwrite OS state or system indicators.

The desktop stores normalized free rectangles and named snap zones, and reserves the bottom row for its taskbar. Its two-step flyout first chooses a grid, then a pane; choosing the grid alone does not change saved geometry. Resize and Move remain first-level actions. Each pane is partitioned from shared integer boundaries, including thirds. User layout menus and placement are OS overlays, so application hooks need no pointer-drag handling. See [desktop behavior](documentation_desktop.md).

Built-in OS settings lives in `lib_settings.lua` and a private system-app registry, with saved window identifier `@settings`. It is always offered by Start and requires no `enabledApps` entry or app download. User-app registration/consent remains separate. The saved state's `appearance` table holds `backgroundColour`, `windowBorderColour`, `taskbarColour` and `appColours`; these are separate from business state in `appStates`. Border/taskbar defaults are gray. `api.pickColour(windowId, target)` supports the system-only targets `background`, `windowBorder` and `taskbar` in an `@settings` view; ordinary apps use the default app-accent target. System colour choices affect every monitor and use automatic text contrast. Border colour applies to title bars and frames, with a red Close control. Taskbar geometry and text coordinates are unchanged. Cosmetic changes checkpoint immediately and roll back on save failure. A future screensaver can extend desktop appearance; only solid background colour is implemented now.

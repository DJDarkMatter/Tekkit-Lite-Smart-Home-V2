# App and network reference

## Single-file apps

The installer contains no apps. A user app is a Lua file returning an app table, stored as `apps_NAME.lua` in the OS computer root. It executes only if `enabledApps[APP_NAME] = true` in `configs_os.txt`; restart the OS after changing this setting. The default is an empty table. The saved legacy `appRegistry` does not enable execution. Enabled app definitions are registered at OS boot. Ordinary apps initialize when first opened (or when saved views restore), run while any view exists, and stop after their last view closes. Apps with `backgroundService = true`, and apps without a render hook, start at boot and continue with zero views. `apps_coffee.lua` is the first optional app.

Explicit installation uses the same installer: `inst app APP_NAME` downloads the root file `apps_APP_NAME.lua` from `DJDarkMatter/Tekkit-Lite-Smart-Home-V2` on GitHub (`main` branch). `inst app APP_NAME --ref BRANCH_OR_COMMIT` selects another ref. Apps therefore need no separate Pastebin upload. Optional alternatives remain `inst app APP_NAME PASTE_ID` or `inst app APP_NAME --file /path/to/app.lua`. The installer checks syntax, installs the file and enables that one app for the next OS start. It preserves existing settings, startup and saved app state, backing up replaced code/settings. It does not execute the app at install time. GitHub mode uses the CC 1.5 `http.get` API; role installation remains offline and app-free.

Bundled-v7 tries the raw file first, then the GitHub contents API if needed. The API response is decoded from base64 without `textutils.unserializeJSON`; it must describe the requested filename with a matching decoded size and valid Lua. Request exceptions are caught through a child coroutine so CC 1.5 HTTP can still yield; response handles are closed and termination aborts without retrying. Failures print separate raw/API reasons before any app/settings replacement. Server network restrictions and Java TLS failures require server-side investigation.

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

Hooks must return promptly and must not call `sleep`, `read`, `os.pullEvent`, HTTP, or other yielding functions. Lua 5.1 hooks run under `pcall` for fault isolation. Apps are trusted code, not sandboxed plugins.

| API | Result |
| --- | --- |
| `api.mapOutput(name, clientId, side, color, initialValue)` | `ok, error`; nil colour means ordinary/digital redstone; otherwise one CC colour bit. Optional boolean sets mapping and initial intent in one checkpoint, useful for safely binding a new wire OFF |
| `api.setOutput(name, boolean)` | `ok, error`; saves desired state before sending it |
| `api.getOutput(name)` | Desired boolean; false if unknown |
| `api.getOutputs()` | Sorted array of `{name, clientId, side, color, value, online, confirmed}` |
| `api.getInput(clientId, side)` | `{value = bundledMask, digital = boolean}`, or nil if unknown/offline |
| `api.readInput(address)` | Boolean for one Digital/bundled input, or `nil, reason` if unconfigured/offline; address is `{clientId, side, color}` with nil color for Digital |
| `api.getIOClients()` | Sorted `{id, computerId, online, sides}` records; sides exclude the modem and unavailable/config-disabled ports |
| `api.pickIO(windowId, key, direction, currentAddress)` | Opens the reusable touch selector in this window; direction is `input` or `output`. Needs at least 12×6 content characters |
| `api.getSensor(clientId, name)` | Raw scalar reading, or nil if unknown/offline |
| `api.getSystem()` | `{gameTime, clockSource, playerOnline}`; Minecraft time is read locally through `os.time()`, with sensor fallback |
| `api.getClients()` | Sorted array of `{id, type, online, computerId}` |
| `api.openApp(name, monitorId, x, y, width, height)` | `windowId, error`; geometry optional, outer dimensions |
| `api.closeWindow(windowId)` | `ok, error`; closes only this view and stops a normal app after its last view |
| `api.placeWindow(windowId, x, y, width, height)` | `ok, error`; nil fields retain the old values |
| `api.layoutWindow(windowId, mode)` | `ok, error`; maximize, restore, left/right/top/bottom, top_left/top_right/bottom_left/bottom_right |
| `api.save()` | `ok, error`; checkpoints central state |

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

The callback should validate/apply the change, roll back its own state on failed save/mapping, and return `true` or `false, error`. For outputs use `api.mapOutput` and a logical output name; apps never write redstone directly. The coffee callback demonstrates committing an OFF binding with its address. A future switchboard can reuse the same picker for each output.

OS checkpoints include all app states and window position/size/order/minimized status, snap/restore metadata and per-monitor taskbar scrolling at an interval no longer than one second, even when an older config still specifies 30 seconds. Important transitions and applied settings save immediately. This is checkpoint recovery, not an exact transaction with the external Minecraft machine.

`dt` is elapsed ComputerCraft `os.clock()` time between OS ticks. It is not reconstructed across program/server downtime. A real coffee app must define its own online/pause/harvest state transitions and explicitly save important counters.

## Transport

`lib_network.lua` handles modem detection, string encoding and envelope checks. Configuration is a serialized Lua table in `configs_network.txt`.

- Server listens on `channel` (default `45231`).
- Client listens on `1000 + (computerId % 40000)`, substituting `41001` if that equals the server channel.
- Clients announce to the server channel with their own channel as `replyChannel`.
- Server replies to that channel with its server channel as `replyChannel`.
- Every message is `textutils.serialize(packet)`; receivers use protected `textutils.unserialize`.

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

## Handshake and output state

1. Client sends `announce` with `clientType` (`io`, `monitor`, `sensor`), an increasing `nonce`, and capabilities/resolution.
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

A future sensor adapter must implement the same announce/welcome/heartbeat process. Once welcomed, send `sensorData` with `varName`, scalar `value`, and `serverSession`. `playerOnline` must be boolean and `gameTime` must be a string; other names remain raw readings under that sensor client. There is no sensor peripheral driver included yet.

The desktop stores normalized free rectangles and named snap zones, and reserves the bottom row for its taskbar. User layout menus and placement are OS overlays, so application hooks need no pointer-drag handling. See [desktop behavior](documentation_desktop.md).

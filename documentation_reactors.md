# Reactor panel

`apps_reactors.lua` is the optional **Reactors** app. It runs on the central OS, using the generic [sensor client](documentation_sensors.md). The display follows the supplied Core 1/Core 2 reference: heat, maximum heat, melting threshold, output, remaining time and actual On/Off state, with a coloured heat bar and separate manual switch.

## Install and add reactors

Upload the current package files to the V2 repository root. Replace your installer paste with bundled-v15 `install.lua`, download a fresh `inst`, and quit the central OS to CraftOS:

```text
cd /
inst server --startup
inst app reactors
reboot
```

Install `inst sensor --startup` on the sensor computer. Existing monitor/IO clients need no update. Apps are not bundled or enabled by a role install; only `inst app reactors` downloads/enables this app. Coffee and Switchboard remain unchanged.

Open **Reactors** through the monitor's `[+]` launcher:

1. **+ Add reactor**.
2. Select the sensor client.
3. Select the sensor peripheral side/card.
4. Select the detected reactor target.
5. Review and press **Use**.

The entry opens immediately. Repeat to add more reactors from the **same card/client**, choosing different target keys, or use other sensor clients. Up to 64 entries are supported. Reactor-compatible target/card choices are filtered; the dedicated Applied Energistics card remains available to the generic client for future ME use, not as a substitute reactor card.

The home screen displays multiple reactor cards side by side when the window is wide enough, with Add and Settings below. It pages on smaller windows/monitors. Touch a card to open its full readout; small readouts page the metrics. Back returns to the overview. The same saved reactor can appear on several monitors; settings/outputs are shared, navigation remains per window.

## Readings

| Field | Meaning |
| --- | --- |
| Heat / T | Raw hull heat supplied by the sensor; no invented Celsius conversion |
| MaxHeat | Sensor-reported maximum hull heat |
| Melting | Sensor-provided melting point, when available |
| Melting* | Otherwise calculated as 85% of MaxHeat, matching the reference's 49,300 at 58,000 maximum; the asterisk marks this derived value |
| Output | Sensor-reported EU/t |
| Remaining | Card-reported remaining duration, formatted as hours:minutes:seconds |
| On / Off | Actual `Active` reading from the sensor, independent of the manual switch |

**Remaining time is not fabricated.** The old OpenCCSensors IC2 reactor target exposes core operating fields but does not necessarily expose fuel lifetime. This app displays **Unavailable** (`n/a` on compact pages) if there is no supported remaining-time reading. The screenshot is a reference for the layout; it does not establish that every field is available through this mod API. Edit → **Raw readings** lists the fields received on your actual server, helping identify additional supported data for later adapters.

Supported time fields include numeric `RemainingTime`, `TimeRemaining`, `Remaining`, `remainingTime`, `FuelRemainingSeconds` (seconds), explicit `RemainingTicks` (Minecraft ticks, divided by 20), or an hours:minutes:seconds string. Unknown data is `?`/Unavailable, not zero. Genuine zero remaining and actual Off are preserved.

Data age is shown in roomy readouts. Missing cards/targets, a changed card/type, request errors, stale readings and offline clients are labelled; last available values may appear gray but never claim to be live. Replacing a same-type machine at the same mod target address cannot be identified uniquely by these sensors.

## Per-reactor switch and editing

Press **Set IO** on a card/readout, or Edit → **Control output**. Select **IO client → physical side → Digital or bundled colour → Use**. Each reactor can use any available output on any IO client; its sensor and control computer need not be the same. Previously unused wires start OFF; shared routes adopt their existing state.

The control reads **Switch ON/OFF**, showing saved requested output intent. Orange/dots mean acknowledgement is pending; offline output status is red. The reactor's separate **On/Off** indicator reflects observed activity. The app never assumes that a commanded output successfully started the reactor, and it does not add automatic shutdown or restart logic. ON means energize the selected output; wire the reactor accordingly.

Each Edit menu offers **Rename**, **Sensor target**, **Control output**, **Raw readings** and confirmed **Delete reactor**. Names use a touch keyboard with letter pages, case/digit modes, Space, Del, Clear, Save and Back. Changing or deleting an output reference releases only that reference; an unused old wire turns OFF after a successful checkpoint, while other shared references retain their state. Every copy controls the same shared desired value.

Home → **Settings** offers **UI colour**, **Panel colour** and **About readings**. Both colour palettes stage selection before Apply/Cancel and include a preview at 24×15 content characters or larger. OS window borders/taskbar stay independent.

## Persistence and lifecycle

Names, sensor bindings, output bindings, panel colour and stable IDs are saved in `appStates.reactors` within `configs_os_state.txt`. Desired output state remains in the OS's shared output map. Important edits and commands save before IO; failed saves roll back. Geometry is restored by the OS. Current readings are runtime data and must arrive again after restart.

Reactors is a normal app: it runs while at least one window exists, including minimized/covered windows. Closing its last window releases its sensor subscriptions and stops detailed polling, while saved manual switch intent stays applied by the OS. Reopening/restoring a window subscribes again. No background alarm/history service or automatic reactor control is introduced.

Tests use real app, server, sensor, IO and monitor entry points under simulated ComputerCraft Lua 5.1, including old asynchronous OCS replies. In-game values, sensor range, physical wiring and rendering still need verification on the user's server.

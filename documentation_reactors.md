# Reactor panel

`apps_reactors.lua` is the optional **Reactors** app. It runs on the central OS, using the generic [sensor client](documentation_sensors.md). The display follows the supplied Core 1/Core 2 reference: heat, maximum heat, melting threshold, output and actual On/Off state, with a colored heat bar and separate manual switch.

## Install and add reactors

Upload the current package files to the V2 repository root. Replace your installer paste with bundled-v22 `install.lua`, download a fresh `inst`, and quit the central OS to CraftOS:

```text
cd /
inst server --startup
inst app reactors
reboot
```

Install `inst sensor --startup` on the sensor computer. Existing monitor/IO clients need no update. Apps are not bundled or enabled by a role install; only `inst app reactors` downloads/enables this app. Coffee and Switchboard remain unchanged.

For out-of-range computers, see [wireless relays](documentation_relay.md). Update the OS and each endpoint that should use relays to v16, then install relay computers along the path. Reactors itself needs no app update for relaying. Its sensor and IO selections continue to show the actual devices, including devices reached through several relays.

If a connected sensor reports targets locally but the selector has no available side, update the OS and sensor roles to v17. It fixes blank machine names rejecting the whole catalog and preserves OCS raw reactor identities behind localized names. The selector now explains waiting/rejected data. `sensors sensor_ID` on the OS shows received sides, counts and catalog errors. Reactors, relays and saved bindings need no change for this repair.

Open **Reactors** through the monitor's `[+]` launcher:

1. **+ Add reactor**.
2. Select the sensor client.
3. Select the sensor peripheral side/card.
4. Select the detected reactor target.
5. Review and press **Use**.

The entry opens immediately. Repeat to add more reactors from the **same card/client**, choosing different target keys, or use other sensor clients. Up to 64 entries are supported. Reactor-compatible target/card choices are filtered; the dedicated Applied Energistics card remains available to the generic client for future ME use, not as a substitute reactor card.

The home screen displays multiple reactor cards side by side when the window is wide enough, with Add and Settings below. It pages on smaller windows/monitors. Touch a card to open its full readout; small readouts page the metrics. Back returns to the overview. The same saved reactor can appear on several monitors; settings/outputs are shared, navigation remains per window.

Bundled-v18 expands the detail view with heat headroom to melting/MaxHeat, supplied EnergyEmitted/EnergySunken counters, sensor ID, peripheral side, target key and native target type. Wide content areas (50 characters or more) use two columns. Long fields wrap and small windows page all fields; the pager no longer shares the data-age row. The heat bar shows the precise calculated percentage. Native energy counters use compact EU units and are not app-maintained lifetime totals. Negative headroom means the reported heat is above that threshold. No chamber or secondary sensor is added automatically; the selected core remains the only source.

## Readings

| Field | Meaning |
| --- | --- |
| Heat / T | Raw hull heat supplied by the sensor; no invented Celsius conversion |
| MaxHeat | Sensor-reported maximum hull heat |
| Melting | Sensor-provided melting point, when available |
| Melting* | Otherwise calculated as 85% of MaxHeat, matching the reference's 49,300 at 58,000 maximum; the asterisk marks this derived value |
| Output | Sensor-reported EU/t |
| On / Off | Actual `Active` reading from the sensor, independent of the manual switch |

**The stock old IC2 card does not supply fuel lifetime or reactor inventory.** Its [reactor-target source](https://github.com/Cloudhunter/OpenCCSensors/blob/6a8c39407ebfde0d2ccfb049b7f9ff7108dd5b62/src/openccsensors/common/sensors/targets/industrialcraft/ReactorTarget.java) reports heat, maximum heat, output, activity and percentage; the [IC2 card implementation](https://github.com/Cloudhunter/OpenCCSensors/blob/6a8c39407ebfde0d2ccfb049b7f9ff7108dd5b62/src/openccsensors/common/sensors/IndustrialCraftSensor.java) offers no extra lifetime method. Selecting the core instead of a chamber does not add that missing field. Adding chamber views cannot repair it. A real fuel countdown needs another source that exposes fuel wear/lifetime. The original reference panel uses a different data interface; it cannot establish that OCS supplies the same fields. V26 removes the Remaining readout from overview cards, detail pages and color previews. It does not guess fuel lifetime from heat/output or create a manual countdown.

For adapters that do supply time, supported seconds fields are `RemainingTime`, `TimeRemaining`, `Remaining`, `remainingTime`, `FuelRemainingSeconds`, `RemainingSeconds`, `remainingSeconds`, `RemainingTimeSeconds`, `TimeLeft` and `timeLeft`. Numeric strings and hours:minutes:seconds are accepted. Explicit `RemainingTicks`, `remainingTicks` and `TimeLeftTicks` accept numbers/numeric strings and are divided by 20. Invalid, negative, nonfinite or oversized durations are ignored; genuine zero is retained. This backend compatibility parsing remains intact, but the operational app no longer displays a Remaining or Time field row. Raw diagnostics retain data that was actually reported.

Edit → **Raw readings** now expands nested fields to four levels, wraps long values and pages the output, with a 256-line display bound. This can reveal server-specific fields for future adapters without pretending they are available on every installation.

Data age is shown in roomy readouts. Missing cards/targets, a changed card/type, request errors, stale readings and offline clients are labelled; last available values may appear gray but never claim to be live. Replacing a same-type machine at the same mod target address cannot be identified uniquely by these sensors.

## Per-reactor switch and editing

Press **Set IO** on a card/readout, or Edit → **Control output**. Select **IO client → physical side → Digital or bundled color → Use**. Each reactor can use any available output on any IO client; its sensor and control computer need not be the same. Previously unused wires start OFF; shared routes adopt their existing state.

The control reads **ON** or **OFF**, showing saved requested output intent rather than naming the next action. Orange/dots mean acknowledgement is pending; offline output status is red. The reactor's separate **On/Off** indicator reflects observed activity. The app never assumes that a commanded output successfully started the reactor, and it does not add automatic shutdown or restart logic. ON means energize the selected output; wire the reactor accordingly.

Each Edit menu offers **Rename**, **Sensor target**, **Control output**, **Raw readings** and confirmed **Delete reactor**. Names use a touch keyboard with letter pages, case/digit modes, Space, Del, Clear, Save and Back. Changing or deleting an output reference releases only that reference; an unused old wire turns OFF after a successful checkpoint, while other shared references retain their state. Every copy controls the same shared desired value.

Home → **Settings** offers **UI color**, **Panel color** and **About readings**. Both color palettes stage selection before Apply/Cancel and include a preview at 24×15 content characters or larger. OS window borders/taskbar stay independent.

## Persistence and lifecycle

Names, sensor bindings, output bindings, panel color and stable IDs are saved in `appStates.reactors` within `configs_os_state.txt`. Desired output state remains in the OS's shared output map. Important edits and commands save before IO; failed saves roll back. Geometry is restored by the OS. Current readings are runtime data and must arrive again after restart.

Reactors is a normal app: it runs while at least one window exists, including minimized/covered windows. Closing its last window releases its sensor subscriptions and stops detailed polling, while saved manual switch intent stays applied by the OS. Reopening/restoring a window subscribes again. No background alarm/history service or automatic reactor control is introduced.

Bundled-v19 fixes the OS-side cleanup crash seen after closing the last window (`lib_sensor_server.lua:199: invalid key to 'next'`). If Reactors is already installed, update only the server role using a fresh v19 installer and reboot the OS; do not reinstall the app or clients for this fix. Closing one of several windows continues to leave the app and its subscriptions running.

## A possible fuel-time source in Tekkit Lite

An additional OpenCCSensors Inventory Sensor Card exposes per-slot item identity, count and DamageValue. A [period Tekkit Lite reactor-control program](https://forums.technicpack.net/topic/39819-cc-breeder-reactor-control/) specifically describes using inventory-sensor uranium usage to determine cycle time. This makes fuel inspection a candidate, rather than requiring more chamber readings. However, the [native inventory helper](https://github.com/Cloudhunter/OpenCCSensors/blob/96e89c135c846c406f6eea3f7006ac5b81dbcf68/src/openccsensors/common/helper/InventoryHelper.java) reports ordinary item damage with NBT disabled; we must verify what the actual fuel item on this server reports before promising an exact remaining-time formula. Nuclear Control location cards use a different interface and are not OpenCCSensors cards. V21 does not add fuel bindings or a guessed reactor countdown.

Tests use real app, server, sensor, IO and monitor entry points under simulated ComputerCraft Lua 5.1, including old asynchronous OCS replies. In-game values, sensor range, physical wiring and rendering still need verification on the user's server.

## Responsive extra fields and removed Remaining display (v26)

The Remaining/n/a/Unavailable lifetime row and its palette preview are removed completely. There is no blank/nil placeholder. The overview uses the available card area for actual reactor entries instead of reserving empty rows for absent reactors, so one or two reactors get more room on large monitors. Essential heat, maximum heat, melting threshold and EU/t stay first. Where space permits, cards add precise heat percentage, headroom to melting/max, supplied emitted/received energy counters and extra scalar sensor fields. Touch a card for the full paginated detail view; small windows keep the compact labels and essential fields.

Detail pages show genuine reported extra numeric, boolean and short string fields (up to 32), omitting duplicate normalized fields and fuel-time aliases. Examples such as Chambers or Cooling appear only if the installed sensor actually provides them; the stock OCS 1.4.7 card normally supplies only Heat, MaxHeat, Output, Active, HeatPercentage and basic identity/relative position. Large detail windows use two columns; long label/value pairs keep a fitting number together on its own row. Integer counters use plain grouped digits without depending on legacy float formatting. Relative Position and raw type are shown when supplied. Heat percentage is not duplicated as a text row when the large detail heat bar already displays it.

No fuel/chamber/inventory subscriptions, output behaviour or state schema changes are introduced. Raw readings continues to expose actual source fields, including nested structures; unsupported metrics are omitted rather than filled with unavailable labels. Updating only this app uses `inst app reactors` on the central OS and a reboot; the core OS and client roles need no change for the display update itself.


## Independent output confirmation (v34 core update)

A reactor's manual IO switch now loses confirmation only when its own physical output changes. Other reactor controls on the same IO computer or bundled cable retain their known state. Controls sharing the same route change together. A toggle reads cached sensor data; it does not re-query every reactor. Real IO restarts/reconnects still invalidate all of that client's outputs until restoration is acknowledged. Update the central server with the bundled-v34 installer; neither the Reactors app nor the remote clients require reinstalling for this fix.

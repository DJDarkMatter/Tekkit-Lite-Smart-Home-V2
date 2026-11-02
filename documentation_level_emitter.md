# Level emitter

Install with `inst app level_emitter` on a **bundled-v30** central OS, then reboot. This independent background app watches selected AE1 item counts and raises saved popup/IO alarms. It shares the existing `ae_items` feeds with other ME apps. No Level emitter window needs to remain open.

Choose **+ Add**, then sensor client → side → ME target → Use → item. Each rule has its own source, so Main ME, Farm ME and any additional ME networks can be monitored independently. Use **Find → Manual item** to register an item that is currently absent, providing exact RawName, damage and display name. Name/Amount sorting, search, registered identities and source selections are saved. Selected count variants remain separate; this old sensor card does not expose NBT.

Set a name, **Under (<)**, **Over (>)** or **Exactly (=)**, and a whole-number level. A hold interval requires continuous known matching data. A valid complete inventory reports zero for an absent item; an offline/unpowered/incomplete source is unknown and cannot trigger an empty-stock alarm. Holds restart after unknown data, client reboot or an OS restart.

Each occurrence creates an OK popup above every monitor, including fullscreen apps and the screensaver. After acknowledgement the rule remains latched until its non-trigger/reset condition is observed. Under rules rearm at/above their reset value; Over rules at/below it; Exactly rearms when the count differs. Reset can equal the strict comparison threshold. Imported Solar farm rules retain their original inclusive **At least** comparator and lower reset level until explicitly edited.

## Signals and acknowledgement

Output selection is optional; without it, the rule only raises a popup. Select any IO client, available side and bundled colour, or digital line, through the normal picker.

- **Constant**: ON for the configured real seconds. Length **0** stays ON until dismissed.
- **Pattern**: alternate the selected ON/OFF seconds. Total **0** repeats until dismissed; a positive total stops after that many real seconds.

Positive finite durations stop the output but leave the popup waiting for OK. Pattern ON/OFF intervals are at least one second. An optional separately selected redstone input dismisses the occurrence and closes its popup. It must be observed LOW then HIGH; already-high or unknown/reconnected inputs do not dismiss saved alerts. OK has the same effect on every monitor and stops the active signal.

Rules can share output routes. Within Level emitter their active signal phases combine so one alarm ending does not turn off another active alarm on the same wire. Other apps retain the OS's existing shared-routing semantics. All hardware changes use the normal IO queue and per-side cooldown; this app never writes a peripheral directly.

Rules, names, exact item/source identities, appearance, pending popups and active signal progress survive checkpoints/restarts. They continue with all windows closed. Changes to a triggered or concurrently edited rule cannot silently overwrite newer state. Failed trigger/acknowledgement saves retain prior output/popup intent for retry. Disabling/deleting a rule clears its owned occurrence/mapping, leaving unrelated aliases intact.

## v29 migration

Install Level emitter and the v30 Solar farm app **before rebooting**. Level emitter starts first and atomically moves old Solar farm rules into its own namespace. It retains original output mapping names, source addresses, enabled/latch state and pending episodes. Migration is idempotent and rolls back on save failure. Solar farm then changes to its rate-only schema. See [Solar farm update instructions](documentation_solar_farm.md).

# Solar farm overview

`apps_solar_farm.lua` is an optional single-file app installed as `solar_farm`. It reads two independently selected AE1 networks: **Farm** for inventory overview and **Main** for stock-based speed estimates. It runs centrally and shares the existing `ae_items` sensor feeds with ME monitors. SMF-specific production measurement is outside this app.

## Install and select sources

Upload the full v29 package to the V2 GitHub repository. On the central OS, stop its program with Ctrl+T, then run:

```text
cd /
inst app solar_farm
reboot
```

The existing bundled-v28 installer works unchanged. The new app requires a v25-or-newer OS and v22-or-newer AE sensor roles; an installation already using v28 needs no core/client reinstall or new Pastebin paste. User apps remain explicit downloads rather than installer payloads.

Open **Solar farm** from Start. Select **Main ME** and **Farm ME**, each through sensor client → peripheral side → AE Wireless Access Point target → Use. They may use different sensor computers or two targets visible to one sensor. The same clients/cards may serve the other ME apps. Both role bindings are saved centrally. Selecting the same target for both is allowed for testing and reported in Source details.

## Stocks, rates and pinned items

**Stocks** browses the farm's complete item catalog with ordinary decimal quantities. **Rate** browses the main network's items and their signed net change per hour. Find opens search, Name/Amount/Rate sorting, ascending/descending order, Refresh list and Manual item. Counts/rates update live while row order stays fixed until Refresh/Sort/Search; a changing value cannot silently move a touch target.

Pin useful items through **Menu → + Pin item**, or from an item's details. Up to 64 pins show farm stock, main net rate and, where space permits, main stock. Each pin can be renamed and coloured. Larger windows use a tiled dashboard; 1×1 screens page pins, and fullscreen can show more cards. Item details show counts, sampled time, excluded drops and a rate-history graph when the window fits it. Graph colours distinguish positive/negative rates, observed zero and missing-data gaps.

Source details include both source addresses/statuses, item identities, total counted stock, and available native used/free bytes and item room. Detailed drive/cell capacity remains in the independent ME storage app.

Item identity is RawName plus DamageValue, with a display-name fallback only when a raw name is unavailable. Equivalent stacks are summed, and damage variants remain distinct. The old AE card does not expose NBT, so equal raw-name/damage items with differing NBT cannot be separated. Choose **Manual item** to register an item that is currently absent: enter its exact RawName, damage and display name. Selected identities are saved independently of live amounts. A bounded catalog retains up to 1,024 registered/selected identities; when full, a new item replaces an unreferenced identity, preserving every pinned/alarmed binding.

## Meaning of the speed estimates

These are **filtered main-ME stock changes**, not gross production or per-SMF output. Positive changes include incoming crafted panels and any other additions. Small negative changes include consumption and transfers. Simultaneous additions/removals can cancel, and a player deposit can raise the estimate. Stationary items and intentional full/empty buffers are normal.

The default player-withdrawal filter excludes a downward movement only when it satisfies **both**:

- At least **64 items** were removed.
- The removal is at least **5%** of the preceding stock.

For example, removing 64 from 200,000 UU is counted as ordinary consumption; removing 100 from 1,000 HV panels is excluded. These defaults are a user-adjustable interpretation of the requested large-drop assumption. Menu changes the global minimum/percentage, and each pin can override either. Its details report the current rule and excluded event/magnitude counts.

An excluded interval contributes neither its stock delta nor sampled duration. The new quantity becomes the baseline immediately; the next increase is measured from that baseline, preventing a false recovery spike. Production concealed within a withdrawal cannot be reconstructed. Changing a filter resets the affected history/smoother so values measured under different rules are not silently combined.

The all-item Main list uses a 30-second exponential smoother. Pins retain up to 60 one-minute history buckets, with selectable 5/15/60-minute observed-time windows. Each average is total accepted delta divided by accepted sampled seconds, multiplied by 3,600. Sampled duration is shown rather than assuming a full window has been observed. Bucket boundaries make these approximate rolling windows.

Only new sensor samples contribute; repeated reads of the OS cache do not add deltas or time. Unchanged-but-fresh sensor heartbeats do contribute known zero changes. Error, unpowered or incomplete readings are unknown, never fabricated zero inventories. A missing item in a valid complete catalog is zero. Outages, sensor boot changes, intervals over ten seconds and OS restarts rebase the first reading without counting the stock difference through the gap. Source changes reset main histories. Historical buckets persist, but current inventory/baselines are runtime-only; they are never restored as fresh data. The history clock excludes OS downtime and is not a wall-clock audit trail.

## Item buildup alarms

**Menu → Stock alarms → + Add stock alarm** selects any current or registered item. Each alarm chooses **Main** or **Farm**, an enabled flag, trigger amount, hold seconds and a lower rearm amount. It triggers at/above the high threshold only while fresh stock continuously satisfies it. A gap/unpowered source resets the hold. It rearms at/below its lower threshold after acknowledgement; acknowledging a high stock episode does not immediately trigger it again. Withdrawal filtering affects rate estimates, not these inventory thresholds.

Each occurrence creates a persistent queued OK popup on every monitor, including fullscreen and monitors without a Solar farm window. An optional IO output supports **Constant** and **Pattern** signals. Constant length **0**, or Pattern total **0**, continues until dismissal; positive durations stop the output while the popup still waits for acknowledgement. Pattern on/off periods are at least one real second. Choose an optional IO input for dismissal. It must be observed LOW then HIGH after the alert; an already-high/reconnected input does not silently dismiss a saved alert.

OK or that fresh input press closes the occurrence across monitors and stops its signal. Multiple Solar farm alarms sharing an output are combined, keeping the wire ON while any current signal requires it. Outputs still share the OS's normal routing semantics with other apps and always use the existing per-side IO cooldown. Trigger/acknowledgement changes save before physical output intent is sent. Failed saves retain the prior signal/popup for retry.

## Background operation and persistence

Once explicitly installed, Solar farm starts its background service at OS boot without automatically opening a window. Closing its last window leaves rate tracking, subscriptions and alarms running. Selected sources, pins, item identities, filters, appearance, history, alarm episodes and active signal progress are checkpointed in `configs_os_state.txt`. Normal desktop checkpoints retain each window's page and selection. Active alerts restore after reboot; hold intervals begin again from fresh observations and no elapsed downtime is invented.

The app implements none of the farm's Solar farm/HV farm/Use minium switches, recipe rules, UU reserve thresholds or transport conditions. The only outputs it writes are explicitly configured alarm signals.

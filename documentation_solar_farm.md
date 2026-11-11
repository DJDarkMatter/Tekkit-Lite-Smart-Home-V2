# Solar farm

In **Menu → ME sources**, select the farm inventory and the main inventory. Farm supplies the item list. Main supplies finished HV panels. **HV panel type / detection** can select an exact item if several variants are present. The app can automatically select a unique HV item once it appears.

## Production and stock

The **HV output** card shows stock on Main and observed arrivals per minute and per hour. The first estimate requires one complete observation minute. It updates at the end of each further minute and uses the latest five completed live minutes at most. The item details also show the last complete minute's count and the time covered by the rate. A withdrawal does not count as a finished panel. After a reading gap, the next valid snapshot sets the baseline.

Solar, LV, MV and HV panels contribute 1, 8, 64 and 512 panel equivalents. The farm card shows equivalent stock in the farm. The combined equivalent rate measures the net change of weighted farm stock plus HV on Main. Consuming 64 LV panels and delivering one HV panel has zero net effect once both readings arrive. Intermediate transfers and manual inventory changes can affect individual observations.

These figures come from inventory snapshots. A deposit can look like an arrival. A withdrawal between samples can mask an arrival. Farm item rates show net stock change. Item details include recent changes, observed time and withdrawal filters.

The large display graphs the published HV rate across the selected **Graph/change** period. The plot uses six height levels over three character rows and leaves gaps when no live rate was available. **Rate unit** controls the table and graph. The large HV card shows both units.

## List and pins

**Production order** groups panels, components and materials. Recent activity determines order within each group, with item names breaking ties. The name colors match those groups. Counts use a high-contrast foreground. On dark rows, gains are lime and losses are pink. Compact windows with at least 22 content columns show the item, amount and rate on one line. Large values can use short units to fit. Tap a row to see its full name and values. Tap **Item** or **Amount** to sort directly. Tap the heading again to reverse it. The same choices are in **Menu → List sorting** on compact windows.

The default HV pin sits first. **Pin item** adds a shortcut for a farm item. Open **Edit pin** to rename it, change its color, customize its withdrawal filter, enable **Stick** or unpin it. Stick places a pin above the sorted rows. A saved pin can represent an absent item using **Find → Register absent item**.

Tracking continues while the window is closed. **Reset rate learning** resets observations for the selected source and keeps source and pin settings. The app starts a new HV rate history on upgrade and retains the saved farm stock history. Logic Sandbox handles item-count alarms.

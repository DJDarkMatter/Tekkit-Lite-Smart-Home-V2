# Version 37 — Screensaver Matrix and touch improvements

This is a Screensaver app update. The complete ZIP includes every project file and the v36 central startup fix. Its core and installer remain unchanged at **bundled-v36**, with 22 embedded core sources and no bundled apps.

## Changes

- The invisible Previous/Next areas are **2×2 character cells** at the top-left/top-right. Any other touch exits as before. Very tiny displays clip the areas so they do not overlap and an exit row remains available.
- Sparse Matrix uses the original 5–20-cell/second falling speeds and 8–20-cell tails, in every other native column.
- Matrix wall follows the supplied smaller-monitor reference: digits and symbols, independently falling white sources, stable lime/green/gray trails, and small black gaps after glyphs expire. It runs at the reference's eight source steps per second. The previous wall of constantly changing letters is removed.
- Visible screensavers request refreshes every **0.1 seconds**, previously 0.2. Actual frame delivery depends on server/network load.
- Normal displays keep cell-level color detail. Maximum-size frames can share foreground runs to stay within legacy modem limits while preserving each cell's glyph and gap. Long pauses do not require unbounded frame catch-up.

Monitor text scale is unchanged. Alarm popups still appear above the screensaver and consume their touches. Screensavers remain manual, transient and isolated per monitor; saved design rotation is retained. No routing, other apps, central runtime or remote clients change in this release.

## Installation from v36

Upload the full archive's root files to the V2 GitHub repository. On the **central OS computer**, quit the OS and run:

```text
cd /
inst app screensaver
reboot
```

**Only reinstall Screensaver.** Keep your existing installer/Pastebin; bundled-v36 is the expected installer banner in this full v37 release. No `inst server` or remote IO/monitor/sensor/relay reinstall is needed when already on v36.

If you have not installed the v36 startup repair yet, the included installer can update the central OS with `inst server` before installing Screensaver. Earlier v33–v35 app requirements remain in **documentation_update_v36.md**.

## Validation

- **335 Lua 5.1 integration checks pass**, including all project Lua syntax and the unchanged installer/source check.
- **40 distinct focused standalone LuaJ 2.0.3 checks pass**, covering Screensaver, maximum-size live frames, cooperative work and startup.
- Tests cover all four cells of each corner, adjacent exit taps, tiny screens, modal alerts, both Matrix speeds, stable digits/symbols and full fade colors.
- All 15 designs remain within the modem frame budget; Matrix wall also passes maximum-size checks with several seeds and a one-day clock jump. The simulated monitor client receives the reference cadence.
- The glyph/color output was rendered for visual review. These tests do not run Minecraft or measure the public server's frame rate.

## Exact files changed from v36

- `README.md`
- `apps_screensaver.lua`
- `documentation_api.md`
- `documentation_file_map.md`
- `documentation_review.md`
- `documentation_screensaver.md`
- `documentation_update_v37.md`
- `tests_screensaver.lua`

The only changed installed program is **apps_screensaver.lua**. `install.lua`, `main_os.lua`, every `lib_`/`clients_` file and every other app are byte-for-byte unchanged from v36.

# Screensaver

Install `inst app screensaver` on a **bundled-v33** OS and reboot. Open **Start → Screensaver** on the desired monitor. It always occupies that monitor's full screen, without a frame, taskbar or visible corner buttons. It never opens automatically, including after a reboot.

- Touch the **very top-left cell** for the previous design.
- Touch the **very top-right cell** for the next design.
- Touch **anywhere else** to close it and reveal the existing windows. The exit touch is consumed, so it cannot trigger a control underneath.
- Each new opening uses the next design. This rotation is saved; different open monitors can show different designs.

The screensaver adds no taskbar entry on other monitors. Other windows, app backgrounds, IO and saved layouts continue normally. Alarm popups remain visible and modal above the animation; acknowledge the popup first to use either corner. Closing it on one monitor leaves screensavers on other monitors running. Screensaver windows are deliberately excluded from desktop recovery, while the next-design index persists.

## Designs and credits

| Design | Visual |
| --- | --- |
| Matrix streams | Falling bright heads with sparse green tails |
| Matrix wall | A character in every cell, with moving white heads and green/gray trails; no empty columns |
| Plasma | Slowly flowing color interference |
| Ripple fields | Moving circular wave sources |
| Truchet flow | Repeating curved tile paths |
| Silk waves | Interlaced colored ribbons |
| Kaleidoscope | Rotating symmetric wave fields |
| Life garden | Toroidal Conway-style cellular patterns, periodically reseeded |
| Nyan Cat | Twelve original animation frames, cropped to the cat/rainbow, with wrapping stars |
| Starflight | Stars approaching from a central vanishing point |
| Northern lights | Flowing green, cyan and purple curtains |
| Lava lamp | Smooth moving blobs merging into bright cores |
| Neon tunnel | Rotating spokes and advancing rings |
| Fireworks | Colored bursts with staggered lifetimes |
| Spiral ribbons | Animated multicolored spiral bands |

Both `ConvertToScreenSaverLater` files in [DJDarkMatter/TekkitSwitchBoard](https://github.com/DJDarkMatter/TekkitSwitchBoard) are Matrix-style animations, so both are represented. Their standalone peripheral/IO/event logic is not reused. The second file credits **Felix Maxwell (2013), CC BY-SA 3.0**. This app's pattern renderers are new implementations inspired by those visuals and established mathematical patterns; they are not claimed to be a collection of independently human-authored assets. `apps_screensaver.lua` is distributed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) with those credits retained. The Nyan Cat design adapts the twelve animation frames from [K. Lange’s ComputerCraft port](https://github.com/klange/nyancat-cc/blob/main/nyancat.lua), copyright 2016–2022 K. Lange. Its full permissive copyright/permission/warranty notice is retained directly above the embedded frames. The original Nyan Cat animation is by prguitarman (Chris Torres), as credited by [the upstream terminal project](https://github.com/klange/nyancat). Only the cropped artwork is reused; monitor discovery, loops and palette changes are replaced by the OS renderer. The other added patterns are new implementations, not claimed to be third-party programs. No runtime downloads, custom palettes, sound or external files are required.

## Legacy monitor limits

All designs use CC1.5 character cells and its 16 colors with existing `write`/color APIs, not custom glyphs or CC:Tweaked features. The monitor's text scale is unchanged. Small monitors retain cell-level detail; large pattern screens group color runs to keep complete frames below the legacy modem packet limit, including maximum-size 256×128 displays. The Nyan sprite retains cell detail and merges adjacent color spans, so large monitors do not flatten the cat. Dense Matrix fills every physical character column while sharing color runs. Animations request a 0.2-second server tick only while a screensaver is visible; otherwise the configured tick interval resumes. Network/sensor/IO handling remains in the normal OS event loop.

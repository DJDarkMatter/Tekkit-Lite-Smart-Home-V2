# Screensaver

Install `inst app screensaver` on the central computer and reboot. **Settings → Screensavers** lists the installed designs in cycle order. Nyan Cat is number 9. Open **Start → Screensaver** on the desired monitor. It always occupies that monitor's full screen, without a frame, taskbar or visible corner buttons. It never opens automatically, including after a reboot.

- Touch any cell in the **top-left 2×2 area** for the previous design.
- Touch any cell in the **top-right 2×2 area** for the next design.
- Touch **anywhere else** to close it and reveal the existing windows. The exit touch is consumed, so it cannot trigger a control underneath.
- Each new opening uses the next design. This rotation is saved; different open monitors can show different designs.

These remain invisible touch areas. On unusually tiny displays, they are clipped to avoid overlap and leave an exit row.

The screensaver adds no taskbar entry on other monitors. Other windows, app backgrounds, IO and saved layouts continue normally. Alarm popups remain visible and modal above the animation; acknowledge the popup first to use either corner. Closing it on one monitor leaves screensavers on other monitors running. Screensaver windows are deliberately excluded from desktop recovery, while the next-design index persists.

## Designs and credits

| # | Design | Visual |
| --- | --- | --- |
| 1 | Matrix Rain | White heads and green tails in alternating columns |
| 2 | Matrix Wall | Dense symbols with lime, green and gray fading trails |
| 3 | Plasma | Flowing color interference |
| 4 | Ripple Pools | Moving circular waves |
| 5 | Rainbow Tiles | Repeating curved tile paths |
| 6 | Silk Waves | Interlaced ribbons |
| 7 | Kaleidoscope | Rotating symmetric waves |
| 8 | Life Garden | Reseeded cellular patterns |
| 9 | Nyan Cat | Cat and rainbow animation with wrapping stars and visible eyes, cheeks, smile, and chin across all twelve frames |
| 10 | Starflight | Stars approaching from a central vanishing point |
| 11 | Northern Lights | Green, cyan and purple curtains |
| 12 | Lava Lamp | Moving blobs that merge into bright cores |
| 13 | Neon Tunnel | Rotating spokes and advancing rings |
| 14 | Fireworks | Colored bursts with staggered lifetimes |
| 15 | Spiral Ribbons | Multicolored spiral bands |
| 16 | Prism Tide | Bright ribbons bending across the monitor |
| 17 | Candy Confetti | Falling colored diamonds over a purple field |
| 18 | Sunset Surf | Warm sky, a moving sun and turquoise waves |
| 19 | Pixel Quilt | Scrolling multicolor triangles with bright seams |
| 20 | Orbit Parade | Alternating rings of colorful orbiting segments |
| 21 | DVD Bounce | Color-changing DVD badge that bounces off the edges |
| 22 | Pac-Man Chase | Pac-Man and two ghosts looping through a pellet tunnel |
| 23 | Tetris Rain | Seven familiar block shapes falling in colored lanes. Compact displays keep whole pieces in view. |
| 24 | Rainbow Road | Scrolling rainbow track bending into a starry horizon |
| 25 | Among Us Drift | Crewmate drifting through space and changing suit colors |

Both `ConvertToScreenSaverLater` files in [DJDarkMatter/TekkitSwitchBoard](https://github.com/DJDarkMatter/TekkitSwitchBoard) are Matrix-style animations, so both are represented. Their standalone peripheral/IO/event logic is not reused. The second file credits **Felix Maxwell (2013), CC BY-SA 3.0**. This app's pattern renderers are new implementations inspired by those visuals and established mathematical patterns; they are not claimed to be a collection of independently human-authored assets. `apps_screensaver.lua` is distributed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) with those credits retained. The Nyan Cat design adapts the twelve animation frames from [K. Lange’s ComputerCraft port](https://github.com/klange/nyancat-cc/blob/main/nyancat.lua), copyright 2016–2022 K. Lange. Its full permissive copyright/permission/warranty notice is retained directly above the embedded frames. The original Nyan Cat animation is by prguitarman (Chris Torres), as credited by [the upstream terminal project](https://github.com/klange/nyancat). Only the cropped artwork is reused; monitor discovery, loops and palette changes are replaced by the OS renderer. The other added patterns are new implementations, not claimed to be third-party programs. No runtime downloads, custom palettes, sound or external files are required.

## Legacy monitor limits

All designs use CC1.5 character cells and its 16 colors with existing `write`/color APIs, not custom glyphs or CC:Tweaked features. The monitor's text scale is unchanged. Small monitors retain cell-level detail; large pattern screens group color runs to keep complete frames below the legacy modem packet limit, including maximum-size 256×128 displays. The Nyan sprite retains cell detail and merges adjacent color spans. The compact renderer uses more of the display height for the original frames. When the sprite must shrink, it retains separate eye, cheek, mouth, and chin rows where they fit. The rainbow joins the sprite at the left edge. Compact Tetris lays out whole lanes and gives the falling pieces space from the edges. Matrix wall samples falling sources at eight steps per second, as in the supplied Felix Maxwell reference. A trail character stays fixed until it expires or another source overwrites it; the whole alphabet does not flicker on every update. All native columns can contain sources. Density scales with screen width, and expired glyphs leave small black gaps. Normal screens retain independent per-cell colors; maximum-size frames can share neighboring color runs while preserving every glyph and gap. A bounded recent-source calculation handles long pauses without replaying every missed frame. Animations request a 0.1-second server tick only while a screensaver is visible; otherwise the configured tick interval resumes. Network/sensor/IO handling remains in the normal OS event loop.

# Version 40

## The CraftOS watchdog

The relay screenshot shows `parallel:22: rednet:44: Too long without yielding`. In stock CraftOS 1.5, that Rednet line probes the modem. Its worker used to do this for incoming packets before checking the destination channel. The shared network code now lets the worker skip channels that Rednet would discard. Packets addressed to the computer's Rednet ID or the Rednet broadcast channel still follow the normal Rednet path. [Tekkit Lite 0.6.5 stock distribution](https://www.technicpack.net/article/tekkit-lite-updated-to-065).

The earlier report was from the central OS and had no readable source line. V40 applies the Rednet filter on the central OS and every client role. The central OS retains its cooperative worker for rendering and checkpoints. Large packets are decoded and processed in separate work slices. The relay decodes each packet once, encodes it cooperatively, and uses a fixed-size duplicate cache. Queued traffic is bounded during pauses.

## Install

Replace the single installer paste with this release's `install.lua`. Download a fresh `inst` showing **bundled-v40** on each SmartHome computer. Stop the current program and run the command for that computer's role, then reboot.

| Computer | Command from `cd /` |
| --- | --- |
| Central OS | `inst server` |
| Relay | `inst relay` |
| IO client | `inst io` |
| Monitor client | `inst monitor` |
| Sensor client | `inst sensor` |

The central computer and relay 20033 are the two computers from the reports. Updating the other SmartHome computers applies the same CraftOS fix there. Roles can be updated one at a time because they use the existing packet format. Use `--startup` when setting up autorun on a new computer. The installer keeps existing startup scripts and configuration files.

On startup, a compatible runtime prints `CraftOS 1.5 Rednet channel filter active`. The relay can save caught errors in `diagnostics_relay_error.txt`. On the central OS, type `errorlog` to read its saved diagnostics. If the computer stops, the full error line and the startup message identify which path ran.

## Verification

The actual stock CraftOS 1.5 Rednet and parallel scripts reproduced the screenshot's stack when the test injected a watchdog at the modem lookup. The patched central OS and relay handled the same traffic and still received direct and broadcast Rednet. The suite passed 362 Lua 5.1 checks and 64 focused LuaJ 2.0.3 checks. LycoDon's IDT-Fixed runtime still needs an in-game run.

## Changed files

- `clients_relay_client.lua`
- `lib_network.lua`
- `lib_relay.lua`
- `lib_work.lua`
- `main_os.lua`
- `install.lua`
- `tools_build_installer.py`
- `tests_relay.lua`
- `tests_run.lua`
- `tests_work.lua`
- `README.md`
- `documentation_relay.md`
- `documentation_update_v40.md`

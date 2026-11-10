# Version 42

## Switchboard

Open a view and go to **Edit → Edit switches**. Pick a tile, open **Behavior** (**Mode** on compact windows), select **Button**, then tap **Time**. Enter a decimal such as **0.75**. Tapping the tile again while it is on restarts its timer. Choose **Switch** to return to normal on/off behavior.

The default IO minimum is 0.6 seconds because writes on the same side share a cooldown. The mode screen shows the selected client's minimum. Enter seconds with up to two decimal places. The IO client rounds the duration up to a game tick. One timed press can run per physical IO side at a time. Presses on other sides can run together.

The IO computer ends a press locally, including after you close the window or lose the OS connection while the IO computer is still running. An existing steady ON from a shared switch takes precedence. An explicit OFF or removing the timed button's route cancels its press. Scenes capture and apply ordinary switch positions.

## Logic Sandbox

**Delay** waits for a condition to stay on. **If / Then** takes a condition under **When** and runs named **Wait**, **Set output**, and **Alarm** blocks. You can pick the same block again in another position or rule. Each Set output chooses a destination and ON or OFF. The **Flow** view shows the rule in text. The guide shows how to group conditions like `Input 1 OR (Input 2 AND Input 3)` and use the blocks in a timed rule. [Logic Sandbox guide](documentation_logic_sandbox.md)

## Install from v41

Upload the flat-root release to GitHub and replace your installer paste with this version's `install.lua`. Use the installer that shows **bundled-v42**.

| Computer | Commands |
| --- | --- |
| Central OS | `inst server`, `inst app switchboard`, `inst app logic_sandbox`, then reboot |
| IO clients | `inst io`, then reboot |

Run the commands from the CraftOS root directory. Existing switches load in normal Switch mode.

## Changed files

| Area | Files |
| --- | --- |
| Apps | `apps_switchboard.lua`, `apps_logic_sandbox.lua` |
| Central OS and IO | `lib_server.lua`, `lib_gui.lua`, `lib_io.lua`, `clients_io_client.lua`, `main_os.lua` |
| Installer | `install.lua`, `tools_build_installer.py` |
| Tests | `tests_switchboard.lua`, `tests_v39.lua`, `tests_run.lua`, `tests_work.lua` |
| Docs | `README.md`, `documentation_api.md`, `documentation_logic_sandbox.md`, `documentation_update_v42.md` |

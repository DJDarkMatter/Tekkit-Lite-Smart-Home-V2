# Version 45

## Logic Sandbox

Create a rule directly from the Rules screen. Edit its **IF** condition and its ordered **THEN** actions in separate screens. Item counts, redstone inputs, combined conditions, delays, output actions and named alarms are available in that flow. The setup button leads to the next missing part. Existing circuits, routes and alerts retain their saved data. **Wiring** is available for shared nodes and advanced circuits.

## Solar farm

Finished HV rates come from up to five completed observation minutes. The dashboard waits for its first minute, then updates on minute boundaries. Farm items use production tiers and recent activity for default sorting, with matching tier colors. Existing pins and sort choices are retained. The combined net panel-equivalent rate uses both sources to account for solar tiers and transfers.

## Install from v44

Upload the release contents to the root of the GitHub repository. On the central computer, run:

```text
inst app logic_sandbox
inst app solar_farm
reboot
```

The release includes bundled-v45 for a fresh OS or client installation. The two app updates run with the v44 central OS.

## Changed files

| Area | Files |
| --- | --- |
| Apps | `apps_logic_sandbox.lua`, `apps_solar_farm.lua` |
| Release | `main_os.lua`, `tools_build_installer.py`, `install.lua` |
| Tests | `tests_app_helpers.lua`, `tests_v39.lua`, `tests_solar_farm.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_logic_sandbox.md`, `documentation_solar_farm.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v45.md` |

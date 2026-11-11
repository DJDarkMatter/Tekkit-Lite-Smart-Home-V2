# Version 44

## Live Item amount readings

The saved Item amount editor previously stopped requesting its ME snapshot when you left the count setup unless the circuit was enabled. It could show `Count --` after successfully selecting the source and item. Visible saved editors now maintain their live subscription independently of circuit activation. Source errors explain an unavailable count. An item absent from a complete live inventory reads zero.

The circuit list has a visible **OFF - Enable / ON - Disable** control. Enabled circuits evaluate in the background with their windows closed. Disabled circuits allow setup and count preview.

Block rows are numbered. Condition states use ON, OFF and Waiting. Rules use Running or Ready, and actions use Action or Alert. Compact screens prioritize the block label. Setup tips explain missing connections and link to the relevant editor. Menu → Check setup opens the check manually. An unattached Alarm explains how to add it to an If / Then rule.

## Alarm setup

Configure Item amount, add **If / Then**, choose the Item amount node under **When**, then add **Alarm** through **Then blocks → + Block**. The Alarm action remains part of the rule's ordered actions.

The Item amount editor's Popup option is removed. An existing Item amount popup is migrated into an If / Then rule with an Alarm action. Pending alerts retain their notification keys during migration. Failed migration saves restore the original configuration.

An Alarm block has a **Name** control. Saving an empty name uses the circuit name. Its popup title is **Alarm**, and the next line contains that name. Previously renamed Alarm blocks retain their names. Other signal nodes retain their existing optional popup controls.

## Install from v43

Upload the release contents to the repository root. On the central computer, run the following commands using the existing app installer.

```text
inst app logic_sandbox
reboot
```

The complete release includes `bundled-v44` for fresh role installs. The [v43 OS update](documentation_update_v43.md) includes the earlier watchdog repair.

## Verification

All 386 integration tests pass on Lua 5.1 and LuaJ 2.0.3. Checks cover the live disabled editor, unavailable ME data, an Item amount condition triggering an If / Then Alarm, custom and fallback names, small windows, popup acknowledgement, rearming, restart persistence, migration rollback, numbered rows, and setup tips for an unattached action. Existing output, delay and sequence tests run alongside them. Tests use simulated ComputerCraft APIs. In-game verification on LycoDon remains necessary.

The menu tree has 19 portrait pages and 819 verified link destinations. Every page was rendered and visually checked, and its freshness check passes.

## Changed files from v43

| Area | Files |
| --- | --- |
| App | `apps_logic_sandbox.lua` |
| Release version and installer | `main_os.lua`, `tools_build_installer.py`, `install.lua` |
| Tests | `tests_v39.lua`, `tests_run.lua`, `tests_work.lua` |
| Documentation | `README.md`, `documentation_api.md`, `documentation_logic_sandbox.md`, `documentation_menu_tree.md`, `documentation_menu_tree.pdf`, `documentation_update_v44.md` |
| Repository file handling | `.gitattributes` preserves PDF bytes and treats generated PDFs as binary files in Git |

# Version 39

## Install on the central computer

Upload the full ZIP's root files to the V2 repository. System Overview moved into the OS, so remove the old `apps_system.lua` from the GitHub root. An existing computer automatically moves that app's saved filter and open windows into OS Settings.

Replace the single installer paste with this release's `install.lua` and download a fresh copy of `inst` showing **bundled-v39**. Quit to CraftOS and run the central update.

```text
cd /
inst server
inst app screensaver
inst app switchboard
```

The last two commands update those apps if you use them. Install the new apps you want with the same installer, then reboot.

```text
inst app io_scope
inst app logic_sandbox
inst app notes
inst app window_presets
reboot
```

Only the central computer needs this update. The 25 core sources in `install.lua` include built-in Settings and System Overview. Optional apps download from GitHub when requested. Existing startup, app data, monitor layouts, routing and client programs carry over.

## OS Settings and desktop

- **Client names** lets you name each detected device or monitor side. Every client picker shows the name with the client ID as the fallback. Saved bindings use stable IDs.
- **Screensavers** lists the installed patterns by their cycle index. **9. Nyan Cat** is the anchor. **16–20** are Prism Tide, Candy Confetti, Sunset Surf, Pixel Quilt and Orbit Parade.
- **System Overview** includes live diagnostics, a recent **Uptime history**, and a **Relay map**. Select a device to see its last observed path. Select a relay to see the devices that reported a path through it.
- **App data** groups **Backup & restore**, **Reset data**, and **Delete apps**. The first two offer Entire OS, OS settings, and individual app scopes. A factory reset needs two confirmations.
- **Alert Inbox** opens from the taskbar clock, or from Start when the clock is hidden. The sidebar fills small screens and has a Back button. The OS saves the last 128 occurrences with the world day when available. Alarm popups draw above the screensaver, which draws above the inbox.

### Backups and uninstall

| Action | Result |
| --- | --- |
| Create backup | Saves a slot as `backup_os_all.txt`, `backup_os_settings.txt`, or `backup_app_NAME.txt` on the OS computer. Copy these files if you want to keep additional snapshots. |
| Restore backup | Previews the scope and saved window count, then replaces that scope's data after confirmation. Window layouts use their saved monitor IDs. Restored output bindings adopt an existing shared wire's intent or start OFF. App services then resume their own saved logic. |
| Reset data | Clears the chosen managed data. Backup slots, program files, startup and network config remain available. |
| Delete apps | Removes the installed program, closes its windows and releases its live routes. Reinstalling with `inst app NAME` picks up the retained app settings and routing. Released shared wires continue under their surviving owners. |

### Shared redstone picker

On the final routing screen, an input shows ON, OFF, or Unknown. **Test** on an output briefly inverts the selected wire, then restores its saved intent. The test uses the same acknowledgement and retry path as normal outputs and leaves unrelated wires alone.

## Apps

| App | How to use it |
| --- | --- |
| IO Scope | Choose **Used by apps**, a **Client side**, or a saved view. Colored piano keys open wire details. The timeline runs left to right. Hold freezes the time cursor, arrows move through history, and Menu changes the range or adds lanes. Green is ON, gray is OFF, orange is pending, and dots show unknown periods. Bright markers retain edges within a column. History records received redstone events and output confirmations in the current OS session. |
| Logic Sandbox | Create a circuit, add Inputs and Outputs, choose their redstone lines, and link AND, OR, NOT and XOR gates with the source buttons. Enable the circuit when wired. Optional popups fire when a node becomes ON. An unknown result drives an unshared Logic output OFF. |
| Window Presets | Save the current monitor or all online monitors. Tap a monitor slot to inspect its windows and assign a destination. Preview before applying. On smaller screens, a window that fits may be minimized to avoid overlap. A window that cannot fit is listed as unavailable. Applying replaces the layout on the assigned monitors and keeps app data. |
| Notes | Create a note and add text or checkbox rows. Tap a checkbox to toggle it. Use **Menu → Edit lines** to change or delete rows and **Export Markdown** to create `notes_export_ID.md` on the central computer. |
| Switchboard | **Scenes → + New scene** captures one view or all views. Tap the scene to apply the saved states as a batch. If a switch was removed or rerouted, the scene skips its old route. |

## Changed files

**Added**

- `apps_io_scope.lua`
- `apps_logic_sandbox.lua`
- `apps_notes.lua`
- `apps_window_presets.lua`
- `lib_alert_inbox.lua`
- `lib_io_history.lua`
- `lib_system.lua`
- `documentation_update_v39.md`
- `tests_v39.lua`

**Updated**

- `apps_screensaver.lua`
- `apps_switchboard.lua`
- `install.lua`
- `lib_desktop.lua`
- `lib_gui.lua`
- `lib_io_picker.lua`
- `lib_sensor_picker.lua`
- `lib_server.lua`
- `lib_settings.lua`
- `main_os.lua`
- `tools_build_installer.py`
- `README.md`
- `documentation_api.md`
- `documentation_desktop.md`
- `documentation_file_map.md`
- `documentation_screensaver.md`
- `documentation_switchboard.md`
- `documentation_system.md`
- `tests_appearance.lua`
- `tests_run.lua`
- `tests_screensaver.lua`
- `tests_switchboard.lua`
- `tests_system.lua`
- `tests_work.lua`

**Removed**

- `apps_system.lua` moved to `lib_system.lua`.

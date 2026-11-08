# System Overview

Open **Start → OS settings → System overview** on a monitor. System Overview is built into bundled-v39. On upgrade, saved preferences and windows from the former CC System app move into Settings.

| Page | Information |
| --- | --- |
| Central computer | Computer and network IDs, wireless channels, uptime, checkpoint age, world clock and player indicator |
| Clients | Online status, friendly name and ID, reply channel, uptime, monitor size, IO capabilities and confirmation revisions |
| Sensors | Card types, targets, catalog progress and cached target details |
| Outputs | Logical mappings, requested state and confirmation |
| Apps and Windows | Enabled apps, running services and saved window geometry |
| Uptime history | Up to 128 observed events, including OS boots, clean quits, client connects and client timeouts |
| Relay map | Last observed path from the OS toward each client, with downstream devices listed for selected relays |

**OS settings → Client names** changes display labels across pickers. The stable ID is available in client details. A monitor computer with two screens has one selectable endpoint per side.

History records what the OS observes while it is running. After a restart, a client appears online when it announces. Relay paths describe received packets and can change as devices reconnect. Sensor inspection here uses cached data.

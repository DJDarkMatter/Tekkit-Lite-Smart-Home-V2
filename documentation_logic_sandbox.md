# Logic Sandbox

Open **+ New rule** to edit **IF** and **THEN**. **IF** is the condition the OS checks. **THEN** is the ordered list of actions it starts when that condition first becomes true. New rules start off. **Set up IF** or **Set up THEN** takes you to the part that needs configuring. **Turn on** becomes available when both are ready.

## IF

| Choice | Set up |
| --- | --- |
| Item count | Select an AE sensor, its side and an ME target. Pick an item and choose **Below**, **Above** or **Exactly**, then enter the **Level** and save. |
| Redstone | Select the IO client, side and wire. Tap **When ON** or **When OFF** to change which reading makes the condition true. |
| All true | Both conditions must be true. |
| Any true | At least one condition must be true. |
| Exactly one | One of the two conditions must be true. |
| Invert | Reverses a condition. An unknown reading stays unknown. |
| Hold true | The condition must stay true for the selected time. |

**Combine** opens the group choices. On an existing condition, **Change → Combine** wraps that condition in the new group. Open a numbered condition within a group to configure or nest it.

Item counts stay live when the rule is off and its summary or condition is visible. A complete ME inventory gives an absent item a count of zero. An unavailable inventory shows a missing reading. **Find** searches by item name or RawName. **Find → Manual item** registers an absent item using its display name, exact RawName and damage value.

## THEN

Open **THEN → + Add**. The list runs from top to bottom.

- **Alarm** opens a popup headed **Alarm**. Its optional **Name** supplies the message. Saving an empty name uses the circuit name.
- **Set redstone** chooses a destination directly. Set the level to ON or OFF. Two actions in the same rule can choose the same wire.
- **Wait** pauses before the next action. Times accept up to two decimal places and round up to a game tick.

Tap an action to edit it. Its **Order** menu moves it earlier, moves it later or removes it. A running sequence can finish after its condition falls. A new run starts after the condition has been observed false and becomes true again. Enabled rules run with the app window closed. Saved conditions, actions and routes resume after restart.

For a wire that follows the condition continuously, use **More → New output** from the Rules screen. Set the condition in **IF** and select the wire in **THEN**. The wire is off while the condition is false or unknown.

## Saved circuits

Saved sequences and outputs open in the rule editor. Circuits with multiple rules show their rule list. The **Wiring** menu keeps shared nodes and connections editable, including existing reusable action blocks and output targets. Wiring also has the connection check and text flow view. The upgrade retains saved circuits and resumes any open Logic Sandbox window at the circuit's rule screen or list.

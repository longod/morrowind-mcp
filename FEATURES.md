# Morrowind MCP Server Features

## Prompts

| Name | Title | Description |
|---|---|---|
| `mw-loar` | | Tell me about loar of this. |
| `mw-role` | | Role-play the character in Morrowind. |
| `mw-todo` | | Tell me what to do next. |
| `mw-translate` | | Translate it! |
| `mw-walkthrough` | | Give me some tips on how to beat the game. |

## Resources

| Name | URI | Title | Description |
|---|---|---|---|
| `memory/index.json` | `morrowind://memory/index.json` | Memory Index | Root index of Morrowind memory resources. |
| `memory/player/index.json` | `morrowind://memory/player/index.json` | Player Memory | Memory entity for the current player. |
| `memory/player/inventory.json` | `morrowind://memory/player/inventory.json` | Player Inventory Memory | Memory snapshot of the current player's inventory. |
| `memory/player/journal.json` | `morrowind://memory/player/journal.json` | Player Journal Memory | Memory collection of current player journal entries. |
| `memory/player/quests.json` | `morrowind://memory/player/quests.json` | Player Quest Memory | Memory collection of current player quest states. |
| `memory/actors/index.json` | `morrowind://memory/actors/index.json` | Observed Actor Memory | Memory collection of observed actors in active cells. |
| `memory/unattributed/dialogue.json` | `morrowind://memory/unattributed/dialogue.json` | Unattributed Dialogue Memory | Dialogue text observed without a resolved actor. |

## Tools

| Name | Title | Description | Input | Output | Annotations |
|---|---|---|---|---|---|
| `mw-capabilities-fetch` | | Fetch general conditions for published tools. | <ul><li>`tool_name` (string, optional) - Optional published tool name to filter by.</li></ul> | <ul><li>`tools` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-activator-fetch` | | Fetch active activators in current cells. | | <ul><li>`activators` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-actor-fetch` | | Fetch active actors in current cells. | | <ul><li>`actors` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-debug-action` | | Perform a debug command. | <ul><li>`action` (string, required) - Dump all Memory documents to Data Files\MWSE\mods\morrowind-mcp\memory-dump\</li></ul> | | |
| `mw-inventory-fetch` | | Fetch current inventory. | | <ul><li>`inventory` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-journal-fetch` | | Fetch active journal entries. | | <ul><li>`entries` (array)</li><li>`current_time` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-menu-action` | | Action to a non-root menu. | <ul><li>`action` (string, required) - Action to perform on the menu.</li><li>`menu_id` (number, optional) - Action to perform on the non-root menu by ID (key name is `id`). One of `menu_id` or `menu_name` should be specified.</li><li>`menu_name` (string, optional) - Action to perform on the non-root menu by name (key name is `name`). One of `menu_id` or `menu_name` should be specified.</li><li>`text` (string, optional) - Text to input if action is `textInput`.</li></ul> | | |
| `mw-menu-fetch` | | Fetch current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. some menus have `widget` or `actionable` properties to indicate what kind of action can be performed on this menu. | <ul><li>`menu_id` (number, optional) - Fetch a non-root hierarchy of menu by ID (key name is `id`). If not specified, all menus will be returned. One of `menu_id` or `menu_name` should be specified.</li><li>`menu_name` (string, optional) - Fetch a non-root hierarchy of menu by name (key name is `name`). If not specified, all menus will be returned. One of `menu_id` or `menu_name` should be specified.</li></ul> | <ul><li>`menu` (object)</li><li>`help` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-action` | | Perform an action on the player. This is the player character that the user is controlling. | <ul><li>`action` (string, required) - Action to perform on the player character.</li><li>`how` (string, required) - How to perform the action. Tap is a single press, push is a press and hold, hammer is a rapid repeat.</li><li>`seconds` (number, optional) - Time in seconds to hold the action. Only used for push and hammer.</li></ul> | | |
| `mw-player-fetch` | | Fetch current player state. | | <ul><li>`player` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-look` | | Direct the player view at an active reference or to absolute world-space angles. Any active player navigation is cancelled before the view is applied. | <ul><li>`mode` (string, required) - target looks at the nearest active reference with target_id. angles uses absolute yaw and pitch in degrees.</li><li>`pitch` (number, optional) - Required for angles mode. Absolute vertical angle in degrees; positive values look upward.</li><li>`target_id` (string, optional) - Required for target mode. Matches active-cell reference base IDs; nearest matching reference is used.</li><li>`yaw` (number, optional) - Required for angles mode. Absolute compass heading in degrees: 0 is north and 90 is east.</li></ul> | <ul><li>`navigation_cancelled` (boolean) - Whether an active player navigation route was cancelled before looking.</li><li>`pitch` (number) - Applied absolute pitch in degrees.</li><li>`target_id` (string) - Resolved target ID when mode is target.</li><li>`target_point_kind` (string) - Method used to select the target look point.</li><li>`yaw` (number) - Applied absolute yaw in degrees.</li></ul> | |
| `mw-player-navigate` | | Navigate the player character. Looking and Locomotion. | <ul><li>`action` (string, required) - Action to perform on the player character.</li></ul> | | |
| `mw-quest-fetch` | | Fetch active quests. | <ul><li>`is_active` (boolean, optional) - Filter quests by active state. If not specified, quests will not be filtered by active state.</li><li>`is_finished` (boolean, optional) - Filter quests by finished state. If not specified, quests will not be filtered by finished state.</li><li>`is_started` (boolean, optional) - Filter quests by started state. If not specified, quests will not be filtered by started state.</li></ul> | <ul><li>`quests` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-screenshot-save` | | Save a screenshot of the current game state to a file. The screenshot will be saved to the resources | <ul><li>`capture_with_ui` (boolean, optional) - The screenshot will include the user interface.</li><li>`extension` (string, optional) - Select screenshot file extension.</li><li>`file_name` (string, optional) - Screenshot file name (without extension). If not specified, a timestamp will be used.</li></ul> | | |
| `mw-static-fetch` | | Fetch active statics in current cells. | | <ul><li>`statics` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-target-fetch` | | Fetch current target state. This is the object that the player is currently looking at or cursor is currently pointing at. | | <ul><li>`playerTarget` (object)</li><li>`helpLayerMenu` (object)</li><li>`inventoryTile` (object)</li><li>`serviceActor` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-world-fetch` | | Fetch the world state. | | <ul><li>`world` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |

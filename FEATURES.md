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
| `memory/player/equipment.json` | `morrowind://memory/player/equipment.json` | Player Equipment Memory | Memory snapshot of the current player's equipped items. |
| `memory/player/spellbook.json` | `morrowind://memory/player/spellbook.json` | Player Spellbook Memory | Current player spells and powers. |
| `memory/player/progression.json` | `morrowind://memory/player/progression.json` | Player Progression Memory | Current player level, attributes, and skills. |
| `memory/player/vitals.json` | `morrowind://memory/player/vitals.json` | Player Vitals Memory | Current player health, magicka, fatigue, and life state. |
| `memory/player/visited-cells.json` | `morrowind://memory/player/visited-cells.json` | Player Visited Places Memory | Places the player has entered, represented by TES3 cells. |
| `memory/player/journal.json` | `morrowind://memory/player/journal.json` | Player Journal Memory | Memory collection of current player journal entries. |
| `memory/player/quests.json` | `morrowind://memory/player/quests.json` | Player Quest Memory | Memory collection of current player quest states. |
| `memory/actors/index.json` | `morrowind://memory/actors/index.json` | Observed Actor Memory | Memory collection of observed actors in active cells. |
| `memory/unattributed/index.json` | `morrowind://memory/unattributed/index.json` | Unattributed Memory | Observations that do not have a stable domain subject. |
| `memory/unattributed/dialogue.json` | `morrowind://memory/unattributed/dialogue.json` | Unattributed Dialogue Memory | Dialogue text observed without a resolved actor. |
| `memory/unattributed/notifications.json` | `morrowind://memory/unattributed/notifications.json` | Notification Memory | Transient notification text observed without a stable domain subject. |

## Resource Templates

| Name | URI Template | Description |
|---|---|---|
| `memory-entity` | `morrowind://memory/{collection}/{entity_id}/{document}.json` | Read a published dynamic Memory entity document; player and unattributed documents are listed resources. |
| `screenshot` | `morrowind://screenshot/{file}` | Read a published JPEG or PNG screenshot. |

## Tools

| Name | Title | Description | Input | Output | Annotations |
|---|---|---|---|---|---|
| `mw-capabilities-fetch` | | Fetch general conditions for published tools. We recommend using this tool to check then. | <ul><li>`tool_name` (string, optional) - Optional published tool name to filter by.</li></ul> | <ul><li>`tools` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-debug-action` | | Perform a debug command. | <ul><li>`action` (string, required) - Debug command to perform.</li></ul> | | |
| `mw-inventory-fetch` | | Fetch current inventory. | | <ul><li>`inventory` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-menu-action` | | Action to a non-root menu element selected by its path. | <ul><li>`action` (string, required) - Action to perform on the menu.</li><li>`menu_path` (string, required) - Action to perform using a `path` returned by `mw-menu-fetch`; paths use raw MWSE child indexes, not serialized array positions.</li><li>`text` (string, optional) - Text to input if action is `textInput`.</li></ul> | | |
| `mw-menu-fetch` | | Fetch current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. Some menus have `widget` or `actionable` properties to indicate what kind of action can be performed on this menu. | <ul><li>`menu_id` (number, optional) - Fetch a non-root hierarchy by ID.</li><li>`menu_name` (string, optional) - Fetch a non-root hierarchy by name.</li></ul> | <ul><li>`help` (object)</li><li>`menu` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-action` | | Perform direct player input such as movement keys, activation, jumping, sneaking, combat preparation, or other short manual actions. Use this for interaction, immediate input, or fine movement adjustment. For intentional travel toward a known world destination, player-navigate may be more suitable. | <ul><li>`action` (string, required) - Action to perform on the player character.</li><li>`how` (string, required) - How to perform the action. Tap is a single press, push is a press and hold, hammer is a rapid repeat.</li><li>`seconds` (number, optional) - Time in seconds to hold the action. Only used for push and hammer.</li></ul> | | |
| `mw-player-fetch` | | Fetch current player state. | | <ul><li>`mobilePlayer` (object)</li><li>`player` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-look` | | Direct the player view at an active reference or to absolute world-space angles. Any active player navigation is cancelled before the view is applied. | <ul><li>`mode` (string, required) - Target or absolute-angle look mode.</li><li>`pitch` (number, optional) - Required for angles mode.</li><li>`target_id` (string, optional) - Required for target mode.</li><li>`yaw` (number, optional) - Required for angles mode.</li></ul> | <ul><li>`navigation_cancelled` (boolean)</li><li>`pitch` (number)</li><li>`target_id` (string)</li><li>`target_point_kind` (string)</li><li>`yaw` (number)</li></ul> | |
| `mw-player-navigate` | | Navigate the player character through the game world toward an intentional destination, such as an observed NPC, door, reference, location, or world-space coordinate. This is useful for travel when a reachable destination is known. Navigation returns route node and waypoint counts; verify arrival with player, reference, or world state. Use cancel_navigation to stop an active route. | <ul><li>`action` (string, required) - Method to navigate the player character or cancel active navigation.</li><li>`position_x` (number, optional) - Destination X coordinate in world space, in Morrowind game units.</li><li>`position_y` (number, optional) - Destination Y coordinate in world space, in Morrowind game units.</li><li>`position_z` (number, optional) - Destination Z coordinate in world space, in Morrowind game units.</li><li>`cell_id` (string, optional) - Optional cell containing the destination.</li></ul> | <ul><li>`route_node_count` (number) - Number of pathgrid nodes in the started route.</li><li>`waypoint_count` (number) - Number of waypoints in the started route.</li></ul> | |
| `mw-reference-fetch` | | Fetch references near the player by default, or from all active cells when requested. In minimal and standard results, distance is reported from the player as both Morrowind game units and meters; reference positions remain Morrowind game-space coordinates in game units. | <ul><li>`category` (array, optional) - Filter by activators, actors, or statics.</li><li>`detail_level` (string, optional) - Serialization detail: minimal, standard, or full.</li><li>`id` (string, optional) - Filter references by ID.</li><li>`scope` (string, optional) - Reference cell scope: nearby or active.</li></ul> | <ul><li>`activators` (array)</li><li>`actors` (array)</li><li>`serialization` (object)</li><li>`statics` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-screenshot-save` | | Save a screenshot of the current game state to a file. The screenshot will be saved to the resources | <ul><li>`capture_with_ui` (boolean, optional) - The screenshot will include the user interface.</li><li>`file_name` (string, optional) - A timestamp is used if omitted.</li></ul> | | |
| `mw-target-fetch` | | Fetch current target state. This is the object that the player is currently looking at or cursor is currently pointing at. | <ul><li>`detail_level` (string, optional) - Serialization detail; default is full.</li></ul> | <ul><li>`helpLayerMenu` (object)</li><li>`inventoryTile` (object)</li><li>`playerTarget` (object)</li><li>`serialization` (object)</li><li>`serviceActor` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-world-fetch` | | Fetch the world state. | | <ul><li>`world` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |

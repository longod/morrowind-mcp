# Morrowind MCP Server Features

## Prompts

| Name | Title | Description |
|---|---|---|
| `mw-loar` |  | Tell me about loar of this. |
| `mw-role` |  | Role-play the character in Morrowind. |
| `mw-todo` |  | Tell me what to do next. |
| `mw-translate` |  | Translate it! |
| `mw-walkthrough` |  | Give me some tips on how to beat the game. |

## Resources

| Name | URI | Title | Description |
|---|---|---|---|
| `active_quest.json` | `morrowind://game/active_quest.json` | Active Quests | Current player's active quest entries. |
| `finished_quest.json` | `morrowind://game/finished_quest.json` | Finished Quests | Current player's finished quest entries. |
| `game/journal.json` | `morrowind://game/journal.json` | Journal | Current player's journal entries. |
| `started_quest.json` | `morrowind://game/started_quest.json` | Started Quests | Current player's started quest entries. |

## Tools

| Name | Title | Description | Input | Output | Annotations |
|---|---|---|---|---|---|
| `mw-activator-fetch` |  | Fetch active activators in current cells. |  | <ul><li>`activators` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-actor-fetch` |  | Fetch active actors in current cells. |  | <ul><li>`actors` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-inventory-fetch` |  | Fetch current inventory. |  | <ul><li>`inventory` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-journal-fetch` |  | Fetch active journal entries. |  | <ul><li>`entries` (array)</li><li>`current_time` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-menu-action` |  | Action to a non-root menu. | <ul><li>`menu_id` (number, optional)</li><li>`menu_name` (string, optional, min: 1, max: 255)</li><li>`action` (string enum: `mouseClick`, `mouseDoubleClick`, required)</li></ul> |  |  |
| `mw-menu-fetch` |  | Fetch current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. | <ul><li>`menu_id` (number, optional)</li><li>`menu_name` (string, optional, min: 1, max: 255)</li></ul> | <ul><li>`menu` (object)</li><li>`help` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-fetch` |  | Fetch current player state. |  | <ul><li>`player` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-quest-fetch` |  | Fetch active quests. | <ul><li>`is_started` (boolean, optional)</li><li>`is_active` (boolean, optional)</li><li>`is_finished` (boolean, optional)</li></ul> | <ul><li>`quests` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-screenshot-save` |  | Save a screenshot of the current game state to a file. The screenshot will be saved to the resources | <ul><li>`capture_with_ui` (boolean, optional, default: true)</li><li>`file_name` (string, optional, min: 1, max: 255)</li><li>`extension` (string enum: `.jpg`, `.png`, `.bmp`, `.tga`, `.dds`, optional, default: `.jpg`)</li></ul> |  |  |
| `mw-static-fetch` |  | Fetch active statics in current cells. |  | <ul><li>`statics` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-target-fetch` |  | Fetch current target state. This is the object that the player is currently looking at or cursor is currently pointing at. |  | <ul><li>`playerTarget` (object)</li><li>`helpLayerMenu` (object)</li><li>`inventryTile` (object)</li><li>`serviceActor` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-world-fetch` |  | Fetch the world state. |  | <ul><li>`world` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |

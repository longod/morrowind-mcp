# Morrowind MCP Server Features

## Prompts

## Resources

| Name | URI | Title | Description |
|---|---|---|---|
| `journal.json` | `morrowind://game/journal.json` | Journal | Current player's journal entries. |

## Tools

| Name | Title | Description | Input | Output | Annotations |
|---|---|---|---|---|---|
| `mw-activator-fetch` |  | [Morrowind] Fetch active activators in current cells. |  | <ul><li>`activators` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-actor-fetch` |  | [Morrowind] Fetch active actors in current cells. |  | <ul><li>`actors` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-journal-fetch` |  | [Morrowind] Fetch active journal entries. |  | <ul><li>`entries` (array)</li><li>`current_time` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-menu-action` |  | [Morrowind] Action to a non-root menu. | <ul><li>`menu_id` (number, optional)</li><li>`menu_name` (string, optional, min: 1, max: 255)</li><li>`action` (string enum: `mouseClick`, `mouseDoubleClick`, required)</li></ul> |  |  |
| `mw-menu-fetch` |  | [Morrowind] Fetch current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. | <ul><li>`menu_id` (number, optional)</li><li>`menu_name` (string, optional, min: 1, max: 255)</li></ul> | <ul><li>`menu` (object)</li><li>`help` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-player-fetch` |  | [Morrowind] Fetch current player state. |  | <ul><li>`player` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-quest-fetch` |  | [Morrowind] Fetch active quests. | <ul><li>`is_started` (boolean, optional)</li><li>`is_active` (boolean, optional)</li><li>`is_finished` (boolean, optional)</li></ul> | <ul><li>`quests` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-screenshot-save` |  | [Morrowind] Save a screenshot of the current game state to a file. The screenshot will be saved to the resources | <ul><li>`capture_with_ui` (boolean, optional, default: true)</li><li>`file_name` (string, optional, min: 1, max: 255)</li><li>`extension` (string enum: `.jpg`, `.png`, `.bmp`, `.tga`, `.dds`, optional, default: `.jpg`)</li></ul> |  |  |
| `mw-static-fetch` |  | [Morrowind] Fetch active statics in current cells. |  | <ul><li>`statics` (array)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-target-fetch` |  | [Morrowind] Fetch current target state. This is the object that the player is currently looking at or cursor is currently pointing at. |  | <ul><li>`playerTarget` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-world-fetch` |  | [Morrowind] Fetch the world state. |  | <ul><li>`world` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |

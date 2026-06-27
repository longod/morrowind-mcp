# Morrowind MCP Server Features

## Prompts

## Resources

## Tools

| Name | Title | Description | Input | Output | Annotations |
|---|---|---|---|---|---|
| `mw-menu-find` |  | [Morrowind] Find current menu hierarchy. `menu` is user interface such as inventory. `help` is overlay such as tooltips. | <ul><li>`menu_id` (number, optional)</li><li>`menu_name` (string, optional, min: 1, max: 255)</li></ul> | <ul><li>`menu` (object)</li><li>`help` (object)</li></ul> | <ul><li>`readOnlyHint`: true</li></ul> |
| `mw-screenshot-save` |  | [Morrowind] Save a screenshot of the current game state to a file. The screenshot will be saved to the resources | <ul><li>`capture_with_ui` (boolean, optional, default: true)</li><li>`file_name` (string, optional, min: 1, max: 255)</li><li>`extension` (string enum: `.jpg`, `.png`, `.bmp`, `.tga`, `.dds`, optional, default: `.jpg`)</li></ul> |  | <ul><li>`readOnlyHint`: true</li></ul> |

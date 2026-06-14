---
description: lua programming guidelines.
applyTo: MWSE/mods/morrowind-mcp/**/*.lua
---

- 関数はUpperCamelCaseで命名してください。
- `match` など、pattern matchingやregular expressionを必要とする処理は、可能な限り避けてください。
- `table` 型のサイズを取得する場合、`#table` を使用するのではなく、`table.size()` を使用してください

---
description: lua programming guidelines.
applyTo: MWSE/mods/morrowind-mcp/**/*.lua
---

- クラス名と関数は先頭大文字`CamelCase`で命名してください。
- 変数は先頭小文字`camelCase`か`snake_case`で命名してください。使い分けは状況次第です。
- `match` など、pattern matchingやregular expressionを必要とする処理は、使用しない方が高速と思われる簡易の処理の場合は、使用しないでください
- `table` 型のサイズを取得する場合、`#table` を使用するのではなく、`table.size()` を使用してください
- `logger` に外部入力や URI を渡す場合は `logger:debug("%s", value)` のように format を明示する

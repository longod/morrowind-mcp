---
description: lua programming guidelines.
applyTo: MWSE/mods/morrowind-mcp/**/*.lua
---

- クラス名と関数は`UpperCamelCase`で命名してください。
- 変数は`lowerCamelCase`か`snake_case`で命名してください。使い分けは状況次第です。
- `match` など、pattern matchingやregular expressionを必要とする処理は、使用しない方が高速と思われる簡易の処理の場合は、使用しないでください
- `table` 型のサイズを取得する場合、`#table` を使用するのではなく、`table.size()` を使用してください

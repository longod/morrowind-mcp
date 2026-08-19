# Object Serializer: Exploration-Oriented Fields

対象: `MWSE/mods/morrowind-mcp/tes3/object.lua`

## Serialization detail levels

`reference-fetch` and `target-fetch` expose a `detail_level` parameter with `minimal`, `standard`, and `full` values. Every response includes `serialization.detailLevel` and `serialization.availableDetailLevels` once at the response root.

- `minimal` identifies and selects a placed reference. It includes reference `id`, placed object `type`, `name`, `position`, `cell`, activation capability, and lightweight state such as death, emptiness, stack size, destination presence, and locked state.
- `standard` adds fields needed to decide the next game action without traversing large collections: movement direction, destination, locks/traps, item state, container capacity/respawn state, actor identity/vitals/state, and lightweight item values such as value, weight, quality, durability, book/apparatus type, light lifetime, and leveled-list settings.
- `full` delegates to the existing `object.lua` serializer and therefore means every field currently supported by this project, not every MWSE property.

`reference-fetch` defaults to `minimal` for an unfiltered list and to `full` when `id` is supplied. `target-fetch` defaults to `full`.

The summary serializer reads selected TES3 properties directly so read failures remain observable. In development debug mode it validates the completed JSON-compatible output, including unsupported userdata and table cycles, without converting read failures into `nil`.

## 1. 既に serialize されていて有用な field

### 識別・意味

- `id`
- `objectType`
- `name`
- `object`
- `baseObject`
- `object.isInstance`
- `persistent`
- `supportsActivate`

### 探索・位置

- `cell`
- `cell.name`
- `cell.displayName`
- `cell.gridX`
- `cell.gridY`
- `cell.isInterior`
- `cell.behavesAsExterior`
- `cell.region`
- `position`
- `facing`
- `forwardDirection`
- `destination`
- `destination.cell`
- `destination.marker`

### 相互作用・状態

- `hasNoCollision`
- `isDead`
- `isEmpty`
- `isLeveledSpawn`
- `isRespawn`
- `stackSize`
- `hasMapMarker`
- `hasWater`
- `waterLevel`
- `restingIsIllegal`
- `lockpick` / `probe` / `repairTool` の `quality`, `maxCondition`
- 武器・防具・衣服の `value`, `weight`, `condition`, `enchantment`
- 書物の `skill`, `type`
- 錬金術品の `effects`
- NPC の `class`, `race`, `faction`, `factionRank`, `disposition`
- NPC の `isEssential`, `isGuard`, `level`
- actor の `health`, `fatigue`, `magicka`
- actor の `inCombat`, `isDead`, `isPlayerDetected`, `isPlayerHidden`
- actor の `isSneaking`, `isSwimming`, `underwater`
- actor の `canAct`, `canMove`, `canJump`
- actor の `invisibility`, `chameleon`, `levitate`, `waterBreathing`
- player の `bounty`, `inJail`, `sleeping`, `waiting`, `traveling`
- quest の `isStarted`, `isActive`, `isFinished`
- dialogue の `text`, `journalIndex`, `actor`, `cell`

## 2. 現在 serialize されているが探索への有用性が低い field

完全に不要とは限らないが、通常の探索判断では優先度が低い。

### 描画・モデル情報

- `mesh`
- `icon`
- `scale`
- `color`
- `width`
- `height`
- `cloudTexture`
- `particleTexture`
- `glareView`
- `sun*Color`
- `ambient*Color`
- `fog*Color`

### エンジン内部状態

- `simulationTimeScalar`
- `systemTime`
- `transitionDelta`
- `transitionScalar`
- `scanInterval`
- `scanTimer`
- `inactivityTime`
- `corpseHourstamp`
- `lastGroundZ`
- `impulseVelocity`
- `velocity`
- `animTime`
- `rotationSpeed`

### 戦闘・移動の一時的なフラグ

- `isMovingForward`
- `isMovingBack`
- `isMovingLeft`
- `isMovingRight`
- `isTurningLeft`
- `isTurningRight`
- `isWalking`
- `isRunning`
- `isJumping`
- `isFalling`
- `isSliding`
- `isReadyingWeapon`
- `weaponDrawn`
- `idleAnim`

これらは戦闘ログやリアルタイム観測には有用だが、静的な世界理解や経路計画ではノイズになりやすい。

### 気象・表示状態

- weather の色・粒子・音響関連 field
- `weatherController` の星、太陽、雲、霧の描画パラメータ
- fader の状態
- world controller の各種表示・カメラ関連状態

## 3. 未 serialize で、探索エージェントに有用そうな field

優先度順。

### 優先度: 高

#### `tes3reference`

- `itemData`
  - `owner`
  - `requirement`
  - `charge`
  - `condition`
  - `count`
  - `soul`
  - `timeLeft`
- `lockNode`
  - `locked`
  - `level`
  - `trap`
  - `key`
- `sourceModId`
- `sourceFormId`
- `targetModId`
- `targetFormId`
- `startingPosition`
- `startingOrientation`
- `orientation`
- `supportsLuaData`

用途:

- 盗品・所有権の判定
- 鍵、ロック、罠の識別
- アイテムの実状態の把握
- MOD 由来オブジェクトの追跡
- オブジェクトが移動・配置変更されたかの判定

#### `tes3container` / `tes3containerInstance`

- inventory item list
- 各 item の `id`, `name`, `count`
- 各 item の `itemData`
- `capacity`
- `organic`
- `respawns`

用途:

- 宝箱、収納、死体、NPC 所持品の探索
- 未取得アイテムの認識
- コンテナの再出現可能性の判断

#### `tes3npc` / `tes3creature`

- `spells`
- `aiConfig`
- `autoCalc`
- `attributes`
- `skills`
- `soul`
- creature の `attacks`
- creature の `aiConfig`

用途:

- NPC の能力、魔法、戦闘力の推定
- 会話・商取引・戦闘相手としての評価
- 魂石や魂捕獲対象の判断

#### `tes3mobileActor`

- `activeMagicEffectList`
- `currentSpell`
- `currentEnchantedItem`
- `readiedWeapon`
- `readiedShield`
- `readiedAmmo`
- `hostileActors`
- `friendlyActors`
- `aiPlanner`
- `collidingReference`
- `effectAttributes`

用途:

- 現在の脅威や敵対関係の把握
- NPC の現在の装備・魔法の把握
- バフ、デバフ、病気、透明化などの判定
- 戦闘回避や戦闘準備の判断

### 優先度: 中

#### `tes3cell`

- `actors`
- `activators`
- `statics`
- `doors`
- `containers`
- `items`
- `landscape`
- `pathGrid`
- `editorName`
- `ambientColor`
- `fogColor`
- `fogDensity`

用途:

- 現在セルの可視オブジェクト一覧
- 探索済み・未探索オブジェクトの比較
- ドア、収納、NPC、アイテムの発見
- 屋外・屋内の環境理解

注意:

- 全オブジェクトを再帰的に出すと出力が巨大になる。
- `summary` と `objects` の shallow/deep モードを分けるべき。

#### `tes3pathGrid`

- `isLoaded`
- `parentCell`
- `nodes`
- 各 path node の位置と接続先

用途:

- NPC 用経路の推定
- 屋内セルのナビゲーション
- 障害物を避けた移動計画

注意:

- `nodes` はセルごとに大きくなるため、通常は専用の navigation resource として出す方がよい。

#### `tes3door`

- `lockNode`
- destination の詳細
- `openSound`
- `closeSound`
- script

用途:

- 開錠が必要か
- どこへ移動するドアか
- トラップ付きか
- ドアがクエスト進行上の移動点か

### 優先度: 低または用途限定

- `animationData`
- `attachments`
- `bodyPartManager`
- `sceneNode`
- `light`
- `nodeData`
- `nextNode`
- `previousNode`
- `context`
- `data`
- `tempData`
- `scriptVariables`
- `animationController`
- `combatSession`
- `actionData`

これらはデバッグ、MOD 連携、詳細な戦闘解析には使えるが、通常の探索用 serializer に直接含めると循環参照や巨大な出力を招きやすい。

## 4. 推奨する追加順序

1. `tes3reference.itemData`
2. `tes3reference.lockNode`
3. container inventory の shallow serializer
4. NPC/creature の `spells`、`aiConfig`、skills の名前付き表現
5. mobile actor の active effects と現在装備
6. cell 内オブジェクトの shallow 一覧
7. path grid nodes の専用 navigation 出力
8. 詳細な attachments、animation、script variables

## 5. 実装時の注意

- `itemData.owner`、`lockNode.trap`、`mobile`、`cell` は循環参照を起こしやすい。
- セル一覧と inventory は常に shallow 出力を基本にする。
- `id`, `objectType`, `name`, `cell`, `position` を各 object summary の共通キーにすると agent が扱いやすい。
- ここでいう共通キーとは、NPC、ドア、アイテムなど種類が異なるオブジェクトでも、探索用の shallow summary に同じ名前で基本情報を返すことを指す。例えば、エージェントは種類ごとに異なる field を探さず、`objectType` で種類、`name` で名称、`cell` と `position` で場所、`id` で識別子を確認できる。base object のように場所を持たない場合は `cell` と `position` を `nil` にする。
- `spells`, `skills`, `attributes` は数値配列ではなく名前付き map にする。
- `sourceModId`、`sourceFormId` は MOD 起因の問題調査に有用なので、通常出力では optional にする。
- `sceneNode`、`animationData`、`data`、`tempData` は通常出力から除外する。

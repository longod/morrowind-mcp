# MenuInventory Action Plan

## Goal

Validate the UI-only inventory interaction contract using `MenuInventory`, where the existing server test can reliably open menu mode and inspect actions. Do not use direct TES3 inventory mutation APIs.

The completed Phase 1 contract is:

1. `mw-menu-fetch` returns visible item tiles as flat actions with `mouseClick` and `inventory_tile` metadata.
2. `mw-menu-action` accepts a selected tile path.
3. A later `mw-menu-fetch` returns `cursor_tile` with the selected item and count.

After an item tile is clicked, its cursor representation is owned by the help layer rather than the inventory menu. `cursor_tile.path` is therefore not required and must not be used as a post-click locator.

## Scope

Included:

- `MenuInventory` only.
- Normal success paths before recovery or cancellation paths.
- Player inventory tiles, player inventory drop region, character portrait, and the quantity UI reached from a Gold stack.
- One separate probe for dropping an item into the 3D scene.

Deferred:

- `MenuContents`, `MenuBarter`, pickpocket, and merchant operations.
- Automatic recovery if a destination click fails.
- Inventory ownership, stealing, prices, and crime semantics.
- Equipment-state postconditions. Equipment Memory may be used for later observation, but it is not a gate for this milestone.
- Publishing or implementing `mw-inventory-action`.

## Source Context

The source tile path is required only to start an operation: it tells `mw-menu-action` which live inventory tile to click. Before that click, the caller records a source snapshot:

- `path`
- item id and name
- count
- `inventory_pane`
- menu name
- equipped and bartered flags

After the click, the original tile path may be stale and is not reused. The cursor item and subsequent action list are the authoritative live state.

## Phase 2A: Discover MenuInventory Targets

1. During the existing `menu mode on` to `menu mode off` interval in `tests/server_test.ps1`, fetch `mw-menu-fetch` with `output_mode=actions`.
2. Record every visible executable action with its path, id, name, type, text, and widget/action metadata.
3. Identify candidate targets for the player inventory region and character portrait from the returned action list and the corresponding tree output.
4. Do not promote a candidate to `inventory_target` merely because `triggerEvent(mouseClick)` is accepted. The `MenuInventory_character_box` probe was accepted but did not place `ring_keley` or clear the cursor.
5. Vanilla placement requires a physical pointer position and mouse-button release instead of an element event. MWSE's drag-release dispatcher hit-tests mainRoot using the current mouse coordinates and dispatches the release to the element below it; it does not dispatch to `CursorIcon`.
6. Determine the empty player inventory-grid cell that receives the release. Rerun `tests/server_test.ps1` after each focused probe and preserve the input/action evidence.

Acceptance criteria:

- Every published target completes its intended vanilla placement and clears the cursor in two subsequent fetches.
- No target is inferred from a name alone or from an accepted `triggerEvent` without a successful placement probe.

### Confirmed Routing Constraint

`tes3ui.getCursor()` and `tes3ui.getCursorTile()` expose the help-layer cursor representation. They are state-observation APIs, not drop destinations. A `triggerEvent` on `CursorIcon`, `MenuInventory_character_box`, or another element bypasses the native drag-release hit test and is not equivalent to a player drop.

MWSE's `MenuInputController::dispatchMouseReleaseEvent` in `TES3UIMenuController.cpp` resolves the live pointer location against mainRoot while mouse drag capture is active, then sends the release to the element under that location. OpenMW's `mwgui/draganddrop.cpp` follows the same architecture: the dragged widget follows the cursor, while the destination is selected by GUI hit-testing.

The next probe must therefore:

1. Click a safe non-equipped tile and verify `cursor_tile`.
2. Calculate an on-screen point within a confirmed empty inventory-grid cell.
3. Move the actual Morrowind-window cursor to that point and release the primary mouse button through the existing direct mouse input path.
4. Fetch twice and require an empty cursor while verifying that the item remains in player inventory.

Add a temporary release observer only to record the actual destination element; do not advertise it as an `inventory_target` until the probe succeeds.

## Phase 2B: Equip and Unequip Normal Paths

1. Select a non-equipped player item tile and retain its source snapshot.
2. Click the source tile, then verify the expected `cursor_tile` in a later `mw-menu-fetch` call.
3. Click the confirmed `character_portrait` target once.
4. Fetch actions and cursor state twice; verify that the cursor is empty after the destination click.
5. Use an equipped tile and the confirmed `player_inventory` target to run the corresponding unequip path.

Acceptance criteria:

- Each destination click is accepted by `mw-menu-action`.
- The cursor is empty on both post-destination fetches.
- The test records the source snapshot, target path, and cursor observations in the Inspector log.

## Phase 2C: Gold Quantity UI

1. Select a Gold tile with count greater than one.
2. Click it and observe when `MenuQuantity` becomes visible through `mw-menu-fetch`.
3. Identify the amount input and confirm action from the live action list/tree.
4. Enter a smaller positive integer and confirm once.
5. Fetch twice and record the cursor item/count and visible quantity UI state.

Acceptance criteria:

- The input and confirm paths are derived from the live UI, not hard-coded.
- The timing of `MenuQuantity` appearance and completion is recorded.
- No direct item transfer, removal, or count mutation API is used.

## Phase 2D: 3D Scene Drop Probe

1. Select a disposable player inventory tile and confirm its cursor state.
2. Use the existing player input/click mechanism to release it into the 3D scene, rather than an inventory target.
3. Fetch cursor state twice and inspect memory/inventory output only as observational evidence.

Acceptance criteria:

- The probe establishes whether the existing UI/input surface can express a scene drop.
- This result does not publish a `drop` workflow or add it to `mw-inventory-action`.

## Test Sequence

Each live probe must run inside `tests/server_test.ps1` after `menu mode on` and before `menu mode off`. The server test owns server startup, foreground activation, shutdown, Inspector logging, and MWSE.log capture.

For every new action path, add a focused UnitWind test only for reusable helpers under `tes3/` or `util/`; do not add UnitWind tests for `tools/`. Then delegate both focused UnitWind and server-test execution to the Test Runner.

## Stop Gates

Stop and review after each phase. Do not implement or publish `mw-inventory-action` until all of these are measured:

- stable paths for the intended `MenuInventory` targets;
- successful normal equip and unequip cursor lifecycle;
- `MenuQuantity` timing and controls for Gold;
- whether 3D scene drop is reachable through the supported UI/input surface.

Any recovery, container, barter, pickpocket, ownership, or equipment-memory postcondition work requires a later plan update.

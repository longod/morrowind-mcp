# MenuInventory Action Plan

## Goal

Validate the UI-only inventory interaction contract using `MenuInventory`, where the existing server test can reliably open menu mode and inspect actions. Do not use direct TES3 inventory mutation APIs.

The completed Phase 1 contract is:

1. `mw-menu-fetch` returns visible item tiles as flat actions with `mouseClick` and `inventory_tile` metadata.
2. `mw-menu-action` accepts a selected tile path.
3. A later `mw-menu-fetch` returns `cursor_tile` with the selected item and count.

After an item tile is clicked, its cursor representation is owned by the help layer rather than the inventory menu. `cursor_tile.path` is therefore not required and must not be used as a post-click locator. Immediate cursor visibility is diagnostic only and does not block a same-call destination click.

## Scope

Included:

- `MenuInventory` only.
- Normal success paths before recovery or cancellation paths.
- Player inventory tiles, player inventory drop region, character portrait, and the quantity UI reached from a Gold stack.
- One separate probe for dropping an item into the 3D scene.

Verified in development debug mode:

- A count-one, non-bound `MenuContents` tile can be transferred to the player inventory through one source click followed by the curated player-inventory destination click.
- `MenuContents_takeallbutton` is the fixed vanilla Take All shortcut. Its verified static path is `layout/MenuContents/PartDragMenu_thick_border/PartDragMenu_center_frame/PartDragMenu_drag_frame/null/null/PartDragMenu_main/Buttons/Buttons/MenuContents_takeallbutton`.
- Take All closes `MenuContents`. Its completion is verified from an empty cursor and two stable, increased player `mw-inventory-fetch` snapshots; the closed menu is not reused.
- A focused merchant probe can use `activate`, then click the live `MenuDialog_service_barter` choice to open `MenuBarter` without navigation or view changes.
- `MenuBarter_Offerbutton` is a verified native Offer shortcut. Its fixed static path is `layout/MenuBarter/PartDragMenu_thick_border/PartDragMenu_center_frame/PartDragMenu_drag_frame/null/null/PartDragMenu_main/null/null/MenuBarter_Offerbutton`. The debug-only `offer` action resolves its curated effect, clicks its unique enabled live instance once with an empty cursor, and reports later UI observation as the postcondition. The live probe confirmed vanilla `MenuNotify3` activation.
- A focused scene-drop probe moved to a live UI-free input point, initiated a timed DirectInput left tap, and verified an empty cursor, `common_pants_01` inventory count from 1 to 0, and a new nearby world reference.

Each action remains development-debug-only. Do not implement a 3D drop workflow until its supported input path is measured.

Deferred:

- Selecting player or merchant inventory tiles to construct a barter offer, pickpocket, and ownership or price semantics.
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

### Confirmed Targets

Manual live probes confirmed these exact `mw-menu-action` destinations:

- `MenuInventory_CharacterImage` accepts `mouseClick` as the equipment destination.
- The MenuInventory `PartScrollPane_outer_frame` accepts `mouseClick` as the player inventory background destination.

Both paths are published through curated `staticHints` in `util/ui_action.lua`; generic `image` or scroll-pane action discovery is intentionally not enabled. Vanilla inventory interaction is click-to-pick and click-to-place: selecting a tile enters the drag state without an OS-style pointer hold, and clicking another target attempts placement.

1. During the existing `menu mode on` to `menu mode off` interval in `tests/server_test.ps1`, fetch `mw-menu-fetch` with `output_mode=actions`.
2. Record every visible executable action with its path, id, name, type, text, and widget/action metadata.
3. Identify candidate targets for the player inventory region and character portrait from the returned action list and the corresponding tree output.
4. Do not promote a candidate to `inventory_target` merely because `triggerEvent(mouseClick)` is accepted. The `MenuInventory_character_box` probe was accepted but did not place `ring_keley` or clear the cursor.
5. Use the existing portrait and inventory-background static hints as the destination; no new destination discovery is required for this probe.
6. Invoke exactly one source click and one destination click in the same `inventory-action` call, with no wait or retry between them. Record cursor observations after each click, but continue even when the immediate cursor is absent.

Acceptance criteria:

- Every published target completes its intended vanilla placement and clears the cursor in two subsequent fetches.
- No target is inferred from a name alone or from an accepted `triggerEvent` without a successful placement probe.

### Same-Call Probe Constraint

`tes3ui.getCursorTile()` exposes the help-layer cursor representation. It is an observation API, not a destination locator. The development-only `mw-inventory-action` probe records the cursor before and after each event but never gates its second click on an immediate cursor result.

The server test selects at most one equipped player tile, performs one unequip probe, and stops. It does not retry, choose a fallback item, attempt the reverse equip operation, or recover a remaining cursor item. The recorded Inspector and MWSE logs are the outcome of the probe whether it succeeds or fails.

## Phase 2B: Equip and Unequip Normal Paths

### Routing Status

The portrait and player inventory background targets have both completed manual `mouseClick` probes. The remaining work is to record the two post-destination fetches and cursor lifecycle in `tests/server_test.ps1` before this phase can meet its acceptance criteria.

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

1. Start from a safe, open-area save with a disposable, count-one player item identified by ID.
2. Select the item tile and scan visible mouse-consuming UI regions for the lowest UI-free input point.
3. Move the DirectInput mouse to that UI-viewport point and initiate a timed left tap in the same debug-only tool call; its release occurs after the engine observes the press.
4. Verify that the cursor is empty, player inventory decreases by one, and a new nearby world reference with the item ID is observed.

Acceptance criteria:

- The probe establishes whether the existing UI/input surface can start a same-call scene drop, with completion observed by later fetches.
- Any failed postcondition stops the workflow; no retry, recovery click, or fallback item is attempted.

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

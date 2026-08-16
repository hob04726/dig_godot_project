# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A 2D isometric "digging" game built in **Godot 4.7** (Forward Plus renderer, Jolt 3D physics, `d3d12` on Windows). Gameplay scene: `res://scenes/main.tscn`. Game logic is **pure GDScript** — the project declares a `.NET` assembly name (`[dotnet] project/assembly_name`) and the installed editor is the Mono build, but there are no `.cs` files; do not add C# build steps.

The Godot binary is not on `PATH`. It lives at:
`D:/Program Files (x86)/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe`
(referred to as `godot` below).

## Commands

```bash
# Run the game (or press F5 in the editor)
godot --path .

# Run the DefDb smoke test (a SceneTree script, prints defs + weighted rolls, then quits)
godot --headless --script res://test/scripts/tex_path_test.gd

# Run the tile placement/removal rules test (GridModel data-layer rules)
godot --headless --script res://test/scripts/tile_rules_test.gd

# Run the block animation state-machine test (Tween-driven Fall/Shake/Float transitions)
godot --headless --script res://test/scripts/block_animation_test.gd

# Run the tile behavior test (data-layer: water/volcano/upgrade/stone/grass/spawn/push/pull/fire)
godot --headless --script res://test/scripts/tile_behavior_test.gd

# Regenerate the talent CSVs from the design tables (Node, not Godot)
node test/scripts/gen_talent_csv.mjs

# Validate the talent CSVs (column counts, references, coords, cost formula)
node test/scripts/validate_talent_csv.mjs

# Run the economy tests (BigNumber / GameState / SaveManager)
godot --headless --script res://test/scripts/big_number_test.gd
godot --headless --script res://test/scripts/game_state_test.gd
godot --headless --script res://test/scripts/save_test.gd

# Run the money-display formatting boundary test
godot --headless --script res://test/scripts/money_display_test.gd

# Run the talent CSV → TalentDef loader test
godot --headless --script res://test/scripts/talent_db_test.gd

# Run the talent effect-aggregation test (TalentSystem)
godot --headless --script res://test/scripts/talent_system_test.gd

# Run the tile placement/sell pricing test (TilePricing)
godot --headless --script res://test/scripts/tile_pricing_test.gd

# Run the tile behavior override test (GridModel.set_tile_overrides)
godot --headless --script res://test/scripts/grid_override_test.gd

# Run the ore-pool filtering test (DefDb.roll_ore allowed set)
godot --headless --script res://test/scripts/def_db_pool_test.gd
```

There is no linter or formal test framework. Tests are plain `extends SceneTree` scripts under `test/scripts/` run with `--headless --script`. To run a single check, copy that pattern (or add a script alongside the existing one). Debug prints and `push_warning`/`push_error` output are the primary diagnostic channel. Note: `main.tscn`'s root node runs `res://test/scripts/test.gd`, a debug helper that spawns a random ore when you press `C`.

## Architecture

The code follows a strict **data layer / view layer** split, built on a `BlockDef`-based data system (see the commit "重构：数据层迁移到 BlockDef 体系").

### Data layer (single source of truth)

- **`GridModel`** (`scripts/game/block/grid_model.gd`) — the one authoritative container and the game's only event source. Rules enforced here (see the header comment):
  1. Every write goes through `try_*` / `remove_*` and returns a `MutResult`; signals are emitted only after a successful write.
  2. Entities (`OreBlock`) never back-reference the grid and never emit cross-system signals.
  3. Signal callbacks must not write back into the model (views/economy are read-only subscribers).
  4. Tile placement/removal rules (`try_place_tile` / `try_remove_tile`) — placement only adjacent to the center-connected group; the center tile (0,0) is undeletable; deletion must preserve the group's connectivity; deleting a tile also removes any ore on it without a coin reward (`remove_ore(cell, false)` → `ore_discarded`).
  5. Tile behaviors (`GridModel.tick(delta)`, driven by GameManager each frame) — periodic behaviors: volcano attacks neighbor ores, upgrade levels the ore above, spawn emits `tile_request_spawn` (fulfilled by the view factory), push/pull move ores (`ore_moved`), fire damages the ore above. Water/volcano are hazard cells: ores can't rest there (sink on landing / spawn & move rejected), and auto-spawn/push/pull exclude them. Water refunds `sink_refund_ratio` (10% base; `TILE_BEHAVIOR_UP` water upgrades can raise it) on sink; the reward ratio flows through the `ore_removed(ore, cell, reward_ratio)` signal. Behavior params are read through `tile_overrides` (injected by the composition root from `TalentSystem.get_tile_behavior_overrides()` — see View layer), so talent upgrades modify damage/`tick_interval`/multipliers without touching the shared `.tres`. Rarity raises the auto-spawn roll's `min_rarity`; `settle_value` (stone) and `hit_damage` (grass) are model helpers the view uses.
- **`DefDb`** (`scripts/game/block/def_db.gd`) — read-only definition registry. On startup it scans `res://defs/ores/*.tres` and `res://defs/tiles/*.tres`, validates them, and files them into `ores`/`tiles` dictionaries keyed by `StringName` id. **Adding a new ore or tile = drop a `.tres` file into the right directory**; no code change needed.
- **Definition resources** (`scripts/game/block/`) — `BlockDef` (id, display_name, `texture`/`textures`, `z_bias`) with two subclasses:
  - `OreDef` — rarity, spawn_weight, base_value/hp, max_level, growth curves; level-scaled getters.
  - `TileDef` — a `Behavior` enum (`NONE/WATER/VOLCANO/UPGRADE/STONE/SPAWN/RARITY/PUSH/PULL/GRASS/FIRE`) plus behavior params (`tick_interval`, `damage`, `value_multiplier`, `damage_multiplier`, `min_rarity`, `spawn_ore_id`), `base_cost` (placement pricing base), `sink_refund_ratio` (water refund, default 0.1). Periodic behaviors run in `GridModel.tick`; event behaviors hook landing/mining/settlement.
  - `CellData` — one cell's two slots: `above_block` / `below_block`, each holding a `BlockDef` (null = empty).

### View layer (presentation / interaction)

- **`GameManager`** (`scripts/game/game_manager.gd`) — the **composition root**. It owns a `GridModel` + `DefDb` + `GameState` (economy) + `TalentSystem` + `SaveManager` and is the only place that both reads the model *and* instantiates scenes. The block/ore factory deliberately lives here (not in `DefDb`) because `OreBlock` requires scene files. It wires grid signals to effects (`ore_removed` → full settlement pipeline via `TalentSystem.compute_coin_gain`), handles ore spawning/falling (with `UNLOCK_ORE` gating — natural pool excludes crystal, spawn tiles bypass), mining + the mining progress bar + damage jump numbers (damage pipeline `hit_damage_details` with crit; crits show a rainbow/shake popup), hover, tile placement/removal mode (**with `TilePricing` costs & sell refunds**), pushes `TILE_BEHAVIOR_UP` overrides to the grid, the save/load lifecycle (**`grid.run_version != state.run_version` → new run**), and the isometric coordinate mapping. It also animates the money panel's fire shader (`money_fire_material`) when the player breaks their own 60-second coin record (`_update_fire`).
- **`Block` / `OreBlock`** (`scripts/game/block/`) — runtime `Node2D`s. `Block` runs a state machine with four states as child nodes: `Idle`, `Shake`, `Fall`, `Float` (`scripts/game/block/states/`). Each state drives its own visual effect with the built-in `Tween`; there is no `AnimationPlayer`/`AnimationTree` in the scenes. `OreBlock extends Block`, adding `level`/`hp`/`value` and a `landed` signal.
- **`Camera2D`** (`scripts/camera/camera.gd`) — shared camera script (used by both main and talent scenes): wheel zoom (smoothed, clamped to `min_zoom`/`max_zoom`), middle-drag pan, `reset_camera()`.
- **Scenes** — `scenes/block.tscn` (generic tile/block) and `scenes/ore_block.tscn` are near-identical: `Sprite2D` + `GPUParticles2D` + `States/{Idle,Shake,Fall,Float}`. `main.tscn` instantiates `GameManager` (node `World`) with `AboveGridLayer`/`BelowGridLayer`, a pointer `AnimatedSprite2D` (z_index 4096), a `BackgroundLayer` (animated-pattern shader), and a `CanvasLayer` holding the HUD, money panel, and tile drawer. `scenes/talent.tscn` is a separate talent-tree scene (see below), not part of the main loop.

### UI layer

- **Tile drawer** (`scripts/ui/tile_drawer.gd`, node `CanvasLayer/BlowContainer`) — a bottom-right "drawer" PanelContainer. The handle button toggles it open/closed via Tween; closing it exits placement mode. The 11 ground-tile buttons are **statically pre-placed** in `main.tscn`'s HBoxContainer (not built at runtime) and wired by order to `TILE_IDS` (`dirt/grass/stone/fire/water/volcano_stable/upgrade/rarity/spawn/push/pull`). **Only tiles unlocked in the talent tree (`UNLOCK_TILE`) appear** — `_refresh_visible()` hides locked buttons, applied at ready and on GameManager's `initialized` signal. Clicking a button calls `GameManager.toggle_tile_selection(id)` (which also rejects locked tiles); the drawer reflects the current selection via the `tile_selection_changed` signal. Container backgrounds are `mouse_filter = IGNORE` so clicks pass through.
- **Money counter** — `CanvasLayer/PanelContainer` (StyleBoxTexture panel, 86×40) with a `RichTextLabel` showing the coin total. The panel carries the fire shader `balatro_original_fire.gdshader` (see Shaders).
- **Global fonts** — project-wide default font set via `themes/main_theme.tres` + `project.godot` `gui/theme/custom` (no per-node font overrides anywhere). `default_font` is a `FontVariation` wrapping `assets/fonts/BoldPixels.ttf` (Latin/digits) with `fallbacks = [ark-pixel-10px-monospaced-zh_cn.ttf]`, so CJK glyphs fall back to the 10px pixel font automatically. Both font imports use `antialiasing=0` (crisp pixels). **Gotcha**: in Godot 4.7.1, *accessing* `Theme.default_font_antialiasing` from GDScript hangs the process (confirmed) — keep antialiasing at the font-import level, never read that property in scripts.
- **Dev console** — `scenes/ui/console.tscn` + `scripts/ui/dev_console.gd`, registered as the `Console` autoload (layer 150, above the scene transition). Toggle with backtick `` ` `` (or `~`); `_input` consumes the key so it never types into the `LineEdit`. Commands: `help`, `clear`, `give gold <n>` (e.g. `give gold 1999999` / `1e9`), `give lifetime <n>` (ascension-point testing), `unlock <talent_id>`. State is located from the current scene (`World`/`GameManager.state`, or `TalentGrid._state`); after `give` it refreshes the scene's views (`GameManager._update_money_label()`, or `TalentGrid._refresh_all(false)` + `_update_gold_label()`). `give gold` calls `GameState.add_coins`, which also bumps `lifetime_coins`. Command table is a `match` in `_run_command` — extend by adding cases there.
- **Scene transition & navigation** — `scripts/ui/scene_transition.gd` is a `CanvasLayer` singleton (`SceneTransition`, layer 100, attached to `SceneTree.root` via `get_instance()`, survives scene changes, `process_mode = ALWAYS`). `SceneTransition.play_to(path)` covers with a luminance-mask shader (`scripts/shaders/scene_transition.gdshader`, grayscale mask `assets/masks/mask.png`, white cover color), swaps scene, then reveals; a `_busy` flag + `MOUSE_FILTER_STOP` block re-entry mid-transition. Navigation buttons: `scripts/button/open_talent.gd` (main → talent, force-saves via `GameManager.save_now()` first since switching frees it) and `back_to_main.gd` (talent → main, calls `TalentGrid.persist()` then transitions).
- **Talent tree** (`scenes/talent.tscn`, `scripts/ui/talent_grid.gd` + `talent_node.gd`, `scripts/game/talent/talent_def.gd` + `talent_db.gd` + `talent_system.gd`, `scenes/talent_node.tscn`) — a separate Node2D world with its own `Camera2D` and animated-pattern background. `TalentGrid` loads `TalentDef`s dynamically from `defs/talents/*.csv` via `TalentDb` and places `TalentNode`s at `(col,row) * cell_size`. The scene shows the **normal (金币) tree only** — the ascension (升华点) tree had a toggle button that has been removed; the redesigned flow (reset → dedicated ascension screen → "new round" button) is pending design, so `TreeMode`/`tree_mode` remain but are effectively fixed to `NORMAL`. Purchases go through the real `GameState` (`spend_coins`/`record_*`); the scene loads `user://save.json` standalone or takes an injected state via `setup_state()`, and persists after each purchase/ascension. Clicking the 重置·升华 node runs `apply_ascension` directly (no confirm). Prerequisite gating: a node reveals only after **all** its `prerequisite_ids` (and its `ascension_prerequisite_id`, if any) are purchased. Hovering a node shows a RichTextLabel tooltip (BBCode description + cost + prereqs + unlock condition) via the `scenes/vfx/talent_label.tscn` prototype. Node states are `LOCKED`/`AVAILABLE`/`PURCHASED`; costs are BigNumber (the CSV goes to e+49, int would overflow). Node visuals: no name label; LOCKED is 0.3-alpha/0.9-scale, AVAILABLE 0.8-alpha/0.9-scale, PURCHASED full/1.0; hover tweens to 1.15/1.0; purchase plays a 0.9→1.2→1 pop and then newly-unlocked affordable nodes bounce in 0→1.2→0.9 (`TalentNode.set_state`, sequenced in `TalentGrid._click`). Each purchase also spawns `scenes/vfx/impact.tscn` at the node — one of its 5 `symmetrical_impact_0xx` animations picked at random, auto-freed when the animation finishes (`TalentGrid._play_purchase_impact`, `impact_prototype` wired in `talent.tscn`).

### VFX

- **`scenes/vfx/explosion.tscn`** — an `AnimatedSprite2D` whose `SpriteFrames` are sliced from the `assets/VfxMix/fx/` sheets. Animation names: `break_1/2/3` (crystal-type ores), `explosion` (other ores), plus `explosion_big/little/rock`. `GameManager._play_explosion` picks the pool by ore type and scales it with the kill damage.
- **`scenes/vfx/coin.tscn`** — `GPUParticles2D` whose `CanvasItemMaterial` enables `particles_animation` (sprite-sheet particle — `AnimatedTexture` does not work with GPUParticles2D). `GameManager._play_coin_and_count` plays it where the ore leaves the screen (edges shoot inward) and runs a Balatro-style coin number count-up for a duration tied to the value. It also triggers the **coin flight** effect, rendered in the main UI CanvasLayer (screen space, negative z so it passes behind the counter): an edge jump number (gold, flies along the exit edge's tangent — straight up/down/left/right — quick scale-up then fade) plus several `tail.tscn` trails (thin/long, count scales with the gain, capped) that fan outward from the screen edge then get pulled to converge behind the money counter and fade; the pull is `max(ramp-up force, K/(dist/3))` — distance-inverse (i.e. 3K/dist, floor at 40 px), so the final approach snaps in (`_spawn_coin_flight` / `_update_coin_flights`).
- **Mining progress bar** (`scenes/vfx/progress_bar.tscn`, `scripts/ui/progress_bar.gd`) — a 15-frame sprite strip (`assets/UI/Cute_Fantasy_UI/UI/Loading_Icon.png`, each frame 16×16). The script slices the atlas into per-frame textures and `set_progress(0..1)` picks the frame. GameManager pops it in/out over the hovered ore with a Tween scale animation (z_index 4000, drawn above tiles).
- **Damage jump number** (`scenes/vfx/jumpnumber.tscn`) — a Node2D + centered RichTextLabel damage popup. `GameManager._spawn_damage_number` launches it on every mine hit with the **same physics as a destroyed ore** (random −45°…+45° upward velocity at `ore_launch_base + damage×ore_launch_per_damage`, gravity-integrated per frame in `_update_jump_numbers` — no Tween); white text with a dark outline for contrast on the light background, fading out while falling then freed. Crits (driven by `TalentSystem.hit_damage_details()`'s `crit` flag) cycle a rainbow hue + rotation shake during flight.
- **Talent tooltip** (`scenes/vfx/talent_label.tscn`) — a PanelContainer + RichTextLabel tooltip prototype (dark panel, BBCode enabled, mouse-transparent). `TalentGrid` instantiates it and follows the mouse to show a hovered talent's description/cost/prereqs/unlock condition.
- **Trail** (`scenes/vfx/tail.tscn`, `scripts/ui/tail.gd`) — a fading motion trail: records the node's `global_position` each frame into a `Line2D` (square caps/joins), fading from semi-transparent yellow at the head to transparent + tapered at the tail. Exports: `color`, `trail_length`, `width` (thickness), `max_alpha`, `taper`, `record_interval`; `clear()` empties it. Attach as a child of a moving object to leave a trail.

### Shaders

- `scripts/shaders/animated_pattern_background.gdshader` — scrolling pattern background (kenney pattern pack); drives both the main and talent scene backgrounds.
- `scripts/shaders/balatro_original_fire.gdshader` — fire effect for the money panel. `amount` (0–10) controls intensity; below 0.1 the fragment just returns so the panel stays opaque and unchanged. `texture_details`/`image_details` size the effect to the panel and must be non-zero (zero → NaN UVs → invisible). `GameManager._trigger_fire` sets `amount` to 6.0 on a new coin record, holds 2.5 s, then tweens back to 0.
- `scripts/shaders/scene_transition.gdshader` — luminance-mask iris transition driven by `SceneTransition` (see UI layer). `mask_texture` is grayscale (`assets/masks/mask.png`); `luminance_cutoff` sweeps 1→0 to cover with the display texture/white color, 0→1 to reveal. No mask texture → runtime-generated radial-gradient fallback.

### Talent & economy design (`defs/talents/*.csv`)

The talent system is data-driven from two CSV files (the authoritative design source; they replace the older `docs/talent_design.xlsx`). Key facts to preserve when editing:

- **`normal_talents.csv`** (204 rows, 24 cols) — per-run talents bought with 金币. Effect types: `PICKAXE_UPGRADE`/`PICKAXE_DAMAGE_FLAT`/`PICKAXE_CRIT_CHANCE`/`PICKAXE_CRIT_DAMAGE`/`PICKAXE_AOE` (pickaxe branch, col 0 rows −1…−8 above the center), `GLOBAL_COIN_MULT`/`GLOBAL_ORE_VALUE_MULT` (global income branch, row 0 cols −1…−6 left of center), `UNLOCK_ORE` (allow an ore into the natural spawn pool), `ORE_VALUE_MULT` (ore settle value ×2 per tier — 10 tiers per ore, gated by `ore_mined ≥ N` and, from tier 5 up, by ascension permits), `UNLOCK_TILE` (availability gate for a tile type — **only dirt is free at start; grass and everything else must be unlocked**), `TILE_BEHAVIOR_UP` (5 levels per tile strengthening the tile's own behavior), `TERRAIN_ORE_SYNERGY` (per 10 placed tiles of a type, a mapped ore's value +10/15/20%), `PRESTIGE_RESET`. `gold_council` is a standalone "金矿价值 ×4" capstone.
- **`ascension_talents.csv`** (6 rows, 13 cols) — permanent meta unlocks bought with 升华点: `UNLOCK_META` (legacy root), `UNLOCK_TIER_RANGE` (three mining permits gating value-upgrade tiers 5–6 / 7–8 / 9–10; the last two require BigNumber), `PERMANENT_SLOT` (keep N normal talents across a reset). Deliberately **no** bulk-buy / buy-max / offline-income / synergy talents — pacing comes from exponential prices alone.
- **Economy model** (implemented): there are **no auto-buildings**. Ores are click-loot (mined once for a value lump); tiles are the infinitely-purchasable "buildings". Unlocking a tile happens in the talent tree; **placing / selling a tile happens in the game** — placement costs `base × 1.15^placed_count` per tile type (`TileDef.base_cost`, dirt 10 … spawn 2.5M in `defs/tiles/*.tres`), selling refunds 25% of the current buy price (`TilePricing`). The full settlement pipeline is `settle_value × ore_value_mult × terrain_synergy × global_ore_value × reward_ratio × global_coin × permanent_multiplier`, computed by `TalentSystem.compute_coin_gain`.
- **Ascension points** (Cookie Clicker / Heavenly Chips model): `总升华点 = floor(cbrt(累计金币 / 1e6))` is derived from all-time cumulative coins and never decreases; each reset claims the delta (`新总数 − 已领取`, tracked in `ascension_points_earned`). Each claimed point grants +1% coin gain permanently (spent points don't reduce the bonus). No per-run cap — when a run can't afford anything, the player naturally ascends.
- **Tooling** (Node, `test/scripts/`): `gen_talent_csv.mjs` regenerates both CSVs from the design tables; `validate_talent_csv.mjs` checks column counts, id/prerequisite referential integrity, (col,row) uniqueness, `cost == mantissa×10^exponent`, and that `target_ids` map to real ores/tiles. Run them with `node`, not Godot.

### Economy & persistence (data layer)

- **`BigNumber`** (`scripts/game/economy/big_number.gd`) — mantissa/exponent big-number type (break_infinity.js style), covers ±1e308 with ~15 significant digits. Operations return new instances (immutable style). `normalize()` snaps values < 2^53 back to exact integers so the integer economy doesn't drift; comparisons use a 1e-9 relative tolerance to absorb float alignment noise. `to_save_string()`/`from_string()` round-trip for save.
- **`Prestige`** (`scripts/game/economy/prestige.gd`) — pure ascension math, no state: `points_for = floor(cbrt(lifetime / 1e6))`, `multiplier_from_points = 1 + points × 1%`.
- **`GameState`** (`scripts/game/economy/game_state.gd`) — data-layer owner of the persistable economy, single write entry (same discipline as `GridModel`): `coins`, `lifetime_coins`, `ascension_points_earned` (points claimed at resets) / `ascension_points_spent`, `run_version` (bumped on ascension; the main scene uses it to detect a reset), `ore_mined`, `talent_purchases`, `ascension_purchases`. All writes go through methods that emit `changed`; views subscribe read-only. `ascension_points_total()` is derived from `lifetime_coins` (Cookie Clicker: never decreases); `apply_ascension(preserve_ids)` claims the delta, resets coins + normal talents (keeping `preserve_ids` for permanent slots), bumps `run_version`. `to_dict()`/`load_from_dict()` handle save.
- **`TalentSystem`** (`scripts/game/talent/talent_system.gd`) — data-layer effect aggregator: reads `GameState` purchases + `TalentDb` defs and exposes semantic queries (`get_ore_value_multiplier`, `get_global_coin_multiplier`, `get_pickaxe_*`, `get_tile_behavior_overrides`, `get_unlocked_ores`, `get_terrain_synergy`, `get_permanent_multiplier`, …) plus the settlement/hit pipelines `compute_coin_gain` / `compute_hit_damage`. Holds no grid — `placed_counts` are passed in. `invalidate()` after purchases/ascension.
- **`TilePricing`** (`scripts/game/economy/tile_pricing.gd`) — static placement/sell math: `placement_cost(tile, n) = round(base × 1.15^n)`, `refund_value(tile, n) = round(25% × base × 1.15^(n-1))`.
- **`SaveManager`** (`scripts/game/save/save_manager.gd`) — JSON I/O to `user://save.json`, versioned, with corrupt-file quarantine (`save.json.corrupt` backup) and an instance `save_path` so tests use an isolated file. It only serializes/deserializes a generic payload — the composition root decides what to persist.
- **`GameManager`** wiring — owns `state` + `_talent_system` + `_save_manager`. Coins are `state.coins` (BigNumber); the money label, count-up, and fire shader all read it. Mining runs the damage pipeline (`compute_hit_damage`) and increments `ore_mined` on player kills in `_mine_at`; coin settlement runs `compute_coin_gain`. Tile placement/spend & sell/refund go through `TilePricing` + `state.spend_coins`/`add_coins`. Natural ore spawn is gated by `get_natural_spawn_ores()` (crystal excluded). `_load_or_init` restores state + grid, but if the saved grid's `run_version` differs from `state.run_version` (an ascension happened in the talent scene), it resets to a fresh dirt run. Saves on window close + every 15 s when dirty.
- **`GridModel`** — `get_placed_count`/`get_placed_counts` derive per-type placed tile counts from the grid (single source of truth, no drift); `snapshot_cells`/`snapshot_ores` produce the save format; `set_tile_overrides` + effective readers (`effective_value_multiplier(cell)` / `effective_damage_multiplier(cell)` / `effective_min_rarity(cell)`, plus internal `_effective_damage`/`_effective_tick_interval`/`_effective_sink_refund`) apply talent behavior upgrades at query/tick time.

### TODO — 天赋系统后续

天赋系统落地已完成：效果引擎（TalentSystem 聚合 + 结算/伤害管线）、放置计价（TilePricing + TileDef.base_cost）、落矿门控（UNLOCK_ORE，水晶排除）、地块行为升级运行时（GridModel overrides）、天赋场景接真实 GameState + 升华重置、初始 dirt、run_version 跨进程协调、12 个数据层测试全绿。剩余：

- [ ] **升华流程 UI** — 升华/普通切换按钮已移除；规划中：点击「重置·升华」后进入独立的升华天赋界面，再点「新一轮」按钮开始新轮（当前点击重置直接重建普通树，`TreeMode` 恒为 `NORMAL`）。
- [ ] **稿子暴击视觉 + AOE 范围命中** — 数值已接入（`compute_hit_damage` 含暴击乘区），暴击飘字与 `PICKAXE_AOE` 的范围攻击（`get_pickaxe_aoe_radius` 数据已就绪）尚未实现。
- [ ] **`tile_up_rarity_3..5` 的"结算 ×1.1/1.2/1.3"机器化** — CSV `value` 只编码了 min_rarity；加 `value2` 列 + 改 validate/gen/TalentDb 才能读结算加成。
- [ ] **存档版本迁移** — SAVE_VERSION=2 起 schema 稳定；未来改 schema 需 bump 版本 + 迁移旧档。

### Key conventions to preserve

- **Ownership discipline**: `OreBlock` never removes itself from the grid — the caller does `grid.remove_ore(cell)` and then `queue_free()`s the node (see `take_damage` comment). This is called out as the core robustness rule.
- **`MutResult`** (`scripts/game/block/mut_result.gd`) — grid writes return an explicit success/failure (`Code` enum + message); callers must handle the failure branch rather than assume success.
- **Isometric coordinates** — `grid_to_world` / `world_to_grid` in `GameManager` (tile 32×16). `z_index` is derived from `cell.x + cell.y` (+ bias) so sprites overlap correctly; there is no tilemap node, sprites are positioned manually.
- **Layer split** — tiles render in `below_grid_layer`, ores/above-blocks in `above_grid_layer` (both under the `World` node in `main.tscn`), with `ABOVE_LAYER_OFFSET` for visual separation.
- Code comments and `display_name` values (e.g. "金矿", "草地") are written in Chinese; keep them consistent with the surrounding files.

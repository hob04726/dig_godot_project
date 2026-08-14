# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A 2D isometric "digging" game built in **Godot 4.7** (Forward Plus renderer, Jolt 3D physics, `d3d12` on Windows). Main scene: `res://scenes/main.tscn`. Game logic is **pure GDScript** — the project declares a `.NET` assembly name (`[dotnet] project/assembly_name`) and the installed editor is the Mono build, but there are no `.cs` files; do not add C# build steps.

The Godot binary is not on `PATH`. It lives at:
`D:/Godot/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe`
(referred to as `godot` below).

## Commands

```bash
# Run the game (or press F5 in the editor)
godot --path .

# Run the DefDb smoke test (a SceneTree script, prints defs + weighted rolls, then quits)
godot --headless --script res://test/scripts/tex_path_test.gd
```

There is no linter or formal test framework. Tests are plain `extends SceneTree` scripts under `test/scripts/` run with `--headless --script`. To run a single check, copy that pattern (or add a script alongside the existing one). Debug prints and `push_warning`/`push_error` output are the primary diagnostic channel.

## Architecture

The code follows a strict **data layer / view layer** split. The current `develop` branch is mid-refactor into a `BlockDef`-based data system (commit "重构：数据层迁移到 BlockDef 体系").

### Data layer (single source of truth)

- **`GridModel`** (`scripts/game/block/grid_model.gd`) — the one authoritative container and the game's only event source. Rules enforced here (see the header comment):
  1. Every write goes through `try_*` / `remove_*` and returns a `MutResult`; signals are emitted only after a successful write.
  2. Entities (`OreBlock`) never back-reference the grid and never emit cross-system signals.
  3. Signal callbacks must not write back into the model (views/economy are read-only subscribers).
- **`DefDb`** (`scripts/game/block/def_db.gd`) — read-only definition registry. On startup it scans `res://defs/ores/*.tres` and `res://defs/tiles/*.tres`, validates them, and files them into `ores`/`tiles` dictionaries keyed by `StringName` id. **Adding a new ore or tile = drop a `.tres` file into the right directory**; no code change needed.
- **Definition resources** (`scripts/game/block/`) — `BlockDef` (id, display_name, `texture`/`textures`, `z_bias`) with two subclasses:
  - `OreDef` — rarity, spawn_weight, base_value/hp, max_level, growth curves; level-scaled getters.
  - `TileDef` — skeleton; behavior fields are deferred to a later "tile phase".
  - `CellData` — one cell's two slots: `above_block` / `below_block`, each holding a `BlockDef` (null = empty).

### View layer (presentation / interaction)

- **`GameManager`** (`scripts/game/game_manager.gd`) — the **composition root**. It owns a `GridModel` + `DefDb` and is the only place that both reads the model *and* instantiates scenes. The block/ore factory deliberately lives here (not in `DefDb`) because `OreBlock` requires scene files. It wires grid signals to effects (e.g. `ore_removed` → coin tally), handles ore spawning/falling, mining, hover, and the isometric coordinate mapping.
- **`Block` / `OreBlock`** (`scripts/game/block/`) — runtime `Node2D`s. `Block` runs a state machine with four states as child nodes: `Idle`, `Shake`, `Fall`, `Float` (`scripts/game/block/states/`), driven by an `AnimationTree` (`AnimationNodeStateMachine`) whose conditions the states toggle. `OreBlock extends Block`, adding `level`/`hp`/`value` and a `landed` signal.
- **Scenes** — `scenes/block.tscn` (generic tile/block) and `scenes/ore_block.tscn` are near-identical: `Sprite2D` + `GPUParticles2D` + `AnimationPlayer` + `AnimationTree` + `States/{Idle,Shake,Fall,Float}`. `main.tscn` instantiates `GameManager` (node `World`) and points it at `block.tscn`/`ore_block.tscn` as prototypes.

### Key conventions to preserve

- **Ownership discipline**: `OreBlock` never removes itself from the grid — the caller does `grid.remove_ore(cell)` and then `queue_free()`s the node (see `take_damage` comment). This is called out as the core robustness rule.
- **`MutResult`** (`scripts/game/block/mut_result.gd`) — grid writes return an explicit success/failure (`Code` enum + message); callers must handle the failure branch rather than assume success.
- **Isometric coordinates** — `grid_to_world` / `world_to_grid` in `GameManager` (tile 32×16). `z_index` is derived from `cell.x + cell.y` (+ bias) so sprites overlap correctly; there is no tilemap node, sprites are positioned manually.
- **Layer split** — tiles render in `below_grid_layer`, ores/above-blocks in `above_grid_layer` (both under the `World` node in `main.tscn`), with `ABOVE_LAYER_OFFSET` for visual separation.
- Code comments and `display_name` values (e.g. "金矿", "草地") are written in Chinese; keep them consistent with the surrounding files.

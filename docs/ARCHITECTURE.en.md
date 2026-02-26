# Project Architecture

Russian version: `docs/ARCHITECTURE.md`.

## 1.1 Entry point and startup flow

- **Project main scene**: `res://ui/flow/LoginUI.tscn` from `run/main_scene` in `project.godot`.
- **Main runtime scene**: `res://game/scenes/Main.tscn`.

## 1.2 UI flow

- `core/managers/app_state.gd` stores session/account/character data and controls transitions.
- `core/managers/flow_router.gd` switches scenes between login/character select/game.
- Login and character selection UI are in `ui/flow/*`.

## 1.3 Core subsystems (`core/`)

- **combat/** — combat helpers (`CombatReset`, `RegenHelper`).
- **stats/** — stat formulas and snapshot calculation (`StatConstants`, `StatCalculator`).
- **loot/** — loot generation (`LootGenerator`, `LootProfile`, `LootRights`).
- **save/** — JSON-based persistence (`SaveSystem`).
- **managers/** — app/game flow managers (`AppState`, `FlowRouter`, `GameManager`).
- **game/characters/shared/** — shared character helpers (`TargetMarkerHelper`).
- **world/** — world logic (`DeathPipeline`, spawners, etc.).

## 1.4 Data layout

- Ability code/models: `core/abilities/*`.
- Ability content/manifest: `core/data/abilities/*`.
- JSON databases (items/mobs): `core/data/json/*`.

## 1.5 UI layout

- flow UI: `ui/flow/*`
- game UI root: `ui/game/root/*`
- overlays: `ui/game/overlays/*`
- HUD modules: `ui/game/hud/{core,windows,systems,auras,shared}`

## 1.6 Assets

- reusable textures/icons: `assets/*`
- UI textures should be stored under `assets/ui/*`.

## 1.7 Principles currently used

1. Keep domain code in `core/<domain>`.
2. Keep content resources in `core/data/<domain>`.
3. Keep UI-specific scenes/scripts in `ui/*`.
4. Keep reusable art assets in `assets/*`.

## 1.8 Known constraints

- Some legacy flow pieces still depend on global singletons/autoloads.
- UI remains tightly coupled to some runtime services in parts of HUD.
- See `docs/TECH_DEBT.md` for risk details and remediation priorities.

# UI Structure Rules

This document defines where UI-related code, data and assets should live.

## 1) High-level split

- `ui/` — UI scenes and UI scripts.
- `assets/` — reusable art assets (textures/icons/tiles), including UI textures.
- `core/` — gameplay/framework code and game data loaders.
- `core/data/` — game content resources (non-UI), e.g. abilities and JSON databases.

## 2) UI folders

- `ui/flow/` — login/character-select flow scenes and HUD.
- `ui/game/root/` — game UI entry scene (`GameUI.tscn`) and root glue script.
- `ui/game/overlays/` — global overlays (tooltips/popups shown above HUD).
- `ui/game/hud/core/` — always-on HUD blocks (target/player/xp/buffs/etc.).
- `ui/game/hud/windows/` — window-like HUD panels (inventory/character/menu/etc.).
- `ui/game/hud/systems/` — subsystem HUD modules (mobile/trainer/combat text).
- `ui/game/hud/auras/` — aura-specific HUD and aura flyouts.
- `ui/game/hud/shared/` — shared HUD widgets/components/builders.

## 3) Assets placement

- UI textures/icons must be stored in `assets/ui/...` (or existing `assets/icons/...` for icon packs).
- HUD scenes should reference textures from `assets/...`, not from `ui/...` folders.

## 4) Code/Data placement rule of thumb

- Domain code in `core/<domain>/...`.
- Domain content resources in `core/data/<domain>/...`.
- Example for abilities:
  - code: `core/abilities/...`
  - data: `core/data/abilities/...`

## 5) Naming and co-location

- Scene names: PascalCase (e.g. `CharacterHUD.tscn`).
- Script names: snake_case (e.g. `character_hud.gd`).
- Keep scene + primary script in the same module folder.

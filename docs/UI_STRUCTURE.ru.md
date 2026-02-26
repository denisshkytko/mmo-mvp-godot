# Правила структуры UI

English version: `docs/UI_STRUCTURE.md`.

Этот документ определяет, где должны находиться UI-код, UI-данные и UI-ассеты.

## 1) Разделение верхнего уровня

- `ui/` — UI-сцены и UI-скрипты.
- `assets/` — переиспользуемые ассеты (textures/icons/tiles), включая UI-текстуры.
- `core/` — gameplay/framework-код и загрузчики игровых данных.
- `core/data/` — игровые ресурсы контента (не UI), например abilities и JSON-базы.

## 2) Папки UI

- `ui/flow/` — сцены и HUD экрана логина/выбора персонажа.
- `ui/game/root/` — входная сцена игрового UI (`GameUI.tscn`) и root-скрипт.
- `ui/game/overlays/` — глобальные оверлеи (tooltips/popups поверх HUD).
- `ui/game/hud/core/` — постоянные HUD-блоки (target/player/xp/buffs и т.д.).
- `ui/game/hud/windows/` — оконные HUD-панели (inventory/character/menu и т.д.).
- `ui/game/hud/systems/` — подсистемные HUD-модули (mobile/trainer/combat text).
- `ui/game/hud/auras/` — aura-специфичный HUD и связанные flyout-сцены.
- `ui/game/hud/shared/` — общие HUD-виджеты/компоненты/билдеры.

## 3) Размещение ассетов

- UI-текстуры/иконки должны лежать в `assets/ui/...` (или в `assets/icons/...` для иконок).
- HUD-сцены должны ссылаться на текстуры из `assets/...`, а не из `ui/...`.

## 4) Правило Code/Data

- код домена: `core/<domain>/...`.
- ресурсы контента домена: `core/data/<domain>/...`.
- пример для abilities:
  - code: `core/abilities/...`
  - data: `core/data/abilities/...`

## 5) Именование и colocate

- сцены: PascalCase (например, `CharacterHUD.tscn`).
- скрипты: snake_case (например, `character_hud.gd`).
- сцена и её основной скрипт должны лежать в одном модуле.

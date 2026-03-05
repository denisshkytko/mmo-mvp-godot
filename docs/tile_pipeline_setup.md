# Подготовка тайлсетов и decor/props из `assets/tiles`

Сделана автоматическая сборка каталогов ассетов скриптом:

```bash
python tools/tiles/build_asset_catalog.py
```

Скрипт формирует файлы в `assets/tilesets/generated/`:

- `land_and_road_tilesets.json` — готовые наборы для TileMap (только папки `Land And Road`).
- `decor_props_catalog.json` — все остальные ассеты классифицированы как `decor` или `props`.
- `asset_catalog_summary.json` — короткая сводка по количеству.

## Что уже разложено

### 1) Land And Road (как тайлсеты)
- `Desert/Land And Road` -> базовый размер `64x64`.
- `Forest/Land And Road` -> базовый размер `32x32`.
- `Swamp/Land And Road` -> базовый размер `64x64`.

Для файлов `256x256` в Desert/Swamp указана нарезка на `64x64` (по 16 тайлов с листа).

### 2) Остальное (как decor/props)
Все PNG вне `Land And Road` автоматически попадают в:
- `decor` (папки `Decor`, `Grass`, `Stone`, `Shadow`),
- `props` (остальные группы: здания, интерьер, объекты лагерей и т.д.).

## Специальная проверка `Cities And Settlements`

Добавлены явные группы нарезки для цельных листов:

- `assets/tiles/Cities And Settlements/Cathedral`
- `assets/tiles/Cities And Settlements/Workshop`

Обе группы в `decor_props_catalog.json` отмечены как `special_sheet_slicing` с шагом `16x16`, чтобы их можно было импортировать в Godot как atlas-источники тайлов/пропов.

## Как использовать в проекте (Godot)
1. Открыть `land_and_road_tilesets.json` и создать `TileSet`-ресурсы для каждого биома с указанным `tile_size`.
2. Для `direct_tiles` добавить текстуры как отдельные atlas sources.
3. Для `sheets` добавить нарезку по `slice_size`.
4. Для `decor` и `props` создать отдельные слои (например, `YSort`/`Node2D` с `Sprite2D`/сценами), не смешивая их со strict grid-тайлами.

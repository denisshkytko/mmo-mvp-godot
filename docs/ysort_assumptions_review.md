# Проверка гипотез по Y-сортировке игрока

Дата проверки: 2026-03-29

## Краткий итог

- Основное наблюдение о том, что `_sync_player_sort_pivot()` возвращает `Player.global_position` обратно после выставления pivot — **верно**.
- Однако вывод, что из-за этого Godot в текущей архитектуре точно сортирует по `Player.global_position.y`, — **не полностью подтверждается**.
  - В проекте уже используется отдельный `__player_sort_pivot`, который сам участвует в Y-sort как дочерний узел `__y_sort_runtime`.
  - Плюс есть логика установки `y_sort_origin` от `WorldCollider` как у `Player`, так и у других сущностей.
- Предложенный «Вариант A» (жёстко держать `Player` в ногах и смещать модель) потенциально рабочий, но в текущем коде это **архитектурная замена**, а не точечный фикс.

## Что подтверждено по коду

1. В `game_manager.gd` действительно есть логика:
   - вычислить `anchor_global` через `get_sort_anchor_global()`;
   - поставить `_player_sort_pivot.global_position = anchor_global`;
   - затем вернуть `player.global_position` в `desired_player_global`.

2. В `player.gd`:
   - `get_sort_anchor_global()` возвращает `get_world_collider_center_global()`;
   - `get_world_collider_center_global()` возвращает `world_collision.global_position`.

3. Debug overlay действительно рисует маркер по `WorldCollider` (через `get_world_collider_center_global` / прямой fallback).

4. В проекте есть существующая логика `y_sort_origin`:
   - в `Player` — `_sync_y_sort_origin_from_world_collider()` и `_apply_y_sort_origin()`;
   - в `GameManager` — `_try_sync_node_y_sort_origin_from_world_collider()` и `_apply_node_y_sort_origin()`.

## Что важно уточнить

### 1) «Godot сортирует только по Player.global_position.y»
Это утверждение в текущем проекте не строго доказано, потому что:

- `Player` помещается под `__player_sort_pivot`.
- `__player_sort_pivot` находится в y-sorted runtime-слое и сам имеет позицию якоря сортировки.

То есть сортировка между объектами может определяться именно позицией pivot-ветки (и/или `y_sort_origin`), а не обязательно текущим `Player.global_position`.

### 2) Вариант B уже частично реализован
Идея про `y_sort_origin` (с fallback) у вас уже есть в коде. Поэтому перед архитектурным переходом на Вариант A логично сначала подтвердить факт ошибки на runtime с включённым `SortProbe`/debug-выводом.

## Практический вывод

1. Ваше описание проблемы **частично верное**, но причинно-следственная связь «сброс позиции Player => гарантированно неправильная сортировка» в текущей реализации **не доказана однозначно**.
2. В коде уже присутствуют два механизма выравнивания сортировки по ногам:
   - pivot-якорь;
   - `y_sort_origin` от `WorldCollider`.
3. Рекомендованный путь:
   - сначала подтвердить, какой именно механизм ломается на конкретной сцене (pivot или `y_sort_origin`);
   - только потом решать, нужен ли полный переход на «Player в ногах + visual offset».

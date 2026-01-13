# Архитектура проекта

## 1.1 Точка входа и поток запуска

- **Стартовая сцена проекта**: `res://ui/flow/LoginUI.tscn` указана в `run/main_scene` в `project.godot`.
- **Дальнейший UI-флоу**:
  1. **Login** — сцена `LoginUI.tscn`, логика входа в `ui/flow/login_ui.gd`.
  2. **Выбор персонажа / создание** — сцена `CharacterSelectUI.tscn`, логика в `ui/flow/character_select_ui.gd`, `ui/flow/character_select_hud.gd`, `ui/flow/create_character_hud.gd`.
  3. **Игровой мир** — сцена `res://game/scenes/Main.tscn`.

- **Переключение сцен** происходит через автолоад `FlowRouter` и метод `get_tree().change_scene_to_file()`:
  - `go_login()` → `LoginUI.tscn`.
  - `go_character_select()` → `CharacterSelectUI.tscn`.
  - `go_world()` → `game/scenes/Main.tscn`.
- **Точки вызова переходов**:
  - В логине успешный вход вызывает `FlowRouter.go_character_select()`.
  - В Character Select кнопка Enter вызывает `FlowRouter.go_world()`.
  - Кнопка Logout в Character Select вызывает `FlowRouter.go_login()`.

## 1.2 Autoload-синглтоны

### AppState
- **Путь к скрипту**: `res://core/managers/app_state.gd` (autoload в `project.godot`).
- **Назначение**: хранит состояние авторизации и выбора персонажа, без навигации между сценами.
- **Данные/состояния**:
  - `is_logged_in` — флаг авторизации.
  - `selected_character_id` — id выбранного персонажа.
  - `selected_character_data` — полный словарь данных персонажа.
- **Использование**:
  - UI логина вызывает `login()`.
  - UI выбора персонажа вызывает `get_characters()`, `select_character()`, `create_character()`, `delete_character()`.
  - Менеджер мира (GameManager) читает `selected_character_data` и сохраняет данные через `save_selected_character()`.

### FlowRouter
- **Путь к скрипту**: `res://core/managers/flow_router.gd` (autoload в `project.godot`).
- **Назначение**: слой навигации сцен для основных экранов (login, выбор персонажа, игровой мир).
- **Ответственность**: единая точка переключения сцен через `SceneTree.change_scene_to_file()` без хранения состояния.

### SaveSystem
- **Путь к скрипту**: `res://core/save/save_system.gd` (autoload в `project.godot`).
- **Назначение**: сохранение и загрузка данных персонажей в JSON-файлы в `user://`.
- **Данные/состояния**:
  - каталоги `user://mmo_mvp/` и `user://mmo_mvp/characters/`;
  - файл индекса `index.json` со списком персонажей.
- **Использование**:
  - `AppState` вызывает `list_characters()`, `load_character_full()`, `save_character_full()`, `delete_character()`.

### DataDB
- **Путь к скрипту**: `res://core/data/data_db.gd` (autoload в `project.godot`).
- **Назначение**: загрузка справочных данных (items/mobs) из JSON при старте, предоставление helper-методов для чтения.
- **Данные/состояния**:
  - `items` и `mobs` — словари из JSON `items_db_1500_v6.json` и `mobs.json`.
- **Использование**:
  - `LootGenerator` использует базу предметов через `DataDB` (см. `core/loot/loot_generator.gd`).

### LootSystem
- **Путь к скрипту**: `res://core/data/loot_system.gd` (autoload в `project.godot`).
- **Назначение**: единая точка генерации лута по `LootProfile`.
- **Данные/состояния**:
  - состояния не хранит; проксирует вызовы `LootGenerator.generate()`.
- **Использование**:
  - `DeathPipeline` вызывает `LootSystem.generate_loot_from_profile()` при создании трупа.

## 1.3 Основные подсистемы (core/)

- **combat/** — вспомогательные утилиты боя: `CombatReset` для сброса боя и `RegenHelper` для регена HP по проценту от max HP.
- **stats/** — вычисление характеристик: `StatConstants` содержит константы формул, `StatCalculator` строит снапшоты статов игрока/мобов и breakdown для UI.
- **loot/** — генерация лута: `LootGenerator`, `LootProfile`, `LootRights` и профили в `core/loot/profiles/`.
- **save/** — подсистема сохранения: `SaveSystem` для чтения/записи данных персонажей в JSON.
- **managers/** — менеджеры состояния: `AppState` управляет состоянием аккаунта/персонажа, `FlowRouter` отвечает за навигацию сцен, `GameManager` загружает персонажа в мир, управляет сменой зон и сохранением.
- **ui/** — UI-хелперы: `TargetMarkerHelper` управляет видимостью маркера цели.
- **world/** — логика мира: `DeathPipeline` — единый пайплайн смерти (труп, лут, XP, очистка цели).

extends Node2D
class_name Spawner

@export var mob_scene: PackedScene
@export var respawn_seconds: float = 6.0

@export var level_min: int = 1
@export var level_max: int = 1

# Не менять задание эти параметров через индексы
@export_enum("Guard", "Patrol") var behavior: int = 0

@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5

var _current_mob: Mob = null
var _current_corpse: Corpse = null

var _respawn_timer: float = 0.0
var _waiting_for_corpse: bool = false
var _waiting_respawn: bool = false


func _ready() -> void:
	# Важно: call_deferred, чтобы не ловить "Parent node is busy setting up children"
	_spawn_now_deferred()


func _process(delta: float) -> void:
	# 1) Если живой моб есть — ничего не делаем
	if _current_mob != null and is_instance_valid(_current_mob):
		return

	# 2) Если ждём исчезновения трупа — тоже ничего не делаем
	if _waiting_for_corpse:
		return

	# 3) Если трупа нет/уже исчез — запускаем/тикаем таймер респавна
	if not _waiting_respawn:
		_waiting_respawn = true
		_respawn_timer = respawn_seconds

	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_waiting_respawn = false
		_spawn_now_deferred()


func _spawn_now_deferred() -> void:
	call_deferred("_spawn_now")


func _spawn_now() -> void:
	if mob_scene == null:
		return

	var mob_node := mob_scene.instantiate()
	var mob := mob_node as Mob
	if mob == null:
		push_error("Spawner: mob_scene root must have Mob.gd (class_name Mob).")
		return

	_current_mob = mob
	add_child(mob)

	# Уровень моба (если у Mob есть mob_level)
	var lvl: int = 1
	if level_min <= level_max:
		lvl = randi_range(level_min, level_max)
	else:
		lvl = level_min

	mob.mob_level = lvl

	# Подписываемся на смерть (получим corpse)
	if not mob.died.is_connected(_on_mob_died):
		mob.died.connect(_on_mob_died)

	# Применяем настройки спавна/ИИ
	mob.apply_spawn_settings(
		global_position,
		int(behavior),
		aggro_radius,
		leash_distance,
		patrol_radius,
		patrol_pause_seconds
	)


func _on_mob_died(corpse: Corpse) -> void:
	# Моб уже умрёт и queue_free() внутри себя, но нам важно:
	# - ждать исчезновения corpse
	_current_mob = null
	_waiting_respawn = false
	_respawn_timer = 0.0

	_current_corpse = corpse

	# Если труп не создан (corpse_scene null) — начинаем таймер респавна сразу
	if _current_corpse == null or not is_instance_valid(_current_corpse):
		_waiting_for_corpse = false
		_waiting_respawn = true
		_respawn_timer = respawn_seconds
		return

	_waiting_for_corpse = true

	# Ждём сигнал despawned от Corpse
	if not _current_corpse.despawned.is_connected(_on_corpse_despawned):
		_current_corpse.despawned.connect(_on_corpse_despawned)


func _on_corpse_despawned() -> void:
	_waiting_for_corpse = false
	_current_corpse = null

	_waiting_respawn = true
	_respawn_timer = respawn_seconds

extends Node2D
class_name Spawner

@export var mob_scene: PackedScene
@export var respawn_seconds: float = 6.0

@export var mob_id: String = "slime"
@export var loot_table_id: String = "lt_slime_low"

@export var level_min: int = 1
@export var level_max: int = 1

@export_enum("Melee", "Ranged") var attack_mode: int = 0

# Не менять задание эти параметров через индексы
@export_enum("Guard", "Patrol") var behavior: int = 0

@export var speed: float = 120.0
@export var aggro_radius: float = 260.0
@export var leash_distance: float = 420.0
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5

var _waiting_respawn: bool = false
var _respawn_timer: float = 0.0

var _current_mob: NormalAggresiveMob = null
var _current_corpse: Corpse = null
var _waiting_for_corpse: bool = false

func _ready() -> void:
	call_deferred("_spawn_now")

func _process(delta: float) -> void:
	if _waiting_for_corpse:
		return

	if _waiting_respawn:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_waiting_respawn = false
			_spawn_now()

func _spawn_now() -> void:
	if mob_scene == null:
		push_error("Spawner: mob_scene is empty.")
		return

	var inst := mob_scene.instantiate()
	var mob := inst as NormalAggresiveMob
	if mob == null:
		push_error("Spawner: mob_scene root must have NormalAggresiveMob (class_name NormalAggresiveMob).")
		return

	get_parent().add_child.call_deferred(mob)
	_current_mob = mob

	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)

	# ВАЖНО: инициализируем ПОСЛЕ добавления в дерево
	mob.call_deferred(
		"apply_spawn_init",
		global_position,
		behavior,
		aggro_radius,
		leash_distance,
		patrol_radius,
		patrol_pause_seconds,
		speed,
		lvl,
		attack_mode,
		mob_id,
		loot_table_id
	)

	# Death
	if not mob.died.is_connected(_on_mob_died):
		mob.died.connect(_on_mob_died)


func _on_mob_died(corpse: Corpse) -> void:
	_current_mob = null
	_current_corpse = corpse

	# Если трупа нет — просто respawn timer
	if _current_corpse == null:
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

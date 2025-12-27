extends Node2D
class_name NamSpawnerGroup

# SpawnerGroup теперь всегда спавнит только эту сцену
const MOB_SCENE: PackedScene = preload("res://game/characters/mobs/NormalAggressiveMob.tscn")

enum Behavior { GUARD, PATROL }
enum AttackMode { MELEE, RANGED }

# -----------------------------
# Общие параметры группы
# -----------------------------

@export_group("Mob Setup")
@export var loot_table_id: String = "lt_slime_low"
@export var level_min: int = 1
@export var level_max: int = 1
@export_enum("Melee", "Ranged") var attack_mode: int = AttackMode.MELEE

@export_group("AI Common")
@export var speed: float = 120.0

# Радиус преследования (leash)
@export var leash_distance: float = 420.0

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD

# Используются только если Patrol
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5

@export_group("Respawn")
@export var respawn_seconds: float = 10.0

# -----------------------------
# На будущее
# -----------------------------
@export_group("Future (not used yet)")
@export var visual_set_id: String = ""
@export var ability_kit_id: String = ""

# -----------------------------
# Runtime
# -----------------------------
var _points: Array[NamSpawner] = []
var _mob_by_point: Array = []
var _corpse_by_point: Array = []
var _waiting_corpse: Array[bool] = []
var _waiting_respawn: Array[bool] = []
var _respawn_timer: Array[float] = []

func _ready() -> void:
	_collect_points()
	call_deferred("_spawn_all")

func _process(delta: float) -> void:
	for i in range(_points.size()):
		if _waiting_corpse[i]:
			continue

		if _waiting_respawn[i]:
			_respawn_timer[i] -= delta
			if _respawn_timer[i] <= 0.0:
				_waiting_respawn[i] = false
				_spawn_at(i)

func _collect_points() -> void:
	_points.clear()

	for c in get_children():
		if c is NamSpawner:
			_points.append(c)

	_mob_by_point.resize(_points.size())
	_corpse_by_point.resize(_points.size())
	_waiting_corpse.resize(_points.size())
	_waiting_respawn.resize(_points.size())
	_respawn_timer.resize(_points.size())

	for i in range(_points.size()):
		_mob_by_point[i] = null
		_corpse_by_point[i] = null
		_waiting_corpse[i] = false
		_waiting_respawn[i] = false
		_respawn_timer[i] = 0.0

func _spawn_all() -> void:
	for i in range(_points.size()):
		_spawn_at(i)

func _spawn_at(index: int) -> void:
	if index < 0 or index >= _points.size():
		return

	var p: NamSpawner = _points[index]
	if p == null:
		return

	var inst := MOB_SCENE.instantiate()
	var mob := inst as NormalAggresiveMob
	if mob == null:
		push_error("NamSpawnerGroup: MOB_SCENE root must be NormalAggresiveMob.")
		return

	get_parent().add_child.call_deferred(mob)
	_mob_by_point[index] = mob

	var lvl: int = level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)

	mob.call_deferred(
		"apply_spawn_init",
		p.global_position,
		behavior,
		-1.0, # aggro_radius не задаём → моб использует своё значение
		leash_distance,
		patrol_radius,
		patrol_pause_seconds,
		speed,
		lvl,
		attack_mode,
		"",              # mob_id больше не используется
		loot_table_id
	)

	var cb := Callable(self, "_on_mob_died").bind(index)
	if not mob.died.is_connected(cb):
		mob.died.connect(cb)

func _on_mob_died(corpse: Corpse, index: int) -> void:
	if index < 0 or index >= _points.size():
		return

	_mob_by_point[index] = null
	_corpse_by_point[index] = corpse

	if corpse == null:
		_waiting_respawn[index] = true
		_respawn_timer[index] = respawn_seconds
		return

	_waiting_corpse[index] = true

	var cb := Callable(self, "_on_corpse_despawned").bind(index)
	if corpse.has_signal("despawned"):
		if not corpse.despawned.is_connected(cb):
			corpse.despawned.connect(cb)
	else:
		_waiting_corpse[index] = false
		_waiting_respawn[index] = true
		_respawn_timer[index] = respawn_seconds

func _on_corpse_despawned(index: int) -> void:
	if index < 0 or index >= _points.size():
		return

	_waiting_corpse[index] = false
	_corpse_by_point[index] = null

	_waiting_respawn[index] = true
	_respawn_timer[index] = respawn_seconds

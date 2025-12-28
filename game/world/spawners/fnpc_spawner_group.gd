extends Node2D
class_name FnpcSpawnerGroup

const NPC_SCENE: PackedScene = preload("res://game/characters/npcs/FactionNPC.tscn")
const DEFAULT_PROJECTILE: PackedScene = preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")

enum Behavior { GUARD, PATROL }
enum FighterType { CIVILIAN, FIGHTER, MAGE }
enum InteractionType { NONE, MERCHANT, QUEST, TRAINER }

@export_group("Faction NPC Setup")
@export_enum("blue", "red", "yellow", "green") var faction_id: String = "blue"
@export_enum("Civilian", "Fighter", "Mage") var fighter_type: int = FighterType.FIGHTER
@export_enum("None", "Merchant", "Quest", "Trainer") var interaction_type: int = InteractionType.NONE

@export var loot_table_id: String = "lt_guard_low"
@export var level_min: int = 1
@export var level_max: int = 1

@export_group("Behavior After Spawn")
@export_enum("Guard", "Patrol") var behavior: int = Behavior.GUARD
@export var aggro_radius: float = 220.0
@export var leash_distance: float = 420.0
@export var patrol_radius: float = 140.0
@export var patrol_pause_seconds: float = 1.5
@export var speed: float = 115.0

@export_group("Respawn")
@export var respawn_seconds: float = 10.0

var _points: Array[FnpcSpawner] = []
var _npc_by_point: Array = []
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
		if c is FnpcSpawner:
			_points.append(c)

	_npc_by_point.resize(_points.size())
	_corpse_by_point.resize(_points.size())
	_waiting_corpse.resize(_points.size())
	_waiting_respawn.resize(_points.size())
	_respawn_timer.resize(_points.size())

	for i in range(_points.size()):
		_npc_by_point[i] = null
		_corpse_by_point[i] = null
		_waiting_corpse[i] = false
		_waiting_respawn[i] = false
		_respawn_timer[i] = 0.0

func _spawn_all() -> void:
	for i in range(_points.size()):
		_spawn_at(i)

func _spawn_at(index: int) -> void:
	var p := _points[index]
	var inst := NPC_SCENE.instantiate()
	var npc := inst as FactionNPC
	if npc == null:
		push_error("FnpcSpawnerGroup: NPC_SCENE root must be FactionNPC.")
		return

	get_parent().add_child.call_deferred(npc)
	_npc_by_point[index] = npc

	var lvl := level_min
	if level_max > level_min:
		lvl = randi_range(level_min, level_max)

	npc.call_deferred(
		"apply_spawn_init",
		p.global_position,
		faction_id,
		fighter_type,
		interaction_type,
		behavior,
		aggro_radius,
		leash_distance,
		patrol_radius,
		patrol_pause_seconds,
		speed,
		lvl,
		loot_table_id,
		DEFAULT_PROJECTILE
	)

	var cb := Callable(self, "_on_npc_died").bind(index)
	if not npc.died.is_connected(cb):
		npc.died.connect(cb)

func _on_npc_died(corpse: Corpse, index: int) -> void:
	_npc_by_point[index] = null
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
	_waiting_corpse[index] = false
	_corpse_by_point[index] = null
	_waiting_respawn[index] = true
	_respawn_timer[index] = respawn_seconds

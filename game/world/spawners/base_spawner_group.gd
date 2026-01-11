extends Node2D
class_name BaseSpawnerGroup

## SpawnPoint is a global class (class_name). Avoid shadowing.

@export_group("Respawn")
@export var respawn_seconds: float = 10.0

var _points: Array[SpawnPoint] = []
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
		if c is SpawnPoint:
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
	var p: SpawnPoint = _points[index]
	if p == null:
		return

	var scene := _get_spawn_scene()
	if scene == null:
		push_error("BaseSpawnerGroup: _get_spawn_scene() returned null")
		return

	var inst := scene.instantiate()
	var mob := inst as Node
	if mob == null:
		push_error("BaseSpawnerGroup: spawn scene root is not Node")
		return

	get_parent().add_child.call_deferred(mob)
	_mob_by_point[index] = mob

	var lvl: int = _compute_level()
	_call_apply_spawn_init(mob, p, lvl)

	# died(corpse) is used by spawner groups to detect respawn timing
	var cb := Callable(self, "_on_mob_died").bind(index)
	if mob.has_signal("died") and not mob.died.is_connected(cb):
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


# ---------------------
# Virtuals for children
# ---------------------
func _get_spawn_scene() -> PackedScene:
	return null


func _call_apply_spawn_init(_mob: Node, _point: SpawnPoint, _level: int) -> void:
	pass


func _compute_level() -> int:
	return 1

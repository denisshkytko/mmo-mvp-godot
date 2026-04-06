extends Node

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const CACHE_REFRESH_SEC: float = 0.25
const CELL_SIZE: float = 64.0

var _cache_timer: float = 0.0
var _spatial_hash: Dictionary = {}


func _physics_process(delta: float) -> void:
	var t_total := Time.get_ticks_usec()
	_cache_timer -= delta
	if _cache_timer > 0.0:
		FRAME_PROFILER.add_usec("mob_cache.physics.total", Time.get_ticks_usec() - t_total)
		return
	_cache_timer = CACHE_REFRESH_SEC
	_rebuild_cache()
	FRAME_PROFILER.add_usec("mob_cache.physics.total", Time.get_ticks_usec() - t_total)


func _rebuild_cache() -> void:
	_spatial_hash.clear()
	var tree := get_tree()
	if tree == null:
		return
	for unit in tree.get_nodes_in_group("faction_units"):
		if unit == null or not is_instance_valid(unit) or not (unit is Node2D):
			continue
		_add_to_spatial_hash(unit as Node2D)


func _add_to_spatial_hash(mob: Node2D) -> void:
	var pos := mob.global_position
	var cell_x := int(floor(pos.x / CELL_SIZE))
	var cell_y := int(floor(pos.y / CELL_SIZE))
	var key := "%d,%d" % [cell_x, cell_y]
	if not _spatial_hash.has(key):
		_spatial_hash[key] = []
	var bucket: Array = _spatial_hash[key]
	bucket.append(mob)
	_spatial_hash[key] = bucket


func get_nearby_mobs(center: Node2D, radius: float, group_name: String = "mobs") -> Array[Node2D]:
	return get_nearby_faction_units(center, radius, group_name)

func get_nearby_faction_units(center: Node2D, radius: float, group_name: String = "faction_units") -> Array[Node2D]:
	var result: Array[Node2D] = []
	if center == null or not is_instance_valid(center):
		return result
	var pos := center.global_position
	var min_cell_x := int(floor((pos.x - radius) / CELL_SIZE))
	var max_cell_x := int(floor((pos.x + radius) / CELL_SIZE))
	var min_cell_y := int(floor((pos.y - radius) / CELL_SIZE))
	var max_cell_y := int(floor((pos.y + radius) / CELL_SIZE))
	for x in range(min_cell_x, max_cell_x + 1):
		for y in range(min_cell_y, max_cell_y + 1):
			var key := "%d,%d" % [x, y]
			if not _spatial_hash.has(key):
				continue
			var bucket: Array = _spatial_hash[key]
			for mob_v in bucket:
				if not (mob_v is Node2D):
					continue
				var mob := mob_v as Node2D
				if mob == center or not is_instance_valid(mob):
					continue
				if group_name != "" and not mob.is_in_group(group_name):
					continue
				if pos.distance_squared_to(mob.global_position) <= radius * radius:
					result.append(mob)
	return result

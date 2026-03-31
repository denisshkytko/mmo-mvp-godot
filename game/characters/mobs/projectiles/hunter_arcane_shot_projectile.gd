extends Node2D
class_name HunterArcaneShotProjectile

signal impacted(target: Node2D)

const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")

@export var speed: float = 520.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 4.0

var _target: Node2D = null
var _source: Node2D = null
var _life: float = 0.0
var _done: bool = false

func setup(target: Node2D, source: Node2D = null) -> void:
	_target = target
	_source = source
	_sync_sort_layer()

func _physics_process(delta: float) -> void:
	var t_total := Time.get_ticks_usec()
	if _done:
		FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.total", Time.get_ticks_usec() - t_total)
		return
	var t_sync := Time.get_ticks_usec()
	_sync_sort_layer()
	FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.sync_layer", Time.get_ticks_usec() - t_sync)

	_life += delta
	if _life >= max_lifetime:
		queue_free()
		FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.total", Time.get_ticks_usec() - t_total)
		return

	if _target == null or not is_instance_valid(_target):
		queue_free()
		FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.total", Time.get_ticks_usec() - t_total)
		return

	var target_pos: Vector2 = _resolve_target_anchor()
	var to_target: Vector2 = target_pos - global_position
	var dist: float = to_target.length()
	if dist <= hit_distance:
		_done = true
		impacted.emit(_target)
		queue_free()
		FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.total", Time.get_ticks_usec() - t_total)
		return

	var t_move := Time.get_ticks_usec()
	var dir: Vector2 = to_target / dist
	rotation = dir.angle()
	global_position += dir * speed * delta
	FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.move", Time.get_ticks_usec() - t_move)
	FRAME_PROFILER.add_usec("projectile.arcane_shot.physics.total", Time.get_ticks_usec() - t_total)

func _resolve_target_anchor() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return global_position
	if _target.has_method("get_body_hitbox_center_global"):
		var v: Variant = _target.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return _target.global_position


func _sync_sort_layer() -> void:
	var layer_source: Node2D = _source if _source != null and is_instance_valid(_source) else _target
	if layer_source == null or not is_instance_valid(layer_source):
		return
	var base_z: int = 0
	var visual_v: Variant = layer_source.get("visual_root")
	if visual_v is CanvasItem and is_instance_valid(visual_v):
		base_z = int((visual_v as CanvasItem).z_index)
	elif layer_source is CanvasItem:
		base_z = int((layer_source as CanvasItem).z_index)
	z_as_relative = false
	z_index = base_z
	if has_method("set_y_sort_origin"):
		call("set_y_sort_origin", 0)
	else:
		set("y_sort_origin", 0)

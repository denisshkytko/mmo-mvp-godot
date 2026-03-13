extends Node2D
class_name MageFireballProjectile

signal impacted(target: Node2D)
signal impacted_with_result(target: Node2D, dealt_damage: int, dmg_type: String)

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var speed: float = 420.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 6.0
@export var default_visual_scale: Vector2 = Vector2(0.6, 0.6)
@export var damage_school: String = "magic"
@export var visual_rotation_offset_deg: float = 180.0
@export var use_curved_path: bool = false
@export var path_arc_offset_px: float = 0.0
@export var path_start_global: Vector2 = Vector2.ZERO

var _target: Node2D = null
var _damage: int = 0
var _source: Node2D = null
var _hit: bool = false
var _life: float = 0.0
var _path_initial_target_global: Vector2 = Vector2.ZERO
var _path_total_dist: float = 0.0

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

func setup(target: Node2D, damage: int, source: Node2D = null) -> void:
	_target = target
	_damage = damage
	_source = source
	if _animated_sprite != null:
		_animated_sprite.scale = default_visual_scale
		if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(StringName("default")):
			_animated_sprite.play("default")
	if path_start_global == Vector2.ZERO:
		path_start_global = global_position
	refresh_path_from_current_target()

func _physics_process(delta: float) -> void:
	if _hit:
		return

	_life += delta
	if _life >= max_lifetime:
		queue_free()
		return

	if _target == null or not is_instance_valid(_target):
		queue_free()
		return

	if _source != null and not is_instance_valid(_source):
		_source = null

	if "is_dead" in _target and bool(_target.get("is_dead")):
		queue_free()
		return

	var target_anchor: Vector2 = _resolve_target_anchor()
	var desired_anchor: Vector2 = target_anchor
	if use_curved_path and absf(path_arc_offset_px) > 0.001:
		desired_anchor = _resolve_curved_anchor(target_anchor)

	var to_desired: Vector2 = desired_anchor - global_position
	var dist_to_desired: float = to_desired.length()
	if dist_to_desired <= hit_distance:
		_apply_hit()
		return

	var dir: Vector2 = to_desired / maxf(0.001, dist_to_desired)
	rotation = dir.angle() + deg_to_rad(visual_rotation_offset_deg)
	global_position += dir * speed * delta


func refresh_path_from_current_target() -> void:
	_path_initial_target_global = _resolve_target_anchor()
	if path_start_global == Vector2.ZERO:
		path_start_global = global_position
	_path_total_dist = maxf(1.0, path_start_global.distance_to(_path_initial_target_global))

func _resolve_curved_anchor(final_target_anchor: Vector2) -> Vector2:
	var total_dist: float = _path_total_dist
	if total_dist <= 0.001:
		total_dist = maxf(1.0, path_start_global.distance_to(final_target_anchor))
	var progressed: float = clampf(path_start_global.distance_to(global_position) / total_dist, 0.0, 1.0)
	var blend_arc: float = sin(progressed * PI)
	var path_vec: Vector2 = final_target_anchor - path_start_global
	var base_dir: Vector2 = path_vec.normalized()
	if base_dir.length_squared() <= 0.0001:
		base_dir = Vector2.RIGHT
	var side: Vector2 = Vector2(-base_dir.y, base_dir.x)
	var center_point: Vector2 = path_start_global + path_vec * progressed
	return center_point + side * path_arc_offset_px * blend_arc

func _apply_hit() -> void:
	if _hit:
		return
	_hit = true
	var dealt: int = 0
	if _target != null and is_instance_valid(_target):
		if "is_dead" in _target and bool(_target.get("is_dead")):
			queue_free()
			return
		var source_node: Node2D = _source if _source != null and is_instance_valid(_source) else null
		dealt = DAMAGE_HELPER.apply_damage_typed_with_result(source_node, _target, _damage, damage_school)

	impacted.emit(_target)
	impacted_with_result.emit(_target, dealt, damage_school)
	queue_free()

func _resolve_target_anchor() -> Vector2:
	if _target == null or not is_instance_valid(_target):
		return global_position
	if _target.has_method("get_body_hitbox_center_global"):
		var hitbox_center: Variant = _target.call("get_body_hitbox_center_global")
		if hitbox_center is Vector2:
			return hitbox_center as Vector2
	var wc: Variant = _target.get("world_collision")
	if wc is CollisionShape2D and is_instance_valid(wc):
		return (wc as CollisionShape2D).global_position
	var world_collider := _target.get_node_or_null("WorldCollider") as CollisionShape2D
	if world_collider != null:
		return world_collider.global_position
	return _target.global_position

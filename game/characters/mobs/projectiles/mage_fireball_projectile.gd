extends Node2D
class_name MageFireballProjectile

signal impacted(target: Node2D)
signal impacted_with_result(target: Node2D, dealt_damage: int, dmg_type: String)

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var speed: float = 420.0
@export var hit_distance: float = 10.0
@export var max_lifetime: float = 6.0
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

var _curve_enabled: bool = false
var _curve_t: float = 0.0
var _curve_total_dist: float = 1.0
var _curve_p0: Vector2 = Vector2.ZERO
var _curve_p1: Vector2 = Vector2.ZERO
var _curve_p2: Vector2 = Vector2.ZERO

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

func setup(target: Node2D, damage: int, source: Node2D = null) -> void:
	_target = target
	_damage = damage
	_source = source
	if _animated_sprite != null:
		if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(StringName("default")):
			_animated_sprite.play("default")
	if path_start_global == Vector2.ZERO:
		path_start_global = global_position
	refresh_path_from_current_target()
	_update_initial_visual_rotation()

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

	if _is_target_dead(_target):
		queue_free()
		return

	if _curve_enabled:
		_curve_t = clampf(_curve_t + (speed * delta) / maxf(1.0, _curve_total_dist), 0.0, 1.0)
		var pos: Vector2 = _bezier_point(_curve_t)
		var tangent: Vector2 = _bezier_tangent(_curve_t)
		if tangent.length_squared() > 0.0001:
			rotation = tangent.angle() + deg_to_rad(visual_rotation_offset_deg)
		global_position = pos
		if _curve_t >= 1.0:
			_apply_hit()
		return

	var target_anchor: Vector2 = _resolve_target_anchor()
	var to_target: Vector2 = target_anchor - global_position
	var dist: float = to_target.length()
	if dist <= hit_distance:
		_apply_hit()
		return

	var dir: Vector2 = to_target / maxf(0.001, dist)
	rotation = dir.angle() + deg_to_rad(visual_rotation_offset_deg)
	global_position += dir * speed * delta

func refresh_path_from_current_target() -> void:
	var target_anchor: Vector2 = _resolve_target_anchor()
	if path_start_global == Vector2.ZERO:
		path_start_global = global_position

	_curve_enabled = use_curved_path and absf(path_arc_offset_px) > 0.001
	if not _curve_enabled:
		return

	_curve_t = 0.0
	_curve_p0 = path_start_global
	_curve_p2 = target_anchor
	var center: Vector2 = (_curve_p0 + _curve_p2) * 0.5
	var axis: Vector2 = (_curve_p2 - _curve_p0).normalized()
	if axis.length_squared() <= 0.0001:
		axis = Vector2.RIGHT
	var normal: Vector2 = Vector2(-axis.y, axis.x)
	_curve_p1 = center + normal * path_arc_offset_px
	# Approximate bezier length for normalized travel speed.
	_curve_total_dist = maxf(1.0, _curve_p0.distance_to(_curve_p1) + _curve_p1.distance_to(_curve_p2))

func _update_initial_visual_rotation() -> void:
	var anchor: Vector2 = _resolve_target_anchor()
	if _curve_enabled:
		var tangent: Vector2 = _bezier_tangent(0.01)
		if tangent.length_squared() > 0.0001:
			rotation = tangent.angle() + deg_to_rad(visual_rotation_offset_deg)
			return
	var to_target: Vector2 = anchor - global_position
	if to_target.length_squared() > 0.0001:
		rotation = to_target.angle() + deg_to_rad(visual_rotation_offset_deg)

func _bezier_point(t: float) -> Vector2:
	var u: float = 1.0 - t
	return (u * u) * _curve_p0 + (2.0 * u * t) * _curve_p1 + (t * t) * _curve_p2

func _bezier_tangent(t: float) -> Vector2:
	var u: float = 1.0 - t
	return 2.0 * u * (_curve_p1 - _curve_p0) + 2.0 * t * (_curve_p2 - _curve_p1)

func _apply_hit() -> void:
	if _hit:
		return
	_hit = true
	var dealt: int = 0
	if _target != null and is_instance_valid(_target):
		if _is_target_dead(_target):
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


func _is_target_dead(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if "is_dead" in target and bool(target.get("is_dead")):
		return true
	if "c_stats" in target:
		var stats_v: Variant = target.get("c_stats")
		if stats_v != null and is_instance_valid(stats_v) and "is_dead" in stats_v and bool(stats_v.get("is_dead")):
			return true
	return false

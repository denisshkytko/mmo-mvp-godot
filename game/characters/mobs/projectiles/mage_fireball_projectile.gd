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

var _target: Node2D = null
var _damage: int = 0
var _source: Node2D = null
var _hit: bool = false
var _life: float = 0.0

@onready var _animated_sprite: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

func setup(target: Node2D, damage: int, source: Node2D = null) -> void:
	_target = target
	_damage = damage
	_source = source
	if _animated_sprite != null:
		_animated_sprite.scale = default_visual_scale
		if _animated_sprite.sprite_frames != null and _animated_sprite.sprite_frames.has_animation(StringName("default")):
			_animated_sprite.play("default")

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
	var to_target: Vector2 = target_anchor - global_position
	var dist: float = to_target.length()
	if dist <= hit_distance:
		_apply_hit()
		return

	var dir: Vector2 = to_target / maxf(0.001, dist)
	rotation = dir.angle() + deg_to_rad(visual_rotation_offset_deg)
	global_position += dir * speed * delta

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

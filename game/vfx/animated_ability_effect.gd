extends Node2D
class_name AnimatedAbilityEffect

@export var autoplay: bool = true
@export var free_on_finish: bool = true
@export var animation_name: StringName = &"default"
@export var follow_target: Node2D = null
@export var follow_world_collider_center: bool = false
@export var follow_offset: Vector2 = Vector2.ZERO
@export var free_on_target_death: bool = true

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

func _ready() -> void:
	if _anim == null:
		return
	if not _anim.animation_finished.is_connected(_on_animation_finished):
		_anim.animation_finished.connect(_on_animation_finished)
	if autoplay:
		_anim.play(animation_name)
	_update_follow_position()

func _process(_delta: float) -> void:
	_update_follow_position()

func play_once(name: StringName = &"default") -> void:
	animation_name = name
	if _anim == null:
		return
	_anim.play(animation_name)

func _on_animation_finished() -> void:
	if free_on_finish:
		queue_free()

func _update_follow_position() -> void:
	if follow_target == null:
		return
	if not is_instance_valid(follow_target):
		if free_on_target_death:
			queue_free()
		return
	if free_on_target_death and "is_dead" in follow_target and bool(follow_target.get("is_dead")):
		queue_free()
		return
	var anchor: Vector2 = _resolve_target_anchor(follow_target)
	global_position = anchor + follow_offset

func _resolve_target_anchor(target: Node2D) -> Vector2:
	if target == null or not is_instance_valid(target):
		return global_position
	if follow_world_collider_center:
		var wc: Variant = target.get("world_collision")
		if wc is CollisionShape2D and is_instance_valid(wc):
			return (wc as CollisionShape2D).global_position
		var node_wc := target.get_node_or_null("WorldCollider") as CollisionShape2D
		if node_wc != null:
			return node_wc.global_position
	if target.has_method("get_body_hitbox_center_global"):
		var center_v: Variant = target.call("get_body_hitbox_center_global")
		if center_v is Vector2:
			return center_v as Vector2
	return target.global_position

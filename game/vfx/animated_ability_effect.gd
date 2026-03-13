extends Node2D
class_name AnimatedAbilityEffect

signal carrier_layer_changed(new_z_index: int)

@export var autoplay: bool = true
@export var free_on_finish: bool = true
@export var animation_name: StringName = &"default"
@export var follow_target: Node2D = null
@export var follow_world_collider_center: bool = false
@export var follow_offset: Vector2 = Vector2.ZERO
@export var free_on_target_death: bool = true
@export var keep_layer_offset_from_target: bool = true
@export var layer_offset_from_target: int = 1

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

var _connected_follow_target: Variant = null

func _ready() -> void:
	if _anim == null:
		return
	if not _anim.animation_finished.is_connected(_on_animation_finished):
		_anim.animation_finished.connect(_on_animation_finished)
	if autoplay:
		_anim.play(animation_name)
	_sync_follow_target_connections()
	_update_follow_position()

func _process(_delta: float) -> void:
	_sync_follow_target_connections()
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
	if free_on_target_death and _is_target_dead(follow_target):
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

func _exit_tree() -> void:
	_disconnect_follow_target_signals(_connected_follow_target)
	_connected_follow_target = null

func _sync_follow_target_connections() -> void:
	if follow_target == _connected_follow_target:
		return
	_disconnect_follow_target_signals(_connected_follow_target)
	_connected_follow_target = follow_target
	_connect_follow_target_signals(_connected_follow_target)
	if _connected_follow_target != null:
		_apply_layer_from_target(_connected_follow_target)

func _connect_follow_target_signals(target: Variant) -> void:
	if not (target is Node2D):
		return
	var target_node: Node2D = target as Node2D
	if target_node == null or not is_instance_valid(target_node):
		return
	if target_node.has_signal("visual_layer_changed"):
		var cb_layer := Callable(self, "_on_follow_target_visual_layer_changed")
		if not target_node.is_connected("visual_layer_changed", cb_layer):
			target_node.connect("visual_layer_changed", cb_layer)
	if target_node.has_signal("carrier_effects_stop"):
		var cb_stop := Callable(self, "_on_follow_target_effects_stop")
		if not target_node.is_connected("carrier_effects_stop", cb_stop):
			target_node.connect("carrier_effects_stop", cb_stop)

func _disconnect_follow_target_signals(target: Variant) -> void:
	if not (target is Node2D):
		return
	var target_node: Node2D = target as Node2D
	if target_node == null or not is_instance_valid(target_node):
		return
	if target_node.has_signal("visual_layer_changed"):
		var cb_layer := Callable(self, "_on_follow_target_visual_layer_changed")
		if target_node.is_connected("visual_layer_changed", cb_layer):
			target_node.disconnect("visual_layer_changed", cb_layer)
	if target_node.has_signal("carrier_effects_stop"):
		var cb_stop := Callable(self, "_on_follow_target_effects_stop")
		if target_node.is_connected("carrier_effects_stop", cb_stop):
			target_node.disconnect("carrier_effects_stop", cb_stop)

func _on_follow_target_visual_layer_changed(new_z_index: int) -> void:
	_apply_layer_from_z_index(new_z_index)

func _apply_layer_from_target(target: Variant) -> void:
	var resolved_z: int = _resolve_follow_target_base_z(target)
	_apply_layer_from_z_index(resolved_z)


func _resolve_follow_target_base_z(target: Variant) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if target is Node:
		var target_node: Node = target as Node
		if target_node != null:
			var visual_v: Variant = target_node.get("visual_root")
			if visual_v is CanvasItem and is_instance_valid(visual_v):
				return int((visual_v as CanvasItem).z_index)
			var direct_visual := target_node.get_node_or_null("Visual")
			if direct_visual is CanvasItem and is_instance_valid(direct_visual):
				return int((direct_visual as CanvasItem).z_index)
	if target is CanvasItem:
		var target_item: CanvasItem = target as CanvasItem
		if target_item != null and is_instance_valid(target_item):
			return int(target_item.z_index)
	return 0

func _apply_layer_from_z_index(base_z_index: int) -> void:
	if not keep_layer_offset_from_target:
		return
	z_as_relative = false
	z_index = base_z_index + layer_offset_from_target
	emit_signal("carrier_layer_changed", z_index)

func _on_follow_target_effects_stop() -> void:
	if free_on_target_death:
		queue_free()


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

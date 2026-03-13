extends RefCounted
class_name VfxAnchorHelper

static func resolve_validated_world_anchor(target: Node2D, default_pos: Vector2 = Vector2.ZERO) -> Vector2:
	if target == null or not is_instance_valid(target):
		return default_pos

	var anchor: Vector2 = _resolve_world_collider_center(target)
	var sprite: AnimatedSprite2D = _resolve_target_sprite(target)
	if sprite == null or not is_instance_valid(sprite):
		return anchor

	var rect: Rect2 = _resolve_sprite_bounds_global(sprite)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return anchor

	# Keep VFX anchored near the actually rendered model footprint.
	# This prevents the effect from slipping under terrain when collider offsets/scales differ.
	var min_x: float = rect.position.x + rect.size.x * 0.10
	var max_x: float = rect.position.x + rect.size.x * 0.90
	var min_y: float = rect.position.y + rect.size.y * 0.35
	var max_y: float = rect.position.y + rect.size.y + 6.0
	return Vector2(clampf(anchor.x, min_x, max_x), clampf(anchor.y, min_y, max_y))

static func resolve_world_collider_center(target: Node2D, default_pos: Vector2 = Vector2.ZERO) -> Vector2:
	if target == null or not is_instance_valid(target):
		return default_pos
	return _resolve_world_collider_center(target)

static func resolve_visual_root(target: Node2D) -> Node2D:
	if target == null or not is_instance_valid(target):
		return null
	var visual_v: Variant = target.get("visual_root")
	if visual_v is Node2D and is_instance_valid(visual_v):
		return visual_v as Node2D
	var direct := target.get_node_or_null("Visual")
	if direct is Node2D:
		return direct as Node2D
	return null

static func resolve_backdrop_z_index(target: Node2D, fallback_z_index: int = 0) -> int:
	if target == null or not is_instance_valid(target):
		return fallback_z_index
	var visual_v: Variant = target.get("visual_root")
	if visual_v is CanvasItem and is_instance_valid(visual_v):
		return int((visual_v as CanvasItem).z_index) - 1
	if target is CanvasItem:
		return int((target as CanvasItem).z_index) - 1
	return fallback_z_index

static func resolve_carrier_z_index(target: Node2D, fallback_z_index: int = 0) -> int:
	if target == null or not is_instance_valid(target):
		return fallback_z_index
	var visual_v: Variant = target.get("visual_root")
	if visual_v is CanvasItem and is_instance_valid(visual_v):
		return int((visual_v as CanvasItem).z_index)
	var direct_visual := target.get_node_or_null("Visual")
	if direct_visual is CanvasItem and is_instance_valid(direct_visual):
		return int((direct_visual as CanvasItem).z_index)
	if target is CanvasItem:
		return int((target as CanvasItem).z_index)
	return fallback_z_index

static func _resolve_world_collider_center(target: Node2D) -> Vector2:
	var wc: Variant = target.get("world_collision")
	if wc is CollisionShape2D and is_instance_valid(wc):
		return (wc as CollisionShape2D).global_position
	var node_wc := target.get_node_or_null("WorldCollider") as CollisionShape2D
	if node_wc != null:
		return node_wc.global_position
	if target.has_method("get_body_hitbox_center_global"):
		var v: Variant = target.call("get_body_hitbox_center_global")
		if v is Vector2:
			return v as Vector2
	return target.global_position

static func _resolve_target_sprite(target: Node2D) -> AnimatedSprite2D:
	if target == null or not is_instance_valid(target):
		return null
	var visual_v: Variant = target.get("visual_root")
	if visual_v is Node:
		var visual_node: Node = visual_v as Node
		if visual_node != null and is_instance_valid(visual_node):
			var direct: AnimatedSprite2D = visual_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
			if direct != null:
				return direct
			var deep: AnimatedSprite2D = visual_node.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
			if deep != null:
				return deep
	var own: AnimatedSprite2D = target.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if own != null:
		return own
	return target.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D

static func _resolve_sprite_bounds_global(sprite: AnimatedSprite2D) -> Rect2:
	if sprite == null:
		return Rect2()
	var tex: Texture2D = null
	if sprite.sprite_frames != null:
		var anim: StringName = sprite.animation
		if anim != StringName("") and sprite.sprite_frames.has_animation(anim):
			var frame_count: int = sprite.sprite_frames.get_frame_count(anim)
			if frame_count > 0:
				var frame_idx: int = clampi(sprite.frame, 0, frame_count - 1)
				tex = sprite.sprite_frames.get_frame_texture(anim, frame_idx)
	if tex == null:
		return Rect2(sprite.global_position, Vector2.ZERO)

	var size: Vector2 = tex.get_size()
	var local_pos: Vector2 = sprite.offset
	if sprite.centered:
		local_pos -= size * 0.5

	var top_left: Vector2 = sprite.to_global(local_pos)
	var top_right: Vector2 = sprite.to_global(local_pos + Vector2(size.x, 0.0))
	var bottom_left: Vector2 = sprite.to_global(local_pos + Vector2(0.0, size.y))
	var bottom_right: Vector2 = sprite.to_global(local_pos + size)

	var min_x: float = min(min(top_left.x, top_right.x), min(bottom_left.x, bottom_right.x))
	var max_x: float = max(max(top_left.x, top_right.x), max(bottom_left.x, bottom_right.x))
	var min_y: float = min(min(top_left.y, top_right.y), min(bottom_left.y, bottom_right.y))
	var max_y: float = max(max(top_left.y, top_right.y), max(bottom_left.y, bottom_right.y))
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))

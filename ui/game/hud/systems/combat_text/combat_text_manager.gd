extends Node2D
class_name CombatTextManager

const FLOATING_DAMAGE_NUMBER_SCENE := preload("res://ui/game/hud/systems/combat_text/floating_damage_number.tscn")
const NODE_CACHE := preload("res://core/runtime/node_cache.gd")

const PHYSICAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const MAGIC_COLOR := Color(0.98, 0.86, 0.28, 1.0)
const HEAL_COLOR := Color(0.42, 1.0, 0.45, 1.0)
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const BASE_Y_OFFSET := -30.0
const SIDE_OFFSET_STEP := 22.0
const DUAL_HIT_SIDE_OFFSET_STEP := 36.0
const BURST_WINDOW_MS := 160
const FLOAT_TEXT_Z_INDEX := 4096
const FLOAT_TEXT_GAP_ABOVE_CASTBAR := 8.0
const FLOAT_TEXT_GAP_ABOVE_SPRITE := 6.0

var _burst_state: Dictionary = {}

func show_damage(source: Node2D, target: Node2D, final_damage: int, dmg_type: String) -> void:
	_show_value(source, target, final_damage, dmg_type)

func show_heal(source: Node2D, target: Node2D, heal_amount: int) -> void:
	_show_value(source, target, heal_amount, "heal")

func _show_value(source: Node2D, target: Node2D, value: int, value_type: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if value <= 0:
		return
	if FLOATING_DAMAGE_NUMBER_SCENE == null:
		return
	if not _is_player_involved(source, target):
		return

	var instance: FloatingDamageNumber = FLOATING_DAMAGE_NUMBER_SCENE.instantiate() as FloatingDamageNumber
	if instance == null:
		return

	var burst_index: int = _next_burst_index(target)
	var start: Vector2 = _resolve_start_position(target, burst_index, value_type)
	var drift_dir: Vector2 = _resolve_float_direction(target, value_type)
	instance.position = start
	instance.z_as_relative = false
	instance.z_index = FLOAT_TEXT_Z_INDEX
	add_child(instance)
	instance.show_value(value, _color_for_value_type(value_type), drift_dir)

func _is_player_involved(source: Node2D, target: Node2D) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var player: Node = NODE_CACHE.get_player(tree)
	if player == null or not is_instance_valid(player):
		return false
	if target == player:
		return true
	if source != null and is_instance_valid(source) and source == player:
		return true
	if _node_has_player_engagement(target, player):
		return true
	if source != null and is_instance_valid(source) and _node_has_player_engagement(source, player):
		return true
	return false


func _node_has_player_engagement(node: Node, player: Node) -> bool:
	if node == null or player == null:
		return false
	if "current_target" in node and node.get("current_target") == player:
		return true
	if "aggressor" in node and node.get("aggressor") == player:
		return true
	if "direct_attackers" in node:
		var d: Variant = node.get("direct_attackers")
		if d is Dictionary and (d as Dictionary).has(player.get_instance_id()):
			return true
	return false

func _resolve_start_position(target: Node2D, burst_index: int, value_type: String) -> Vector2:
	var side_offset: float = _resolve_type_lane_offset(target, value_type)
	if burst_index >= 3:
		side_offset += _burst_side_offset(burst_index) * 0.5
	var sprite: AnimatedSprite2D = _resolve_target_sprite(target)
	if sprite != null and is_instance_valid(sprite):
		var sprite_rect: Rect2 = _resolve_sprite_rect_local(sprite)
		var top_left: Vector2 = sprite.to_global(sprite_rect.position)
		var top_right: Vector2 = sprite.to_global(sprite_rect.position + Vector2(sprite_rect.size.x, 0.0))
		var spawn_from_right: bool = sprite.flip_h
		var corner: Vector2 = top_right if spawn_from_right else top_left
		return corner + Vector2(side_offset, -FLOAT_TEXT_GAP_ABOVE_SPRITE)

	var x_offset: float = side_offset
	var y_anchor: float = target.global_position.y + BASE_Y_OFFSET
	var overlay_v: Variant = target.get("overlay_bars_widget") if target.has_method("get") else null
	if overlay_v is OverlayBarsWidget:
		var overlay: OverlayBarsWidget = overlay_v as OverlayBarsWidget
		if is_instance_valid(overlay):
			var cast_bar: CastBarWidget = overlay.get_cast_bar_widget()
			if cast_bar != null and is_instance_valid(cast_bar):
				var cast_size: Vector2 = cast_bar.get_visual_size()
				y_anchor = cast_bar.global_position.y - (cast_size.y * 0.5) - FLOAT_TEXT_GAP_ABOVE_CASTBAR
	return Vector2(target.global_position.x + x_offset, y_anchor)

func _resolve_float_direction(target: Node2D, value_type: String = "physical") -> Vector2:
	var sprite: AnimatedSprite2D = _resolve_target_sprite(target)
	if sprite != null and is_instance_valid(sprite):
		var look_dir_x: float = -1.0 if sprite.flip_h else 1.0
		var up := Vector2(0.0, -1.0)
		if value_type == "heal":
			return up
		var yellow_dir := Vector2(-look_dir_x, -1.0).normalized()
		if value_type == "magic":
			return yellow_dir
		# white (physical/default): between yellow and green(up)
		return (up + yellow_dir).normalized()
	return Vector2(0.0, -1.0)

func _resolve_type_lane_offset(target: Node2D, value_type: String) -> float:
	var sprite: AnimatedSprite2D = _resolve_target_sprite(target)
	if sprite == null or not is_instance_valid(sprite):
		return 0.0
	var face_dir_x: float = -1.0 if sprite.flip_h else 1.0
	if value_type == "heal":
		return face_dir_x * DUAL_HIT_SIDE_OFFSET_STEP
	if value_type == "magic":
		return -face_dir_x * DUAL_HIT_SIDE_OFFSET_STEP
	return 0.0

func _resolve_target_sprite(target: Node2D) -> AnimatedSprite2D:
	if target == null or not is_instance_valid(target):
		return null
	var visual_v: Variant = target.get("visual_root") if target.has_method("get") else null
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

func _resolve_sprite_rect_local(sprite: AnimatedSprite2D) -> Rect2:
	if sprite == null:
		return Rect2(Vector2(-16.0, -16.0), Vector2(32.0, 32.0))
	var tex: Texture2D = null
	if sprite.sprite_frames != null:
		var anim: StringName = sprite.animation
		if anim != StringName("") and sprite.sprite_frames.has_animation(anim):
			var frame_count: int = sprite.sprite_frames.get_frame_count(anim)
			if frame_count > 0:
				var frame_idx: int = clampi(sprite.frame, 0, frame_count - 1)
				tex = sprite.sprite_frames.get_frame_texture(anim, frame_idx)
	var size: Vector2 = tex.get_size() if tex != null else Vector2(32.0, 32.0)
	var pos: Vector2 = sprite.offset
	if sprite.centered:
		pos -= size * 0.5
	return Rect2(pos, size)

func _burst_side_offset(index: int) -> float:
	if index == 0:
		return -DUAL_HIT_SIDE_OFFSET_STEP
	if index == 1:
		return DUAL_HIT_SIDE_OFFSET_STEP
	var pair: int = int(floor(float(index - 2) / 2.0))
	var magnitude: float = SIDE_OFFSET_STEP * float(pair + 2)
	return -magnitude if index % 2 == 0 else magnitude

func _next_burst_index(target: Node2D) -> int:
	var key: int = target.get_instance_id()
	var now_ms: int = Time.get_ticks_msec()
	var entry: Dictionary = _burst_state.get(key, {}) as Dictionary
	var last_ms: int = int(entry.get("time", 0))
	var next_index: int = 0
	if now_ms - last_ms <= BURST_WINDOW_MS:
		next_index = int(entry.get("index", -1)) + 1
	_burst_state[key] = {
		"time": now_ms,
		"index": next_index,
	}
	return next_index

func _color_for_value_type(value_type: String) -> Color:
	if value_type == "physical":
		return PHYSICAL_COLOR
	if value_type == "magic":
		return MAGIC_COLOR
	if value_type == "heal":
		return HEAL_COLOR
	return DEFAULT_COLOR

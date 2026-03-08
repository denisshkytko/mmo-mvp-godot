@tool
extends Node2D
class_name CharacterSpriteModel

signal death_pose_ready(snapshot: Dictionary)

@export var animation_fps: float = 24.0
@export var idle_animation: String = "none"
@export var walk_animation: String = "none"
@export var run_animation: String = "none"
@export var hurt_animation: String = "none"
@export var death_animation: String = "none"
@export var melee_stand_animation: String = "none"
@export var melee_run_animation: String = "none"
@export var unarmed_stand_animation: String = "none"
@export var unarmed_run_animation: String = "none"
@export var ranged_stand_animation: String = "none"
@export var ranged_run_animation: String = "none"
@export var warrior_stun_ability_animation: String = "none"
@export var hp_bar_offset: Vector2 = Vector2(0.0, -30.0)
@export var cast_bar_offset: Vector2 = Vector2(0.0, -42.0)
@export var hp_bar_size: Vector2 = Vector2(36.0, 6.0)
@export var hp_bar_back_color: Color = Color(0.0, 0.0, 0.0, 0.88235295)
@export var hp_bar_fill_color: Color = Color(0.38720772, 0.18201989, 0.97702104, 1.0)
@export_range(0.0, 128.0, 1.0) var hp_bar_corner_radius: float = 0.0
@export var hp_bar_outline_enabled: bool = false
@export_range(0, 32, 1) var hp_bar_outline_width: int = 0
@export var hp_bar_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var cast_bar_size: Vector2 = Vector2(38.0, 12.0)
@export var cast_bar_icon_size: Vector2 = Vector2(16.0, 16.0)
@export var cast_bar_back_color: Color = Color(0.0, 0.0, 0.0, 0.8)
@export var cast_bar_fill_color: Color = Color(0.2, 0.8, 1.0, 0.9)
@export_range(0.0, 128.0, 1.0) var cast_bar_corner_radius: float = 0.0
@export var cast_bar_outline_enabled: bool = false
@export_range(0, 32, 1) var cast_bar_outline_width: int = 0
@export var cast_bar_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var cast_bar_icon_visible: bool = true
@export var overlay_name_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var overlay_name_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export_range(0, 8, 1) var overlay_name_outline_size: int = 3
@export_range(1.0, 512.0, 1.0) var model_highlight_radius: float = 200.0
@export var model_highlight_override_widget_colors: bool = false
@export var model_highlight_center_color: Color = Color(0.2, 0.6, 1.0, 0.28)
@export var model_highlight_edge_color: Color = Color(0.2, 0.6, 1.0, 0.0)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var world_collision_shape: CollisionShape2D = $CollisionProfile/WorldCollider as CollisionShape2D
@onready var body_hitbox_shape: CollisionShape2D = $CollisionProfile/BodyHitbox as CollisionShape2D
@onready var interaction_radius_shape: CollisionShape2D = $CollisionProfile/InteractionRadius as CollisionShape2D
@onready var overlay_hp_bar: Node2D = _resolve_overlay_node("HealthBar")
@onready var overlay_cast_bar: Node2D = _resolve_overlay_node("CastBar")
@onready var overlay_bars_widget: Node = get_node_or_null("OverlayProfile/Bars")
@onready var model_highlight_widget: Node2D = _resolve_overlay_node("ModelHighlight")

var _is_moving: bool = false
var _prefer_walk_mode: bool = false
var _is_dead: bool = false
var _queued_idle_after_one_shot: bool = false
var _queued_locomotion_after_one_shot: bool = false
var _one_shot_lock_active: bool = false
var _death_pose_emitted: bool = false
@export var idle_liveliness_delay_min_sec: float = 5.0
@export var idle_liveliness_delay_max_sec: float = 7.0
var _idle_liveliness_timer_sec: float = 5.0

const ANIMATION_SELECT_PROPERTIES := [
	"idle_animation",
	"walk_animation",
	"run_animation",
	"hurt_animation",
	"death_animation",
	"melee_stand_animation",
	"melee_run_animation",
	"unarmed_stand_animation",
	"unarmed_run_animation",
	"ranged_stand_animation",
	"ranged_run_animation",
	"warrior_stun_ability_animation",
]

func _validate_property(property: Dictionary) -> void:
	var property_name := String(property.get("name", ""))
	if not ANIMATION_SELECT_PROPERTIES.has(property_name):
		return
	property["hint"] = PROPERTY_HINT_ENUM
	property["hint_string"] = _build_animation_hint_string()

func _build_animation_hint_string() -> String:
	var options: Array[String] = ["none:None"]
	var sprite: AnimatedSprite2D = animated_sprite
	if sprite == null:
		sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		for anim_name in sprite.sprite_frames.get_animation_names():
			var clean_name := String(anim_name).strip_edges()
			if clean_name == "" or clean_name == "none":
				continue
			if options.has(clean_name):
				continue
			options.append(clean_name)
	return ",".join(options)

func _ready() -> void:
	_apply_animation_speed_to_all()
	if animated_sprite != null and not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	play_idle()
	_reset_idle_liveliness_timer()
	_apply_overlay_name_profile()
	_sync_model_highlight_profile()

func _process(delta: float) -> void:
	if animated_sprite == null:
		return
	if _is_dead or _is_moving or _one_shot_lock_active:
		_reset_idle_liveliness_timer()
		return
	_idle_liveliness_timer_sec = max(0.0, _idle_liveliness_timer_sec - delta)
	if _idle_liveliness_timer_sec > 0.0:
		return
	animated_sprite.flip_h = not animated_sprite.flip_h
	_reset_idle_liveliness_timer()

func set_move_direction(dir: Vector2) -> void:
	set_move_direction_mode(dir, false)

func set_move_direction_mode(dir: Vector2, prefer_walk: bool) -> void:
	if animated_sprite == null:
		return
	_is_moving = dir.length() > 0.05
	_prefer_walk_mode = prefer_walk
	if _is_dead:
		return
	if _one_shot_lock_active:
		return
	_apply_facing_from_direction(dir)
	if _is_moving:
		_reset_idle_liveliness_timer()

	if _is_moving:
		if prefer_walk and _has_animation(walk_animation):
			_play_locomotion_animation(walk_animation)
		elif _has_animation(run_animation):
			_play_locomotion_animation(run_animation)
		elif _has_animation(walk_animation):
			_play_locomotion_animation(walk_animation)
		else:
			play_idle()
	else:
		play_idle()

func set_facing_to_world_position(world_position: Vector2) -> void:
	if animated_sprite == null:
		return
	var dir := world_position - global_position
	_apply_facing_from_direction(dir)
	_reset_idle_liveliness_timer()

func play_hurt() -> void:
	if _is_dead:
		return
	if _has_animation(hurt_animation):
		_play_one_shot(hurt_animation, true)

func play_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	if _has_animation(death_animation):
		if animated_sprite.sprite_frames != null:
			animated_sprite.sprite_frames.set_animation_loop(death_animation, false)
		_one_shot_lock_active = true
		_play_animation_if_needed(death_animation)

func play_combat_action(action_kind: String, is_moving_now: bool, class_id: String) -> void:
	if _is_dead:
		return
	var anim := _resolve_combat_animation(action_kind, is_moving_now, class_id)
	if anim == "":
		return
	_play_one_shot(anim, is_moving_now)

func play_idle() -> void:
	if animated_sprite == null:
		return
	if _has_animation(idle_animation):
		_play_animation_if_needed(idle_animation)
	elif _has_animation("Idle"):
		_play_animation_if_needed("Idle")
	elif _has_animation(walk_animation):
		_play_animation_if_needed(walk_animation)
	elif _has_animation(run_animation):
		_play_animation_if_needed(run_animation)
	elif animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.get_animation_names().size() > 0:
		_play_animation_if_needed(animated_sprite.sprite_frames.get_animation_names()[0])

func get_collision_profile() -> Dictionary:
	var model_scale := Vector2(abs(scale.x), abs(scale.y))
	if model_scale.x <= 0.0001:
		model_scale.x = 1.0
	if model_scale.y <= 0.0001:
		model_scale.y = 1.0

	var world_shape: Shape2D = null
	var world_offset := Vector2.ZERO
	var world_rotation := 0.0
	if world_collision_shape != null:
		world_shape = _duplicate_scaled_shape(world_collision_shape.shape, model_scale)
		world_offset = Vector2(
			world_collision_shape.position.x * model_scale.x,
			world_collision_shape.position.y * model_scale.y
		)
		world_rotation = world_collision_shape.rotation

	var body_shape: Shape2D = null
	var body_offset := world_offset
	var body_rotation := 0.0
	if body_hitbox_shape != null:
		body_shape = _duplicate_scaled_shape(body_hitbox_shape.shape, model_scale)
		body_offset = Vector2(
			body_hitbox_shape.position.x * model_scale.x,
			body_hitbox_shape.position.y * model_scale.y
		)
		body_rotation = body_hitbox_shape.rotation

	var interaction_radius := 80.0
	if interaction_radius_shape != null and interaction_radius_shape.shape is CircleShape2D:
		interaction_radius = (interaction_radius_shape.shape as CircleShape2D).radius * model_scale.x

	return {
		"world_collision_shape": world_shape.duplicate(true) if world_shape != null else null,
		"world_collision_offset": world_offset,
		"world_collision_rotation": world_rotation,
		"body_hitbox_shape": body_shape.duplicate(true) if body_shape != null else null,
		"body_hitbox_offset": body_offset,
		"body_hitbox_rotation": body_rotation,
		"interaction_radius": interaction_radius,
	}

func get_overlay_profile() -> Dictionary:
	var model_scale := Vector2(abs(scale.x), abs(scale.y))
	if model_scale.x <= 0.0001:
		model_scale.x = 1.0
	if model_scale.y <= 0.0001:
		model_scale.y = 1.0

	var hp_offset := hp_bar_offset
	if overlay_hp_bar != null:
		hp_offset = Vector2(overlay_hp_bar.position.x * model_scale.x, overlay_hp_bar.position.y * model_scale.y)
	var hp_size := hp_bar_size
	if overlay_hp_bar != null and overlay_hp_bar.has_method("get_visual_size"):
		var hp_size_v: Variant = overlay_hp_bar.call("get_visual_size")
		if hp_size_v is Vector2:
			var raw_hp_size := hp_size_v as Vector2
			hp_size = Vector2(raw_hp_size.x * model_scale.x, raw_hp_size.y * model_scale.y)

	var cast_offset := cast_bar_offset
	if overlay_cast_bar != null:
		cast_offset = Vector2(overlay_cast_bar.position.x * model_scale.x, overlay_cast_bar.position.y * model_scale.y)
	var cast_size := cast_bar_size
	if overlay_cast_bar != null and overlay_cast_bar.has_method("get_visual_size"):
		var cast_size_v: Variant = overlay_cast_bar.call("get_visual_size")
		if cast_size_v is Vector2:
			var raw_cast_size := cast_size_v as Vector2
			cast_size = Vector2(raw_cast_size.x * model_scale.x, raw_cast_size.y * model_scale.y)
	var cast_icon_size := cast_bar_icon_size
	if overlay_cast_bar != null and overlay_cast_bar.has_method("get_icon_visual_size"):
		var cast_icon_size_v: Variant = overlay_cast_bar.call("get_icon_visual_size")
		if cast_icon_size_v is Vector2:
			var raw_icon_size := cast_icon_size_v as Vector2
			cast_icon_size = Vector2(raw_icon_size.x * model_scale.x, raw_icon_size.y * model_scale.y)
	var cast_icon_visible := cast_bar_icon_visible
	if overlay_cast_bar != null and overlay_cast_bar.has_method("is_icon_visual_visible"):
		var icon_visible_v: Variant = overlay_cast_bar.call("is_icon_visual_visible")
		if icon_visible_v is bool:
			cast_icon_visible = icon_visible_v

	return {
		"hp_bar_offset": hp_offset,
		"cast_bar_offset": cast_offset,
		"hp_bar": {
			"offset": hp_offset,
			"size": hp_size,
			"back_color": hp_bar_back_color,
			"fill_color": hp_bar_fill_color,
			"corner_radius": hp_bar_corner_radius,
			"outline_enabled": hp_bar_outline_enabled,
			"outline_width": hp_bar_outline_width,
			"outline_color": hp_bar_outline_color,
		},
		"cast_bar": {
			"offset": cast_offset,
			"size": cast_size,
			"icon_size": cast_icon_size,
			"back_color": cast_bar_back_color,
			"fill_color": cast_bar_fill_color,
			"corner_radius": cast_bar_corner_radius,
			"outline_enabled": cast_bar_outline_enabled,
			"outline_width": cast_bar_outline_width,
			"outline_color": cast_bar_outline_color,
			"icon_visible": cast_icon_visible,
		},
		"name": {
			"text_color": overlay_name_text_color,
			"outline_color": overlay_name_outline_color,
			"outline_size": overlay_name_outline_size,
		},
		"model_highlight": {
			"radius": model_highlight_radius,
			"override_widget_colors": model_highlight_override_widget_colors,
			"center_color": model_highlight_center_color,
			"edge_color": model_highlight_edge_color,
		},
	}


func _apply_overlay_name_profile() -> void:
	if overlay_bars_widget == null or not is_instance_valid(overlay_bars_widget):
		return
	if overlay_bars_widget.has_method("set_name_visual"):
		overlay_bars_widget.call("set_name_visual", overlay_name_text_color, overlay_name_outline_color, overlay_name_outline_size)

func _sync_model_highlight_profile() -> void:
	if model_highlight_widget == null or not is_instance_valid(model_highlight_widget):
		return
	if model_highlight_widget.has_method("set_radius"):
		var scale_factor: float = max(0.0001, abs(scale.x))
		model_highlight_widget.call("set_radius", model_highlight_radius / scale_factor)
	if model_highlight_override_widget_colors and model_highlight_widget.has_method("set_colors"):
		model_highlight_widget.call("set_colors", model_highlight_center_color, model_highlight_edge_color)
	if body_hitbox_shape != null:
		model_highlight_widget.position = body_hitbox_shape.position

func _resolve_overlay_node(node_name: String) -> Node2D:
	var direct := get_node_or_null("OverlayProfile/%s" % node_name)
	if direct is Node2D:
		return direct as Node2D
	var nested := get_node_or_null("OverlayProfile/Bars/%s" % node_name)
	if nested is Node2D:
		return nested as Node2D
	return null

func _duplicate_scaled_shape(shape: Shape2D, model_scale: Vector2) -> Shape2D:
	if shape == null:
		return null
	var dup := shape.duplicate(true)
	if dup is CapsuleShape2D:
		var cap := dup as CapsuleShape2D
		cap.radius *= model_scale.x
		cap.height *= model_scale.y
		return cap
	if dup is RectangleShape2D:
		var rect := dup as RectangleShape2D
		rect.size = Vector2(rect.size.x * model_scale.x, rect.size.y * model_scale.y)
		return rect
	if dup is CircleShape2D:
		var circ := dup as CircleShape2D
		circ.radius *= model_scale.x
		return circ
	return dup

func _play_animation_if_needed(anim_name: String) -> void:
	if animated_sprite == null or anim_name == "":
		return
	if animated_sprite.animation == anim_name and animated_sprite.is_playing():
		return
	animated_sprite.play(anim_name)

func _play_one_shot(anim_name: String, back_to_locomotion: bool) -> void:
	if not _has_animation(anim_name):
		if back_to_locomotion:
			_refresh_locomotion_animation()
		else:
			play_idle()
		return
	if animated_sprite.sprite_frames != null:
		animated_sprite.sprite_frames.set_animation_loop(anim_name, false)
	_one_shot_lock_active = true
	_queued_locomotion_after_one_shot = back_to_locomotion
	_queued_idle_after_one_shot = not back_to_locomotion
	_play_animation_if_needed(anim_name)

func reset_after_respawn() -> void:
	_is_dead = false
	_is_moving = false
	_one_shot_lock_active = false
	_queued_idle_after_one_shot = false
	_queued_locomotion_after_one_shot = false
	_death_pose_emitted = false
	visible = true
	play_idle()

func hide_model_for_corpse() -> void:
	visible = false

func build_corpse_pose_snapshot() -> Dictionary:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return {}
	var anim_name := death_animation
	if not _has_animation(anim_name):
		return {}
	var frame_count := animated_sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return {}
	var tex := animated_sprite.sprite_frames.get_frame_texture(anim_name, frame_count - 1)
	if tex == null:
		return {}
	return {
		"texture": tex,
		"flip_h": animated_sprite.flip_h,
		"scale": scale,
		"offset": animated_sprite.position,
	}

func _resolve_combat_animation(action_kind: String, is_moving_now: bool, class_id: String) -> String:
	match action_kind:
		"ranged":
			return ranged_run_animation if is_moving_now else ranged_stand_animation
		"melee", "melee_weapon":
			return melee_run_animation if is_moving_now else melee_stand_animation
		"melee_unarmed":
			return unarmed_run_animation if is_moving_now else unarmed_stand_animation
		"warrior_stun":
			if class_id == "warrior":
				return warrior_stun_ability_animation
			return ""
		_:
			return ""

func _refresh_locomotion_animation() -> void:
	if _is_dead:
		return
	if _is_moving:
		if _prefer_walk_mode and _has_animation(walk_animation):
			_play_locomotion_animation(walk_animation)
			return
		if _has_animation(run_animation):
			_play_locomotion_animation(run_animation)
			return
		if _has_animation(walk_animation):
			_play_locomotion_animation(walk_animation)
			return
	play_idle()

func _play_locomotion_animation(anim_name: String) -> void:
	if animated_sprite == null or anim_name == "":
		return
	if animated_sprite.sprite_frames != null:
		animated_sprite.sprite_frames.set_animation_loop(anim_name, true)
	_play_animation_if_needed(anim_name)

func _on_animation_finished() -> void:
	if animated_sprite == null:
		return
	if animated_sprite.animation == death_animation and _is_dead:
		var frame_count := animated_sprite.sprite_frames.get_frame_count(death_animation)
		if frame_count > 0:
			animated_sprite.stop()
			animated_sprite.frame = frame_count - 1
		if not _death_pose_emitted:
			_death_pose_emitted = true
			emit_signal("death_pose_ready", build_corpse_pose_snapshot())
		return
	_one_shot_lock_active = false
	if _queued_locomotion_after_one_shot:
		_queued_locomotion_after_one_shot = false
		_refresh_locomotion_animation()
		return
	if _queued_idle_after_one_shot:
		_queued_idle_after_one_shot = false
		play_idle()

func _apply_animation_speed_to_all() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var frames := animated_sprite.sprite_frames
	for anim in frames.get_animation_names():
		frames.set_animation_speed(anim, animation_fps)

func _has_animation(anim_name: String) -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	if anim_name == "":
		return false
	return animated_sprite.sprite_frames.has_animation(anim_name)

func _apply_facing_from_direction(dir: Vector2) -> void:
	if animated_sprite == null:
		return
	if dir.x < -0.01:
		animated_sprite.flip_h = true
	elif dir.x > 0.01:
		animated_sprite.flip_h = false

func _reset_idle_liveliness_timer() -> void:
	_idle_liveliness_timer_sec = _pick_idle_liveliness_delay()

func _pick_idle_liveliness_delay() -> float:
	var lo: float = float(max(0.1, min(idle_liveliness_delay_min_sec, idle_liveliness_delay_max_sec)))
	var hi: float = float(max(0.1, max(idle_liveliness_delay_min_sec, idle_liveliness_delay_max_sec)))
	return randf_range(lo, hi)

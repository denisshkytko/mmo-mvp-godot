extends Node2D
class_name CharacterSpriteModel

signal death_pose_ready(snapshot: Dictionary)

@export var animation_fps: float = 24.0
@export var idle_animation: String = "Idle Blinking"
@export var walk_animation: String = "Walking"
@export var run_animation: String = "Running"
@export var hurt_animation: String = "Hurt"
@export var death_animation: String = "Dying"
@export var melee_stand_animation: String = "Slashing"
@export var melee_run_animation: String = "Run Slashing"
@export var unarmed_stand_animation: String = "Throwing"
@export var unarmed_run_animation: String = "Run Throwing"
@export var ranged_stand_animation: String = "Throwing"
@export var ranged_run_animation: String = "Run Throwing"
@export var hunter_ranged_stand_animation: String = "Shooting"
@export var hunter_ranged_run_animation: String = "Run Shooting"
@export var warrior_stun_ability_animation: String = "Kicking"

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var world_collision_shape: CollisionShape2D = $CollisionProfile/WorldCollider as CollisionShape2D
@onready var body_hitbox_shape: CollisionShape2D = $CollisionProfile/BodyHitbox as CollisionShape2D
@onready var interaction_radius_shape: CollisionShape2D = $CollisionProfile/InteractionRadius as CollisionShape2D

var _is_moving: bool = false
var _is_dead: bool = false
var _queued_idle_after_one_shot: bool = false
var _queued_locomotion_after_one_shot: bool = false
var _one_shot_lock_active: bool = false
var _death_pose_emitted: bool = false
@export var idle_liveliness_delay_min_sec: float = 5.0
@export var idle_liveliness_delay_max_sec: float = 7.0
var _idle_liveliness_timer_sec: float = 5.0

func _ready() -> void:
	_apply_animation_speed_to_all()
	if animated_sprite != null and not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	play_idle()
	_reset_idle_liveliness_timer()

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
	if animated_sprite == null:
		return
	_is_moving = dir.length() > 0.01
	if _is_dead:
		return
	if _one_shot_lock_active:
		return
	_apply_facing_from_direction(dir)
	if _is_moving:
		_reset_idle_liveliness_timer()

	if _is_moving:
		if _has_animation(run_animation):
			_play_animation_if_needed(run_animation)
		elif _has_animation(walk_animation):
			_play_animation_if_needed(walk_animation)
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

func _play_animation_if_needed(name: String) -> void:
	if animated_sprite == null or name == "":
		return
	if animated_sprite.animation == name and animated_sprite.is_playing():
		return
	animated_sprite.play(name)

func _play_one_shot(name: String, back_to_locomotion: bool) -> void:
	if not _has_animation(name):
		if back_to_locomotion:
			_refresh_locomotion_animation()
		else:
			play_idle()
		return
	if animated_sprite.sprite_frames != null:
		animated_sprite.sprite_frames.set_animation_loop(name, false)
	_one_shot_lock_active = true
	_queued_locomotion_after_one_shot = back_to_locomotion
	_queued_idle_after_one_shot = not back_to_locomotion
	_play_animation_if_needed(name)

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
			if class_id == "hunter":
				return hunter_ranged_run_animation if is_moving_now else hunter_ranged_stand_animation
			return ranged_run_animation if is_moving_now else ranged_stand_animation
		"melee_weapon":
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
		if _has_animation(run_animation):
			_play_animation_if_needed(run_animation)
			return
		if _has_animation(walk_animation):
			_play_animation_if_needed(walk_animation)
			return
	play_idle()

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

func _has_animation(name: String) -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	if name == "":
		return false
	return animated_sprite.sprite_frames.has_animation(name)

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

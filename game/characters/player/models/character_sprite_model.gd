extends Node2D
class_name CharacterSpriteModel

@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Walking"
@export var run_animation: String = "Running"

# Physics / hitbox tuning lives here so it can be edited per model scene in the editor.
@export var body_collision_size: Vector2 = Vector2(24, 24)
@export var body_collision_offset: Vector2 = Vector2.ZERO
@export var interaction_radius: float = 80.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	play_idle()

func set_move_direction(dir: Vector2) -> void:
	if animated_sprite == null:
		return
	if dir.x < -0.01:
		animated_sprite.flip_h = true
	elif dir.x > 0.01:
		animated_sprite.flip_h = false

	if dir.length() > 0.01:
		if _has_animation(run_animation):
			_play_animation_if_needed(run_animation)
		elif _has_animation(walk_animation):
			_play_animation_if_needed(walk_animation)
		else:
			play_idle()
	else:
		play_idle()

func play_idle() -> void:
	if animated_sprite == null:
		return
	if _has_animation(idle_animation):
		_play_animation_if_needed(idle_animation)
	elif animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.get_animation_names().size() > 0:
		_play_animation_if_needed(animated_sprite.sprite_frames.get_animation_names()[0])

func get_collision_profile() -> Dictionary:
	return {
		"body_collision_size": body_collision_size,
		"body_collision_offset": body_collision_offset,
		"interaction_radius": interaction_radius,
	}

func _play_animation_if_needed(name: String) -> void:
	if animated_sprite == null or name == "":
		return
	if animated_sprite.animation == name and animated_sprite.is_playing():
		return
	animated_sprite.play(name)

func _has_animation(name: String) -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	if name == "":
		return false
	return animated_sprite.sprite_frames.has_animation(name)

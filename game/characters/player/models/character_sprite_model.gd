extends Node2D
class_name CharacterSpriteModel

@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Walking"
@export var run_animation: String = "Running"

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
			animated_sprite.play(run_animation)
		elif _has_animation(walk_animation):
			animated_sprite.play(walk_animation)
		else:
			play_idle()
	else:
		play_idle()

func play_idle() -> void:
	if animated_sprite == null:
		return
	if _has_animation(idle_animation):
		animated_sprite.play(idle_animation)
	elif animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.get_animation_names().size() > 0:
		animated_sprite.play(animated_sprite.sprite_frames.get_animation_names()[0])

func _has_animation(name: String) -> bool:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	if name == "":
		return false
	return animated_sprite.sprite_frames.has_animation(name)

extends Node2D
class_name CharacterSpriteModel

@export_dir var sequences_root: String = ""
@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Walking"
@export var run_animation: String = "Running"
@export var fps: float = 12.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _frames_built: bool = false

func _ready() -> void:
	_rebuild_frames_if_needed()
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
		elif _has_animation(idle_animation):
			animated_sprite.play(idle_animation)
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

func _rebuild_frames_if_needed() -> void:
	if _frames_built:
		return
	_frames_built = true
	if animated_sprite == null or sequences_root == "":
		return
	var dir := DirAccess.open(sequences_root)
	if dir == null:
		push_warning("CharacterSpriteModel: can't open root: %s" % sequences_root)
		return

	var frames := SpriteFrames.new()
	var anim_dirs: PackedStringArray = dir.get_directories()
	anim_dirs.sort()
	for anim_name in anim_dirs:
		var anim_path := "%s/%s" % [sequences_root, anim_name]
		var adir := DirAccess.open(anim_path)
		if adir == null:
			continue
		var files: PackedStringArray = adir.get_files()
		files.sort()
		var png_files: Array[String] = []
		for file_name in files:
			if file_name.to_lower().ends_with(".png"):
				png_files.append(file_name)
		if png_files.is_empty():
			continue

		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, fps)
		frames.set_animation_loop(anim_name, true)
		for png_name in png_files:
			var texture := load("%s/%s" % [anim_path, png_name]) as Texture2D
			if texture != null:
				frames.add_frame(anim_name, texture)

	animated_sprite.sprite_frames = frames

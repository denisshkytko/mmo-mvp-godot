extends Node2D
class_name AnimatedAbilityEffect

@export var autoplay: bool = true
@export var free_on_finish: bool = true
@export var animation_name: StringName = &"default"

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D as AnimatedSprite2D

func _ready() -> void:
	if _anim == null:
		return
	if not _anim.animation_finished.is_connected(_on_animation_finished):
		_anim.animation_finished.connect(_on_animation_finished)
	if autoplay:
		_anim.play(animation_name)

func play_once(name: StringName = &"default") -> void:
	animation_name = name
	if _anim == null:
		return
	_anim.play(animation_name)

func _on_animation_finished() -> void:
	if free_on_finish:
		queue_free()

extends Node2D
class_name FloatingDamageNumber

@export var float_distance: float = 40.0
@export var lifetime_sec: float = 1.55
@export var start_scale: Vector2 = Vector2(1.0, 1.0)
@export var end_scale: Vector2 = Vector2(1.07, 1.07)

@onready var value_label: Label = $Label
var _move_dir: Vector2 = Vector2(0.0, -1.0)

func show_value(value: Variant, color: Color, move_dir: Vector2 = Vector2(0.0, -1.0)) -> void:
	if value_label == null:
		return
	if value is String:
		value_label.text = String(value)
	elif value is StringName:
		value_label.text = String(value)
	else:
		value_label.text = str(max(0, int(value)))
	value_label.modulate = color
	_move_dir = move_dir.normalized() if move_dir.length() > 0.001 else Vector2(0.0, -1.0)
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	scale = start_scale
	_play_anim()

func _play_anim() -> void:
	var duration: float = maxf(0.05, lifetime_sec)
	var target_pos: Vector2 = position + (_move_dir * float_distance)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", end_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

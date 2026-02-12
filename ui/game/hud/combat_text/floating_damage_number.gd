extends Node2D
class_name FloatingDamageNumber

@export var float_distance: float = 30.0
@export var lifetime_sec: float = 0.55
@export var start_scale: Vector2 = Vector2(1.0, 1.0)
@export var end_scale: Vector2 = Vector2(1.07, 1.07)

@onready var value_label: Label = $Label

func show_value(value: int, color: Color) -> void:
	if value_label == null:
		return
	value_label.text = str(max(0, value))
	value_label.modulate = color
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	scale = start_scale
	_play_anim()

func _play_anim() -> void:
	var duration := max(0.05, lifetime_sec)
	var target_pos := position + Vector2(0.0, -float_distance)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", end_scale, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

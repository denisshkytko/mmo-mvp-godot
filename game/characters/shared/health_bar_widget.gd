extends Node2D
class_name HealthBarWidget

@onready var hp_back: ColorRect = $HpBack
@onready var hp_fill: ColorRect = $HpFill

var _default_profile: Dictionary = {}

func _ready() -> void:
	_default_profile = {
		"size": _rect_size(hp_back),
		"back_color": hp_back.color,
		"fill_color": hp_fill.color,
	}
	set_progress01(1.0)

func set_progress01(progress: float) -> void:
	var p: float = clamp(progress, 0.0, 1.0)
	if hp_back == null or hp_fill == null:
		return
	hp_fill.offset_left = hp_back.offset_left
	hp_fill.offset_top = hp_back.offset_top
	hp_fill.offset_bottom = hp_back.offset_bottom
	var full_w: float = hp_back.offset_right - hp_back.offset_left
	hp_fill.offset_right = hp_fill.offset_left + (full_w * p)

func apply_visual_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		restore_default_visual_profile()
		return
	var size_v: Variant = profile.get("size", _default_profile.get("size", _rect_size(hp_back)))
	if size_v is Vector2:
		_set_rect_size_keep_center(hp_back, size_v as Vector2)
		_set_rect_size_keep_center(hp_fill, size_v as Vector2)
	var back_color_v: Variant = profile.get("back_color", _default_profile.get("back_color", hp_back.color))
	if back_color_v is Color:
		hp_back.color = back_color_v as Color
	var fill_color_v: Variant = profile.get("fill_color", _default_profile.get("fill_color", hp_fill.color))
	if fill_color_v is Color:
		hp_fill.color = fill_color_v as Color

func restore_default_visual_profile() -> void:
	apply_visual_profile(_default_profile)

func _set_rect_size_keep_center(rect: Control, size: Vector2) -> void:
	var w: float = max(1.0, size.x)
	var h: float = max(1.0, size.y)
	var cx: float = (rect.offset_left + rect.offset_right) * 0.5
	var cy: float = (rect.offset_top + rect.offset_bottom) * 0.5
	rect.offset_left = cx - (w * 0.5)
	rect.offset_right = cx + (w * 0.5)
	rect.offset_top = cy - (h * 0.5)
	rect.offset_bottom = cy + (h * 0.5)

func _rect_size(rect: Control) -> Vector2:
	return Vector2(rect.offset_right - rect.offset_left, rect.offset_bottom - rect.offset_top)

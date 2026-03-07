extends Node2D
class_name CastBarWidget

@onready var icon: TextureRect = $Icon
@onready var bar_back: ColorRect = $BarBack
@onready var bar_fill: ColorRect = $BarBack/BarFill

var _default_profile: Dictionary = {}

func _ready() -> void:
	_default_profile = {
		"size": _rect_size(bar_back),
		"icon_size": _rect_size(icon),
		"back_color": bar_back.color,
		"fill_color": bar_fill.color,
		"icon_visible": icon.visible,
	}

func set_cast_visible(v: bool) -> void:
	visible = v

func set_progress01(progress: float) -> void:
	var p: float = clamp(progress, 0.0, 1.0)
	bar_fill.anchor_right = p

func set_icon_texture(tex: Texture2D) -> void:
	icon.texture = tex

func apply_visual_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		restore_default_visual_profile()
		return

	var size_v: Variant = profile.get("size", _default_profile.get("size", _rect_size(bar_back)))
	if size_v is Vector2:
		_set_rect_size_keep_center(bar_back, size_v as Vector2)

	var icon_size_v: Variant = profile.get("icon_size", _default_profile.get("icon_size", _rect_size(icon)))
	if icon_size_v is Vector2:
		_set_rect_size_keep_center(icon, icon_size_v as Vector2)

	var back_color_v: Variant = profile.get("back_color", _default_profile.get("back_color", bar_back.color))
	if back_color_v is Color:
		bar_back.color = back_color_v as Color

	var fill_color_v: Variant = profile.get("fill_color", _default_profile.get("fill_color", bar_fill.color))
	if fill_color_v is Color:
		bar_fill.color = fill_color_v as Color

	var icon_visible_v: Variant = profile.get("icon_visible", _default_profile.get("icon_visible", true))
	if icon_visible_v is bool:
		icon.visible = icon_visible_v

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

extends Node2D
class_name CastBarWidget

@onready var icon: TextureRect = $Icon
@onready var progress: ProgressBar = $Progress

var _default_profile: Dictionary = {}

func _ready() -> void:
	_default_profile = {
		"size": _rect_size(progress),
		"icon_size": _rect_size(icon),
		"back_style": progress.get("theme_override_styles/background"),
		"fill_style": progress.get("theme_override_styles/fill"),
		"icon_visible": icon.visible,
	}

func set_cast_visible(v: bool) -> void:
	visible = v

func set_progress01(progress01: float) -> void:
	if progress == null:
		return
	progress.value = clamp(progress01, 0.0, 1.0) * 100.0

func set_icon_texture(tex: Texture2D) -> void:
	icon.texture = tex

func apply_visual_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		restore_default_visual_profile()
		return

	var size_v: Variant = profile.get("size", _default_profile.get("size", _rect_size(progress)))
	if size_v is Vector2:
		_set_rect_size_keep_center(progress, size_v as Vector2)

	var icon_size_v: Variant = profile.get("icon_size", _default_profile.get("icon_size", _rect_size(icon)))
	if icon_size_v is Vector2:
		_set_rect_size_keep_center(icon, icon_size_v as Vector2)

	var back_color_v: Variant = profile.get("back_color", null)
	if back_color_v is Color:
		var back := StyleBoxFlat.new()
		back.bg_color = back_color_v as Color
		progress.add_theme_stylebox_override("background", back)

	var fill_color_v: Variant = profile.get("fill_color", null)
	if fill_color_v is Color:
		var fill := StyleBoxFlat.new()
		fill.bg_color = fill_color_v as Color
		progress.add_theme_stylebox_override("fill", fill)

	var icon_visible_v: Variant = profile.get("icon_visible", _default_profile.get("icon_visible", true))
	if icon_visible_v is bool:
		icon.visible = icon_visible_v

func restore_default_visual_profile() -> void:
	var size_v: Variant = _default_profile.get("size", _rect_size(progress))
	if size_v is Vector2:
		_set_rect_size_keep_center(progress, size_v as Vector2)
	var icon_size_v: Variant = _default_profile.get("icon_size", _rect_size(icon))
	if icon_size_v is Vector2:
		_set_rect_size_keep_center(icon, icon_size_v as Vector2)

	var back_style_v: Variant = _default_profile.get("back_style", null)
	if back_style_v is StyleBox:
		progress.add_theme_stylebox_override("background", (back_style_v as StyleBox).duplicate(true))
	var fill_style_v: Variant = _default_profile.get("fill_style", null)
	if fill_style_v is StyleBox:
		progress.add_theme_stylebox_override("fill", (fill_style_v as StyleBox).duplicate(true))

	var icon_visible_v: Variant = _default_profile.get("icon_visible", true)
	if icon_visible_v is bool:
		icon.visible = icon_visible_v

func get_visual_size() -> Vector2:
	return _rect_size(progress)

func get_icon_visual_size() -> Vector2:
	return _rect_size(icon)

func is_icon_visual_visible() -> bool:
	return icon.visible

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

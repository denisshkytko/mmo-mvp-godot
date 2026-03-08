extends Node2D
class_name HealthBarWidget

@onready var progress: ProgressBar = $Progress

@export_range(0.0, 128.0, 1.0) var corner_radius: float = 0.0
@export var outline_enabled: bool = false
@export_range(0, 32, 1) var outline_width: int = 0
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var _default_profile: Dictionary = {}

func _ready() -> void:
	_default_profile = {
		"size": _rect_size(progress),
		"back_style": progress.get("theme_override_styles/background"),
		"fill_style": progress.get("theme_override_styles/fill"),
	}
	_apply_shape_settings()
	set_progress01(1.0)

func set_progress01(progress01: float) -> void:
	if progress == null:
		return
	progress.value = clamp(progress01, 0.0, 1.0) * 100.0

func apply_visual_profile(profile: Dictionary) -> void:
	if progress == null:
		return
	if profile.is_empty():
		restore_default_visual_profile()
		return

	var size_v: Variant = profile.get("size", _default_profile.get("size", _rect_size(progress)))
	if size_v is Vector2:
		_set_rect_size_keep_center(progress, size_v as Vector2)

	var profile_corner_radius_v: Variant = profile.get("corner_radius", corner_radius)
	if profile_corner_radius_v is float:
		corner_radius = profile_corner_radius_v as float
	elif profile_corner_radius_v is int:
		corner_radius = float(profile_corner_radius_v)

	var profile_outline_enabled_v: Variant = profile.get("outline_enabled", outline_enabled)
	if profile_outline_enabled_v is bool:
		outline_enabled = profile_outline_enabled_v as bool

	var profile_outline_width_v: Variant = profile.get("outline_width", outline_width)
	if profile_outline_width_v is int:
		outline_width = profile_outline_width_v as int
	elif profile_outline_width_v is float:
		outline_width = int(round(profile_outline_width_v as float))

	var profile_outline_color_v: Variant = profile.get("outline_color", outline_color)
	if profile_outline_color_v is Color:
		outline_color = profile_outline_color_v as Color

	var back_color_v: Variant = profile.get("back_color", null)
	var fill_color_v: Variant = profile.get("fill_color", null)
	_apply_shape_settings(back_color_v, fill_color_v)

func restore_default_visual_profile() -> void:
	if progress == null:
		return
	var size_v: Variant = _default_profile.get("size", _rect_size(progress))
	if size_v is Vector2:
		_set_rect_size_keep_center(progress, size_v as Vector2)
	var back_style_v: Variant = _default_profile.get("back_style", null)
	if back_style_v is StyleBox:
		progress.add_theme_stylebox_override("background", (back_style_v as StyleBox).duplicate(true))
	var fill_style_v: Variant = _default_profile.get("fill_style", null)
	if fill_style_v is StyleBox:
		progress.add_theme_stylebox_override("fill", (fill_style_v as StyleBox).duplicate(true))

func get_visual_size() -> Vector2:
	return _rect_size(progress)

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

func set_fill_color(color: Color) -> void:
	if progress == null:
		return
	_apply_shape_settings(null, color)

func _apply_shape_settings(back_color_override: Variant = null, fill_color_override: Variant = null) -> void:
	if progress == null:
		return
	var back := _resolve_stylebox_flat("background")
	if back == null:
		back = StyleBoxFlat.new()
	if back_color_override is Color:
		back.bg_color = back_color_override as Color
	_apply_style_shape(back)
	progress.add_theme_stylebox_override("background", back)

	var fill := _resolve_stylebox_flat("fill")
	if fill == null:
		fill = StyleBoxFlat.new()
	if fill_color_override is Color:
		fill.bg_color = fill_color_override as Color
	_apply_style_shape(fill)
	progress.add_theme_stylebox_override("fill", fill)

func _resolve_stylebox_flat(slot: StringName) -> StyleBoxFlat:
	if progress == null:
		return null
	var current_v: Variant = progress.get("theme_override_styles/%s" % slot)
	if current_v is StyleBoxFlat:
		return (current_v as StyleBoxFlat).duplicate(true)
	if current_v is StyleBox:
		var fallback := StyleBoxFlat.new()
		if slot == &"background":
			fallback.bg_color = Color(0.0, 0.0, 0.0, 0.3)
		else:
			fallback.bg_color = Color(1.0, 1.0, 1.0, 1.0)
		return fallback
	return StyleBoxFlat.new()

func _apply_style_shape(style: StyleBoxFlat) -> void:
	var radius_i: int = int(max(0.0, corner_radius))
	style.corner_radius_top_left = radius_i
	style.corner_radius_top_right = radius_i
	style.corner_radius_bottom_left = radius_i
	style.corner_radius_bottom_right = radius_i
	if outline_enabled:
		var w: int = max(0, outline_width)
		style.border_width_left = w
		style.border_width_top = w
		style.border_width_right = w
		style.border_width_bottom = w
		style.border_color = outline_color
	else:
		style.border_width_left = 0
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0

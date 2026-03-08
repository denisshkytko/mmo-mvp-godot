extends Node2D
class_name OverlayBarsWidget

@onready var cast_bar: CastBarWidget = $CastBar
@onready var name_label: Label = $NameLabel
@onready var hp_bar: HealthBarWidget = $HealthBar

@export var show_name: bool = false
@export var display_name: String = ""
@export var name_text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var name_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export_range(0, 8, 1) var name_outline_size: int = 3
@export_range(0.0, 64.0, 1.0) var name_cast_spacing: float = 6.0
@export var cast_bar_base_y: float = -42.0

func _ready() -> void:
	_refresh_name_visuals()
	_refresh_layout()

func set_show_name(v: bool) -> void:
	show_name = v
	_refresh_layout()

func set_display_name(v: String) -> void:
	display_name = v
	_refresh_name_visuals()

func set_name_visual(text_color: Color, outline_color: Color, outline_size: int) -> void:
	name_text_color = text_color
	name_outline_color = outline_color
	name_outline_size = max(0, outline_size)
	_refresh_name_visuals()

func get_hp_bar_widget() -> HealthBarWidget:
	return hp_bar

func get_cast_bar_widget() -> CastBarWidget:
	return cast_bar

func _refresh_layout() -> void:
	if name_label == null or cast_bar == null:
		return
	name_label.visible = show_name
	var hidden_shift: float = _measure_name_slot_height() + max(0.0, name_cast_spacing)
	cast_bar.position.y = cast_bar_base_y if show_name else cast_bar_base_y + hidden_shift
	_refresh_name_visuals()

func _refresh_name_visuals() -> void:
	if name_label == null:
		return
	name_label.text = display_name
	name_label.modulate = name_text_color
	name_label.add_theme_color_override("font_color", name_text_color)
	name_label.add_theme_color_override("font_outline_color", name_outline_color)
	name_label.add_theme_constant_override("outline_size", max(0, name_outline_size))


func _measure_name_slot_height() -> float:
	if name_label == null:
		return 0.0
	var h: float = name_label.size.y
	if h <= 0.001:
		h = max(0.0, name_label.offset_bottom - name_label.offset_top)
	return max(0.0, h)

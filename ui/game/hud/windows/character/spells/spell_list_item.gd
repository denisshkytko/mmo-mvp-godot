extends HBoxContainer

signal name_clicked(ability_id: String)
signal icon_clicked(ability_id: String)

var ability_id: String = ""
var ability_type: String = ""

@onready var icon_button: Button = $IconBtn
@onready var icon_rect: TextureRect = $IconBtn/Icon
@onready var name_button: LinkButton = $NameBtn

func _ready() -> void:
	if name_button != null and not name_button.pressed.is_connected(_on_name_pressed):
		name_button.pressed.connect(_on_name_pressed)
	if name_button != null:
		if name_button.has_method("set_text_overrun_behavior"):
			name_button.call("set_text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
	if icon_button != null and not icon_button.pressed.is_connected(_on_icon_pressed):
		icon_button.pressed.connect(_on_icon_pressed)

func set_data(definition: AbilityDefinition, learned_rank: int) -> void:
	if definition == null:
		return
	ability_id = definition.id
	ability_type = String(definition.ability_type)
	if icon_rect != null:
		icon_rect.texture = definition.icon
	if name_button != null:
		name_button.text = tr("ability.common.level_short_with_name").format({
			"name": definition.get_display_name(),
			"level": learned_rank,
		})

func set_selected(is_selected: bool) -> void:
	if is_selected:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		if name_button != null:
			name_button.add_theme_color_override("font_color", Color("8dff8d"))
			name_button.add_theme_color_override("font_hover_color", Color("aaffaa"))
	else:
		modulate = Color(0.82, 0.82, 0.82, 1.0)
		if name_button != null:
			name_button.remove_theme_color_override("font_color")
			name_button.remove_theme_color_override("font_hover_color")

func _on_name_pressed() -> void:
	emit_signal("name_clicked", ability_id)

func _on_icon_pressed() -> void:
	emit_signal("icon_clicked", ability_id)

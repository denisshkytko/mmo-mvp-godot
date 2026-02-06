extends HBoxContainer

signal clicked(ability_id: String)

var ability_id: String = ""

@onready var icon_rect: TextureRect = $Icon
@onready var name_button: LinkButton = $NameBtn

func _ready() -> void:
	if name_button != null and not name_button.pressed.is_connected(_on_pressed):
		name_button.pressed.connect(_on_pressed)

func set_data(definition: AbilityDefinition, learned_rank: int) -> void:
	if definition == null:
		return
	ability_id = definition.id
	if icon_rect != null:
		icon_rect.texture = definition.icon
	if name_button != null:
		name_button.text = "%s (R%d)" % [definition.get_display_name(), learned_rank]

func set_selected(is_selected: bool) -> void:
	modulate = Color(1, 1, 1, 1) if is_selected else Color(0.85, 0.85, 0.85, 1)

func _on_pressed() -> void:
	emit_signal("clicked", ability_id)

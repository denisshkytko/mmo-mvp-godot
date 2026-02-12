extends Control
class_name BuffAuraFlyout

@export var slot_index: int = 0

signal subslot_pressed(slot_index: int, sub_index: int)

@onready var slots_vbox: VBoxContainer = $SlotsVBox
var _ref_size: Vector2 = Vector2(34, 34)
var _spacing: float = 6.0

func _ready() -> void:
	_refresh_layout()

func apply_reference_size(ref_size: Vector2, spacing: float) -> void:
	_ref_size = ref_size
	_spacing = spacing
	_refresh_layout()

func set_entries(ability_ids: Array[String], ability_db: AbilityDatabase) -> void:
	if slots_vbox == null:
		return
	for child in slots_vbox.get_children():
		child.queue_free()
	for i in range(ability_ids.size()):
		var ability_id: String = ability_ids[i]
		var btn := TextureButton.new()
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = _ref_size
		btn.pressed.connect(_on_subslot_pressed.bind(i))
		if ability_db != null:
			var def: AbilityDefinition = ability_db.get_ability(ability_id)
			if def != null:
				btn.texture_normal = def.icon
				btn.texture_pressed = def.icon
		btn.set_meta("ability_id", ability_id)
		slots_vbox.add_child(btn)
	_refresh_layout()

func _on_subslot_pressed(sub_index: int) -> void:
	emit_signal("subslot_pressed", slot_index, sub_index)

func _refresh_layout() -> void:
	if slots_vbox == null:
		return
	slots_vbox.add_theme_constant_override("separation", int(_spacing))
	var slot_count := slots_vbox.get_child_count()
	var slot_height := _ref_size.y * slot_count
	var total_spacing: float = _spacing * float(max(slot_count - 1, 0))
	custom_minimum_size = Vector2(_ref_size.x, slot_height + total_spacing)

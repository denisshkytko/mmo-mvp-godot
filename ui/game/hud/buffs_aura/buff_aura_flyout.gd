extends Control
class_name BuffAuraFlyout

@export var slot_index: int = 0

signal subslot_pressed(slot_index: int, sub_index: int)

@onready var slots_vbox: VBoxContainer = $SlotsVBox

func _ready() -> void:
	_connect_subslots()

func apply_reference_size(ref_size: Vector2, spacing: float) -> void:
	if slots_vbox == null:
		return
	var slot_count := slots_vbox.get_child_count()
	var slot_height := ref_size.y * slot_count
	var total_spacing: float = spacing * float(max(slot_count - 1, 0))
	custom_minimum_size = Vector2(ref_size.x, slot_height + total_spacing)
	var buttons: Array = slots_vbox.get_children()
	for btn in buttons:
		var typed := btn as TextureButton
		if typed == null:
			continue
		typed.custom_minimum_size = ref_size

func _connect_subslots() -> void:
	if slots_vbox == null:
		return
	var buttons: Array = slots_vbox.get_children()
	for i in range(buttons.size()):
		var btn := buttons[i] as TextureButton
		if btn == null:
			continue
		btn.pressed.connect(_on_subslot_pressed.bind(i))

func _on_subslot_pressed(sub_index: int) -> void:
	emit_signal("subslot_pressed", slot_index, sub_index)

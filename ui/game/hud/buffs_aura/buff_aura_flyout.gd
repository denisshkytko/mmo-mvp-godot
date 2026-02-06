extends Control
class_name BuffAuraFlyout

@export var slot_index: int = 0

signal subslot_pressed(slot_index: int, sub_index: int)

@onready var slots_vbox: VBoxContainer = $SlotsVBox

func _ready() -> void:
	_connect_subslots()

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

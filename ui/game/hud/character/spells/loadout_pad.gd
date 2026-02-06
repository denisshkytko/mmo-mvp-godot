extends Control

signal slot_pressed(slot_index: int)

@onready var slot0_btn: TextureButton = $LoadoutPad/Slot0Btn
@onready var slot1_btn: TextureButton = $LoadoutPad/Slot1Btn
@onready var slot2_btn: TextureButton = $LoadoutPad/Slot2Btn
@onready var slot3_btn: TextureButton = $LoadoutPad/Slot3Btn
@onready var slot4_btn: TextureButton = $LoadoutPad/Slot4Btn

var _buttons: Array[TextureButton] = []

func _ready() -> void:
	_buttons = [slot0_btn, slot1_btn, slot2_btn, slot3_btn, slot4_btn]
	for i in range(_buttons.size()):
		var btn := _buttons[i]
		if btn == null:
			continue
		if not btn.pressed.is_connected(_on_slot_pressed):
			btn.pressed.connect(_on_slot_pressed.bind(i))

func refresh_icons(spellbook: PlayerSpellbook, ability_db: AbilityDatabase) -> void:
	if spellbook == null:
		return
	for i in range(_buttons.size()):
		var btn := _buttons[i]
		if btn == null:
			continue
		var icon := btn.get_node_or_null("Icon") as TextureRect
		var ability_id := ""
		if i < spellbook.loadout_slots.size():
			ability_id = spellbook.loadout_slots[i]
		if icon == null:
			continue
		if ability_id == "" or ability_db == null:
			icon.texture = null
			continue
		var def := ability_db.get_ability(ability_id)
		icon.texture = def.icon if def != null else null

func _on_slot_pressed(slot_index: int) -> void:
	emit_signal("slot_pressed", slot_index)

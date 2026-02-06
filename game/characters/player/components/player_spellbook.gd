extends Node
class_name PlayerSpellbook

signal spellbook_changed

var learned_ranks: Dictionary = {}
var loadout_slots: Array[String] = ["", "", "", "", ""]

func setup(_player: Player) -> void:
	_ensure_slots()

func _ready() -> void:
	_ensure_slots()

func _ensure_slots() -> void:
	if loadout_slots.size() < 5:
		while loadout_slots.size() < 5:
			loadout_slots.append("")
	elif loadout_slots.size() > 5:
		loadout_slots.resize(5)

func assign_ability_to_slot(ability_id: String, slot_index: int) -> void:
	if ability_id == "":
		return
	if slot_index < 0 or slot_index >= loadout_slots.size():
		return
	for i in range(loadout_slots.size()):
		if loadout_slots[i] == ability_id:
			loadout_slots[i] = ""
	loadout_slots[slot_index] = ability_id
	emit_signal("spellbook_changed")

func learn_next_rank(ability_id: String, max_rank: int) -> int:
	if ability_id == "" or max_rank <= 0:
		return int(learned_ranks.get(ability_id, 0))
	var current := int(learned_ranks.get(ability_id, 0))
	if current >= max_rank:
		return current
	current += 1
	learned_ranks[ability_id] = current
	emit_signal("spellbook_changed")
	return current

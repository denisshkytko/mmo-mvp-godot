extends Node
class_name PlayerSpellbook

signal spellbook_changed

var learned_ranks: Dictionary = {}
var loadout_slots: Array[String] = ["", "", "", "", ""]
var aura_active: String = ""
var stance_active: String = ""
var buff_slots: Array[String] = [""]

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
	if buff_slots.size() < 1:
		while buff_slots.size() < 1:
			buff_slots.append("")
	elif buff_slots.size() > 1:
		buff_slots.resize(1)

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

func get_learned_abilities() -> Array[String]:
	var out: Array[String] = []
	for ability_id in learned_ranks.keys():
		var rank := int(learned_ranks.get(ability_id, 0))
		if rank > 0:
			out.append(String(ability_id))
	return out

func get_learned_by_type(type: String) -> Array[String]:
	var out: Array[String] = []
	var db := get_node_or_null("/root/AbilityDB")
	if db == null:
		return out
	for ability_id in get_learned_abilities():
		if not db.has_method("get_ability"):
			continue
		var def: AbilityDefinition = db.call("get_ability", ability_id)
		if def != null and def.ability_type == type:
			out.append(ability_id)
	return out

func assign_aura_active(ability_id: String) -> void:
	if not _can_assign_type(ability_id, "aura"):
		return
	aura_active = ability_id
	emit_signal("spellbook_changed")

func assign_stance_active(ability_id: String) -> void:
	if not _can_assign_type(ability_id, "stance"):
		return
	stance_active = ability_id
	emit_signal("spellbook_changed")

func assign_buff_to_slot(ability_id: String, slot_idx: int) -> void:
	if not _can_assign_type(ability_id, "buff"):
		return
	if slot_idx < 0 or slot_idx >= buff_slots.size():
		return
	for i in range(buff_slots.size()):
		if buff_slots[i] == ability_id:
			buff_slots[i] = ""
	buff_slots[slot_idx] = ability_id
	emit_signal("spellbook_changed")

func get_buff_candidates_for_flyout() -> Array[String]:
	var known_buffs := get_learned_by_type("buff")
	var excluded: Dictionary = {}
	for ability_id in buff_slots:
		if ability_id != "":
			excluded[ability_id] = true
	var out: Array[String] = []
	for ability_id in known_buffs:
		if not excluded.has(ability_id):
			out.append(ability_id)
	return out

func auto_place_on_first_learn(ability_id: String) -> void:
	var ability_type := ""
	var db := get_node_or_null("/root/AbilityDB")
	if db != null and db.has_method("get_ability"):
		var def: AbilityDefinition = db.call("get_ability", ability_id)
		if def != null:
			ability_type = def.ability_type
	match ability_type:
		"aura":
			if aura_active == "":
				aura_active = ability_id
		"stance":
			if stance_active == "":
				stance_active = ability_id
		"buff":
			for i in range(buff_slots.size()):
				if buff_slots[i] == "":
					buff_slots[i] = ability_id
					break

func learn_next_rank(ability_id: String, max_rank: int) -> int:
	if ability_id == "" or max_rank <= 0:
		return int(learned_ranks.get(ability_id, 0))
	var current := int(learned_ranks.get(ability_id, 0))
	if current >= max_rank:
		return current
	current += 1
	learned_ranks[ability_id] = current
	if current == 1:
		auto_place_on_first_learn(ability_id)
	emit_signal("spellbook_changed")
	return current

func _can_assign_type(ability_id: String, type: String) -> bool:
	if ability_id == "":
		return false
	if int(learned_ranks.get(ability_id, 0)) <= 0:
		return false
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return false
	var def: AbilityDefinition = db.call("get_ability", ability_id)
	return def != null and def.ability_type == type

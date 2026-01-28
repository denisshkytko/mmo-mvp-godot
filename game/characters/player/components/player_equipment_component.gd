extends Node
class_name PlayerEquipmentComponent

signal equipment_changed(snapshot: Dictionary)

const SLOT_IDS: Array[String] = [
	"head",
	"chest",
	"legs",
	"boots",
	"ring1",
	"neck",
	"shoulders",
	"cloak",
	"shirt",
	"bracers",
	"gloves",
	"ring2",
	"weapon_r",
	"weapon_l",
]

const ARMOR_SLOTS: Array[String] = [
	"head",
	"chest",
	"legs",
	"boots",
	"shoulders",
	"cloak",
	"shirt",
	"bracers",
	"gloves",
]

const ACCESSORY_SLOTS: Array[String] = [
	"neck",
	"ring",
]

var p: Player = null
var equipment_slots: Dictionary = {}

func setup(player: Player) -> void:
	p = player
	_reset_slots()

func _get_slot_item(slot_id: String) -> Dictionary:
	var v: Variant = equipment_slots.get(slot_id, null)
	if v is Dictionary:
		return v as Dictionary
	return {}

func _reset_slots() -> void:
	equipment_slots.clear()
	for slot_id in SLOT_IDS:
		equipment_slots[slot_id] = null

func get_equipment_snapshot() -> Dictionary:
	return equipment_slots.duplicate(true)

func apply_equipment_snapshot(snapshot: Dictionary) -> void:
	_reset_slots()
	if snapshot == null:
		_emit_changed(false)
		return
	for slot_id in SLOT_IDS:
		var v: Variant = snapshot.get(slot_id, null)
		if v is Dictionary:
			var d: Dictionary = v as Dictionary
			var id: String = String(d.get("id", ""))
			if id != "":
				equipment_slots[slot_id] = {"id": id, "count": 1}
			else:
				equipment_slots[slot_id] = null
		else:
			equipment_slots[slot_id] = null
	_emit_changed(false)

func get_preferred_slot_for_item(item_id: String) -> String:
	var meta := _get_item_meta(item_id)
	if meta.is_empty():
		return ""
	var typ: String = String(meta.get("type", "")).to_lower()
	if typ == "armor":
		var slot: String = String((meta.get("armor", {}) as Dictionary).get("slot", ""))
		return slot
	if typ == "accessory":
		var slot2: String = String((meta.get("accessory", {}) as Dictionary).get("slot", ""))
		if slot2 == "ring":
			if equipment_slots.get("ring1") == null:
				return "ring1"
			if equipment_slots.get("ring2") == null:
				return "ring2"
			return "ring1"
		return slot2
	if typ == "weapon":
		return "weapon_r"
	if typ == "offhand":
		return "weapon_l"
	return ""

func is_left_hand_blocked() -> bool:
	var right_item := _get_slot_item("weapon_r")
	if right_item.is_empty():
		return false
	var id: String = String(right_item.get("id", ""))
	if id == "":
		return false
	var meta := _get_item_meta(id)
	return _is_two_handed_weapon(meta)

func get_weapon_damage() -> int:
	var right_item := _get_slot_item("weapon_r")
	if right_item.is_empty():
		return 0
	var id: String = String(right_item.get("id", ""))
	if id == "":
		return 0
	var meta := _get_item_meta(id)
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	return int(w.get("damage", 0))

func get_weapon_damage_right() -> int:
	return get_weapon_damage()

func get_weapon_damage_left() -> int:
	if is_left_hand_blocked():
		return 0
	var left_item := _get_slot_item("weapon_l")
	if left_item.is_empty():
		return 0
	var id: String = String(left_item.get("id", ""))
	if id == "":
		return 0
	var meta := _get_item_meta(id)
	if String(meta.get("type", "")).to_lower() != "weapon":
		return 0
	if _is_two_handed_weapon(meta):
		return 0
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	if int(w.get("handed", 1)) != 1:
		return 0
	return int(w.get("damage", 0))

func get_weapon_attack_interval_right() -> float:
	var right_item := _get_slot_item("weapon_r")
	if right_item.is_empty():
		return 0.0
	var id: String = String(right_item.get("id", ""))
	if id == "":
		return 0.0
	var meta := _get_item_meta(id)
	if String(meta.get("type", "")).to_lower() != "weapon":
		return 0.0
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	return float(w.get("attack_interval", 1.0))

func get_weapon_attack_interval_left() -> float:
	if is_left_hand_blocked():
		return 0.0
	var left_item := _get_slot_item("weapon_l")
	if left_item.is_empty():
		return 0.0
	var id: String = String(left_item.get("id", ""))
	if id == "":
		return 0.0
	var meta := _get_item_meta(id)
	if String(meta.get("type", "")).to_lower() != "weapon":
		return 0.0
	if _is_two_handed_weapon(meta):
		return 0.0
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	if int(w.get("handed", 1)) != 1:
		return 0.0
	return float(w.get("attack_interval", 1.0))

func get_right_weapon_subtype() -> String:
	var right_item := _get_slot_item("weapon_r")
	if right_item.is_empty():
		return ""
	var id: String = String(right_item.get("id", ""))
	if id == "":
		return ""
	var meta := _get_item_meta(id)
	if String(meta.get("type", "")).to_lower() != "weapon":
		return ""
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	return String(w.get("subtype", "")).to_lower()

func is_two_handed_equipped() -> bool:
	var right_item := _get_slot_item("weapon_r")
	if right_item.is_empty():
		return false
	var id: String = String(right_item.get("id", ""))
	if id == "":
		return false
	var meta := _get_item_meta(id)
	return _is_two_handed_weapon(meta)

func has_left_weapon() -> bool:
	if is_left_hand_blocked():
		return false
	var left_item := _get_slot_item("weapon_l")
	if left_item.is_empty():
		return false
	var id: String = String(left_item.get("id", ""))
	if id == "":
		return false
	var meta := _get_item_meta(id)
	if String(meta.get("type", "")).to_lower() != "weapon":
		return false
	if _is_two_handed_weapon(meta):
		return false
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	return int(w.get("handed", 1)) == 1

func has_left_offhand_item() -> bool:
	if is_left_hand_blocked():
		return false
	var left_item := _get_slot_item("weapon_l")
	if left_item.is_empty():
		return false
	var id: String = String(left_item.get("id", ""))
	if id == "":
		return false
	var meta := _get_item_meta(id)
	return String(meta.get("type", "")).to_lower() == "offhand"

func try_equip_from_inventory_slot(inv_slot_index: int, target_slot_id: String = "") -> bool:
	if p == null or p.c_inv == null:
		return false
	var inventory: Inventory = p.c_inv.inventory
	if inventory == null:
		return false

	inventory.ensure_layout()
	if inv_slot_index < 0 or inv_slot_index >= inventory.slots.size():
		return false
	var v: Variant = inventory.slots[inv_slot_index]
	if v == null or not (v is Dictionary):
		return false
	var item: Dictionary = v as Dictionary
	var id: String = String(item.get("id", ""))
	if id == "":
		return false

	if target_slot_id == "":
		target_slot_id = get_preferred_slot_for_item(id)
	if target_slot_id == "":
		return false

	var meta := _get_item_meta(id)
	if meta.is_empty():
		return false

	if not _can_equip_in_slot(meta, target_slot_id):
		return false

	var prev_slots: Array = inventory.slots.duplicate(true)
	var prev_equip: Dictionary = equipment_slots.duplicate(true)

	inventory.slots[inv_slot_index] = null
	var new_item := {"id": id, "count": 1}

	if _is_two_handed_weapon(meta):
		if target_slot_id != "weapon_r":
			_restore_state(inventory, prev_slots, prev_equip)
			return false

		var old_right := _get_slot_item("weapon_r")
		var old_left := _get_slot_item("weapon_l")
		equipment_slots["weapon_r"] = new_item
		equipment_slots["weapon_l"] = null

		if not _place_in_inventory(old_right, inv_slot_index, inventory.slots):
			_restore_state(inventory, prev_slots, prev_equip)
			return false
		if not _place_in_inventory(old_left, -1, inventory.slots):
			_restore_state(inventory, prev_slots, prev_equip)
			return false
		_emit_changed(true)
		return true

	if target_slot_id == "weapon_l" and not _can_equip_left_hand(meta):
		_restore_state(inventory, prev_slots, prev_equip)
		return false

	var old_item := _get_slot_item(target_slot_id)
	equipment_slots[target_slot_id] = new_item
	if not old_item.is_empty():
		if not _place_in_inventory(old_item, inv_slot_index, inventory.slots):
			_restore_state(inventory, prev_slots, prev_equip)
			return false

	_emit_changed(true)
	return true

func try_unequip_to_inventory(slot_id: String, preferred_slot_index: int = -1) -> bool:
	if p == null or p.c_inv == null:
		return false
	var inventory: Inventory = p.c_inv.inventory
	if inventory == null:
		return false

	var item := _get_slot_item(slot_id)
	if item.is_empty():
		return false

	inventory.ensure_layout()
	var slots := inventory.slots
	var target := -1
	if preferred_slot_index >= 0 and preferred_slot_index < slots.size() and slots[preferred_slot_index] == null:
		target = preferred_slot_index
	else:
		for i in range(slots.size()):
			if slots[i] == null:
				target = i
				break
	if target == -1:
		return false

	slots[target] = item
	equipment_slots[slot_id] = null
	_emit_changed(true)
	return true

func _can_equip_in_slot(meta: Dictionary, target_slot_id: String) -> bool:
	var typ: String = String(meta.get("type", "")).to_lower()
	var class_id := ""
	if p != null:
		class_id = String(p.class_id)
	var allowed_types := Progression.get_allowed_weapon_types_for_class(class_id)
	if typ == "armor":
		var slot: String = String((meta.get("armor", {}) as Dictionary).get("slot", ""))
		var armor_class: String = String((meta.get("armor", {}) as Dictionary).get("class", "")).to_lower()
		var allowed_armor := Progression.get_allowed_armor_classes_for_class(class_id)
		if armor_class != "" and not allowed_armor.has(armor_class):
			return false
		return slot == target_slot_id
	if typ == "accessory":
		var slot2: String = String((meta.get("accessory", {}) as Dictionary).get("slot", ""))
		if slot2 == "ring":
			return target_slot_id == "ring1" or target_slot_id == "ring2"
		return slot2 == target_slot_id
	if typ == "weapon":
		var subtype := String((meta.get("weapon", {}) as Dictionary).get("subtype", ""))
		if target_slot_id == "weapon_r":
			return allowed_types.has(subtype)
		if target_slot_id == "weapon_l":
			if not ["warrior", "hunter", "shaman"].has(class_id):
				return false
			if _is_two_handed_weapon(meta):
				return false
			if is_left_hand_blocked():
				return false
			return allowed_types.has(subtype)
		return false
	if typ == "offhand":
		if target_slot_id != "weapon_l":
			return false
		if is_left_hand_blocked():
			return false
		var slot_kind := String((meta.get("offhand", {}) as Dictionary).get("slot", "")).to_lower()
		if slot_kind == "shield":
			return allowed_types.has("shield")
		if slot_kind == "offhand":
			return allowed_types.has("offhand")
		return false
	return false

func _can_equip_left_hand(meta: Dictionary) -> bool:
	return _can_equip_in_slot(meta, "weapon_l")

func _is_two_handed_weapon(meta: Dictionary) -> bool:
	if String(meta.get("type", "")).to_lower() != "weapon":
		return false
	var w: Dictionary = meta.get("weapon", {}) as Dictionary
	return int(w.get("handed", 1)) == 2

func _place_in_inventory(item: Dictionary, preferred_index: int, slots: Array) -> bool:
	if item == null or item.is_empty():
		return true
	if preferred_index >= 0 and preferred_index < slots.size() and slots[preferred_index] == null:
		slots[preferred_index] = item
		return true
	for i in range(slots.size()):
		if slots[i] == null:
			slots[i] = item
			return true
	return false

func _restore_state(inventory: Inventory, prev_slots: Array, prev_equip: Dictionary) -> void:
	inventory.slots = prev_slots
	equipment_slots = prev_equip

func _get_item_meta(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item"):
		return db.call("get_item", item_id) as Dictionary
	return {}

func _emit_changed(request_save: bool) -> void:
	if p != null and p.c_stats != null:
		p.c_stats.request_recalculate(false)
	if request_save and p != null and p.has_method("_request_save"):
		p.call("_request_save", "equipment")
	emit_signal("equipment_changed", get_equipment_snapshot())

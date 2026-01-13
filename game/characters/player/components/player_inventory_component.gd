extends Node
class_name PlayerInventoryComponent

var p: Player = null
var inventory: Inventory = null

func setup(player: Player) -> void:
	p = player
	inventory = Inventory.new()

func add_gold(amount: int) -> void:
	if inventory == null:
		return
	inventory.add_gold(amount)

func add_item(item_id: String, amount: int) -> int:
	if inventory == null:
		return amount
	return inventory.add_item(item_id, amount)


func consume_item(item_id: String, amount: int = 1) -> int:
	# Removes up to `amount` items from the inventory. Returns how many were removed.
	if inventory == null:
		return 0
	return inventory.remove_item_by_id(item_id, amount)


# --- Bag equipment (4 slots) ---
func is_bag_item(item_id: String) -> bool:
	var db := get_node_or_null("/root/DataDB")
	if db != null and db.has_method("get_item"):
		var d: Dictionary = db.call("get_item", item_id) as Dictionary
		return String(d.get("type", "")) == "bag"
	return false


func try_equip_bag_from_inventory_slot(inv_slot_index: int, bag_index: int) -> bool:
	# Moves a bag item from an inventory slot into a bag equipment slot.
	if inventory == null:
		return false
	inventory.ensure_layout()
	if inv_slot_index < 0 or inv_slot_index >= inventory.slots.size():
		return false
	if bag_index < 0 or bag_index >= Inventory.BAG_EQUIP_COUNT:
		return false
	if inventory.bag_slots[bag_index] != null:
		return false

	var v: Variant = inventory.slots[inv_slot_index]
	if v == null or not (v is Dictionary):
		return false
	var d: Dictionary = v as Dictionary
	var id: String = String(d.get("id", ""))
	if id == "" or not is_bag_item(id):
		return false

	# Remove from inventory slot and equip.
	inventory.slots[inv_slot_index] = null
	if not inventory.equip_bag(bag_index, id):
		# rollback
		inventory.slots[inv_slot_index] = {"id": id, "count": 1}
		return false
	return true


func try_unequip_bag_to_inventory(bag_index: int, preferred_slot_index: int = -1) -> bool:
	# Unequips a bag (only if empty) and puts it into an inventory slot.
	if inventory == null:
		return false
	if bag_index < 0 or bag_index >= Inventory.BAG_EQUIP_COUNT:
		return false
	if inventory.bag_slots[bag_index] == null:
		return false
	if not inventory.can_unequip_bag(bag_index):
		return false

	# NOTE:
	# Unequipping a bag shrinks the slots array (layout). So we must decide the target slot
	# AFTER unequip, otherwise we may pick an index that no longer exists.
	var equipped: Dictionary = inventory.bag_slots[bag_index] as Dictionary
	var bag_id: String = String(equipped.get("id", ""))
	if bag_id == "":
		return false

	var bag_item: Dictionary = inventory.unequip_bag(bag_index)
	if bag_item.is_empty():
		return false

	# Find target in the *new* layout.
	var target: int = -1
	if preferred_slot_index >= 0 and preferred_slot_index < inventory.slots.size():
		if inventory.slots[preferred_slot_index] == null:
			target = preferred_slot_index
	if target == -1:
		# First free slot anywhere in the remaining inventory.
		for i in range(inventory.slots.size()):
			if inventory.slots[i] == null:
				target = i
				break

	if target == -1:
		# Rollback: put the bag back to its equip slot.
		inventory.equip_bag(bag_index, bag_id)
		return false

	inventory.slots[target] = bag_item
	return true


func try_move_or_swap_bag_slots(from_bag_index: int, to_bag_index: int) -> bool:
	# Reorder equipped bags (or swap) only if the bags are empty (their slot ranges contain no items).
	if inventory == null:
		return false
	inventory.ensure_layout()
	return inventory.move_or_swap_bag_slots(from_bag_index, to_bag_index)
func get_inventory_snapshot() -> Dictionary:
	if inventory == null:
		return {"gold": 0, "slots": [], "bag_slots": []}
	return {"gold": inventory.gold, "slots": inventory.slots, "bag_slots": inventory.bag_slots}


func apply_inventory_snapshot(snapshot: Dictionary) -> void:
	if inventory == null:
		inventory = Inventory.new()

	inventory.gold = int(snapshot.get("gold", 0))

	# bag slots (optional for backward compatibility)
	var bag_v: Variant = snapshot.get("bag_slots", [])
	if bag_v is Array:
		var bag_arr: Array = bag_v as Array
		inventory.bag_slots.resize(Inventory.BAG_EQUIP_COUNT)
		for bi in range(Inventory.BAG_EQUIP_COUNT):
			if bi < bag_arr.size():
				var bv: Variant = bag_arr[bi]
				if bv is Dictionary:
					var bd: Dictionary = bv as Dictionary
					var id_b: String = String(bd.get("id", ""))
					if id_b != "":
						inventory.bag_slots[bi] = {"id": id_b, "count": 1}
					else:
						inventory.bag_slots[bi] = null
				else:
					inventory.bag_slots[bi] = null
			else:
				inventory.bag_slots[bi] = null
	else:
		# no bags in snapshot
		inventory.bag_slots.resize(Inventory.BAG_EQUIP_COUNT)
		for bi2 in range(Inventory.BAG_EQUIP_COUNT):
			inventory.bag_slots[bi2] = null

	# Ensure the slot layout matches bags.
	inventory.ensure_layout()

	# slots
	var slots_v: Variant = snapshot.get("slots", [])
	if not (slots_v is Array):
		slots_v = []
	var slots_arr: Array = slots_v as Array

	# Resize and sanitize
	inventory.slots.resize(inventory.get_total_slot_count())
	for i in range(inventory.slots.size()):
		if i < slots_arr.size():
			var v: Variant = slots_arr[i]
			if v is Dictionary:
				var d: Dictionary = v as Dictionary
				var id: String = String(d.get("id", ""))
				if id != "":
					var count: int = int(d.get("count", 0))
					if count > 0:
						inventory.slots[i] = {"id": id, "count": count}
					else:
						inventory.slots[i] = null
				else:
					inventory.slots[i] = null
			else:
				inventory.slots[i] = null
		else:
			inventory.slots[i] = null

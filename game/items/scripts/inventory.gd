extends RefCounted
class_name Inventory

# Base (starter) bag slots - always present.
const SLOT_COUNT: int = 16

# Additional equipped bag slots (bag equipment) - expands total inventory.
const BAG_EQUIP_COUNT: int = 4

# Fallback stack size if item meta is missing.
const MAX_STACK_FALLBACK: int = 5

# slots[i] = null или Dictionary {"id": String, "count": int}
# This array stores ALL item slots: base bag (16) + extra slots from equipped bags.
var slots: Array[Variant] = []

# bag_slots[i] = null или Dictionary {"id": String, "count": int} for equipped bags only.
var bag_slots: Array[Variant] = []

var gold: int = 0


func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = null

	bag_slots.resize(BAG_EQUIP_COUNT)
	for j in range(BAG_EQUIP_COUNT):
		bag_slots[j] = null


func add_gold(amount: int) -> void:
	gold += amount
	if gold < 0:
		gold = 0


func get_total_slot_count() -> int:
	return SLOT_COUNT + _get_extra_slots_total()


func get_base_slot_range() -> Vector2i:
	# [start, end) in slot indices
	return Vector2i(0, SLOT_COUNT)


func get_bag_slot_range(bag_index: int) -> Vector2i:
	# Returns [start, end) indices of the extra slots that belong to a specific equipped bag.
	# If the bag is not equipped or has 0 slots, returns Vector2i(-1, -1).
	if bag_index < 0 or bag_index >= BAG_EQUIP_COUNT:
		return Vector2i(-1, -1)
	var start: int = SLOT_COUNT
	for i in range(BAG_EQUIP_COUNT):
		var s: int = _get_equipped_bag_slots_count(i)
		if i == bag_index:
			if s <= 0:
				return Vector2i(-1, -1)
			return Vector2i(start, start + s)
		start += s
	return Vector2i(-1, -1)


func is_slot_in_bag(bag_index: int, slot_index: int) -> bool:
	var r := get_bag_slot_range(bag_index)
	return r.x != -1 and slot_index >= r.x and slot_index < r.y


func ensure_layout() -> void:
	# Resizes slots array based on equipped bags. Safe to call often.
	var desired: int = get_total_slot_count()
	var current: int = slots.size()
	if desired == current:
		return
	if desired > current:
		var add_count: int = desired - current
		for _i in range(add_count):
			slots.append(null)
	else:
		# Only shrink if the truncated tail is empty. This should be guaranteed by higher level logic
		# (bags can't be unequipped if they still have items).
		for k in range(desired, current):
			if slots[k] != null:
				# Don't shrink if something is still there.
				return
		slots.resize(desired)


func can_unequip_bag(bag_index: int) -> bool:
	var r := get_bag_slot_range(bag_index)
	if r.x == -1:
		return false
	for i in range(r.x, r.y):
		if i < slots.size() and slots[i] != null:
			return false
	return true


func equip_bag(bag_index: int, bag_item_id: String) -> bool:
	if bag_index < 0 or bag_index >= BAG_EQUIP_COUNT:
		return false
	if bag_item_id == "":
		return false
	if bag_slots[bag_index] != null:
		return false
	# store equipped bag item meta
	bag_slots[bag_index] = {"id": bag_item_id, "count": 1}
	ensure_layout()
	return true


func unequip_bag(bag_index: int) -> Dictionary:
	# Returns the unequipped bag item dictionary (or empty dict).
	if bag_index < 0 or bag_index >= BAG_EQUIP_COUNT:
		return {}
	if bag_slots[bag_index] == null:
		return {}
	if not can_unequip_bag(bag_index):
		return {}
	var bag_item: Dictionary = bag_slots[bag_index] as Dictionary
	bag_slots[bag_index] = null
	ensure_layout()
	return bag_item


func find_first_free_slot_excluding_range(exclude_from: int, exclude_to: int) -> int:
	# Finds the first empty slot outside [exclude_from, exclude_to).
	# Returns -1 if not found.
	for i in range(slots.size()):
		if i >= exclude_from and i < exclude_to:
			continue
		if slots[i] == null:
			return i
	return -1


func add_item(item_id: String, amount: int) -> int:
	if item_id == "" or amount <= 0:
		return amount

	ensure_layout()

	var max_stack: int = _get_stack_max(item_id)
	var remaining: int = amount

	# 1) Достакаем существующие стаки
	for i in range(slots.size()):
		if remaining <= 0:
			break
		var slot: Variant = slots[i]
		if slot == null:
			continue
		if not (slot is Dictionary):
			continue
		if slot.get("id", "") == item_id:
			var count: int = int(slot.get("count", 0))
			var space: int = max_stack - count
			if space > 0:
				var to_add: int = min(space, remaining)
				slot["count"] = count + to_add
				remaining -= to_add
				slots[i] = slot

	# 2) Заполняем пустые слоты
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i] != null:
			continue
		var to_add2: int = min(max_stack, remaining)
		slots[i] = {"id": item_id, "count": to_add2}
		remaining -= to_add2

	return remaining


func remove_item_by_id(item_id: String, amount: int = 1) -> int:
	# Removes up to `amount` items by id across all stacks.
	# Returns how many items were actually removed.
	if item_id == "" or amount <= 0:
		return 0
	ensure_layout()
	var remaining: int = amount
	for i in range(slots.size()):
		if remaining <= 0:
			break
		var v: Variant = slots[i]
		if v == null or not (v is Dictionary):
			continue
		var d: Dictionary = v as Dictionary
		if String(d.get("id", "")) != item_id:
			continue
		var c: int = int(d.get("count", 0))
		if c <= 0:
			slots[i] = null
			continue
		var take: int = min(c, remaining)
		c -= take
		remaining -= take
		if c <= 0:
			slots[i] = null
		else:
			d["count"] = c
			slots[i] = d
	return amount - remaining


func _get_extra_slots_total() -> int:
	var total: int = 0
	for i in range(BAG_EQUIP_COUNT):
		total += _get_equipped_bag_slots_count(i)
	return total


func _get_equipped_bag_slots_count(bag_index: int) -> int:
	if bag_index < 0 or bag_index >= BAG_EQUIP_COUNT:
		return 0
	var v: Variant = bag_slots[bag_index]
	if v == null:
		return 0
	if not (v is Dictionary):
		return 0
	var id: String = String((v as Dictionary).get("id", ""))
	if id == "":
		return 0
	return _get_bag_slots_count(id)


func _get_bag_slots_count(item_id: String) -> int:
	# Pull bag slot sizes from DataDB if possible.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var db := tree.root.get_node_or_null("/root/DataDB")
		if db != null and db.has_method("get_item"):
			var d: Dictionary = db.call("get_item", item_id) as Dictionary
			if d.has("bag") and (d.get("bag") is Dictionary):
				var bag_d: Dictionary = d.get("bag") as Dictionary
				return max(0, int(bag_d.get("slots", 0)))
	return 0



func move_or_swap_bag_slots(from_index: int, to_index: int) -> bool:
	# Move a bag between equipment slots, or swap two bags.
	# Only allowed if involved bags are empty (their slot ranges contain no items).
	if from_index == to_index:
		return false
	if from_index < 0 or from_index >= BAG_EQUIP_COUNT:
		return false
	if to_index < 0 or to_index >= BAG_EQUIP_COUNT:
		return false
	if bag_slots[from_index] == null:
		return false
	# Both sides must be empty in terms of contained inventory slots.
	if not can_unequip_bag(from_index):
		return false
	if bag_slots[to_index] != null and not can_unequip_bag(to_index):
		return false
	var tmp: Variant = bag_slots[to_index]
	bag_slots[to_index] = bag_slots[from_index]
	bag_slots[from_index] = tmp
	ensure_layout()
	return true

func _get_stack_max(item_id: String) -> int:
	# Pull stack limits from DataDB if possible. This keeps inventory & loot
	# behavior in sync with the new item DB.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var db := tree.root.get_node_or_null("/root/DataDB")
		if db != null and db.has_method("get_item_stack_max"):
			return max(1, int(db.call("get_item_stack_max", item_id)))
	return MAX_STACK_FALLBACK

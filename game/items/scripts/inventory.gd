extends RefCounted
class_name Inventory

const SLOT_COUNT: int = 16

# Fallback stack size if item meta is missing.
const MAX_STACK_FALLBACK: int = 5

# slots[i] = null или Dictionary {"id": String, "count": int}
var slots: Array[Variant] = []
var gold: int = 0

func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = null

func add_gold(amount: int) -> void:
	gold += max(amount, 0)

func add_item(item_id: String, amount: int) -> int:
	# Возвращает сколько НЕ удалось положить (0 = всё влезло)
	if amount <= 0:
		return 0

	var remaining: int = amount

	var max_stack: int = _get_stack_max(item_id)

	# 1) Докладываем в существующие стаки
	for i in range(SLOT_COUNT):
		if remaining <= 0:
			break

		var slot_v: Variant = slots[i]
		if slot_v == null:
			continue

		var slot: Dictionary = slot_v as Dictionary
		if slot.get("id", "") == item_id:
			var count: int = int(slot.get("count", 0))
			var space: int = max_stack - count
			if space > 0:
				var to_add: int = min(space, remaining)
				slot["count"] = count + to_add
				remaining -= to_add
				slots[i] = slot

	# 2) Заполняем пустые слоты
	for i in range(SLOT_COUNT):
		if remaining <= 0:
			break

		if slots[i] != null:
			continue

		var to_add2: int = min(max_stack, remaining)
		var new_slot: Dictionary = {"id": item_id, "count": to_add2}
		slots[i] = new_slot
		remaining -= to_add2

	return remaining


func _get_stack_max(item_id: String) -> int:
	# Pull stack limits from DataDB if possible. This keeps inventory & loot
	# behavior in sync with the new item DB.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var db := tree.root.get_node_or_null("/root/DataDB")
		if db != null and db.has_method("get_item_stack_max"):
			return max(1, int(db.call("get_item_stack_max", item_id)))
	return MAX_STACK_FALLBACK

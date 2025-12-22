extends RefCounted
class_name Inventory

const SLOT_COUNT: int = 16
const MAX_STACK: int = 5

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
			var space: int = MAX_STACK - count
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

		var to_add2: int = min(MAX_STACK, remaining)
		var new_slot: Dictionary = {"id": item_id, "count": to_add2}
		slots[i] = new_slot
		remaining -= to_add2

	return remaining

func debug_dump() -> void:
	print("---- INVENTORY ----")
	print("Gold:", gold)
	for i in range(SLOT_COUNT):
		var slot_v: Variant = slots[i]
		if slot_v == null:
			print(i, ": empty")
		else:
			var slot: Dictionary = slot_v as Dictionary
			print(i, ": ", String(slot.get("id", "")), " x", int(slot.get("count", 0)))
	print("-------------------")

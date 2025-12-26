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

func get_inventory_snapshot() -> Dictionary:
	if inventory == null:
		return {"gold": 0, "slots": []}
	return {"gold": inventory.gold, "slots": inventory.slots}


func apply_inventory_snapshot(snapshot: Dictionary) -> void:
	if inventory == null:
		inventory = Inventory.new()

	inventory.gold = int(snapshot.get("gold", 0))

	# slots
	var slots_v: Variant = snapshot.get("slots", [])
	if not (slots_v is Array):
		slots_v = []

	var slots_arr: Array = slots_v as Array

	inventory.slots.resize(Inventory.SLOT_COUNT)
	for i in range(Inventory.SLOT_COUNT):
		if i < slots_arr.size():
			inventory.slots[i] = slots_arr[i]
		else:
			inventory.slots[i] = null

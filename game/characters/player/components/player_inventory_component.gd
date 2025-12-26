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

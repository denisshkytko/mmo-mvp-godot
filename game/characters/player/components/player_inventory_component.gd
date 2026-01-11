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
			var v: Variant = slots_arr[i]
			# Sanitize legacy loot/unknown items.
			if v is Dictionary:
				var d: Dictionary = v as Dictionary
				var id: String = String(d.get("id", ""))
				if id == "" or id == "loot_token":
					inventory.slots[i] = null
				else:
					# Drop items that are no longer in DataDB (old/removed).
					var db := get_node_or_null("/root/DataDB")
					if db != null and db.has_method("has_item") and not bool(db.call("has_item", id)):
						inventory.slots[i] = null
					else:
						inventory.slots[i] = d
			else:
				inventory.slots[i] = null
		else:
			inventory.slots[i] = null

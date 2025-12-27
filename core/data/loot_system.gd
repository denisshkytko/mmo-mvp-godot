extends Node

func generate_loot(table_id: String, _mob_level: int) -> Dictionary:
	if not has_node("/root/DataDB"):
		return {"gold": 0, "slots": []}

	var db := get_node("/root/DataDB")
	var table: Dictionary = db.get_loot_table(table_id)
	if table.is_empty():
		return {"gold": 0, "slots": []}

	var slots_to_generate: int = _roll_slot_count(table.get("slot_rolls", []))
	if slots_to_generate <= 0:
		return {"gold": 0, "slots": []}

	var slots: Array = []

	# Gold занимает 1 слот, если есть настройка gold
	var gold_cfg: Variant = table.get("gold", null)
	var has_gold: bool = (gold_cfg is Dictionary)
	if has_gold and slots_to_generate >= 1:
		var gcfg: Dictionary = gold_cfg as Dictionary
		var gold_min := int(gcfg.get("min", 0))
		var gold_max := int(gcfg.get("max", gold_min))
		var gold_amount := randi_range(gold_min, gold_max)
		if gold_amount > 0:
			slots.append({"type": "gold", "amount": gold_amount})
			slots_to_generate -= 1

	# Остальные слоты заполняем предметами
	var items: Array = table.get("items", [])
	for _i in range(slots_to_generate):
		var item_entry: Dictionary = _pick_item_entry(items)
		if item_entry.is_empty():
			break

		var id: String = String(item_entry.get("id", ""))
		if id == "":
			continue

		var min_c := int(item_entry.get("min", 1))
		var max_c := int(item_entry.get("max", min_c))
		var count := randi_range(min_c, max_c)

		slots.append({"type": "item", "id": id, "count": count})

	return {"gold": _sum_gold(slots), "slots": slots}


func _roll_slot_count(slot_rolls: Array) -> int:
	# slot_rolls: [{slots:int, chance:float}, ...]
	# если список пуст — дефолт 1 слот
	if slot_rolls.is_empty():
		return 1

	var total: float = 0.0
	for r in slot_rolls:
		if r is Dictionary:
			total += float((r as Dictionary).get("chance", 0.0))

	if total <= 0.0:
		return 1

	var roll := randf() * total
	var acc: float = 0.0
	for r in slot_rolls:
		if not (r is Dictionary):
			continue
		var d := r as Dictionary
		acc += float(d.get("chance", 0.0))
		if roll <= acc:
			return int(d.get("slots", 1))

	return int((slot_rolls[-1] as Dictionary).get("slots", 1))


func _pick_item_entry(items: Array) -> Dictionary:
	# items: [{id,min,max,weight}, ...]
	if items.is_empty():
		return {}

	var total: int = 0
	for e in items:
		if e is Dictionary:
			total += int((e as Dictionary).get("weight", 0))

	if total <= 0:
		return {}

	var roll := randi_range(1, total)
	var acc: int = 0
	for e in items:
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		acc += int(d.get("weight", 0))
		if roll <= acc:
			return d

	return items[0] as Dictionary


func _sum_gold(slots: Array) -> int:
	var g: int = 0
	for s in slots:
		if s is Dictionary:
			var d := s as Dictionary
			if String(d.get("type", "")) == "gold":
				g += int(d.get("amount", 0))
	return g

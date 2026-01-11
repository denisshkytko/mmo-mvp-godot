extends Node

const ITEMS_PATH := "res://core/data/json/items_db_1500_v6.json"
const MOBS_PATH := "res://core/data/json/mobs.json"

var items: Dictionary = {}
var mobs: Dictionary = {}

func _ready() -> void:
	_reload_all()

func _reload_all() -> void:
	# Единственный источник предметов: items_db_1500_v6.json
	items = _load_items_any_schema(ITEMS_PATH)
	mobs = _load_json_dict(MOBS_PATH)


func _load_items_any_schema(path: String) -> Dictionary:
	# Supports two schemas:
	# 1) Legacy: { "item_id": {..}, ... }
	# 2) New: { "meta": {...}, "items": [ {"id": "...", ...}, ... ] }
	var parsed: Dictionary = _load_json_dict(path)
	if parsed.is_empty():
		return {}

	if parsed.has("items") and (parsed["items"] is Array):
		var out: Dictionary = {}
		var arr: Array = parsed["items"] as Array
		for v in arr:
			if not (v is Dictionary):
				continue
			var d: Dictionary = v as Dictionary
			var id: String = String(d.get("id", ""))
			if id == "":
				continue
			out[id] = d
		return out

	# Legacy
	return parsed

func _load_json_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataDB: cannot open " + path)
		return {}

	var txt := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or not (parsed is Dictionary):
		push_error("DataDB: invalid JSON in " + path)
		return {}

	return parsed as Dictionary

# --- Item helpers ---
func has_item(id: String) -> bool:
	return items.has(id)

func get_item(id: String) -> Dictionary:
	if items.has(id):
		return items[id] as Dictionary
	return {}

func get_item_name(id: String) -> String:
	var d := get_item(id)
	var n := String(d.get("name", ""))
	return n if n != "" else id

func get_item_stack_max(id: String) -> int:
	var d := get_item(id)
	return int(d.get("stack_max", 99))

# --- Mob helpers ---
func has_mob(id: String) -> bool:
	return mobs.has(id)

func get_mob(id: String) -> Dictionary:
	if mobs.has(id):
		return mobs[id] as Dictionary
	return {}



extends Node

const ITEMS_PATH := "res://core/data/json/items.json"
const MOBS_PATH := "res://core/data/json/mobs.json"
const LOOT_TABLES_PATH := "res://core/data/json/loot_tables.json"

var items: Dictionary = {}
var mobs: Dictionary = {}
var loot_tables: Dictionary = {}

func _ready() -> void:
	_reload_all()

func _reload_all() -> void:
	items = _load_json_dict(ITEMS_PATH)
	mobs = _load_json_dict(MOBS_PATH)
	loot_tables = _load_json_dict(LOOT_TABLES_PATH)

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

# --- Loot helpers ---
func has_loot_table(id: String) -> bool:
	return loot_tables.has(id)

func get_loot_table(id: String) -> Dictionary:
	if loot_tables.has(id):
		return loot_tables[id] as Dictionary
	return {}

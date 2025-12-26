extends Node

const SAVE_DIR := "user://mmo_mvp/"
const CHAR_DIR := SAVE_DIR + "characters/"
const INDEX_FILE := SAVE_DIR + "index.json"

func _ensure_dirs() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(CHAR_DIR):
		DirAccess.make_dir_recursive_absolute(CHAR_DIR)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())

func _write_json(path: String, data: Variant) -> void:
	_ensure_dirs()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write file: " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))

func load_index() -> Dictionary:
	_ensure_dirs()
	var v: Variant = _read_json(INDEX_FILE)
	if v == null or not (v is Dictionary):
		return {"characters": []}
	var d := v as Dictionary
	if not d.has("characters") or not (d["characters"] is Array):
		d["characters"] = []
	return d

func save_index(index: Dictionary) -> void:
	_write_json(INDEX_FILE, index)

func _char_path(id: String) -> String:
	return CHAR_DIR + id + ".json"

func save_character_full(data: Dictionary) -> void:
	var id := String(data.get("id", ""))
	if id == "":
		push_error("save_character_full: missing id")
		return

	_write_json(_char_path(id), data)

	# summary в index (для списка выбора)
	var index := load_index()
	var chars: Array = index.get("characters", [])

	var summary := {
		"id": id,
		"name": String(data.get("name", "Unnamed")),
		"class": String(data.get("class", "adventurer")),
		"level": int(data.get("level", 1)),
		"updated_at": int(Time.get_unix_time_from_system())
	}

	var replaced := false
	for i in range(chars.size()):
		if String(chars[i].get("id", "")) == id:
			chars[i] = summary
			replaced = true
			break
	if not replaced:
		chars.append(summary)

	index["characters"] = chars
	save_index(index)

func load_character_full(id: String) -> Dictionary:
	var v: Variant = _read_json(_char_path(id))
	if v == null or not (v is Dictionary):
		return {}
	return v as Dictionary

func list_characters() -> Array[Dictionary]:
	var index := load_index()
	var chars: Array = index.get("characters", [])
	var out: Array[Dictionary] = []
	for c in chars:
		if c is Dictionary:
			out.append(c)
	return out


func delete_character(id: String) -> bool:
	_ensure_dirs()

	var path := _char_path(id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	# удалить из index
	var index := load_index()
	var chars: Array = index.get("characters", [])
	var new_chars: Array = []
	for c in chars:
		if String(c.get("id", "")) != id:
			new_chars.append(c)
	index["characters"] = new_chars
	save_index(index)
	return true

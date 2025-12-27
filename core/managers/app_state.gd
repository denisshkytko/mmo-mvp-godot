extends Node

const DEFAULT_ZONE: String = "res://game/world/zones/Zone_01.tscn"

var is_logged_in: bool = false

var selected_character_id: String = ""
var selected_character_data: Dictionary = {}

# -------------------------
# Navigation
# -------------------------
func goto_login() -> void:
	get_tree().change_scene_to_file("res://ui/flow/LoginUI.tscn")

func goto_character_select() -> void:
	get_tree().change_scene_to_file("res://ui/flow/CharacterSelectUI.tscn")

func enter_world() -> void:
	get_tree().change_scene_to_file("res://game/scenes/Main.tscn")

# -------------------------
# Auth
# -------------------------
func login(username: String, password: String) -> bool:
	if username == "admin" and password == "admin":
		is_logged_in = true
		return true
	return false

func logout() -> void:
	is_logged_in = false
	selected_character_id = ""
	selected_character_data = {}

# -------------------------
# Characters
# -------------------------
func get_characters() -> Array[Dictionary]:
	if not has_node("/root/SaveSystem"):
		return []
	return SaveSystem.list_characters()

func select_character(char_id: String) -> bool:
	if not has_node("/root/SaveSystem"):
		return false
	var full: Dictionary = SaveSystem.load_character_full(char_id)
	if full.is_empty():
		return false
	selected_character_id = char_id
	selected_character_data = full
	return true

func create_character(char_name: String, class_id: String) -> String:
	if not has_node("/root/SaveSystem"):
		return ""

	var id := "char_%d_%d" % [int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]

	var clean_name := char_name.strip_edges()
	if clean_name == "":
		clean_name = "Hero"

	var clean_class := class_id.strip_edges()
	if clean_class == "":
		clean_class = "adventurer"

	var data := {
		"id": id,
		"name": clean_name,
		"class": clean_class,

		"level": 1,
		"xp": 0,
		"xp_to_next": 10,

		"max_hp": 100,
		"current_hp": 100,
		"attack": 10,
		"defense": 2,

		"max_mana": 60,
		"mana": 60,

		"zone": DEFAULT_ZONE,
		"pos": {"x": 0.0, "y": 0.0},

		"inventory": {"gold": 0, "slots": []}
	}

	SaveSystem.save_character_full(data)
	return id


func delete_character(char_id: String) -> bool:
	if not has_node("/root/SaveSystem"):
		return false
	var ok: bool = SaveSystem.delete_character(char_id)
	if selected_character_id == char_id:
		selected_character_id = ""
		selected_character_data = {}
	return ok


func save_selected_character(data: Dictionary) -> void:
	if selected_character_id == "":
		return
	if not has_node("/root/SaveSystem"):
		return

	# гарантируем id
	data["id"] = selected_character_id

	SaveSystem.save_character_full(data)

	# обновляем кэш в памяти, чтобы UI/мир читали актуальные данные
	selected_character_data = data

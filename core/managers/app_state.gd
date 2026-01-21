extends Node

const DEFAULT_ZONE: String = "res://game/world/zones/Zone_01.tscn"

enum FlowState {
	BOOT,
	LOGIN,
	CHARACTER_SELECT,
	WORLD
}

signal state_changed(old_state: int, new_state: int)

var is_logged_in: bool = false
var current_state: int = FlowState.BOOT

var selected_character_id: String = ""
var selected_character_data: Dictionary = {}

func _ready() -> void:
	set_state(FlowState.LOGIN)

func can_transition(from_state: int, to_state: int) -> bool:
	match from_state:
		FlowState.BOOT:
			return to_state == FlowState.LOGIN
		FlowState.LOGIN:
			return to_state == FlowState.CHARACTER_SELECT
		FlowState.CHARACTER_SELECT:
			return to_state == FlowState.LOGIN or to_state == FlowState.WORLD
		FlowState.WORLD:
			return to_state == FlowState.CHARACTER_SELECT
		_:
			return false

func set_state(new_state: int) -> bool:
	if current_state == new_state:
		return false
	if not can_transition(current_state, new_state):
		push_warning("[Flow] illegal transition %s -> %s" % [
			_flow_state_label(current_state),
			_flow_state_label(new_state)
		])
		return false
	var old_state := current_state
	current_state = new_state
	emit_signal("state_changed", old_state, new_state)
	print("[Flow] %s -> %s" % [_flow_state_label(old_state), _flow_state_label(new_state)])
	return true

func _flow_state_label(state: int) -> String:
	match state:
		FlowState.BOOT:
			return "BOOT"
		FlowState.LOGIN:
			return "LOGIN"
		FlowState.CHARACTER_SELECT:
			return "CHARACTER_SELECT"
		FlowState.WORLD:
			return "WORLD"
		_:
			return "UNKNOWN"

# -------------------------
# Navigation
# -------------------------
func goto_login() -> void:
	push_warning("AppState navigation is deprecated; use FlowRouter")
	var flow_router = get_node("/root/FlowRouter")
	flow_router.go_login()

func goto_character_select() -> void:
	push_warning("AppState navigation is deprecated; use FlowRouter")
	var flow_router = get_node("/root/FlowRouter")
	flow_router.go_character_select()

func enter_world() -> void:
	push_warning("AppState navigation is deprecated; use FlowRouter")
	var flow_router = get_node("/root/FlowRouter")
	flow_router.go_world()

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
	var save_system = _save_system()
	return save_system.list_characters()

func select_character(char_id: String) -> bool:
	if not has_node("/root/SaveSystem"):
		return false
	var save_system = _save_system()
	var full: Dictionary = save_system.load_character_full(char_id)
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
		clean_class = "warrior"

	var data := {
		"id": id,
		"name": clean_name,
		"faction": "blue",
		"class": clean_class,
		"class_id": clean_class,
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

	var save_system = _save_system()
	save_system.save_character_full(data)
	return id


func delete_character(char_id: String) -> bool:
	if not has_node("/root/SaveSystem"):
		return false
	var save_system = _save_system()
	var ok: bool = save_system.delete_character(char_id)
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

	var save_system = _save_system()
	save_system.save_character_full(data)

	# обновляем кэш в памяти, чтобы UI/мир читали актуальные данные
	selected_character_data = data

func _save_system() -> Node:
	return get_node("/root/SaveSystem")

extends CanvasLayer

@onready var list: ItemList = $Root/Panel/Margin/VBox/CharacterList
@onready var delete_button: Button = $Root/Panel/Margin/VBox/Buttons/DeleteButton
@onready var enter_button: Button = $Root/Panel/Margin/VBox/Buttons/EnterButton
@onready var logout_button: Button = $Root/Panel/Margin/VBox/Buttons/LogoutButton
@onready var create_all_test_button: Button = $Root/Panel/Margin/VBox/Buttons/CreateAllTestButton

var _selected_id: String = ""
var _allow_enter: bool = false

func _ready() -> void:
	enter_button.disabled = true

	delete_button.pressed.connect(_on_delete_pressed)
	enter_button.pressed.connect(_on_enter_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	create_all_test_button.pressed.connect(_on_create_all_test_pressed)
	list.item_selected.connect(_on_item_selected)

	refresh_list()

func set_enter_enabled(enabled: bool) -> void:
	_allow_enter = enabled
	_update_enter_state()

func refresh_list() -> void:
	list.clear()
	_selected_id = ""

	var chars: Array = AppState.get_characters()
	for c in chars:
		var d: Dictionary = c as Dictionary
		var id: String = String(d.get("id", ""))
		var char_name: String = String(d.get("name", "Unnamed"))
		var lvl: int = int(d.get("level", 1))

		var cls: String = String(d.get("class", "paladin"))
		list.add_item("%s — %s (lv %d)" % [char_name, cls, lvl])
		list.set_item_metadata(list.item_count - 1, id)

	if list.item_count > 0:
		list.select(0)
		_on_item_selected(0)
	else:
		_update_enter_state()

func reset_transient_ui() -> void:
	_selected_id = ""
	list.deselect_all()
	_update_enter_state()


func _on_item_selected(index: int) -> void:
	_selected_id = String(list.get_item_metadata(index))
	_update_enter_state()


func _update_enter_state() -> void:
	enter_button.disabled = (not _allow_enter) or (_selected_id == "")
	delete_button.disabled = (_selected_id == "")



func _on_enter_pressed() -> void:
	if enter_button.disabled:
		return
	var ok: bool = AppState.select_character(_selected_id)
	if ok:
		FlowRouter.go_world()


func _on_logout_pressed() -> void:
	AppState.logout()
	FlowRouter.go_login()


func _on_delete_pressed() -> void:
	if _selected_id == "":
		return

	AppState.delete_character(_selected_id)

	# сброс выбора и обновление списка
	_selected_id = ""
	refresh_list()


func _on_create_all_test_pressed() -> void:
	var class_ids: Array[String] = ["paladin", "shaman", "mage", "priest", "hunter", "warrior"]
	for class_id in class_ids:
		var nickname := _generate_test_nickname(class_id)
		var char_id := AppState.create_character(nickname, class_id)
		if char_id == "":
			continue
		_apply_max_level_and_all_spells(char_id, class_id)
	refresh_list()


func _generate_test_nickname(class_id: String) -> String:
	var prefix := class_id.substr(0, min(3, class_id.length())).to_upper()
	return "%s_%04d" % [prefix, randi_range(1000, 9999)]


func _apply_max_level_and_all_spells(char_id: String, class_id: String) -> void:
	if char_id == "":
		return
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system == null:
		return
	var full: Dictionary = {}
	if save_system.has_method("load_character_full"):
		full = save_system.call("load_character_full", char_id) as Dictionary
	if full.is_empty():
		return

	full["class"] = class_id
	full["class_id"] = class_id
	full["level"] = Progression.MAX_LEVEL
	full["xp"] = 0
	full["xp_to_next"] = 0

	var learned_ranks := _collect_class_ability_max_ranks(class_id)
	full["spellbook"] = {
		"learned_ranks": learned_ranks,
		"loadout_slots": ["", "", "", "", ""],
		"aura_active": "",
		"stance_active": "",
		"buff_slots": [""],
	}

	if save_system.has_method("save_character_full"):
		save_system.call("save_character_full", full)


func _collect_class_ability_max_ranks(class_id: String) -> Dictionary:
	var learned_ranks: Dictionary = {}
	var db := get_node_or_null("/root/AbilityDB") as AbilityDatabase
	if db != null and db.is_ready:
		for def in db.get_abilities_for_class(class_id):
			if def == null:
				continue
			var ability_id := String(def.id)
			if ability_id == "":
				continue
			var max_rank := int(db.get_max_rank(ability_id))
			if max_rank > 0:
				learned_ranks[ability_id] = max_rank
		return learned_ranks

	var manifest_res: Resource = load("res://data/abilities/abilities_manifest.tres")
	if manifest_res == null or not (manifest_res is AbilitiesManifest):
		return learned_ranks
	var manifest := manifest_res as AbilitiesManifest
	for def in manifest.ability_defs:
		if def == null or String(def.class_id) != class_id:
			continue
		var ability_id := String(def.id)
		var max_rank := int(def.ranks.size())
		if ability_id != "" and max_rank > 0:
			learned_ranks[ability_id] = max_rank
	return learned_ranks

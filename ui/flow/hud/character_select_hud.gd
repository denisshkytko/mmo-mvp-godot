extends CanvasLayer

const UI_TEXT := preload("res://ui/game/hud/shared/ui_text.gd")

@onready var list: ItemList = $Root/Panel/Margin/VBox/CharacterList
@onready var delete_button: Button = $Root/Panel/Margin/VBox/Buttons/DeleteButton
@onready var enter_button: Button = $Root/Panel/Margin/VBox/Buttons/EnterButton
@onready var logout_button: Button = $Root/Panel/Margin/VBox/Buttons/LogoutButton
@onready var create_all_test_button: Button = $Root/Panel/Margin/VBox/Buttons/CreateAllTestButton
@onready var title_label: Label = $Root/Panel/Margin/VBox/Title

var _selected_id: String = ""
var _allow_enter: bool = false

func _ready() -> void:
	if title_label != null:
		title_label.text = tr("ui.flow.character_select.title")
	if delete_button != null:
		delete_button.text = tr("ui.flow.character_select.delete")
	if enter_button != null:
		enter_button.text = tr("ui.flow.character_select.enter_world")
	if logout_button != null:
		logout_button.text = tr("ui.flow.character_select.logout")

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
		var char_name: String = String(d.get("name", tr("ui.flow.character_select.unnamed")))
		var lvl: int = int(d.get("level", 1))

		var cls_id: String = String(d.get("class_id", d.get("class", "paladin")))
		var cls_name: String = UI_TEXT.class_display_name(cls_id)
		var faction_id: String = String(d.get("faction", "blue"))
		var faction_name: String = UI_TEXT.faction_display_name(faction_id)
		list.add_item(tr("ui.flow.character_select.list_item").format({"name": char_name, "class": cls_name, "faction": faction_name, "level": lvl}))
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
	for _i in range(6):
		var combo := _pick_random_allowed_faction_class()
		var faction_id := String(combo.get("faction", "blue"))
		var class_id := String(combo.get("class_id", "warrior"))
		var nickname := _generate_test_nickname(class_id)
		var char_id := AppState.create_character(nickname, class_id, faction_id)
		if char_id == "":
			continue
		_apply_max_level_and_all_spells(char_id, class_id)
	refresh_list()




func _pick_random_allowed_faction_class() -> Dictionary:
	var factions: Array[String] = ["blue", "red"]
	var faction_id := factions[randi() % factions.size()]
	var class_ids: Array[String] = ["paladin", "shaman", "mage", "priest", "hunter", "warrior"]
	var allowed: Array[String] = []
	for class_id in class_ids:
		if AppState.is_class_allowed_for_faction(class_id, faction_id):
			allowed.append(class_id)
	if allowed.is_empty():
		allowed = ["warrior"]
	var class_id := allowed[randi() % allowed.size()]
	return {"faction": faction_id, "class_id": class_id}

func _generate_test_nickname(_class_id: String) -> String:
	var syllables := ["Ар", "Бел", "Вик", "Гор", "Дар", "Ер", "Жан", "Зор", "Ил", "Кор", "Лад", "Мар", "Ник", "Ор", "Ран", "Сав", "Тар", "Фед", "Хор", "Яр"]
	var first := String(syllables[randi() % syllables.size()])
	var second := String(syllables[randi() % syllables.size()]).to_lower()
	var nick := first + second
	if nick.length() < 3:
		nick = "Артур"
	if nick.length() > 18:
		nick = nick.substr(0, 18)
	return nick


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

	var manifest_res: Resource = load("res://core/data/abilities/abilities_manifest.tres")
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

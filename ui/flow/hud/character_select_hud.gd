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
		if id == "":
			continue
		if (not d.has("faction")) or ((not d.has("class_id")) and (not d.has("class"))):
			# Старые записи index.json могли не содержать faction/class_id.
			# Подтягиваем полные данные, чтобы не показывать фракцию всегда как blue.
			var full: Dictionary = _load_character_full_safe(id)
			if not full.is_empty():
				d = full
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



func _load_character_full_safe(char_id: String) -> Dictionary:
	var save_system := get_node_or_null("/root/SaveSystem")
	if save_system == null:
		return {}
	if not save_system.has_method("load_character_full"):
		return {}
	var full_v: Variant = save_system.call("load_character_full", char_id)
	if full_v is Dictionary:
		return full_v as Dictionary
	return {}

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
	var class_plan: Array[String] = ["paladin", "shaman", "mage", "priest", "hunter", "warrior"]
	for class_id in class_plan:
		var faction_id := _pick_random_allowed_faction_for_class(class_id)
		if faction_id == "":
			continue
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

func _pick_random_allowed_faction_for_class(class_id: String) -> String:
	var factions: Array[String] = ["blue", "red"]
	factions.shuffle()
	for faction_id in factions:
		if AppState.is_class_allowed_for_faction(class_id, faction_id):
			return faction_id
	return ""

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
	full["equipment"] = _build_best_rare_equipment_for_class(class_id, Progression.MAX_LEVEL)

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


func _build_best_rare_equipment_for_class(class_id: String, level: int) -> Dictionary:
	var class_data: Dictionary = Progression.get_class_data(class_id)
	var allowed_armor: Array = class_data.get("allowed_armor_classes", [])
	var allowed_weapons: Array = class_data.get("allowed_weapon_types", [])
	var best_armor_class := _pick_max_armor_class(allowed_armor)
	var db := get_node_or_null("/root/DataDB")
	if db == null:
		return {}
	var items_dict: Dictionary = db.get("items", {}) as Dictionary
	if items_dict.is_empty():
		return {}

	var slot_candidates: Dictionary = {
		"head": [], "chest": [], "legs": [], "boots": [], "shoulders": [], "cloak": [], "shirt": [], "bracers": [], "gloves": [],
		"neck": [], "ring": [], "weapon_1h": [], "weapon_2h": [], "offhand": []
	}

	for key in items_dict.keys():
		var item: Dictionary = items_dict[key] as Dictionary
		if String(item.get("rarity", "")).to_lower() != "rare":
			continue
		if int(item.get("required_level", 0)) > level:
			continue
		var typ := String(item.get("type", "")).to_lower()
		if typ == "armor":
			var armor: Dictionary = item.get("armor", {}) as Dictionary
			var slot_id := String(armor.get("slot", ""))
			var armor_class := String(armor.get("class", "")).to_lower()
			if slot_id == "" or armor_class != best_armor_class:
				continue
			if slot_candidates.has(slot_id):
				(slot_candidates[slot_id] as Array).append(item)
		elif typ == "accessory":
			var acc: Dictionary = item.get("accessory", {}) as Dictionary
			var slot_acc := String(acc.get("slot", ""))
			if slot_candidates.has(slot_acc):
				(slot_candidates[slot_acc] as Array).append(item)
		elif typ == "weapon":
			var w: Dictionary = item.get("weapon", {}) as Dictionary
			var subtype := String(w.get("subtype", "")).to_lower()
			var handed := int(w.get("handed", 1))
			if not allowed_weapons.has(subtype):
				continue
			if handed >= 2:
				(slot_candidates["weapon_2h"] as Array).append(item)
			else:
				(slot_candidates["weapon_1h"] as Array).append(item)
		elif typ == "offhand":
			var oh: Dictionary = item.get("offhand", {}) as Dictionary
			var oh_slot := String(oh.get("slot", "")).to_lower()
			if oh_slot == "shield" and not allowed_weapons.has("shield"):
				continue
			if oh_slot == "offhand" and not allowed_weapons.has("offhand"):
				continue
			(slot_candidates["offhand"] as Array).append(item)

	var weights := _class_stat_weights(class_id)
	var equip: Dictionary = {}
	for slot_id in ["head", "chest", "legs", "boots", "shoulders", "cloak", "shirt", "bracers", "gloves"]:
		var best := _pick_best_item(slot_candidates.get(slot_id, []) as Array, weights)
		if not best.is_empty():
			equip[slot_id] = {"id": String(best.get("id", "")), "count": 1}
	var best_neck := _pick_best_item(slot_candidates.get("neck", []) as Array, weights)
	if not best_neck.is_empty():
		equip["neck"] = {"id": String(best_neck.get("id", "")), "count": 1}
	var rings_sorted := _sort_items_by_score(slot_candidates.get("ring", []) as Array, weights)
	if rings_sorted.size() > 0:
		equip["ring1"] = {"id": String((rings_sorted[0] as Dictionary).get("id", "")), "count": 1}
	if rings_sorted.size() > 1:
		equip["ring2"] = {"id": String((rings_sorted[1] as Dictionary).get("id", "")), "count": 1}
	elif rings_sorted.size() > 0:
		equip["ring2"] = {"id": String((rings_sorted[0] as Dictionary).get("id", "")), "count": 1}

	var best_2h := _pick_best_item(slot_candidates.get("weapon_2h", []) as Array, weights)
	var best_1h := _pick_best_item(slot_candidates.get("weapon_1h", []) as Array, weights)
	var best_offhand := _pick_best_item(slot_candidates.get("offhand", []) as Array, weights)
	var score_2h := _item_score(best_2h, weights)
	var score_1h_combo := _item_score(best_1h, weights) + _item_score(best_offhand, weights)
	if score_2h >= score_1h_combo and not best_2h.is_empty():
		equip["weapon_r"] = {"id": String(best_2h.get("id", "")), "count": 1}
	else:
		if not best_1h.is_empty():
			equip["weapon_r"] = {"id": String(best_1h.get("id", "")), "count": 1}
		if not best_offhand.is_empty():
			equip["weapon_l"] = {"id": String(best_offhand.get("id", "")), "count": 1}
	return equip

func _pick_max_armor_class(allowed_armor: Array) -> String:
	var rank := {"cloth": 1, "leather": 2, "mail": 3, "plate": 4}
	var best := "cloth"
	var best_rank := 0
	for a in allowed_armor:
		var cls := String(a).to_lower()
		var r := int(rank.get(cls, 0))
		if r > best_rank:
			best_rank = r
			best = cls
	return best

func _class_stat_weights(class_id: String) -> Dictionary:
	match class_id:
		"warrior":
			return {"STR": 1.8, "END": 1.4, "AGI": 1.0, "DefenseRating": 1.1, "HitRating": 1.0, "CritRating": 0.9, "SpeedRating": 0.8}
		"paladin":
			return {"STR": 1.5, "INT": 1.3, "END": 1.3, "PER": 0.9, "DefenseRating": 0.9, "HitRating": 0.8, "CritRating": 0.7}
		"shaman":
			return {"INT": 1.6, "END": 1.1, "PER": 1.0, "AGI": 0.7, "SpellPower": 1.6, "CritRating": 0.9, "SpeedRating": 0.8}
		"mage":
			return {"INT": 1.8, "PER": 1.2, "END": 0.9, "SpellPower": 1.8, "CritRating": 1.0, "HitRating": 0.9}
		"priest":
			return {"INT": 1.7, "PER": 1.3, "END": 1.0, "HealingPower": 1.7, "SpellPower": 1.2, "CritRating": 0.8}
		"hunter":
			return {"AGI": 1.8, "PER": 1.3, "END": 1.0, "STR": 0.8, "HitRating": 1.0, "CritRating": 1.1, "SpeedRating": 0.9}
		_:
			return {"STR": 1.0, "AGI": 1.0, "END": 1.0, "INT": 1.0, "PER": 1.0}

func _pick_best_item(items: Array, weights: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for v in items:
		if not (v is Dictionary):
			continue
		var d := v as Dictionary
		var sc := _item_score(d, weights)
		if sc > best_score:
			best_score = sc
			best = d
	return best

func _sort_items_by_score(items: Array, weights: Dictionary) -> Array:
	var pairs: Array = []
	for v in items:
		if not (v is Dictionary):
			continue
		var d := v as Dictionary
		pairs.append({"item": d, "score": _item_score(d, weights)})
	pairs.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var out: Array = []
	for pr in pairs:
		out.append((pr as Dictionary).get("item", {}))
	return out

func _item_score(item: Dictionary, weights: Dictionary) -> float:
	if item.is_empty():
		return -INF
	var score := float(item.get("item_level", 0)) * 0.2 + float(item.get("required_level", 0)) * 0.3
	var mods: Dictionary = item.get("stats_modifiers", {}) as Dictionary
	for k in mods.keys():
		var key := String(k)
		var val := float(mods.get(k, 0.0))
		score += val * float(weights.get(key, 0.15))
	if item.has("weapon"):
		var w: Dictionary = item.get("weapon", {}) as Dictionary
		score += float(w.get("damage", 0.0)) * 1.2
		var interval := float(w.get("attack_interval", 1.8))
		if interval > 0.01:
			score += 10.0 / interval
	if item.has("armor"):
		var a: Dictionary = item.get("armor", {}) as Dictionary
		score += float(a.get("physical_armor", 0.0)) * 0.12
		score += float(a.get("magic_armor", 0.0)) * 0.12
	return score

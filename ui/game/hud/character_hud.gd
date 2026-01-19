extends Control

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")

@onready var character_button: Button = $CharacterButton
@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var stats_text: RichTextLabel = $Panel/MarginContainer/VBoxContainer/ContentRow/StatsScroll/StatsText
@onready var equipment_panel: Panel = $Panel/MarginContainer/VBoxContainer/ContentRow/EquipmentPanel

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_rich: RichTextLabel = $TooltipPanel/Margin/TooltipText

var _player: Player = null
var _breakdown_cache: Dictionary = {}
var _equipment_slots: Dictionary = {}
var _icon_cache: Dictionary = {}
var _tooltip_slot: String = ""

func _ready() -> void:
	add_to_group("character_hud")
	character_button.pressed.connect(_on_button)

	stats_text.bbcode_enabled = true
	stats_text.fit_content = true
	stats_text.meta_hover_started.connect(_on_meta_hover_started)
	stats_text.meta_hover_ended.connect(_on_meta_hover_ended)

	tooltip_rich.bbcode_enabled = true
	tooltip_rich.fit_content = true
	tooltip_panel.visible = false
	tooltip_rich.text = ""

	_player = NODE_CACHE.get_player(get_tree()) as Player
	if _player != null and _player.c_stats != null:
		_player.c_stats.stats_changed.connect(_on_stats_changed)
	if _player != null and _player.c_equip != null:
		_player.c_equip.equipment_changed.connect(_on_equipment_changed)

	_setup_equipment_slots()

	_refresh()

func _on_button() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh()
	else:
		_hide_tooltip()

func _on_stats_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _on_equipment_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _on_meta_hover_started(meta) -> void:
	if not panel.visible:
		return

	var key := String(meta)
	if not _breakdown_cache.has(key):
		return

	tooltip_panel.visible = true
	tooltip_rich.text = String(_breakdown_cache[key])
	_position_tooltip()

func _on_meta_hover_ended(_meta) -> void:
	_hide_tooltip()

func _hide_tooltip() -> void:
	tooltip_panel.visible = false
	tooltip_rich.text = ""
	_tooltip_slot = ""

func _refresh() -> void:
	_player = NODE_CACHE.get_player(get_tree()) as Player
	_breakdown_cache.clear()
	_hide_tooltip()
	_refresh_equipment()

	if _player == null:
		title_label.text = "Character"
		stats_text.text = "No player."
		return

	title_label.text = "%s  (Level %d)" % [String(_player.name), _player.level]

	var snap: Dictionary = {}
	if _player.has_method("get_stats_snapshot"):
		snap = _player.get_stats_snapshot()

	if snap.is_empty():
		stats_text.text = _fallback_text()
		return

	stats_text.text = _format_snapshot(snap)

func _setup_equipment_slots() -> void:
	if equipment_panel == null:
		return
	var slot_names := {
		"head": "SlotHead",
		"chest": "SlotChest",
		"legs": "SlotLegs",
		"boots": "SlotBoots",
		"ring1": "SlotRing1",
		"neck": "SlotNeck",
		"shoulders": "SlotShoulders",
		"cloak": "SlotCloak",
		"shirt": "SlotShirt",
		"bracers": "SlotBracers",
		"gloves": "SlotGloves",
		"ring2": "SlotRing2",
		"weapon_r": "SlotWeaponR",
		"weapon_l": "SlotWeaponL",
	}
	for slot_id in slot_names.keys():
		var node_name: String = String(slot_names[slot_id])
		var slot_node := equipment_panel.find_child(node_name, true, false) as Control
		if slot_node == null:
			continue
		_equipment_slots[slot_id] = slot_node
		if not slot_node.gui_input.is_connected(_on_equipment_slot_gui_input.bind(slot_id)):
			slot_node.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_id))
		_style_slot_panel(slot_node)

func _style_slot_panel(slot_node: Control) -> void:
	if slot_node == null:
		return
	if slot_node is Panel:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.35)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(1, 1, 1, 0.2)
		(slot_node as Panel).add_theme_stylebox_override("panel", sb)

func _refresh_equipment() -> void:
	if _equipment_slots.is_empty():
		_setup_equipment_slots()
	if _player == null or _player.c_equip == null:
		for slot_node in _equipment_slots.values():
			var icon := (slot_node as Control).get_node_or_null("Icon") as TextureRect
			if icon != null:
				icon.texture = null
		return

	var equip: Dictionary = _player.c_equip.get_equipment_snapshot()
	for slot_id in _equipment_slots.keys():
		var slot_node: Control = _equipment_slots[slot_id] as Control
		var icon := slot_node.get_node_or_null("Icon") as TextureRect
		var v: Variant = equip.get(slot_id, null)
		var item_id: String = ""
		if v is Dictionary:
			item_id = String((v as Dictionary).get("id", ""))
		if icon != null:
			icon.texture = _get_icon_texture(item_id)

		if slot_id == "weapon_l":
			var blocked := _player.c_equip.is_left_hand_blocked()
			slot_node.modulate = Color(0.6, 0.6, 0.6, 0.65) if blocked else Color(1, 1, 1, 1)
			slot_node.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocked else Control.MOUSE_FILTER_STOP
		else:
			slot_node.modulate = Color(1, 1, 1, 1)
			slot_node.mouse_filter = Control.MOUSE_FILTER_STOP

func _get_icon_texture(item_id: String) -> Texture2D:
	if item_id == "":
		return null
	var db := get_node_or_null("/root/DataDB")
	var icon_path: String = ""
	if db != null and db.has_method("get_item"):
		var meta: Dictionary = db.call("get_item", item_id) as Dictionary
		icon_path = String(meta.get("icon", meta.get("icon_path", "")))
	if icon_path == "":
		return null
	if _icon_cache.has(icon_path):
		return _icon_cache[icon_path]
	var tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path)
	_icon_cache[icon_path] = tex
	return tex

func _on_equipment_slot_gui_input(event: InputEvent, slot_id: String) -> void:
	if not panel.visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_toggle_equipment_tooltip(slot_id)

func _toggle_equipment_tooltip(slot_id: String) -> void:
	if _tooltip_slot == slot_id and tooltip_panel.visible:
		_hide_tooltip()
		return
	_show_equipment_tooltip(slot_id)

func _show_equipment_tooltip(slot_id: String) -> void:
	if _player == null or _player.c_equip == null:
		_hide_tooltip()
		return
	var equip: Dictionary = _player.c_equip.get_equipment_snapshot()
	var v: Variant = equip.get(slot_id, null)
	if v == null or not (v is Dictionary):
		_hide_tooltip()
		return
	var id: String = String((v as Dictionary).get("id", ""))
	if id == "":
		_hide_tooltip()
		return
	var text := _build_item_tooltip_text(id)
	if text.strip_edges() == "":
		_hide_tooltip()
		return
	tooltip_panel.visible = true
	tooltip_rich.text = text
	_tooltip_slot = slot_id
	_position_tooltip()

func _build_item_tooltip_text(item_id: String) -> String:
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return ""
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	if meta.is_empty():
		return ""

	var item_name: String = String(meta.get("name", item_id))
	var typ: String = String(meta.get("type", ""))
	var rarity: String = String(meta.get("rarity", ""))

	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % item_name)
	if rarity != "":
		lines.append("rarity: %s" % rarity)
	if typ != "":
		lines.append("type: %s" % typ)

	if meta.has("armor") and meta.get("armor") is Dictionary:
		var a: Dictionary = meta.get("armor") as Dictionary
		lines.append("armor: %d  magic: %d" % [int(a.get("physical_armor", 0)), int(a.get("magic_armor", 0))])
	if meta.has("weapon") and meta.get("weapon") is Dictionary:
		var w: Dictionary = meta.get("weapon") as Dictionary
		var dmg: int = int(w.get("damage", 0))
		var spd: float = float(w.get("attack_interval", 1.0))
		lines.append("damage: %d  speed: %.2f" % [dmg, spd])
		if spd > 0.0:
			lines.append("dps: %.1f" % (float(dmg) / spd))
	if meta.has("stats_modifiers") and meta.get("stats_modifiers") is Dictionary:
		var sm: Dictionary = meta.get("stats_modifiers") as Dictionary
		for k in sm.keys():
			lines.append("%s: %+d" % [String(k), int(sm[k])])

	return "\n".join(lines)

func get_equipment_slot_at_global_pos(global_pos: Vector2) -> String:
	if not panel.visible:
		return ""
	for slot_id in _equipment_slots.keys():
		var slot_node: Control = _equipment_slots[slot_id] as Control
		if slot_node == null:
			continue
		if slot_id == "weapon_l" and _player != null and _player.c_equip != null and _player.c_equip.is_left_hand_blocked():
			continue
		if slot_node.get_global_rect().has_point(global_pos):
			return slot_id
	return ""

func _fallback_text() -> String:
	return "HP %d/%d\nMana %d/%d\nAttack %d\nDefense %d" % [
		_player.current_hp, _player.max_hp,
		_player.mana, _player.max_mana,
		_player.attack, _player.defense,
	]

func _format_snapshot(snap: Dictionary) -> String:
	var p: Dictionary = snap.get("primary", {}) as Dictionary
	var d: Dictionary = snap.get("derived", {}) as Dictionary

	var lines: Array[String] = []

	# Primary (single column, full names)
	lines.append("[b]Основные характеристики[/b]")
	lines.append("Сила %d" % int(p.get("str", 0)))
	lines.append("Ловкость %d" % int(p.get("agi", 0)))
	lines.append("Выносливость %d" % int(p.get("end", 0)))
	lines.append("Интеллект %d" % int(p.get("int", 0)))
	lines.append("Восприятие %d" % int(p.get("per", 0)))

	lines.append("")
	lines.append("[b]Здоровье и мана[/b]")
	lines.append(_line_with_breakdown("Макс. здоровье", "max_hp", d, ""))
	lines.append(_line_with_breakdown("Макс. мана", "max_mana", d, ""))
	lines.append(_line_with_breakdown("Восстановление здоровья", "hp_regen", d, "в секунду"))
	lines.append(_line_with_breakdown("Восстановление маны", "mana_regen", d, "в секунду"))

	lines.append("")
	lines.append("[b]Урон[/b]")
	lines.append(_line_damage("Урон", d))
	lines.append(_line_with_breakdown("Сила атаки", "attack_power", d, "Увеличивает физический урон на это значение"))
	lines.append(_line_with_breakdown("Сила заклинаний", "spell_power", d, "Увеличивает магический урон и исцеление на это значение"))

	lines.append(_line_with_breakdown(
		"Рейтинг крит. шанса",
		"crit_chance_rating",
		d,
		"Шанс критического удара %.2f%%" % float(snap.get("crit_chance_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Рейтинг крит. урона",
		"crit_damage_rating",
		d,
		"Критический урон x%.2f" % float(snap.get("crit_multiplier", 2.0))
	))

	lines.append("")
	lines.append("[b]Скорость[/b]")
	lines.append(_line_with_breakdown(
		"Скорость",
		"speed",
		d,
		"Снижает время восстановления способностей на %.2f%%" % float(snap.get("cooldown_reduction_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Скорость атаки",
		"attack_speed_rating",
		d,
		"Увеличивает скорость атаки на %.2f%%" % float(snap.get("attack_speed_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Скорость произнесения",
		"cast_speed_rating",
		d,
		"Снижает время произнесения заклинаний на %.2f%%" % float(snap.get("cast_speed_pct", 0.0))
	))

	lines.append("")
	lines.append("[b]Защита[/b]")
	lines.append(_line_with_breakdown(
		"Защита",
		"defense",
		d,
		"Снижает получаемый физический урон на %.2f%%" % float(snap.get("defense_mitigation_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Маг. сопротивление",
		"magic_resist",
		d,
		"Снижает получаемый магический урон на %.2f%%" % float(snap.get("magic_mitigation_pct", 0.0))
	))

	return "\n".join(lines)

func _position_tooltip() -> void:
	# Place tooltip beside the character panel (outside), so it never affects layout.
	if tooltip_panel == null or panel == null:
		return

	var vp: Rect2 = get_viewport_rect()
	var ppos: Vector2 = panel.global_position
	var psz: Vector2 = panel.size

	# Size: keep stable; do not auto-expand based on text width.
	tooltip_panel.size = Vector2(360, max(200, psz.y))

	var desired := ppos + Vector2(psz.x + 12.0, 0.0)
	var tsize := tooltip_panel.size

	# If doesn't fit to the right -> move to the left
	if desired.x + tsize.x > vp.position.x + vp.size.x:
		desired.x = ppos.x - tsize.x - 12.0

	# Clamp vertically
	if desired.y + tsize.y > vp.position.y + vp.size.y:
		desired.y = vp.position.y + vp.size.y - tsize.y - 8.0
	if desired.y < vp.position.y:
		desired.y = vp.position.y + 8.0

	tooltip_panel.global_position = desired

func _line_with_breakdown(title: String, key: String, derived: Dictionary, effect_text: String) -> String:
	var val = derived.get(key, 0)
	var val_str: String = _format_stat_value(val)

	var base_val = val
	var equip_val = 0
	if _player != null and _player.c_stats != null:
		base_val = _player.c_stats.get_base_stat(key)
		equip_val = _player.c_stats.get_equipment_bonus(key)

	var tooltip_lines: Array[String] = []
	if effect_text != "":
		tooltip_lines.append(effect_text)
	tooltip_lines.append("Base: %s" % _format_stat_value(base_val))
	tooltip_lines.append("Equipment: %s" % _format_signed_value(equip_val))
	tooltip_lines.append("Total: %s" % val_str)

	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

	return "[url=%s]%s %s[/url]" % [key, title, val_str]

func _line_damage(title: String, derived: Dictionary) -> String:
	var attack_power_total: float = float(derived.get("attack_power", 0.0))
	var weapon_damage: int = 0
	if _player != null and _player.c_equip != null:
		weapon_damage = _player.c_equip.get_weapon_damage()
	var base_ap: float = 0.0
	var equip_ap: float = 0.0
	if _player != null and _player.c_stats != null:
		base_ap = float(_player.c_stats.get_base_stat("attack_power"))
		equip_ap = float(_player.c_stats.get_equipment_bonus("attack_power"))
	var total_damage: float = attack_power_total + float(weapon_damage)

	var tooltip_lines := [
		"Base: %s" % _format_stat_value(base_ap),
		"Equipment: %s" % _format_signed_value(equip_ap + float(weapon_damage)),
		"Total: %s" % _format_stat_value(total_damage),
	]
	_breakdown_cache["damage"] = "\n".join(tooltip_lines)

	return "[url=damage]%s %s[/url]" % [title, _format_stat_value(total_damage)]

func _format_stat_value(val) -> String:
	if typeof(val) == TYPE_FLOAT:
		return String.num(float(val), 2)
	return str(int(val))

func _format_signed_value(val) -> String:
	var num := float(val)
	var out := String.num(num, 2) if typeof(val) == TYPE_FLOAT else str(int(num))
	if num > 0:
		return "+" + out
	if num < 0 and out[0] != "-":
		return "-" + out
	return out

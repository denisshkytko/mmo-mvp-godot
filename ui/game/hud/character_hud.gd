extends Control

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")
const TOOLTIP_BUILDER := preload("res://ui/game/hud/tooltip_text_builder.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")

const TOOLTIP_MIN_W: float = 260.0
const TOOLTIP_MAX_W: float = 420.0
const TOOLTIP_OFFSET := Vector2(12, 10)
const TOOLTIP_MARGIN: float = 8.0

const PRIMARY_LABELS := {
	"str": "Сила",
	"agi": "Ловкость",
	"end": "Выносливость",
	"int": "Интеллект",
	"per": "Восприятие",
}
const PRIMARY_ORDER := ["str", "agi", "end", "int", "per"]

const DERIVED_PRIMARY_COEFFS := {
	"max_hp": {"end": STAT_CONST.HP_PER_END, "str": STAT_CONST.HP_PER_STR},
	"max_mana": {"int": STAT_CONST.MANA_PER_INT},
	"hp_regen": {"end": STAT_CONST.HP_REGEN_PER_END, "str": STAT_CONST.HP_REGEN_PER_STR},
	"mana_regen": {"int": STAT_CONST.MANA_REGEN_PER_INT},
	"attack_power": {"str": STAT_CONST.AP_FROM_STR, "agi": STAT_CONST.AP_FROM_AGI},
	"spell_power": {"int": STAT_CONST.SP_FROM_INT},
	"defense": {"str": STAT_CONST.DEF_FROM_STR, "agi": STAT_CONST.DEF_FROM_AGI},
	"magic_resist": {"end": STAT_CONST.RES_FROM_END, "int": STAT_CONST.RES_FROM_INT},
	"attack_speed_rating": {"agi": STAT_CONST.AS_FROM_AGI},
	"cast_speed_rating": {"int": STAT_CONST.CS_FROM_INT},
	"crit_chance_rating": {"per": STAT_CONST.CRIT_FROM_PER, "agi": STAT_CONST.CRIT_FROM_AGI},
	"crit_damage_rating": {"per": STAT_CONST.CDMG_FROM_PER},
}

@onready var character_button: Button = $CharacterButton
@onready var panel: Panel = %Panel
@onready var title_label: Label = %TitleLabel
@onready var stats_text: RichTextLabel = %StatsText
@onready var equipment_panel: Panel = %EquipmentPanel

@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_rich: RichTextLabel = $TooltipPanel/Margin/VBox/Text
@onready var tooltip_unequip: Button = $TooltipPanel/Margin/VBox/UnequipButton

var _player: Player = null
var _breakdown_cache: Dictionary = {}
var _equipment_slots: Dictionary = {}
var _icon_cache: Dictionary = {}
var _tooltip_slot: String = ""
var _equip_drag_active: bool = false
var _equip_drag_slot_id: String = ""
var _equip_drag_item: Dictionary = {}
var _equip_drag_start_pos: Vector2 = Vector2.ZERO
var _equip_drag_threshold: float = 8.0
var _equip_drag_icon: TextureRect = null
var _tooltip_anchor_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("character_hud")
	character_button.pressed.connect(_on_button)
	set_process(true)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)

	stats_text.bbcode_enabled = true
	stats_text.fit_content = true
	stats_text.meta_clicked.connect(_on_meta_clicked)

	tooltip_rich.bbcode_enabled = true
	tooltip_rich.fit_content = true
	tooltip_rich.scroll_active = false
	tooltip_rich.autowrap_mode = TextServer.AUTOWRAP_WORD
	tooltip_panel.visible = false
	tooltip_rich.text = ""
	_style_tooltip_panel()
	if tooltip_unequip != null and not tooltip_unequip.pressed.is_connected(_on_unequip_pressed):
		tooltip_unequip.pressed.connect(_on_unequip_pressed)

	_player = NODE_CACHE.get_player(get_tree()) as Player
	if _player != null and _player.c_stats != null:
		_player.c_stats.stats_changed.connect(_on_stats_changed)
	if _player != null and _player.c_equip != null:
		_player.c_equip.equipment_changed.connect(_on_equipment_changed)

	_setup_equipment_slots()

	_refresh()
	call_deferred("_refresh_layout")

func _on_button() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		call_deferred("_refresh_layout")
		_refresh()
	else:
		_hide_tooltip()
		_end_equip_drag()

func _on_stats_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _on_equipment_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _process(_delta: float) -> void:
	if _equip_drag_active:
		_update_equip_drag_icon()

func _on_meta_clicked(meta) -> void:
	if not panel.visible:
		return
	var key := String(meta)
	if not _breakdown_cache.has(key):
		return
	if _tooltip_slot == key and tooltip_panel.visible:
		_hide_tooltip()
		return
	_tooltip_slot = key
	_tooltip_anchor_pos = get_viewport().get_mouse_position()
	_show_tooltip_text(String(_breakdown_cache[key]), false, _tooltip_anchor_pos)

func _unhandled_input(event: InputEvent) -> void:
	if not _equip_drag_active:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_close_tooltip_on_outside_click(mb.global_position)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_finish_equip_drag(mb.global_position)

func _hide_tooltip() -> void:
	tooltip_panel.visible = false
	tooltip_rich.text = ""
	_tooltip_slot = ""
	if tooltip_unequip != null:
		tooltip_unequip.visible = false

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

func _refresh_layout() -> void:
	if panel == null:
		return
	await get_tree().process_frame
	panel.size = panel.get_combined_minimum_size()
	_center_panel()

func _center_panel() -> void:
	if panel == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var size: Vector2 = panel.size
	var pos := (vp_size - size) * 0.5
	pos.x = clamp(pos.x, 0.0, max(0.0, vp_size.x - size.x))
	pos.y = clamp(pos.y, 0.0, max(0.0, vp_size.y - size.y))
	panel.position = pos

func _on_viewport_resized() -> void:
	if panel != null and panel.visible:
		call_deferred("_refresh_layout")

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

func _style_tooltip_panel() -> void:
	if tooltip_panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	tooltip_panel.add_theme_stylebox_override("panel", sb)

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
			_equip_drag_start_pos = mb.position
			_tooltip_anchor_pos = get_viewport().get_mouse_position()
			_toggle_equipment_tooltip(slot_id, _tooltip_anchor_pos)
		else:
			if _equip_drag_active:
				_finish_equip_drag(mb.global_position)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _equip_drag_active:
			var dist := _equip_drag_start_pos.distance_to((event as InputEventMouseMotion).position)
			if dist >= _equip_drag_threshold:
				_start_equip_drag(slot_id)

func _toggle_equipment_tooltip(slot_id: String, anchor_pos: Vector2) -> void:
	if _tooltip_slot == slot_id and tooltip_panel.visible:
		_hide_tooltip()
		return
	_show_equipment_tooltip(slot_id, anchor_pos)

func _show_equipment_tooltip(slot_id: String, anchor_pos: Vector2) -> void:
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
	var text := _build_item_tooltip_text(id, 1)
	if text.strip_edges() == "":
		_hide_tooltip()
		return
	_tooltip_slot = slot_id
	_tooltip_anchor_pos = anchor_pos
	_show_tooltip_text(text, true, _tooltip_anchor_pos)

func _build_item_tooltip_text(item_id: String, count: int) -> String:
	var db := get_node_or_null("/root/DataDB")
	if db == null or not db.has_method("get_item"):
		return ""
	var meta: Dictionary = db.call("get_item", item_id) as Dictionary
	if meta.is_empty():
		return ""
	return TOOLTIP_BUILDER.build_item_tooltip(meta, count, _player)

func _show_tooltip_text(text: String, show_unequip: bool, anchor_pos: Vector2) -> void:
	if tooltip_panel == null or tooltip_rich == null:
		return
	tooltip_panel.visible = false
	tooltip_panel.custom_minimum_size = Vector2.ZERO
	tooltip_panel.size = Vector2.ZERO
	tooltip_rich.custom_minimum_size = Vector2.ZERO
	tooltip_rich.text = text
	tooltip_rich.visible = true
	tooltip_rich.queue_redraw()
	tooltip_rich.update_minimum_size()
	await get_tree().process_frame
	await get_tree().process_frame
	if tooltip_unequip != null:
		tooltip_unequip.visible = show_unequip
	await _resize_tooltip_to_content()
	tooltip_panel.visible = true
	_position_tooltip(anchor_pos)

func _resize_tooltip_to_content() -> void:
	if tooltip_panel == null or tooltip_rich == null:
		return
	var was_visible := tooltip_panel.visible
	var prev_modulate := tooltip_panel.modulate
	tooltip_panel.visible = true
	tooltip_panel.modulate = Color(prev_modulate.r, prev_modulate.g, prev_modulate.b, 0.0)
	tooltip_panel.custom_minimum_size = Vector2(TOOLTIP_MIN_W, 0.0)
	tooltip_panel.size = Vector2(TOOLTIP_MAX_W, 10.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var min_size: Vector2 = tooltip_panel.get_combined_minimum_size()
	var target_w: float = clamp(min_size.x, TOOLTIP_MIN_W, TOOLTIP_MAX_W)
	tooltip_panel.custom_minimum_size = Vector2(target_w, 0.0)
	tooltip_panel.size = Vector2(target_w, 10.0)
	tooltip_rich.custom_minimum_size = Vector2(max(0.0, target_w - 20.0), 0.0)
	await get_tree().process_frame
	var label_min: Vector2 = tooltip_rich.get_combined_minimum_size()
	if label_min.y <= 1.0:
		await get_tree().process_frame
		label_min = tooltip_rich.get_combined_minimum_size()
	var content_h: float = max(float(tooltip_rich.get_content_height()), label_min.y)
	var btn_h: float = 0.0
	if tooltip_unequip != null and tooltip_unequip.visible:
		btn_h = max(32.0, tooltip_unequip.get_combined_minimum_size().y)
	var extra_spacing: float = 8.0 if btn_h > 0.0 else 0.0
	var min_h: float = max(32.0, content_h + btn_h + extra_spacing + 16.0)
	tooltip_panel.custom_minimum_size = Vector2(target_w, min_h)
	tooltip_panel.size = Vector2(target_w, min_h)
	await get_tree().process_frame
	await get_tree().process_frame
	var final_size: Vector2 = tooltip_panel.get_combined_minimum_size()
	final_size.x = target_w
	if final_size.y < min_h:
		final_size.y = min_h
	tooltip_panel.custom_minimum_size = final_size
	tooltip_panel.size = final_size
	tooltip_panel.modulate = prev_modulate
	if not was_visible:
		tooltip_panel.visible = false

func _close_tooltip_on_outside_click(global_pos: Vector2) -> void:
	if not tooltip_panel.visible:
		return
	if tooltip_panel.get_global_rect().has_point(global_pos):
		return
	if stats_text != null and stats_text.get_global_rect().has_point(global_pos):
		return
	_hide_tooltip()

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

func _start_equip_drag(slot_id: String) -> void:
	if _player == null or _player.c_equip == null:
		return
	var equip: Dictionary = _player.c_equip.get_equipment_snapshot()
	var v: Variant = equip.get(slot_id, null)
	if v == null or not (v is Dictionary):
		return
	var item: Dictionary = v as Dictionary
	if String(item.get("id", "")) == "":
		return
	_equip_drag_active = true
	_equip_drag_slot_id = slot_id
	_equip_drag_item = item.duplicate(true)
	_show_equip_drag_icon()
	_hide_tooltip()

func _finish_equip_drag(global_pos: Vector2) -> void:
	if not _equip_drag_active:
		return
	var handled := _try_drop_equip_to_inventory(global_pos)
	if not handled:
		_end_equip_drag()

func _end_equip_drag() -> void:
	_equip_drag_active = false
	_equip_drag_slot_id = ""
	_equip_drag_item = {}
	_hide_equip_drag_icon()

func _show_equip_drag_icon() -> void:
	if _equip_drag_icon == null:
		_equip_drag_icon = TextureRect.new()
		_equip_drag_icon.name = "EquipDragIcon"
		_equip_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_equip_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_equip_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(_equip_drag_icon)
		_equip_drag_icon.z_index = 999
	_update_equip_drag_icon()
	if _equip_drag_icon != null:
		_equip_drag_icon.visible = true

func _hide_equip_drag_icon() -> void:
	if _equip_drag_icon != null:
		_equip_drag_icon.visible = false

func _update_equip_drag_icon() -> void:
	if _equip_drag_icon == null:
		return
	var id: String = String(_equip_drag_item.get("id", ""))
	_equip_drag_icon.texture = _get_icon_texture(id)
	_equip_drag_icon.size = Vector2(36, 36)
	var m := get_viewport().get_mouse_position()
	_equip_drag_icon.position = m + Vector2(12, 12)

func _try_drop_equip_to_inventory(global_pos: Vector2) -> bool:
	var inv := get_tree().root.find_child("InventoryHUD", true, false)
	if inv != null and inv.has_method("try_handle_equipment_drop"):
		var ok: bool = bool(inv.call("try_handle_equipment_drop", global_pos, _equip_drag_slot_id))
		if ok:
			_end_equip_drag()
		return ok
	return false

func _on_unequip_pressed() -> void:
	if _player == null or _player.c_equip == null:
		return
	if _tooltip_slot == "":
		return
	if _player.c_equip.has_method("try_unequip_to_inventory"):
		var ok: bool = bool(_player.c_equip.call("try_unequip_to_inventory", _tooltip_slot))
		if ok:
			_hide_tooltip()
			_refresh()

func _fallback_text() -> String:
	if _is_rage_player():
		return "HP %d/%d\nAttack %d\nDefense %d" % [
			_player.current_hp, _player.max_hp,
			_player.attack, _player.defense,
		]
	return "HP %d/%d\nMana %d/%d\nAttack %d\nDefense %d" % [
		_player.current_hp, _player.max_hp,
		_player.mana, _player.max_mana,
		_player.attack, _player.defense,
	]

func _is_rage_player() -> bool:
	if _player == null:
		return false
	if _player.has_node("Components/Resource"):
		var r: Node = _player.get_node("Components/Resource")
		if r != null:
			return String(r.get("resource_type")) == "rage"
	return false

func _format_snapshot(snap: Dictionary) -> String:
	var p: Dictionary = snap.get("primary", {}) as Dictionary
	var d: Dictionary = snap.get("derived", {}) as Dictionary

	var lines: Array[String] = []
	var is_rage_player := _is_rage_player()

	# Primary (single column, full names)
	lines.append("[b]Основные характеристики[/b]")
	lines.append(_line_primary_stat("Сила", "str", snap, "Увеличивает здоровье и силу атаки"))
	lines.append(_line_primary_stat("Ловкость", "agi", snap, "Увеличивает скорость атаки, шанс крит. удара и силу атаки"))
	lines.append(_line_primary_stat("Выносливость", "end", snap, "Увеличивает здоровье, восстановление здоровья и физическую защиту"))
	var int_text := "Увеличивает силу заклинаний и магическое сопротивление" if is_rage_player else "Увеличивает запас маны, восстановление маны, силу заклинаний и магическое сопротивление"
	lines.append(_line_primary_stat("Интеллект", "int", snap, int_text))
	lines.append(_line_primary_stat("Восприятие", "per", snap, "Увеличивает рейтинг крит. удара и рейтинг крит. урона"))

	lines.append("")
	if is_rage_player:
		lines.append("[b]Здоровье[/b]")
		lines.append(_line_with_breakdown("Здоровье", "max_hp", snap, "Максимальный запас здоровья"))
		lines.append(_line_with_breakdown("Восстановление здоровья", "hp_regen", snap, "Величина восстановления здоровья за каждую секунду"))
	else:
		lines.append("[b]Здоровье и мана[/b]")
		lines.append(_line_with_breakdown("Здоровье", "max_hp", snap, "Максимальный запас здоровья"))
		lines.append(_line_with_breakdown("Мана", "max_mana", snap, "Максимальный запас маны"))
		lines.append(_line_with_breakdown("Восстановление здоровья", "hp_regen", snap, "Величина восстановления здоровья за каждую секунду"))
		lines.append(_line_with_breakdown("Восстановление маны", "mana_regen", snap, "Величина восстановления маны за каждую секунду"))

	lines.append("")
	lines.append("[b]Урон[/b]")
	lines.append(_line_damage("Физический урон", snap))
	lines.append(_line_with_breakdown("Сила атаки", "attack_power", snap, "Увеличивает физический урон"))
	lines.append(_line_with_breakdown("Сила заклинаний", "spell_power", snap, "Увеличивает магический урон и силу исцеления"))

	lines.append(_line_with_breakdown(
		"Рейтинг крит. шанса",
		"crit_chance_rating",
		snap,
		"Шанс критического удара %.2f%%" % float(snap.get("crit_chance_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Рейтинг крит. урона",
		"crit_damage_rating",
		snap,
		"Критический урон x%.2f" % float(snap.get("crit_multiplier", 2.0))
	))

	lines.append("")
	lines.append("[b]Скорость[/b]")
	lines.append(_line_with_breakdown(
		"Скорость",
		"speed",
		snap,
		"Увеличивает скорость атаки, скорость произнесения заклинаний и скорость восстановления способностей"
	))
	lines.append(_line_with_breakdown(
		"Скорость атаки",
		"attack_speed_rating",
		snap,
		"Увеличивает скорость атаки на %.2f%%" % float(snap.get("attack_speed_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Скорость произнесения заклинаний",
		"cast_speed_rating",
		snap,
		"Увеличивает скорость произнесения заклинаний"
	))

	lines.append("")
	lines.append("[b]Защита[/b]")
	lines.append(_line_with_breakdown(
		"Физическая защита",
		"defense",
		snap,
		"Снижает получаемый физический урон на %.2f%%" % float(snap.get("defense_mitigation_pct", 0.0))
	))
	lines.append(_line_with_breakdown(
		"Магическое сопротивление",
		"magic_resist",
		snap,
		"Снижает получаемый магический урон на %.2f%%" % float(snap.get("magic_mitigation_pct", 0.0))
	))

	return "\n".join(lines)

func _position_tooltip(anchor_pos: Vector2) -> void:
	if tooltip_panel == null or panel == null:
		return

	var vp: Rect2 = get_viewport_rect()
	var desired := anchor_pos + TOOLTIP_OFFSET
	var tsize := tooltip_panel.size

	if desired.x + tsize.x > vp.position.x + vp.size.x - TOOLTIP_MARGIN:
		desired.x = anchor_pos.x - tsize.x - TOOLTIP_OFFSET.x
	if desired.y + tsize.y > vp.position.y + vp.size.y - TOOLTIP_MARGIN:
		desired.y = anchor_pos.y - tsize.y - TOOLTIP_OFFSET.y
	desired.x = clamp(desired.x, vp.position.x + TOOLTIP_MARGIN, vp.position.x + vp.size.x - tsize.x - TOOLTIP_MARGIN)
	desired.y = clamp(desired.y, vp.position.y + TOOLTIP_MARGIN, vp.position.y + vp.size.y - tsize.y - TOOLTIP_MARGIN)

	tooltip_panel.global_position = desired

func _line_with_breakdown(title: String, key: String, snap: Dictionary, effect_text: String) -> String:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var val = derived.get(key, 0)
	var val_str: String = _format_stat_value(val)

	_build_derived_tooltip(key, effect_text, snap)

	return "[url=%s]%s %s[/url]" % [key, title, val_str]

func _line_primary_stat(title: String, key: String, snap: Dictionary, effect_text: String) -> String:
	var primary: Dictionary = snap.get("primary", {}) as Dictionary
	var total_val: int = int(primary.get(key, 0))
	_build_primary_tooltip(key, effect_text)
	return "[url=%s]%s %d[/url]" % [key, title, total_val]

func _line_damage(title: String, snap: Dictionary) -> String:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var attack_power_total: float = float(derived.get("attack_power", 0.0))
	var weapon_damage: int = 0
	if _player != null and _player.c_equip != null:
		weapon_damage = _player.c_equip.get_weapon_damage()
	var total_damage: float = attack_power_total + float(weapon_damage)

	var tooltip_lines: Array[String] = []
	tooltip_lines.append("Наносимый урон оружием/без оружия")
	tooltip_lines.append("")
	tooltip_lines.append("Сила атаки: %s" % _format_stat_value(attack_power_total))
	tooltip_lines.append("Урон оружия: %s" % _format_stat_value(weapon_damage))
	_breakdown_cache["damage"] = "\n".join(tooltip_lines).strip_edges()

	return "[url=damage]%s %s[/url]" % [title, _format_stat_value(total_damage)]

func _build_primary_tooltip(key: String, effect_text: String) -> void:
	var base_val = 0
	var equip_val = 0
	if _player != null and _player.c_stats != null:
		base_val = _player.c_stats.get_base_stat(key)
		equip_val = _player.c_stats.get_equipment_bonus(key)
	var tooltip_lines: Array[String] = []
	if effect_text != "":
		tooltip_lines.append(effect_text)
		tooltip_lines.append("")
	tooltip_lines.append("Базовые характеристики: %s" % _format_stat_value(base_val))
	if equip_val != 0:
		tooltip_lines.append("Снаряжение: %s" % _format_signed_value(equip_val))
	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

func _build_derived_tooltip(key: String, effect_text: String, snap: Dictionary) -> void:
	var tooltip_lines: Array[String] = []
	if effect_text != "":
		tooltip_lines.append(effect_text)
	var base_lines := _build_primary_contrib_lines(key, snap)
	if base_lines.size() > 0:
		if tooltip_lines.size() > 0:
			tooltip_lines.append("")
		tooltip_lines.append_array(base_lines)
	var equip_val: float = _get_direct_equipment_bonus(key, snap)
	if equip_val != 0.0:
		if tooltip_lines.size() > 0:
			tooltip_lines.append("")
		tooltip_lines.append("Снаряжение: %s" % _format_signed_value(equip_val))
	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

func _build_primary_contrib_lines(key: String, snap: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var coeffs: Dictionary = DERIVED_PRIMARY_COEFFS.get(key, {}) as Dictionary
	if coeffs.is_empty():
		return out
	var primary: Dictionary = snap.get("primary", {}) as Dictionary
	for stat_key in PRIMARY_ORDER:
		if not coeffs.has(stat_key):
			continue
		var coeff: float = float(coeffs.get(stat_key, 0.0))
		if coeff == 0.0:
			continue
		var base_val: float = float(primary.get(stat_key, 0))
		var delta: float = base_val * coeff
		if base_val == 0.0 and delta == 0.0:
			continue
		var label: String = PRIMARY_LABELS.get(stat_key, String(stat_key))
		out.append("%s: %s × %s = %s" % [
			label,
			_format_stat_value(base_val),
			_format_stat_value(coeff),
			_format_stat_value(delta),
		])
	return out

func _get_direct_equipment_bonus(key: String, snap: Dictionary) -> float:
	var breakdown: Dictionary = snap.get("derived_breakdown", {}) as Dictionary
	var entries: Array = breakdown.get(key, []) as Array
	var total: float = 0.0
	for entry in entries:
		if entry is Dictionary and String((entry as Dictionary).get("label", "")) == "gear":
			total += float((entry as Dictionary).get("value", 0.0))
	return total

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

extends CanvasLayer

const NODE_CACHE := preload("res://core/runtime/node_cache.gd")
const TOOLTIP_BUILDER := preload("res://ui/game/hud/shared/tooltip_text_builder.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const PROG := preload("res://core/stats/progression.gd")
const UI_TEXT := preload("res://ui/game/hud/shared/ui_text.gd")
signal hud_visibility_changed(is_open: bool)

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
	"max_hp": {"end": STAT_CONST.HP_PER_END},
	"max_mana": {"int": STAT_CONST.MANA_PER_INT},
	"hp_regen": {"end": STAT_CONST.HP_REGEN_PER_END},
	"mana_regen": {"int": STAT_CONST.MANA_REGEN_PER_INT},
	"attack_power": {"str": STAT_CONST.AP_FROM_STR, "agi": STAT_CONST.AP_FROM_AGI},
	"spell_power": {"int": STAT_CONST.SP_FROM_INT},
	"defense": {"str": STAT_CONST.DEF_FROM_STR, "end": STAT_CONST.DEF_FROM_END},
	"magic_resist": {"int": STAT_CONST.RES_FROM_INT, "end": STAT_CONST.RES_FROM_END},
	"attack_speed_rating": {"agi": STAT_CONST.AS_FROM_AGI},
	"cast_speed_rating": {"int": STAT_CONST.CS_FROM_INT},
	"crit_chance_rating": {"per": STAT_CONST.CRIT_FROM_PER, "agi": STAT_CONST.CRIT_FROM_AGI},
	"crit_damage_rating": {"per": STAT_CONST.CDMG_FROM_PER},
}

@onready var character_button: Button = get_node_or_null("CharacterButton")
@onready var panel: Panel = %Panel
@onready var panel_close_button: Button = $Root/Panel/CloseButton
@onready var title_label: Label = %TitleLabel
@onready var stats_text: RichTextLabel = %StatsText
@onready var equipment_panel: Panel = %EquipmentPanel

@onready var tooltip_panel: Panel = $Root/TooltipPanel
@onready var tooltip_rich: RichTextLabel = $Root/TooltipPanel/Margin/VBox/Text
@onready var tooltip_unequip: Button = $Root/TooltipPanel/Margin/VBox/UnequipButton
@onready var tooltip_close_button: Button = $Root/TooltipPanel/CloseButton

var _player: Player = null
var _ability_db: Node = null
var _breakdown_cache: Dictionary = {}
var _equipment_slots: Dictionary = {}
var _icon_cache: Dictionary = {}
var _tooltip_slot: String = ""
const TOOLTIP_HOLD_MAX_MS: int = 1000
var _equip_press_start_ms: int = 0
var _equip_press_slot_id: String = ""
var _equip_press_pos: Vector2 = Vector2.ZERO
var _tooltip_anchor_pos: Vector2 = Vector2.ZERO
var _tooltip_layer: CanvasLayer = null

func _trf(key: String, params: Dictionary = {}) -> String:
	return tr(key).format(params)

func _ready() -> void:
	add_to_group("character_hud")
	if character_button != null:
		character_button.pressed.connect(_on_button)
	set_process(true)
	if get_viewport() != null:
		get_viewport().size_changed.connect(_on_viewport_resized)

	panel.visible = false
	emit_signal("hud_visibility_changed", panel.visible)
	if panel_close_button != null and not panel_close_button.pressed.is_connected(_close_panel):
		panel_close_button.pressed.connect(_close_panel)
		panel_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if panel != null and panel_close_button != null and panel_close_button.get_parent() == panel:
		panel.move_child(panel_close_button, panel.get_child_count() - 1)
		panel_close_button.z_index = 100
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
	_ensure_tooltip_layer()
	if tooltip_unequip != null and not tooltip_unequip.pressed.is_connected(_on_unequip_pressed):
		tooltip_unequip.pressed.connect(_on_unequip_pressed)
	if tooltip_close_button != null and not tooltip_close_button.pressed.is_connected(_hide_tooltip):
		tooltip_close_button.pressed.connect(_hide_tooltip)

	_player = NODE_CACHE.get_player(get_tree()) as Player
	_ability_db = get_node_or_null("/root/AbilityDB")
	if _player != null and _player.c_stats != null:
		_player.c_stats.stats_changed.connect(_on_stats_changed)
	if _player != null and _player.c_equip != null:
		_player.c_equip.equipment_changed.connect(_on_equipment_changed)

	_setup_equipment_slots()
	_localize_static_labels()

	_refresh()
	call_deferred("_refresh_layout")

func _on_button() -> void:
	panel.visible = not panel.visible
	emit_signal("hud_visibility_changed", panel.visible)
	if panel.visible:
		call_deferred("_refresh_layout")
		_refresh()
	else:
		_hide_tooltip()

func _close_panel() -> void:
	if panel == null:
		return
	panel.visible = false
	emit_signal("hud_visibility_changed", false)
	_hide_tooltip()


func toggle_character() -> void:
	_on_button()

func is_open() -> bool:
	return panel.visible

func _on_stats_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _on_equipment_changed(_snapshot: Dictionary) -> void:
	if panel.visible:
		_refresh()

func _process(_delta: float) -> void:
	pass

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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_close_tooltip_on_outside_click(mb.global_position)

func _hide_tooltip() -> void:
	tooltip_panel.visible = false
	tooltip_rich.text = ""
	_tooltip_slot = ""
	if tooltip_unequip != null:
		tooltip_unequip.visible = false

func _localize_static_labels() -> void:
	if title_label != null:
		title_label.text = tr("ui.character.title")
	var slot_labels := {
		"HeadLabel": "ui.character.slot.head",
		"NeckLabel": "ui.character.slot.neck",
		"ShouldersLeftLabel": "ui.character.slot.shoulders",
		"CloakLeftLabel": "ui.character.slot.cloak",
		"ChestLabel": "ui.character.slot.chest",
		"ShirtLeftLabel": "ui.character.slot.shirt",
		"BracersLabel": "ui.character.slot.bracers",
		"GlovesLabel": "ui.character.slot.gloves",
		"Ring1RightLabel": "ui.character.slot.ring",
		"Ring2Label": "ui.character.slot.ring",
		"LegsRightLabel": "ui.character.slot.legs",
		"BootsRightLabel": "ui.character.slot.feet",
		"RightHandLabel": "ui.character.slot.right_hand",
		"LeftHandLabel": "ui.character.slot.left_hand",
	}
	for node_name in slot_labels.keys():
		var lbl := panel.find_child(String(node_name), true, false) as Label
		if lbl != null:
			lbl.text = tr(String(slot_labels[node_name]))
	for i in range(5):
		var slot_lbl := panel.find_child("Slot%d" % i, true, false) as Label
		if slot_lbl != null:
			slot_lbl.text = _trf("ui.character.ability_slot", {"index": i + 1})

func _refresh() -> void:
	_player = NODE_CACHE.get_player(get_tree()) as Player
	_breakdown_cache.clear()
	_hide_tooltip()
	_refresh_equipment()

	if _player == null:
		title_label.text = tr("ui.character.title")
		stats_text.text = tr("ui.character.unavailable")
		return

	var player_name := _resolve_player_name()
	var faction_name := UI_TEXT.faction_display_name(String(_player.faction_id))
	title_label.text = _trf("ui.character.title_with_level", {"name": player_name, "class": UI_TEXT.class_display_name(String(_player.class_id)), "faction": faction_name, "level": _player.level})

	var snap: Dictionary = {}
	if _player.has_method("get_stats_snapshot"):
		snap = _player.get_stats_snapshot()

	if snap.is_empty():
		stats_text.text = tr("ui.character.unavailable")
		return

	stats_text.text = _format_snapshot(snap)


func _resolve_player_name() -> String:
	if has_node("/root/AppState"):
		var data_v: Variant = get_node("/root/AppState").get("selected_character_data")
		if data_v is Dictionary:
			var selected_name := String((data_v as Dictionary).get("name", "")).strip_edges()
			if selected_name != "":
				return selected_name
	if _player != null and _player.has_method("get_display_name"):
		var display_name := String(_player.call("get_display_name")).strip_edges()
		if display_name != "":
			return display_name
	if _player != null:
		return String(_player.name).strip_edges()
	return ""

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
		slot_node.mouse_filter = Control.MOUSE_FILTER_STOP
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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_equip_press_start_ms = Time.get_ticks_msec()
			_equip_press_slot_id = slot_id
			_equip_press_pos = mb.global_position
			return
		if _equip_press_slot_id != slot_id:
			return
		if mb.global_position.distance_to(_equip_press_pos) > 1.0:
			_equip_press_slot_id = ""
			return
		var held_ms := Time.get_ticks_msec() - _equip_press_start_ms
		_equip_press_slot_id = ""
		if held_ms > TOOLTIP_HOLD_MAX_MS:
			return
		_tooltip_anchor_pos = mb.global_position
		_toggle_equipment_tooltip(slot_id, _tooltip_anchor_pos)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_equip_press_start_ms = Time.get_ticks_msec()
			_equip_press_slot_id = slot_id
			_equip_press_pos = st.position
			return
		if _equip_press_slot_id != slot_id:
			return
		if st.position.distance_to(_equip_press_pos) > 1.0:
			_equip_press_slot_id = ""
			return
		var held_ms2 := Time.get_ticks_msec() - _equip_press_start_ms
		_equip_press_slot_id = ""
		if held_ms2 > TOOLTIP_HOLD_MAX_MS:
			return
		_tooltip_anchor_pos = st.position
		_toggle_equipment_tooltip(slot_id, _tooltip_anchor_pos)

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
	lines.append(_line_primary_stat("Сила", "str", snap, "Увеличивает силу атаки и физическую защиту"))
	lines.append(_line_primary_stat("Ловкость", "agi", snap, "Увеличивает скорость атаки, рейтинг крит. шанса и силу атаки"))
	lines.append(_line_primary_stat("Выносливость", "end", snap, "Увеличивает здоровье, восстановление здоровья и защиту"))
	var int_text := "Увеличивает силу заклинаний и магическое сопротивление" if is_rage_player else "Увеличивает запас маны, восстановление маны, силу заклинаний и магическое сопротивление"
	lines.append(_line_primary_stat("Интеллект", "int", snap, int_text))
	lines.append(_line_primary_stat("Восприятие", "per", snap, "Увеличивает рейтинг крит. шанса и рейтинг крит. урона"))

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
	var cooldown_reduction := float(snap.get("cooldown_reduction_pct", 0.0))
	var speed_text := "Увеличивает скорость атаки, скорость произнесения заклинаний и скорость восстановления способностей\nВремя восстановления способностей снижено на %.2f%%" % cooldown_reduction
	lines.append(_line_with_breakdown(
		"Скорость",
		"speed",
		snap,
		speed_text
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
		"Увеличивает скорость произнесения заклинаний на %.2f%%" % float(snap.get("cast_speed_pct", 0.0))
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

	var viewport := get_viewport()
	var vp: Rect2 = viewport.get_visible_rect() if viewport != null else Rect2()
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
	_build_primary_tooltip(key, effect_text, snap)
	return "[url=%s]%s %d[/url]" % [key, title, total_val]

func _line_damage(title: String, snap: Dictionary) -> String:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var attack_power_total: float = float(derived.get("attack_power", 0.0))
	var right_weapon_damage: int = 0
	var left_weapon_damage: int = 0
	var has_right_weapon := false
	var has_left_weapon := false
	var is_two_handed := false
	var base_interval_r: float = 1.0
	var base_interval_l: float = 0.0
	if _player != null and _player.c_equip != null:
		right_weapon_damage = _player.c_equip.get_weapon_damage_right()
		left_weapon_damage = _player.c_equip.get_weapon_damage_left()
		has_left_weapon = _player.c_equip.has_left_weapon()
		is_two_handed = _player.c_equip.is_two_handed_equipped()
		base_interval_r = _player.c_equip.get_weapon_attack_interval_right()
		if base_interval_r <= 0.0:
			base_interval_r = PROG.get_base_melee_attack_interval_for_class(_player.class_id)
		if has_left_weapon:
			base_interval_l = _player.c_equip.get_weapon_attack_interval_left()
		has_right_weapon = _player.c_equip.get_weapon_attack_interval_right() > 0.0
	else:
		base_interval_r = PROG.get_base_melee_attack_interval_for_class(_player.class_id)

	var atk_speed_pct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + (atk_speed_pct / 100.0)
	if speed_mult <= 0.01:
		speed_mult = 0.01
	var interval_r: float = base_interval_r / speed_mult
	var interval_l: float = base_interval_l / speed_mult if base_interval_l > 0.0 else 0.0

	var display_damage := ""
	var tooltip_lines: Array[String] = []
	tooltip_lines.append("Наносимый урон оружием/без оружия")
	var base_pct_bonus: float = float(derived.get("physical_damage_base_pct_bonus", 0.0))
	var flat_bonus: float = float(derived.get("flat_physical_bonus", 0.0))
	var base_bonus_label := ""
	var base_bonus_value: float = 0.0
	var flat_bonus_label := ""

	if (base_pct_bonus != 0.0 or flat_bonus != 0.0) and _player != null and _player.c_buffs != null:
		var buffs: Array = _player.c_buffs.get_buffs_snapshot()
		for b in buffs:
			if not (b is Dictionary):
				continue
			var bd := b as Dictionary
			var data: Dictionary = bd.get("data", {}) as Dictionary
			var perc: Dictionary = data.get("percent_add", data.get("percent", {})) as Dictionary
			var sec: Dictionary = data.get("secondary_add", data.get("secondary", {})) as Dictionary
			var resolved_name := _resolve_buff_name(String(data.get("ability_id", bd.get("id", ""))))
			if base_bonus_label == "" and perc.has("physical_damage_base_pct_bonus"):
				base_bonus_label = resolved_name
			if flat_bonus_label == "" and sec.has("flat_physical_bonus"):
				flat_bonus_label = resolved_name

	if not has_right_weapon:
		var ap_part_unarmed: float = attack_power_total * 1.5
		var unarmed_hit: float = ap_part_unarmed * (1.0 + base_pct_bonus) + flat_bonus
		base_bonus_value = ap_part_unarmed * base_pct_bonus
		display_damage = _format_float_clean(unarmed_hit)
		var dps: float = float(unarmed_hit) / max(0.01, interval_r)
		tooltip_lines.append(_trf("ui.terms.dps_with_value", {"value": "%.2f" % dps}))
		tooltip_lines.append("")
		tooltip_lines.append("Сила атаки: %s" % _format_float_clean(ap_part_unarmed))
		tooltip_lines.append("Урон оружия: %s" % _format_float_clean(0.0))
	elif is_two_handed:
		var ap_part_2h: float = attack_power_total * 1.5
		var base_2h: float = float(right_weapon_damage) + ap_part_2h
		var hit_2h: float = base_2h * (1.0 + base_pct_bonus) + flat_bonus
		base_bonus_value = base_2h * base_pct_bonus
		display_damage = _format_float_clean(hit_2h)
		var dps_2h: float = float(hit_2h) / max(0.01, interval_r)
		tooltip_lines.append(_trf("ui.terms.dps_with_value", {"value": "%.2f" % dps_2h}))
		tooltip_lines.append("")
		tooltip_lines.append("Сила атаки: %s" % _format_float_clean(ap_part_2h))
		tooltip_lines.append("Урон оружия: %s" % _format_float_clean(float(right_weapon_damage)))
	elif has_left_weapon:
		var ap_part_dw: float = attack_power_total
		var base_r: float = float(right_weapon_damage) + ap_part_dw
		var base_l: float = (float(left_weapon_damage) + ap_part_dw) * STAT_CONST.OFFHAND_MULT
		var hit_r: float = base_r * (1.0 + base_pct_bonus) + flat_bonus
		var hit_l: float = base_l * (1.0 + base_pct_bonus) + flat_bonus
		base_bonus_value = (base_r + base_l) * base_pct_bonus
		display_damage = "%s / %s" % [_format_float_clean(hit_r), _format_float_clean(hit_l)]
		var dps_dw: float = float(hit_r) / max(0.01, interval_r)
		if interval_l > 0.0:
			dps_dw += float(hit_l) / max(0.01, interval_l)
		tooltip_lines.append(_trf("ui.terms.dps_with_value", {"value": "%.2f" % dps_dw}))
		tooltip_lines.append("")
		tooltip_lines.append("Сила атаки: %s" % _format_float_clean(ap_part_dw))
		tooltip_lines.append(_trf("ui.character.damage.weapon_right", {"value": _format_float_clean(float(right_weapon_damage))}))
		tooltip_lines.append(_trf("ui.character.damage.weapon_left", {"value": _format_float_clean(float(left_weapon_damage))}))
	else:
		var ap_part_1h: float = attack_power_total
		var base_1h: float = float(right_weapon_damage) + ap_part_1h
		var hit_1h: float = base_1h * (1.0 + base_pct_bonus) + flat_bonus
		base_bonus_value = base_1h * base_pct_bonus
		display_damage = _format_float_clean(hit_1h)
		var dps_1h: float = float(hit_1h) / max(0.01, interval_r)
		tooltip_lines.append(_trf("ui.terms.dps_with_value", {"value": "%.2f" % dps_1h}))
		tooltip_lines.append("")
		tooltip_lines.append("Сила атаки: %s" % _format_float_clean(ap_part_1h))
		tooltip_lines.append("Урон оружия: %s" % _format_float_clean(float(right_weapon_damage)))

	if flat_bonus != 0.0:
		if flat_bonus_label == "":
			flat_bonus_label = "Плоский бонус"
		tooltip_lines.append("%s: %s" % [flat_bonus_label, _format_float_clean(flat_bonus)])
	if base_pct_bonus != 0.0:
		if base_bonus_label == "":
			base_bonus_label = "Бонус стойки"
		tooltip_lines.append("%s: %s" % [base_bonus_label, _format_float_clean(base_bonus_value)])

	_breakdown_cache["damage"] = "\n".join(tooltip_lines).strip_edges()

	return "[url=damage]%s %s[/url]" % [title, display_damage]

func _build_primary_tooltip(key: String, effect_text: String, snap: Dictionary) -> void:
	var base_val: int = 0
	var equip_val: int = 0
	if _player != null and _player.c_stats != null:
		base_val = _player.c_stats.get_base_stat(key)
		equip_val = _player.c_stats.get_equipment_bonus(key)
	var tooltip_lines: Array[String] = []
	if effect_text != "":
		tooltip_lines.append(effect_text)
	tooltip_lines.append("Базовые характеристики: %s" % _format_stat_value(base_val))
	if equip_val != 0:
		tooltip_lines.append("Снаряжение: %s" % _format_stat_value(equip_val))
	var primary_breakdown: Dictionary = snap.get("primary_breakdown", {}) as Dictionary
	var entries: Array = primary_breakdown.get(key, []) as Array
	var buff_lines: Array[String] = _extract_buff_lines(entries)
	if buff_lines.size() > 0:
		tooltip_lines.append_array(buff_lines)
	if effect_text != "" and tooltip_lines.size() > 1 and tooltip_lines[1] != "":
		tooltip_lines.insert(1, "")
	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

func _build_derived_tooltip(key: String, effect_text: String, snap: Dictionary) -> void:
	var tooltip_lines: Array[String] = []
	if effect_text != "":
		tooltip_lines.append(effect_text)
	var base_lines := _build_primary_contrib_lines(key, snap)
	if base_lines.size() > 0:
		tooltip_lines.append_array(base_lines)
	var equip_val: float = _get_direct_equipment_bonus(key, snap)
	if equip_val != 0.0:
		tooltip_lines.append("Снаряжение: %s" % _format_stat_value(equip_val))
	var breakdown: Dictionary = snap.get("derived_breakdown", {}) as Dictionary
	var entries: Array = breakdown.get(key, []) as Array
	var buff_lines: Array[String] = _extract_buff_lines(entries)
	if buff_lines.size() > 0:
		tooltip_lines.append_array(buff_lines)
	if effect_text != "" and tooltip_lines.size() > 1 and tooltip_lines[1] != "":
		tooltip_lines.insert(1, "")
	_breakdown_cache[key] = "\n".join(tooltip_lines).strip_edges()

func _extract_buff_lines(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		var label: String = String(d.get("label", d.get("source", "")))
		if label == "" or label == "base" or label == "level" or label == "gear" or label == "percent":
			continue
		if PRIMARY_LABELS.has(label.to_lower()):
			continue
		if label in ["STR", "AGI", "END", "INT", "PER"]:
			continue
		var buff_name: String = _resolve_buff_name(label)
		var val: float = float(d.get("value", 0.0))
		var rendered: String = _format_stat_value(val)
		out.append("%s: %s" % [buff_name, rendered])
	return out

func _resolve_buff_name(raw_label: String) -> String:
	var label := raw_label
	if label == "food/drink":
		return tr("ui.character.buff.food_drink")

	var ability_id := ""
	if label.begins_with("buff:"):
		ability_id = label.trim_prefix("buff:")
	elif label.begins_with("aura:"):
		ability_id = label.trim_prefix("aura:")
	elif label.begins_with("stance:"):
		ability_id = label.trim_prefix("stance:")

	# Fallback for generic active slots persisted as active_aura/active_stance.
	if ability_id == "" and _player != null and _player.c_spellbook != null:
		if label == "active_aura":
			ability_id = String(_player.c_spellbook.aura_active)
		elif label == "active_stance":
			ability_id = String(_player.c_spellbook.stance_active)

	if _ability_db != null and _ability_db.has_method("get_ability"):
		if ability_id != "":
			var def: AbilityDefinition = _ability_db.get_ability(ability_id)
			if def != null:
				var def_name := String(def.get_display_name()).strip_edges() if def.has_method("get_display_name") else ""
				if def_name != "":
					return def_name
		var direct_def: AbilityDefinition = _ability_db.get_ability(label)
		if direct_def != null:
			var direct_name := String(direct_def.get_display_name()).strip_edges() if direct_def.has_method("get_display_name") else ""
			if direct_name != "":
				return direct_name
	return label

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
		out.append("%s: %s" % [
			label,
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

func _format_float_clean(v: float) -> String:
	var s := String.num(v, 2)
	while s.ends_with("0"):
		s = s.left(s.length() - 1)
	if s.ends_with("."):
		s = s.left(s.length() - 1)
	return s

func _ensure_tooltip_layer() -> void:
	if tooltip_panel == null:
		return
	if _tooltip_layer == null:
		_tooltip_layer = CanvasLayer.new()
		_tooltip_layer.name = "TooltipLayer"
		_tooltip_layer.layer = 200
		add_child(_tooltip_layer)
	if tooltip_panel.get_parent() != _tooltip_layer:
		tooltip_panel.reparent(_tooltip_layer)

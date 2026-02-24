extends CanvasLayer

@onready var panel: Panel = $Root/Panel
@onready var name_label: Label = $Root/Panel/Margin/VBox/Header/NameLabel
@onready var level_label: Label = $Root/Panel/Margin/VBox/Header/LevelLabel
@onready var hp_bar: ProgressBar = $Root/Panel/Margin/VBox/HpRow/HpBar
@onready var hp_text: Label = $Root/Panel/Margin/VBox/HpRow/HpBar/HpText
@onready var mana_row: HBoxContainer = $Root/Panel/Margin/VBox/ManaRow
@onready var mana_bar: ProgressBar = $Root/Panel/Margin/VBox/ManaRow/ManaBar
@onready var mana_text: Label = $Root/Panel/Margin/VBox/ManaRow/ManaBar/ManaText
@onready var effects_root: VBoxContainer = $Root/Effects
@onready var buff_grid: GridContainer = $Root/Effects/BuffGrid
@onready var debuff_grid: GridContainer = $Root/Effects/DebuffGrid
const BUFF_ICON_SCENE := preload("res://ui/game/hud/BuffIcon.tscn")

var _gm: Node = null
var _player: Node = null
var _target: Node = null
var _panel_stylebox_base: StyleBox = null
var _mana_fill_color: Color = Color(0.23921569, 0.0, 1.0, 1.0)

func _ready() -> void:
	panel.visible = false
	_gm = get_tree().get_first_node_in_group("game_manager")
	_player = get_tree().get_first_node_in_group("player")
	_cache_panel_stylebox()
	_cache_mana_fill_color()

	hp_text.text = ""
	mana_text.text = ""
	hp_bar.max_value = 1
	hp_bar.value = 1
	mana_bar.max_value = 1
	mana_bar.value = 1
	mana_row.visible = false

func _cache_panel_stylebox() -> void:
	var sb := panel.get_theme_stylebox("panel")
	if sb != null:
		_panel_stylebox_base = sb.duplicate()
	else:
		var fallback := StyleBoxFlat.new()
		fallback.corner_radius_top_left = 12
		fallback.corner_radius_top_right = 12
		fallback.corner_radius_bottom_left = 12
		fallback.corner_radius_bottom_right = 12
		_panel_stylebox_base = fallback

func _cache_mana_fill_color() -> void:
	var sb := mana_bar.get_theme_stylebox("fill")
	if sb is StyleBoxFlat:
		_mana_fill_color = (sb as StyleBoxFlat).bg_color

func _apply_resource_bar_color(resource_type: String) -> void:
	var sb := mana_bar.get_theme_stylebox("fill")
	if sb == null:
		return
	var sb2 := sb.duplicate()
	if sb2 is StyleBoxFlat:
		var fill_color := _mana_fill_color if resource_type != "rage" else Color(0.35, 0.14, 0.10, 1.0)
		(sb2 as StyleBoxFlat).bg_color = fill_color
		mana_bar.add_theme_stylebox_override("fill", sb2)

func _process(_delta: float) -> void:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
		if _gm == null:
			panel.visible = false
			return

	var t: Node = _gm.call("get_target") if _gm.has_method("get_target") else null
	if t == null or not is_instance_valid(t):
		_target = null
		panel.visible = false
		return

	# target changed
	if t != _target:
		_target = t
		panel.visible = true
		_update_identity()
		_update_relation_color()

	_update_hp()
	_update_resource()
	_update_effects()

func _update_identity() -> void:
	if _target == null:
		name_label.text = ""
		level_label.text = ""
		return

	var display_name: String = ""

	if _target.has_method("get_display_name"):
		display_name = String(_target.call("get_display_name"))
	else:
		# 1) aggressive mob
		if _target is NormalAggresiveMob:
			var mob_id_val: Variant = _target.get("mob_id")
			if mob_id_val != null and String(mob_id_val) != "":
				display_name = String(mob_id_val)
			else:
				display_name = String(_target.name)

		# 2) neutral mob
		elif _target is NormalNeutralMob:
			var skin_val: Variant = _target.get("skin_id")
			if skin_val != null and String(skin_val) != "":
				display_name = String(skin_val)
			else:
				display_name = String(_target.name)

		# 3) faction npc
		elif _target is FactionNPC:
			var fid: String = ""
			if _target.has_method("get_faction_id"):
				fid = String(_target.call("get_faction_id"))

			var ft_val: Variant = _target.get("fighter_type")
			var ft: int = 0
			if ft_val != null:
				ft = int(ft_val)

			var ft_name: String = "NPC"
			if ft == 0:
				ft_name = "Civilian"
			elif ft == 1:
				ft_name = "Melee"
			elif ft == 2:
				ft_name = "Ranged"

			display_name = ("%s %s" % [fid, ft_name]).strip_edges()

		else:
			display_name = String(_target.name)

	name_label.text = display_name

	var lvl: int = 0
	if _target.has_method("get_level"):
		lvl = int(_target.call("get_level"))
	else:
		var ml: Variant = _target.get("mob_level")
		if ml != null:
			lvl = int(ml)
		else:
			var nl: Variant = _target.get("npc_level")
			if nl != null:
				lvl = int(nl)

	level_label.text = "lv %d" % lvl if lvl > 0 else ""

func _get_stats_node() -> Node:
	if _target == null:
		return null
	# стандарт у твоих мобов/нпс сейчас: Components/Stats
	if _target.has_node("Components/Stats"):
		var n: Node = _target.get_node("Components/Stats")
		return n
	return null

func _update_hp() -> void:
	if _target == null:
		hp_text.text = ""
		hp_bar.max_value = 1
		hp_bar.value = 1
		return

	var cur: int = -1
	var mx: int = -1

	# 1) через методы (если есть)
	if _target.has_method("get_current_hp") and _target.has_method("get_max_hp"):
		cur = int(_target.call("get_current_hp"))
		mx = int(_target.call("get_max_hp"))
	else:
		# 2) через Stats компонент
		var stats: Node = _get_stats_node()
		if stats != null:
			var cur_v: Variant = stats.get("current_hp")
			var mx_v: Variant = stats.get("max_hp")
			if cur_v != null and mx_v != null:
				cur = int(cur_v)
				mx = int(mx_v)
		else:
			# 3) запасной вариант — прямые поля
			var cur_val: Variant = _target.get("current_hp")
			var mx_val: Variant = _target.get("max_hp")
			if cur_val != null and mx_val != null:
				cur = int(cur_val)
				mx = int(mx_val)

	if cur < 0 or mx <= 0:
		hp_text.text = ""
		hp_bar.max_value = 1
		hp_bar.value = 1
		return

	mx = max(1, mx)
	cur = clamp(cur, 0, mx)

	hp_text.text = "%d/%d" % [cur, mx]
	hp_bar.max_value = mx
	hp_bar.value = cur

func _update_resource() -> void:
	if _target == null:
		mana_row.visible = false
		return

	if _target.has_method("get_current_resource") and _target.has_method("get_max_resource"):
		mana_row.visible = true
		var r_type_m: String = String(_target.call("get_resource_type")) if _target.has_method("get_resource_type") else "mana"
		_apply_resource_bar_color(r_type_m)
		var cur_m: int = int(_target.call("get_current_resource"))
		var mx_m: int = max(1, int(_target.call("get_max_resource")))
		mana_bar.max_value = mx_m
		mana_bar.value = clamp(cur_m, 0, mx_m)
		mana_text.text = "%d/%d" % [clamp(cur_m, 0, mx_m), mx_m]
		return

	if not _target.has_node("Components/Resource"):
		mana_row.visible = false
		return

	var r: Node = _target.get_node("Components/Resource")
	if r == null:
		mana_row.visible = false
		return

	mana_row.visible = true
	if r.has_method("sync_from_owner_fields_if_mana"):
		r.call("sync_from_owner_fields_if_mana")
	var r_type: String = String(r.get("resource_type"))
	_apply_resource_bar_color(r_type)
	if r.has_method("get_text"):
		mana_text.text = String(r.call("get_text"))
	else:
		mana_text.text = ""

	var mx_r: int = max(1, int(r.get("max_resource")))
	var cur_r: int = int(r.get("resource"))
	mana_bar.max_value = mx_r
	mana_bar.value = cur_r

func _update_relation_color() -> void:
	if panel == null:
		return

	var player_faction: String = "blue"
	if _player != null and is_instance_valid(_player) and _player.has_method("get_faction_id"):
		player_faction = String(_player.call("get_faction_id"))

	var target_faction: String = ""
	if _target != null and is_instance_valid(_target):
		if _target.has_method("get_faction_id"):
			target_faction = String(_target.call("get_faction_id"))
		else:
			# мобов определяем по классу
			if _target is NormalAggresiveMob:
				target_faction = "aggressive_mob"
			elif _target is NormalNeutralMob:
				target_faction = "neutral_mob"

	var rel: int = FactionRules.relation(player_faction, target_faction)

	# FRIENDLY -> green, NEUTRAL -> yellow, HOSTILE -> red
	var color: Color
	if rel == FactionRules.Relation.FRIENDLY:
		color = Color(0.15, 0.55, 0.15, 0.45)
	elif rel == FactionRules.Relation.HOSTILE:
		color = Color(0.65, 0.15, 0.15, 0.4)
	else:
		color = Color(0.65, 0.55, 0.15, 0.5)

	var sb: StyleBoxFlat = null
	if _panel_stylebox_base is StyleBoxFlat:
		sb = (_panel_stylebox_base as StyleBoxFlat).duplicate()
	else:
		sb = StyleBoxFlat.new()
		sb.corner_radius_top_left = 12
		sb.corner_radius_top_right = 12
		sb.corner_radius_bottom_left = 12
		sb.corner_radius_bottom_right = 12

	sb.bg_color = color
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0, 0, 0, 1)
	panel.add_theme_stylebox_override("panel", sb)


func _update_effects() -> void:
	if _target == null or not is_instance_valid(_target):
		effects_root.visible = false
		_clear_grid(buff_grid)
		_clear_grid(debuff_grid)
		return
	var snap: Array = []
	if _target.has_method("get_buffs_snapshot"):
		snap = _target.call("get_buffs_snapshot") as Array
	elif "c_buffs" in _target and _target.c_buffs != null and _target.c_buffs.has_method("get_buffs_snapshot"):
		snap = _target.c_buffs.call("get_buffs_snapshot") as Array
	elif "c_stats" in _target and _target.c_stats != null and _target.c_stats.has_method("get_buffs_snapshot"):
		snap = _target.c_stats.call("get_buffs_snapshot") as Array
	_clear_grid(buff_grid)
	_clear_grid(debuff_grid)
	if snap.is_empty():
		effects_root.visible = false
		return
	var columns: int = maxi(1, int(floor(panel.size.x / 32.0)))
	buff_grid.columns = columns
	debuff_grid.columns = columns
	var max_icons: int = columns * 2
	var buff_count: int = 0
	var debuff_count: int = 0
	for entry in snap:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		var is_debuff: bool = _is_debuff_entry(d)
		if is_debuff and debuff_count >= max_icons:
			continue
		if not is_debuff and buff_count >= max_icons:
			continue
		var inst: Control = BUFF_ICON_SCENE.instantiate() as Control
		if inst == null:
			continue
		inst.custom_minimum_size = Vector2(30, 30)
		if is_debuff:
			debuff_grid.add_child(inst)
		else:
			buff_grid.add_child(inst)
		if inst is BuffIcon:
			(inst as BuffIcon).setup(_target, d)
		if is_debuff:
			debuff_count += 1
		else:
			buff_count += 1
	effects_root.visible = (buff_count + debuff_count) > 0
	buff_grid.visible = buff_count > 0
	debuff_grid.visible = debuff_count > 0

func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		child.queue_free()

func _is_debuff_entry(data: Dictionary) -> bool:
	if bool(data.get("is_debuff", false)):
		return true
	if data.has("data") and data.get("data") is Dictionary:
		var inner: Dictionary = data.get("data", {}) as Dictionary
		if bool(inner.get("is_debuff", false)):
			return true
		return String(inner.get("source", "")) == "debuff"
	return String(data.get("source", "")) == "debuff"

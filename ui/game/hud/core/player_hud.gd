extends CanvasLayer

@onready var name_label: Label = $Root/Panel/Margin/VBox/Header/NameLabel
@onready var level_label: Label = $Root/Panel/Margin/VBox/Header/LevelLabel

@onready var hp_bar: ProgressBar = $Root/Panel/Margin/VBox/HpRow/HpBar
@onready var hp_text: Label = $Root/Panel/Margin/VBox/HpRow/HpBar/HpText

@onready var mana_bar: ProgressBar = $Root/Panel/Margin/VBox/ManaRow/ManaBar
@onready var mana_text: Label = $Root/Panel/Margin/VBox/ManaRow/ManaBar/ManaText

var _player: Node = null
var _mana_fill_color: Color = Color(0.23921569, 0.0, 1.0, 1.0)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_cache_mana_fill_color()

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
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	var n: String = ""
	if has_node("/root/AppState"):
		var d: Dictionary = get_node("/root/AppState").get("selected_character_data")
		if d is Dictionary and d.has("name"):
			n = String(d.get("name", "")).strip_edges()
	if n == "" and _player.has_method("get_display_name"):
		n = String(_player.call("get_display_name")).strip_edges()
	name_label.text = n

	# Level
	var lvl_v: Variant = _player.get("level")
	if lvl_v != null:
		level_label.text = tr("ui.hud.level.short") % int(lvl_v)
	else:
		level_label.text = ""

	# HP
	var cur_hp_v: Variant = _player.get("current_hp")
	var mx_hp_v: Variant = _player.get("max_hp")
	if cur_hp_v != null and mx_hp_v != null:
		var cur_hp: int = int(cur_hp_v)
		var mx_hp: int = max(1, int(mx_hp_v))

		hp_text.text = "%d/%d" % [cur_hp, mx_hp]
		hp_bar.max_value = mx_hp
		hp_bar.value = cur_hp
	else:
		hp_text.text = ""
		hp_bar.max_value = 1
		hp_bar.value = 1

	# Resource
	if _player.has_node("Components/Resource"):
		var r: Node = _player.get_node("Components/Resource")
		if r != null:
			if r.has_method("sync_from_owner_fields_if_mana"):
				r.call("sync_from_owner_fields_if_mana")
			var r_type: String = String(r.get("resource_type"))
			_apply_resource_bar_color(r_type)
			var r_text: String = ""
			if r.has_method("get_text"):
				r_text = String(r.call("get_text"))
			mana_text.text = r_text
			var mx_r: int = max(1, int(r.get("max_resource")))
			var cur_r: int = int(r.get("resource"))
			mana_bar.max_value = mx_r
			mana_bar.value = cur_r
			return

	var cur_m_v: Variant = _player.get("mana")
	var mx_m_v: Variant = _player.get("max_mana")
	if cur_m_v != null and mx_m_v != null:
		var cur_m: int = int(cur_m_v)
		var mx_m: int = max(1, int(mx_m_v))

		_apply_resource_bar_color("mana")
		var resource_label := tr("ui.hud.resource.mana")
		var player_resource_type := String(_player.get("resource_type")).to_lower()
		if player_resource_type == "rage":
			resource_label = tr("ui.hud.resource.rage")
		mana_text.text = tr("ui.hud.resource.value") % [resource_label, cur_m, mx_m]
		mana_bar.max_value = mx_m
		mana_bar.value = cur_m
	else:
		_apply_resource_bar_color("mana")
		mana_text.text = ""
		mana_bar.max_value = 1
		mana_bar.value = 1

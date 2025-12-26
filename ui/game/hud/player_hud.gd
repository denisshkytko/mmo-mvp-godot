extends CanvasLayer

@onready var name_label: Label = $Panel/Margin/VBox/Header/NameLabel
@onready var level_label: Label = $Panel/Margin/VBox/Header/LevelLabel

@onready var hp_bar: ProgressBar = $Panel/Margin/VBox/HpRow/HpBar
@onready var hp_text: Label = $Panel/Margin/VBox/HpRow/HpBar/HpText

@onready var mana_bar: ProgressBar = $Panel/Margin/VBox/ManaRow/ManaBar
@onready var mana_text: Label = $Panel/Margin/VBox/ManaRow/ManaBar/ManaText

var _player: Node = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	var n: String = "Player"
	if has_node("/root/AppState"):
		var d: Dictionary = get_node("/root/AppState").get("selected_character_data")
		if d is Dictionary and d.has("name"):
			n = String(d.get("name", "Player"))
	name_label.text = n

	# Level
	var lvl_v: Variant = _player.get("level")
	if lvl_v != null:
		level_label.text = "lv %d" % int(lvl_v)
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

	# Mana
	var cur_m_v: Variant = _player.get("mana")
	var mx_m_v: Variant = _player.get("max_mana")
	if cur_m_v != null and mx_m_v != null:
		var cur_m: int = int(cur_m_v)
		var mx_m: int = max(1, int(mx_m_v))

		mana_text.text = "%d/%d" % [cur_m, mx_m]
		mana_bar.max_value = mx_m
		mana_bar.value = cur_m
	else:
		mana_text.text = ""
		mana_bar.max_value = 1
		mana_bar.value = 1

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

	name_label.text = "player"

	# Level
	if "level" in _player:
		level_label.text = "lv %d" % int(_player.level)
	else:
		level_label.text = ""

	# HP
	if ("current_hp" in _player) and ("max_hp" in _player):
		var cur_hp: int = int(_player.current_hp)
		var mx_hp: int = max(1, int(_player.max_hp))
		hp_text.text = "%d/%d" % [cur_hp, mx_hp]

		hp_bar.max_value = mx_hp
		hp_bar.value = cur_hp
	else:
		hp_text.text = ""
		hp_bar.max_value = 1
		hp_bar.value = 1

	# Mana
	if ("mana" in _player) and ("max_mana" in _player):
		var cur_m: int = int(_player.mana)
		var mx_m: int = max(1, int(_player.max_mana))
		mana_text.text = "%d/%d" % [cur_m, mx_m]

		mana_bar.max_value = mx_m
		mana_bar.value = cur_m
	else:
		mana_text.text = ""
		mana_bar.max_value = 1
		mana_bar.value = 1

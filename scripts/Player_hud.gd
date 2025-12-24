extends CanvasLayer

@onready var panel: Panel = $Panel

@onready var name_label: Label = $Panel/Margin/VBox/Header/NameLabel
@onready var level_label: Label = $Panel/Margin/VBox/Header/LevelLabel

@onready var hp_back: ColorRect = $Panel/Margin/VBox/HpRow/HpBack
@onready var hp_fill: ColorRect = $Panel/Margin/VBox/HpRow/HpBack/HpFill
@onready var hp_text: Label = $Panel/Margin/VBox/HpRow/HpBack/HpText

@onready var mana_back: ColorRect = $Panel/Margin/VBox/ManaRow/ManaBack
@onready var mana_fill: ColorRect = $Panel/Margin/VBox/ManaRow/ManaBack/ManaFill
@onready var mana_text: Label = $Panel/Margin/VBox/ManaRow/ManaBack/ManaText

var _player: Node = null
var _hp_full_w: float = 0.0
var _mana_full_w: float = 0.0

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")

	# чтобы размеры уже были рассчитаны
	await get_tree().process_frame
	_hp_full_w = hp_back.size.x
	_mana_full_w = mana_back.size.x

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	# Name (пока фикс)
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
		hp_fill.size.x = _hp_full_w * clamp(float(cur_hp) / float(mx_hp), 0.0, 1.0)
	else:
		hp_text.text = ""
		hp_fill.size.x = _hp_full_w

	# Mana
	if ("mana" in _player) and ("max_mana" in _player):
		var cur_m: int = int(_player.mana)
		var mx_m: int = max(1, int(_player.max_mana))
		mana_text.text = "%d/%d" % [cur_m, mx_m]
		mana_fill.size.x = _mana_full_w * clamp(float(cur_m) / float(mx_m), 0.0, 1.0)
	else:
		mana_text.text = ""
		mana_fill.size.x = _mana_full_w

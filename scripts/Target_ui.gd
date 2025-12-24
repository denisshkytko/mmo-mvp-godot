extends CanvasLayer

@onready var panel: Panel = $Panel
@onready var name_label: Label = $Panel/NameLabel
@onready var hp_fill: ColorRect = $Panel/HpFill
@onready var hp_text: Label = $Panel/HpText
@onready var hp_back: ColorRect = $Panel/HpBack

var _gm: Node = null
var _target: Node2D = null
var _full_width: float = 0.0

func _ready() -> void:
	panel.visible = false
	_gm = get_tree().get_first_node_in_group("game_manager")
	await get_tree().process_frame
	_full_width = hp_back.size.x

func _process(_delta: float) -> void:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
		return

	if not _gm.has_method("get_target"):
		return

	var t = _gm.call("get_target")
	if t == null or not (t is Node2D) or not is_instance_valid(t):
		_target = null
		panel.visible = false
		return

	_target = t as Node2D
	panel.visible = true

	# Name + level
	var lvl_text := ""
	var lvl_val = _target.get("mob_level")
	if lvl_val != null:
		lvl_text = " (lv %d)" % int(lvl_val)

	name_label.text = _target.name + lvl_text

	# HP values
	var cur_val = _target.get("current_hp")
	var mx_val = _target.get("max_hp")

	if cur_val != null and mx_val != null:
		var cur: int = int(cur_val)
		var mx: int = max(1, int(mx_val))

		hp_text.text = "%d/%d" % [cur, mx]
		var ratio: float = clamp(float(cur) / float(mx), 0.0, 1.0)
		hp_fill.size.x = _full_width * ratio
	else:
		hp_text.text = ""
		hp_fill.size.x = _full_width

extends CanvasLayer

@onready var fill: ColorRect = $Root/BarPanel/XpBar/Fill
@onready var xp_text: Label = $Root/BarPanel/XpBar/XpText
@onready var xp_bar: Control = $Root/BarPanel/XpBar

var player: Node = null
var _full_width: float = 0.0

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	await get_tree().process_frame
	_full_width = xp_bar.size.x

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	var cur_v: Variant = player.get("xp")
	var need_v: Variant = player.get("xp_to_next")
	if cur_v == null or need_v == null:
		return

	var cur: int = int(cur_v)
	var need: int = max(1, int(need_v))

	xp_text.text = "%d/%d" % [cur, need]

	var ratio: float = clamp(float(cur) / float(need), 0.0, 1.0)
	fill.size.x = _full_width * ratio

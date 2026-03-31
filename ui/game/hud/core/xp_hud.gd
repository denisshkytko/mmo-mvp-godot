extends CanvasLayer
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")

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
	var t_total := Time.get_ticks_usec()
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		visible = false
		return

	if player.has_method("is_level_capped") and bool(player.call("is_level_capped")):
		visible = false
		return
	visible = true

	var cur_v: Variant = player.get("xp")
	var need_v: Variant = player.get("xp_to_next")
	if cur_v == null or need_v == null:
		return

	var cur: int = int(cur_v)
	var need: int = max(1, int(need_v))

	xp_text.text = "%d/%d" % [cur, need]

	var ratio: float = clamp(float(cur) / float(need), 0.0, 1.0)
	fill.size.x = _full_width * ratio
	FRAME_PROFILER.add_usec("process.hud.xp.total", Time.get_ticks_usec() - t_total)

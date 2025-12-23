extends CanvasLayer

@onready var level_label: Label = $Root/BarPanel/LevelBadge/LevelLabel
@onready var fill: ColorRect = $Root/BarPanel/XpBar/Fill
@onready var xp_text: Label = $Root/BarPanel/XpBar/XpText
@onready var xp_bar: Control = $Root/BarPanel/XpBar

var player: Node = null
var _full_width: float = 0.0

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	_full_width = xp_bar.size.x

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	# Player должен иметь level/xp/xp_to_next (мы их добавили)
	var lvl: int = int(player.level)
	var cur: int = int(player.xp)
	var need: int = max(1, int(player.xp_to_next))

	level_label.text = str(lvl)
	xp_text.text = "%d/%d" % [cur, need]

	var ratio: float = float(cur) / float(need)
	ratio = clamp(ratio, 0.0, 1.0)

	# меняем ширину Fill, чтобы бар заполнялся
	fill.size.x = _full_width * ratio

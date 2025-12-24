extends CanvasLayer

@onready var skill_panel: Panel = $Root/Skill1
@onready var cd_text: Label = $Root/Skill1/Inner/CooldownText
@onready var range_overlay: ColorRect = $Root/Skill1/RangeOverlay
@onready var icon: TextureRect = $Root/Skill1/Inner/Icon
@onready var cd_text_shadow: Label = $Root/Skill1/Inner/CooldownTextShadow
@onready var inner: Control = $Root/Skill1/Inner
@onready var overlay: ColorRect = $Root/Skill1/Inner/CooldownOverlay

var _player: Node2D = null
var _gm: Node = null


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_gm = get_tree().get_first_node_in_group("game_manager")

	overlay.visible = false
	cd_text.text = ""

	# клики/тапы по панели
	skill_panel.gui_input.connect(_on_gui_input)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return

	_update_cooldown()
	_update_range_state()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_cast()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_cast()

func _cast() -> void:
	if _player != null and _player.has_method("try_cast_skill_1"):
		_player.call("try_cast_skill_1")


func _update_cooldown() -> void:
	# без Variant inference: проверяем поля через "in"
	if not (("_skill_1_timer" in _player) and ("skill_1_cooldown" in _player)):
		overlay.visible = false
		cd_text.text = ""
		return

	var left: float = float(_player._skill_1_timer)
	var total: float = max(0.001, float(_player.skill_1_cooldown))

	if left <= 0.0:
		overlay.visible = false
		cd_text.text = ""
		cd_text_shadow.text = ""
	else:
		overlay.visible = true
		var s := "%.1f" % left
		cd_text.text = s
		cd_text_shadow.text = s

		# overlay закрывает иконку сверху вниз
		var h: float = inner.size.y
		var ratio: float = clamp(left / total, 0.0, 1.0)
		overlay.size.y = h * ratio
		overlay.position.y = 0.0


func _update_range_state() -> void:
	var out: bool = _is_target_out_of_range()
	if out:
		# ярко красная рамка
		range_overlay.color = Color(1, 0, 0, 0.55)
	else:
		# “нормальный” белый/светлый
		range_overlay.color = Color(1, 1, 1, 0.35)


func _is_target_out_of_range() -> bool:
	if _gm == null or not is_instance_valid(_gm):
		_gm = get_tree().get_first_node_in_group("game_manager")
		return false

	if not _gm.has_method("get_target"):
		return false

	var t = _gm.call("get_target")
	if t == null or not (t is Node2D) or not is_instance_valid(t):
		return false

	if not ("skill_1_range" in _player):
		return false

	var dist: float = _player.global_position.distance_to((t as Node2D).global_position)
	return dist > float(_player.skill_1_range)

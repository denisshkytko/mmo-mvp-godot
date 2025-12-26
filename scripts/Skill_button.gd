extends Control

@export var skill_index: int = 1  # 1 / 2 / 3

@onready var mana_cost_text: Label = $Inner/ManaCostText
@onready var range_overlay: ColorRect = $RangeOverlay
@onready var inner: Control = $Inner
@onready var overlay: ColorRect = $Inner/CooldownOverlay
@onready var cd_text_shadow: Label = $Inner/CooldownTextShadow
@onready var cd_text: Label = $Inner/CooldownText

var _player: Node2D = null
var _gm: Node = null

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_gm = get_tree().get_first_node_in_group("game_manager")

	if overlay != null:
		overlay.visible = false
	if cd_text != null:
		cd_text.text = ""
	if cd_text_shadow != null:
		cd_text_shadow.text = ""
	if mana_cost_text != null:
		mana_cost_text.text = ""

	gui_input.connect(_on_gui_input)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return

	_update_cooldown()
	_update_range_state()
	_update_mana_cost()

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
	if _player == null:
		return

	if skill_index == 1:
		if _player.has_method("try_cast_skill_1"):
			_player.call("try_cast_skill_1")
	elif skill_index == 2:
		if _player.has_method("try_cast_skill_2"):
			_player.call("try_cast_skill_2")
	elif skill_index == 3:
		if _player.has_method("try_cast_skill_3"):
			_player.call("try_cast_skill_3")

func _update_cooldown() -> void:
	var left: float = 0.0
	var total: float = 0.0

	if skill_index == 1:
		if not (("_skill_1_timer" in _player) and ("skill_1_cooldown" in _player)):
			_hide_cd()
			return
		left = float(_player._skill_1_timer)
		total = max(0.001, float(_player.skill_1_cooldown))

	elif skill_index == 2:
		if not (("_skill_2_timer" in _player) and ("skill_2_cooldown" in _player)):
			_hide_cd()
			return
		left = float(_player._skill_2_timer)
		total = max(0.001, float(_player.skill_2_cooldown))

	elif skill_index == 3:
		if not (("_skill_3_timer" in _player) and ("skill_3_cooldown" in _player)):
			_hide_cd()
			return
		left = float(_player._skill_3_timer)
		total = max(0.001, float(_player.skill_3_cooldown))

	if left <= 0.0:
		_hide_cd()
		return

	overlay.visible = true
	var s := "%.1f" % left
	cd_text.text = s
	cd_text_shadow.text = s

	# заливка кулдауна сверху вниз
	var h: float = inner.size.y
	var ratio: float = clamp(left / total, 0.0, 1.0)
	overlay.size.y = h * ratio
	overlay.position.y = 0.0

func _hide_cd() -> void:
	overlay.visible = false
	cd_text.text = ""
	cd_text_shadow.text = ""

func _update_range_state() -> void:
	# Skill2 (heal) и Skill3 (self-buff) не зависят от дистанции
	if skill_index == 2 or skill_index == 3:
		range_overlay.color = Color(1, 1, 1, 0.35)
		return

	var out: bool = _is_target_out_of_range()
	range_overlay.color = Color(1, 0, 0, 0.55) if out else Color(1, 1, 1, 0.35)

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

func _update_mana_cost() -> void:
	if mana_cost_text == null or _player == null:
		return
	if not ("mana" in _player):
		mana_cost_text.text = ""
		return

	var cur_mana: int = int(_player.mana)
	var cost: int = 0

	if skill_index == 1:
		if "skill_1_mana_cost" in _player:
			cost = int(_player.skill_1_mana_cost)
	elif skill_index == 2:
		if "skill_2_mana_cost" in _player:
			cost = int(_player.skill_2_mana_cost)
	elif skill_index == 3:
		if "skill_3_mana_cost" in _player:
			cost = int(_player.skill_3_mana_cost)

	mana_cost_text.text = str(cost)

	if cur_mana >= cost:
		mana_cost_text.modulate = Color(0.35, 0.7, 1.0, 1.0)  # blue
	else:
		mana_cost_text.modulate = Color(1.0, 0.25, 0.25, 1.0)  # red

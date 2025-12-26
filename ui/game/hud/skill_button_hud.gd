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
		if not _player.has_method("get_skill_1_cooldown_left"):
			_hide_cd()
			return
		var total_v: Variant = _player.get("skill_1_cooldown")
		if total_v == null:
			_hide_cd()
			return
		left = float(_player.call("get_skill_1_cooldown_left"))
		total = max(0.001, float(total_v))

	elif skill_index == 2:
		if not _player.has_method("get_skill_2_cooldown_left"):
			_hide_cd()
			return
		var total_v2: Variant = _player.get("skill_2_cooldown")
		if total_v2 == null:
			_hide_cd()
			return
		left = float(_player.call("get_skill_2_cooldown_left"))
		total = max(0.001, float(total_v2))

	elif skill_index == 3:
		if not _player.has_method("get_skill_3_cooldown_left"):
			_hide_cd()
			return
		var total_v3: Variant = _player.get("skill_3_cooldown")
		if total_v3 == null:
			_hide_cd()
			return
		left = float(_player.call("get_skill_3_cooldown_left"))
		total = max(0.001, float(total_v3))

	if left <= 0.0:
		_hide_cd()
		return

	overlay.visible = true
	var s := "%.1f" % left
	cd_text.text = s
	cd_text_shadow.text = s

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

	var r_v: Variant = _player.get("skill_1_range")
	if r_v == null:
		return false

	var dist: float = _player.global_position.distance_to((t as Node2D).global_position)
	return dist > float(r_v)

func _update_mana_cost() -> void:
	if mana_cost_text == null or _player == null:
		return

	var cur_mana_v: Variant = _player.get("mana")
	if cur_mana_v == null:
		mana_cost_text.text = ""
		return

	var cur_mana: int = int(cur_mana_v)
	var cost: int = 0

	if skill_index == 1:
		var c1: Variant = _player.get("skill_1_mana_cost")
		if c1 != null:
			cost = int(c1)
	elif skill_index == 2:
		var c2: Variant = _player.get("skill_2_mana_cost")
		if c2 != null:
			cost = int(c2)
	elif skill_index == 3:
		var c3: Variant = _player.get("skill_3_mana_cost")
		if c3 != null:
			cost = int(c3)

	mana_cost_text.text = str(cost)

	# Важно: цвета можно оставить как были (это чисто визуал)
	if cur_mana >= cost:
		mana_cost_text.modulate = Color(0.35, 0.7, 1.0, 1.0)
	else:
		mana_cost_text.modulate = Color(1.0, 0.25, 0.25, 1.0)

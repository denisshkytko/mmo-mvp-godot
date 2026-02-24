extends Control
class_name BuffIcon

@onready var time_label: Label = $TimeText
@onready var icon_rect: TextureRect = $Icon

var _player: Node = null
var _buff_id: String = ""
var _time_left: float = 0.0
var _show_time: bool = true
var _is_debuff: bool = false

func setup(player: Node, data: Dictionary) -> void:
	_player = player
	_buff_id = String(data.get("id", ""))
	_time_left = float(data.get("time_left", 0.0))
	_show_time = _should_show_time(data)
	_is_debuff = _detect_debuff(data)
	_refresh_icon(data)
	_refresh_frame()
	_refresh_time()

func update_data(data: Dictionary) -> void:
	_show_time = _should_show_time(data)
	_is_debuff = _detect_debuff(data)
	_refresh_icon(data)
	_refresh_frame()
	_refresh_time()

func update_time(left: float) -> void:
	_time_left = max(0.0, left)
	_refresh_time()

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# снять баф
			if _player != null and is_instance_valid(_player) and _player.has_method("remove_buff"):
				_player.call("remove_buff", _buff_id)

func _refresh_time() -> void:
	if time_label == null:
		return
	time_label.visible = _show_time
	if not _show_time:
		time_label.text = ""
		return
	time_label.text = _format_time(_time_left)

func _refresh_icon(data: Dictionary) -> void:
	if icon_rect == null:
		return
	var ability_id := ""
	if data.has("ability_id"):
		ability_id = String(data.get("ability_id", ""))
	elif data.has("data") and data.get("data") is Dictionary:
		var inner: Dictionary = data.get("data", {}) as Dictionary
		if inner.has("ability_id"):
			ability_id = String(inner.get("ability_id", ""))
		elif inner.has("source_ability"):
			ability_id = String(inner.get("source_ability", ""))
	if ability_id == "":
		return
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return
	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def != null:
		icon_rect.texture = def.icon

func _should_show_time(data: Dictionary) -> bool:
	var source := String(data.get("source", ""))
	if source == "aura" or source == "stance" or source == "passive":
		return false
	var left: float = float(data.get("time_left", 0.0))
	if left >= 999999.0:
		return false
	return true

func _format_time(seconds: float) -> String:
	var s: int = int(ceil(max(0.0, seconds)))

	# >= 1 hour => show "Nh" rounded: 1h for 1:00–1:29, 2h for 1:30–2:29, etc.
	if s >= 3600:
		var hours_f: float = float(s) / 3600.0
		var hours: int = int(floor(hours_f + 0.5))
		if hours < 1:
			hours = 1
		return "%d h" % hours

	# >= 1 minute => show "Nm" in whole minutes
	if s >= 60:
		var mins: int = int(ceil(float(s) / 60.0))
		return "%d m" % mins

	# < 1 minute => show seconds
	return "%d s" % s

func _refresh_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.85, 0.2, 0.2, 1.0) if _is_debuff else Color(0.75, 0.75, 0.75, 1.0)
	add_theme_stylebox_override("panel", sb)

func _detect_debuff(data: Dictionary) -> bool:
	if bool(data.get("is_debuff", false)):
		return true
	if data.has("data") and data.get("data") is Dictionary:
		var inner: Dictionary = data.get("data", {}) as Dictionary
		if bool(inner.get("is_debuff", false)):
			return true
	var source := String(data.get("source", ""))
	if source == "debuff":
		return true
	if data.has("data") and data.get("data") is Dictionary:
		var inner2: Dictionary = data.get("data", {}) as Dictionary
		return String(inner2.get("source", "")) == "debuff"
	return false

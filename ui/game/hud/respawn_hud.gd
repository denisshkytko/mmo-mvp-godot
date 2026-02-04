extends CanvasLayer
class_name RespawnHUD

@onready var panel: Panel = $Root/Panel
@onready var title_label: Label = $Root/Panel/VBox/TitleLabel
@onready var timer_label: Label = $Root/Panel/VBox/TimerLabel
@onready var respawn_button: Button = $Root/Panel/VBox/RespawnButton

var _player: Node = null
var _time_left: float = 0.0
var _active: bool = false

func _ready() -> void:
	panel.visible = false
	respawn_button.pressed.connect(_on_respawn_pressed)

func open(player: Node, seconds: float) -> void:
	_player = player
	_time_left = seconds
	_active = true
	panel.visible = true
	title_label.text = "You died"
	_update_timer_label()

func close() -> void:
	_active = false
	panel.visible = false
	_player = null

func _process(delta: float) -> void:
	if not _active:
		return

	_time_left = max(0.0, _time_left - delta)
	_update_timer_label()

	if _time_left <= 0.0:
		_force_respawn()

func _update_timer_label() -> void:
	timer_label.text = "Respawn in %.1f" % _time_left

func _on_respawn_pressed() -> void:
	_force_respawn()

func _force_respawn() -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("respawn_now"):
		_player.call("respawn_now")

		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm != null and gm.has_method("request_save"):
			gm.call("request_save", "respawn")

	close()

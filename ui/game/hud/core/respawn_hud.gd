extends CanvasLayer
class_name RespawnHUD

@onready var panel: Panel = $Root/Panel
@onready var title_label: Label = $Root/Panel/VBox/TitleLabel
@onready var timer_label: Label = $Root/Panel/VBox/TimerLabel
@onready var respawn_button: Button = $Root/Panel/VBox/RespawnButton
@onready var spirits_aid_button: Button = $Root/Panel/VBox/SpiritsAidButton

var _player: Node = null
var _time_left: float = 0.0
var _active: bool = false

func _ready() -> void:
	panel.visible = false
	respawn_button.text = tr("ui.respawn.button")
	respawn_button.pressed.connect(_on_respawn_pressed)
	spirits_aid_button.visible = false
	spirits_aid_button.text = tr("ability.spirits_aid.name")
	spirits_aid_button.pressed.connect(_on_spirits_aid_pressed)

func open(player: Node, seconds: float) -> void:
	_player = player
	_time_left = seconds
	_active = true
	panel.visible = true
	title_label.text = tr("You died")
	_update_timer_label()
	_refresh_spirits_aid_button()

func close() -> void:
	_active = false
	panel.visible = false
	_player = null
	if spirits_aid_button != null:
		spirits_aid_button.visible = false

func _process(delta: float) -> void:
	if not _active:
		return

	_time_left = max(0.0, _time_left - delta)
	_update_timer_label()
	_refresh_spirits_aid_button()

	if _time_left <= 0.0:
		_force_respawn()

func _update_timer_label() -> void:
	timer_label.text = tr("Respawn in %.1f") % _time_left

func _refresh_spirits_aid_button() -> void:
	if spirits_aid_button == null:
		return
	var can_use := false
	if _player != null and is_instance_valid(_player) and _player.has_method("can_use_spirits_aid_on_death"):
		can_use = bool(_player.call("can_use_spirits_aid_on_death"))
	spirits_aid_button.visible = can_use

func _on_respawn_pressed() -> void:
	_force_respawn()

func _on_spirits_aid_pressed() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.has_method("use_spirits_aid_respawn"):
		return
	if bool(_player.call("use_spirits_aid_respawn")):
		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm != null and gm.has_method("request_save"):
			gm.call("request_save", "spirit_aid_used")
		close()

func _force_respawn() -> void:
	if _player != null and is_instance_valid(_player) and _player.has_method("respawn_now"):
		_player.call("respawn_now")

		var gm: Node = get_tree().get_first_node_in_group("game_manager")
		if gm != null and gm.has_method("request_save"):
			gm.call("request_save", "respawn")

	close()

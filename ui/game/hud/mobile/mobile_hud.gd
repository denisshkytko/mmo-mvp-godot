extends CanvasLayer
class_name MobileHUD

@onready var move_stick: MoveJoystick = $Root/LeftPad/MoveStick
@onready var skill_pad: SkillPad = $Root/RightPad/SkillPad

var _player: Node = null


func _ready() -> void:
	visible = _is_mobile_enabled()
	if not visible:
		return
	_player = NodeCache.get_player(get_tree())
	if _player == null or not is_instance_valid(_player):
		return
	if move_stick != null:
		move_stick.move_dir_changed.connect(_on_move_dir_changed)
	if skill_pad != null:
		skill_pad.skill_pressed.connect(_on_skill_pressed)
		skill_pad.interact_pressed.connect(_on_interact_pressed)
		var detector := _player.get_node_or_null("InteractionDetector")
		if detector != null and detector.has_signal("interactable_changed"):
			detector.interactable_changed.connect(_on_interactable_changed)


func _is_mobile_enabled() -> bool:
	var mobile_flag := false
	if ProjectSettings.has_setting("application/config/mobile_ui_enabled"):
		mobile_flag = bool(ProjectSettings.get_setting("application/config/mobile_ui_enabled"))
	return true \
		or mobile_flag \
		or OS.has_feature("mobile") \
		or OS.has_feature("android") \
		or OS.has_feature("ios")


func _on_move_dir_changed(dir: Vector2) -> void:
	if _player != null and _player.has_method("set_mobile_move_dir"):
		_player.call("set_mobile_move_dir", dir)


func _on_skill_pressed(slot_index: int) -> void:
	if _player != null and _player.has_method("try_use_skill_slot"):
		_player.call("try_use_skill_slot", slot_index)


func _on_interact_pressed() -> void:
	if _player != null and _player.has_method("try_interact"):
		_player.call("try_interact")


func _on_interactable_changed(available: bool, _target: Node) -> void:
	if skill_pad != null:
		skill_pad.set_interact_visible(available)

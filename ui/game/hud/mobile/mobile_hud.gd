extends CanvasLayer
class_name MobileHUD

@onready var move_stick: MoveJoystick = $Root/LeftPad/MoveStick
@onready var skill_pad: SkillPad = $Root/RightPad/SkillPad

var _player: Node = null
var _base_visible: bool = false
var _inventory_ui: Node = null
var _character_ui: Node = null
var _merchant_ui: Node = null
var _menu_ui: Node = null
var _inventory_open: bool = false
var _character_open: bool = false
var _merchant_open: bool = false
var _menu_open: bool = false


func _ready() -> void:
	_base_visible = _is_mobile_enabled()
	visible = _base_visible
	if not _base_visible:
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
			_on_interactable_changed(bool(detector.get("interact_available")), detector.get("current_interactable"))
	_init_window_tracking()


func _init_window_tracking() -> void:
	_inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	if _inventory_ui != null and _inventory_ui.has_signal("hud_visibility_changed"):
		_inventory_ui.hud_visibility_changed.connect(_on_inventory_visibility_changed)
		if _inventory_ui.has_method("is_open"):
			_inventory_open = bool(_inventory_ui.call("is_open"))
	_character_ui = get_tree().get_first_node_in_group("character_hud")
	if _character_ui != null and _character_ui.has_signal("hud_visibility_changed"):
		_character_ui.hud_visibility_changed.connect(_on_character_visibility_changed)
		if _character_ui.has_method("is_open"):
			_character_open = bool(_character_ui.call("is_open"))
	_merchant_ui = get_tree().get_first_node_in_group("merchant_hud")
	if _merchant_ui != null and _merchant_ui.has_signal("hud_visibility_changed"):
		_merchant_ui.hud_visibility_changed.connect(_on_merchant_visibility_changed)
		if _merchant_ui.has_method("is_open"):
			_merchant_open = bool(_merchant_ui.call("is_open"))
	_menu_ui = get_tree().get_first_node_in_group("menu_hud")
	if _menu_ui != null and _menu_ui.has_signal("hud_visibility_changed"):
		_menu_ui.hud_visibility_changed.connect(_on_menu_visibility_changed)
		if _menu_ui.has_method("is_open"):
			_menu_open = bool(_menu_ui.call("is_open"))
	_update_visibility()


func _update_visibility() -> void:
	visible = _base_visible and not (_inventory_open or _character_open or _merchant_open or _menu_open)


func _on_inventory_visibility_changed(is_open: bool) -> void:
	_inventory_open = is_open
	_update_visibility()


func _on_character_visibility_changed(is_open: bool) -> void:
	_character_open = is_open
	_update_visibility()


func _on_merchant_visibility_changed(is_open: bool) -> void:
	_merchant_open = is_open
	_update_visibility()


func _on_menu_visibility_changed(is_open: bool) -> void:
	_menu_open = is_open
	_update_visibility()


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

extends CanvasLayer

@onready var create_hud: Node = $Root/CreateCharacterHUD
@onready var select_hud: Node = $Root/CharacterSelectHUD

func _ready() -> void:
	if create_hud != null and create_hud.has_signal("character_created"):
		create_hud.connect("character_created", _on_character_created)

	_refresh_visibility()
	_connect_app_state()

func _connect_app_state() -> void:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		return
	if not app_state.state_changed.is_connected(_on_state_changed):
		app_state.state_changed.connect(_on_state_changed)
	_on_state_changed(app_state.current_state, app_state.current_state)

func _on_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == AppState.FlowState.CHARACTER_SELECT:
		_refresh_visibility()
		if select_hud != null and select_hud.has_method("reset_transient_ui"):
			select_hud.call("reset_transient_ui")
	else:
		if select_hud != null and select_hud.has_method("reset_transient_ui"):
			select_hud.call("reset_transient_ui")

func _refresh_visibility() -> void:
	var chars: Array[Dictionary] = AppState.get_characters()
	var has_any: bool = chars.size() > 0

	# CreateCharacterHUD всегда видим (чтобы можно было создавать несколько)
	if create_hud != null:
		create_hud.visible = true

	# вход в мир возможен только если есть хотя бы 1 персонаж
	if select_hud != null and select_hud.has_method("set_enter_enabled"):
		select_hud.call("set_enter_enabled", has_any)

	# обновляем список
	if select_hud != null and select_hud.has_method("refresh_list"):
		select_hud.call("refresh_list")


func _on_character_created(_char_id: String) -> void:
	_refresh_visibility()

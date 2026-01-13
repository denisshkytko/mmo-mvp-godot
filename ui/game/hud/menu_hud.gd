extends Control

@onready var menu_button: Button = $MenuButton
@onready var panel: Panel = $Panel
@onready var exit_world: Button = $Panel/Margin/VBox/ExitWorldButton
@onready var exit_game: Button = $Panel/Margin/VBox/ExitGameButton

func _ready() -> void:
	panel.visible = false
	menu_button.pressed.connect(_toggle)
	exit_world.pressed.connect(_exit_world)
	exit_game.pressed.connect(_exit_game)
	_connect_app_state()

func _connect_app_state() -> void:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		return
	if not app_state.state_changed.is_connected(_on_state_changed):
		app_state.state_changed.connect(_on_state_changed)
	_on_state_changed(app_state.current_state, app_state.current_state)

func _on_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == AppState.FlowState.WORLD:
		panel.visible = false
	else:
		panel.visible = false

func _toggle() -> void:
	panel.visible = not panel.visible

func _save_now() -> void:
	var gm: Node = get_tree().get_first_node_in_group("game_manager")
	if gm != null:
		if gm.has_method("save_now"):
			gm.call("save_now")
			return
		if gm.has_method("request_save"):
			gm.call("request_save", "menu_exit")

	# fallback: если save_now нет, просто пытаемся сохранить напрямую
	if has_node("/root/AppState"):
		var p: Node = get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("export_character_data") and AppState.selected_character_id != "":
			var data: Dictionary = p.call("export_character_data")
			AppState.save_selected_character(data)

func _exit_world() -> void:
	_save_now()
	if has_node("/root/AppState"):
		FlowRouter.go_character_select()

func _exit_game() -> void:
	_save_now()
	get_tree().quit()

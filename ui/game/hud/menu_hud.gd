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

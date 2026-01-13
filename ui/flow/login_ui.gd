extends Control

@onready var username_edit: LineEdit = $Root/Center/Panel/Margin/VBox/UsernameEdit
@onready var password_edit: LineEdit = $Root/Center/Panel/Margin/VBox/PasswordEdit
@onready var login_button: Button = $Root/Center/Panel/Margin/VBox/LoginButton
@onready var error_label: Label = $Root/Center/Panel/Margin/VBox/ErrorLabel

func _ready() -> void:
	error_label.text = ""
	login_button.pressed.connect(_on_login_pressed)
	username_edit.text_submitted.connect(func(_t: String) -> void: _try_login())
	password_edit.text_submitted.connect(func(_t: String) -> void: _try_login())

	# удобство при запуске
	username_edit.grab_focus()

func _on_login_pressed() -> void:
	_try_login()

func _try_login() -> void:
	if not Engine.has_singleton("AppState") and not has_node("/root/AppState"):
		# на всякий случай
		error_label.text = "AppState autoload missing"
		return

	var app_state: Node = get_node("/root/AppState")
	if app_state == null:
		error_label.text = "AppState autoload missing"
		return

	var ok: bool = false
	if app_state.has_method("login"):
		ok = bool(app_state.call("login", username_edit.text, password_edit.text))

	if ok:
		error_label.text = ""
		FlowRouter.go_character_select()
	else:
		error_label.text = "Invalid login or password"

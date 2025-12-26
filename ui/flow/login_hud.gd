extends Control

@onready var username_edit: LineEdit = $Center/Panel/Margin/VBox/UsernameEdit
@onready var password_edit: LineEdit = $Center/Panel/Margin/VBox/PasswordEdit
@onready var login_button: Button = $Center/Panel/Margin/VBox/LoginButton
@onready var error_label: Label = $Center/Panel/Margin/VBox/ErrorLabel

func _ready() -> void:
	error_label.text = ""
	username_edit.text = "admin"
	password_edit.text = "admin"

	login_button.pressed.connect(_on_login_pressed)

	# Enter в поле логина/пароля тоже логинит
	username_edit.text_submitted.connect(func(_t: String) -> void: _try_login())
	password_edit.text_submitted.connect(func(_t: String) -> void: _try_login())

	username_edit.grab_focus()

func _on_login_pressed() -> void:
	_try_login()

func _try_login() -> void:
	var app_state: Node = get_node_or_null("/root/AppState")
	if app_state == null:
		error_label.text = "AppState autoload missing"
		return

	var ok: bool = false
	if app_state.has_method("login"):
		ok = bool(app_state.call("login", username_edit.text, password_edit.text))

	if ok:
		error_label.text = ""
		if app_state.has_method("goto_character_select"):
			app_state.call("goto_character_select")
	else:
		error_label.text = "Invalid login or password"

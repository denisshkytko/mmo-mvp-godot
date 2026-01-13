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
	_connect_app_state()

func _connect_app_state() -> void:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		return
	if not app_state.state_changed.is_connected(_on_state_changed):
		app_state.state_changed.connect(_on_state_changed)
	_on_state_changed(app_state.current_state, app_state.current_state)

func _on_state_changed(_old_state: int, new_state: int) -> void:
	if new_state == AppState.FlowState.LOGIN:
		error_label.text = ""
		login_button.disabled = false
		username_edit.editable = true
		password_edit.editable = true
		username_edit.grab_focus()
	else:
		login_button.disabled = true
		username_edit.editable = false
		password_edit.editable = false

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
		FlowRouter.go_character_select()
	else:
		error_label.text = "Invalid login or password"

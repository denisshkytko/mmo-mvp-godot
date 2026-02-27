extends CanvasLayer

@onready var username_edit: LineEdit = $Root/Panel/Margin/VBox/UsernameEdit
@onready var password_edit: LineEdit = $Root/Panel/Margin/VBox/PasswordEdit
@onready var login_button: Button = $Root/Panel/Margin/VBox/LoginButton
@onready var error_label: Label = $Root/Panel/Margin/VBox/ErrorLabel
@onready var title_label: Label = $Root/Panel/Margin/VBox/Title

func _ready() -> void:
	if title_label != null:
		title_label.text = tr("ui.flow.login.title")
	if username_edit != null:
		username_edit.placeholder_text = tr("ui.flow.login.username")
	if password_edit != null:
		password_edit.placeholder_text = tr("ui.flow.login.password")
	if login_button != null:
		login_button.text = tr("ui.flow.login.sign_in")

	error_label.text = ""
	username_edit.text = "admin"
	password_edit.text = "admin"
	username_edit.focus_mode = Control.FOCUS_CLICK
	password_edit.focus_mode = Control.FOCUS_CLICK
	login_button.focus_mode = Control.FOCUS_NONE

	login_button.pressed.connect(_on_login_pressed)

	# Enter в поле логина/пароля тоже логинит
	username_edit.text_submitted.connect(func(_t: String) -> void: _try_login())
	password_edit.text_submitted.connect(func(_t: String) -> void: _try_login())

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
	else:
		login_button.disabled = true
		username_edit.editable = false
		password_edit.editable = false

func _on_login_pressed() -> void:
	_try_login()

func _try_login() -> void:
	var app_state: Node = get_node_or_null("/root/AppState")
	if app_state == null:
		error_label.text = tr("ui.flow.login.error.service_unavailable")
		push_error("AppState autoload missing")
		return

	var ok: bool = false
	if app_state.has_method("login"):
		ok = bool(app_state.call("login", username_edit.text, password_edit.text))

	if ok:
		error_label.text = ""
		FlowRouter.go_character_select()
	else:
		error_label.text = tr("ui.flow.login.error.invalid_credentials")

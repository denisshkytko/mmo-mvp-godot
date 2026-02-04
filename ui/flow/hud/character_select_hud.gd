extends CanvasLayer

@onready var list: ItemList = $Root/Panel/Margin/VBox/CharacterList
@onready var delete_button: Button = $Root/Panel/Margin/VBox/Buttons/DeleteButton
@onready var enter_button: Button = $Root/Panel/Margin/VBox/Buttons/EnterButton
@onready var logout_button: Button = $Root/Panel/Margin/VBox/Buttons/LogoutButton

var _selected_id: String = ""
var _allow_enter: bool = false

func _ready() -> void:
	enter_button.disabled = true

	delete_button.pressed.connect(_on_delete_pressed)
	enter_button.pressed.connect(_on_enter_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	list.item_selected.connect(_on_item_selected)

	refresh_list()

func set_enter_enabled(enabled: bool) -> void:
	_allow_enter = enabled
	_update_enter_state()

func refresh_list() -> void:
	list.clear()
	_selected_id = ""

	var chars: Array = AppState.get_characters()
	for c in chars:
		var d: Dictionary = c as Dictionary
		var id: String = String(d.get("id", ""))
		var char_name: String = String(d.get("name", "Unnamed"))
		var lvl: int = int(d.get("level", 1))

		var cls: String = String(d.get("class", "paladin"))
		list.add_item("%s — %s (lv %d)" % [char_name, cls, lvl])
		list.set_item_metadata(list.item_count - 1, id)

	if list.item_count > 0:
		list.select(0)
		_on_item_selected(0)
	else:
		_update_enter_state()

func reset_transient_ui() -> void:
	_selected_id = ""
	list.deselect_all()
	_update_enter_state()


func _on_item_selected(index: int) -> void:
	_selected_id = String(list.get_item_metadata(index))
	_update_enter_state()


func _update_enter_state() -> void:
	enter_button.disabled = (not _allow_enter) or (_selected_id == "")
	delete_button.disabled = (_selected_id == "")



func _on_enter_pressed() -> void:
	if enter_button.disabled:
		return
	var ok: bool = AppState.select_character(_selected_id)
	if ok:
		FlowRouter.go_world()


func _on_logout_pressed() -> void:
	AppState.logout()
	FlowRouter.go_login()


func _on_delete_pressed() -> void:
	if _selected_id == "":
		return

	AppState.delete_character(_selected_id)

	# сброс выбора и обновление списка
	_selected_id = ""
	refresh_list()

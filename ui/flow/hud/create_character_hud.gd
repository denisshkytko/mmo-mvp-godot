extends CanvasLayer

signal character_created(char_id: String)

@onready var name_edit: LineEdit = $Root/Panel/Margin/VBox/NameEdit
@onready var class_option: OptionButton = $Root/Panel/Margin/VBox/ClassOption
@onready var create_button: Button = $Root/Panel/Margin/VBox/Buttons/CreateButton
@onready var cancel_button: Button = $Root/Panel/Margin/VBox/Buttons/CancelButton
@onready var error_label: Label = $Root/Panel/Margin/VBox/ErrorLabel
@onready var title_label: Label = $Root/Panel/Margin/VBox/Title

func _ready() -> void:
	if title_label != null:
		title_label.text = tr("ui.flow.character_create.title")
	if name_edit != null:
		name_edit.placeholder_text = tr("ui.flow.character_create.name_placeholder")
	if create_button != null:
		create_button.text = tr("ui.flow.character_create.create")
	if cancel_button != null:
		cancel_button.text = tr("ui.flow.character_create.cancel")

	error_label.text = ""
	name_edit.focus_mode = Control.FOCUS_CLICK
	class_option.focus_mode = Control.FOCUS_CLICK
	create_button.focus_mode = Control.FOCUS_NONE
	cancel_button.focus_mode = Control.FOCUS_NONE

	class_option.clear()
	var classes := [
		{"label": "Paladin", "id": "paladin"},
		{"label": "Shaman", "id": "shaman"},
		{"label": "Mage", "id": "mage"},
		{"label": "Priest", "id": "priest"},
		{"label": "Hunter", "id": "hunter"},
		{"label": "Warrior", "id": "warrior"},
	]
	for entry in classes:
		var idx := class_option.item_count
		class_option.add_item(String(entry.get("label", "")), idx)
		class_option.set_item_metadata(idx, String(entry.get("id", "")))
	class_option.select(0)
	class_option.disabled = false

	create_button.pressed.connect(_on_create_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _on_cancel_pressed() -> void:
	# Мы находимся внутри CharacterSelectUI, поэтому просто очищаем поля.
	# (Если персонажей ещё нет — этот HUD всё равно останется видимым)
	error_label.text = ""
	name_edit.text = ""
	class_option.select(0)

func _on_create_pressed() -> void:
	error_label.text = ""

	var n: String = name_edit.text.strip_edges()
	if n == "":
		error_label.text = tr("ui.flow.character_create.error.invalid_name")
		return

	var selected_class_id: String = ""
	var selected_meta: Variant = class_option.get_item_metadata(class_option.selected)
	if selected_meta != null:
		selected_class_id = String(selected_meta)
	if selected_class_id == "":
		selected_class_id = "paladin"

	var selected_data: Dictionary = AppState.selected_character_data.duplicate(true)
	selected_data["class_id"] = selected_class_id
	selected_data["class"] = selected_class_id
	AppState.selected_character_data = selected_data

	var new_id: String = AppState.create_character(n, selected_class_id)
	if new_id == "":
		error_label.text = tr("ui.flow.character_create.error.create_failed")
		return

	emit_signal("character_created", new_id)
	
	# подготовка к созданию следующего персонажа
	name_edit.text = ""
	error_label.text = ""
	class_option.select(0)

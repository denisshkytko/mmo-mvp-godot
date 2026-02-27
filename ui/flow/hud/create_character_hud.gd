extends CanvasLayer

const UI_TEXT := preload("res://ui/game/hud/shared/ui_text.gd")

signal character_created(char_id: String)

@onready var name_edit: LineEdit = $Root/Panel/Margin/VBox/NameEdit
@onready var faction_label: Label = $Root/Panel/Margin/VBox/FactionLabel
@onready var faction_option: OptionButton = $Root/Panel/Margin/VBox/FactionOption
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
		cancel_button.text = tr("ui.terms.cancel")
	if faction_label != null:
		faction_label.text = tr("ui.flow.character_create.faction")

	error_label.text = ""
	name_edit.focus_mode = Control.FOCUS_CLICK
	faction_option.focus_mode = Control.FOCUS_CLICK
	class_option.focus_mode = Control.FOCUS_CLICK
	create_button.focus_mode = Control.FOCUS_NONE
	cancel_button.focus_mode = Control.FOCUS_NONE

	faction_option.clear()
	faction_option.add_item(tr("ui.faction.blue"), 0)
	faction_option.set_item_metadata(0, "blue")
	faction_option.add_item(tr("ui.faction.red"), 1)
	faction_option.set_item_metadata(1, "red")
	faction_option.select(0)
	if not faction_option.item_selected.is_connected(_on_faction_selected):
		faction_option.item_selected.connect(_on_faction_selected)

	_refresh_class_options_for_faction("blue")
	class_option.disabled = false

	create_button.pressed.connect(_on_create_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _on_faction_selected(index: int) -> void:
	var selected_meta: Variant = faction_option.get_item_metadata(index)
	var faction_id := String(selected_meta)
	if faction_id == "":
		faction_id = "blue"
	_refresh_class_options_for_faction(faction_id)

func _refresh_class_options_for_faction(faction_id: String) -> void:
	class_option.clear()
	var class_ids: Array[String] = ["paladin", "shaman", "mage", "priest", "hunter", "warrior"]
	for class_id in class_ids:
		if not AppState.is_class_allowed_for_faction(class_id, faction_id):
			continue
		var idx := class_option.item_count
		class_option.add_item(UI_TEXT.class_display_name(class_id), idx)
		class_option.set_item_metadata(idx, class_id)
	if class_option.item_count > 0:
		class_option.select(0)


func _on_cancel_pressed() -> void:
	# Мы находимся внутри CharacterSelectUI, поэтому просто очищаем поля.
	# (Если персонажей ещё нет — этот HUD всё равно останется видимым)
	error_label.text = ""
	name_edit.text = ""
	faction_option.select(0)
	_refresh_class_options_for_faction("blue")

func _on_create_pressed() -> void:
	error_label.text = ""

	var validation: Dictionary = AppState.validate_and_normalize_character_name(name_edit.text)
	if not bool(validation.get("ok", false)):
		error_label.text = tr("ui.flow.character_create.error.invalid_name")
		return
	var n: String = String(validation.get("name", "")).strip_edges()
	name_edit.text = n

	var selected_faction_id: String = "blue"
	var faction_meta: Variant = faction_option.get_item_metadata(faction_option.selected)
	if faction_meta != null:
		selected_faction_id = String(faction_meta)
	if selected_faction_id == "":
		selected_faction_id = "blue"

	var selected_class_id: String = ""
	var selected_meta: Variant = class_option.get_item_metadata(class_option.selected)
	if selected_meta != null:
		selected_class_id = String(selected_meta)
	if selected_class_id == "":
		error_label.text = tr("ui.flow.character_create.error.create_failed")
		return

	var selected_data: Dictionary = AppState.selected_character_data.duplicate(true)
	selected_data["faction"] = selected_faction_id
	selected_data["class_id"] = selected_class_id
	selected_data["class"] = selected_class_id
	AppState.selected_character_data = selected_data

	var new_id: String = AppState.create_character(n, selected_class_id, selected_faction_id)
	if new_id == "":
		error_label.text = tr("ui.flow.character_create.error.create_failed")
		return

	emit_signal("character_created", new_id)
	
	# подготовка к созданию следующего персонажа
	name_edit.text = ""
	error_label.text = ""
	faction_option.select(0)
	_refresh_class_options_for_faction("blue")

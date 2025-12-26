extends Control

signal character_created(char_id: String)

@onready var name_edit: LineEdit = $Bg/Panel/Margin/VBox/NameEdit
@onready var class_option: OptionButton = $Bg/Panel/Margin/VBox/ClassOption
@onready var create_button: Button = $Bg/Panel/Margin/VBox/Buttons/CreateButton
@onready var cancel_button: Button = $Bg/Panel/Margin/VBox/Buttons/CancelButton
@onready var error_label: Label = $Bg/Panel/Margin/VBox/ErrorLabel

func _ready() -> void:
	error_label.text = ""

	class_option.clear()
	class_option.add_item("Paladin", 0)
	class_option.select(0)
	class_option.disabled = true

	create_button.pressed.connect(_on_create_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)

	name_edit.grab_focus()

func _on_cancel_pressed() -> void:
	# Мы находимся внутри CharacterSelectUI, поэтому просто очищаем поля.
	# (Если персонажей ещё нет — этот HUD всё равно останется видимым)
	error_label.text = ""
	name_edit.text = ""
	class_option.select(0)
	name_edit.grab_focus()

func _on_create_pressed() -> void:
	error_label.text = ""

	var n: String = name_edit.text.strip_edges()
	if n == "":
		error_label.text = "Enter a name"
		return

	var class_id: String = "paladin"

	var new_id: String = AppState.create_character(n, class_id)
	if new_id == "":
		error_label.text = "Failed to create character"
		return

	emit_signal("character_created", new_id)
	
	# подготовка к созданию следующего персонажа
	name_edit.text = ""
	error_label.text = ""
	class_option.select(0)
	name_edit.grab_focus()

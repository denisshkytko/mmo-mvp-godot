extends Control
class_name QuickMenuHUD

@onready var panel: Panel = $Panel
@onready var button_stack: VBoxContainer = $Panel/ButtonStack
@onready var menu_button: Button = $Panel/ButtonStack/MenuButton
@onready var inventory_button: Button = $Panel/ButtonStack/InventoryButton
@onready var character_button: Button = $Panel/ButtonStack/CharacterButton
@onready var toggle_button: Button = $ToggleButton

var _expanded: bool = false
@export var spacing: float = 6.0
var _menu_hud: Node = null
var _inventory_hud: Node = null
var _character_hud: Node = null
var _collapsed_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	character_button.pressed.connect(_on_character_pressed)
	toggle_button.pressed.connect(_on_toggle_pressed)
	_resolve_targets()
	await get_tree().process_frame
	_cache_layout()
	_set_expanded(false, true)

func _resolve_targets() -> void:
	_menu_hud = get_tree().get_first_node_in_group("menu_hud")
	_inventory_hud = get_tree().get_first_node_in_group("inventory_ui")
	_character_hud = get_tree().get_first_node_in_group("character_hud")

func _cache_layout() -> void:
	panel.size = button_stack.size
	_collapsed_pos = toggle_button.position


func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	toggle_button.text = "▲" if _expanded else "▼"
	var target_panel_pos := _collapsed_pos - Vector2(0.0, panel.size.y + spacing)
	var target_toggle_pos := _collapsed_pos + Vector2(0.0, panel.size.y + spacing)
	var final_panel_pos := target_panel_pos if _expanded else _collapsed_pos
	var final_toggle_pos := target_toggle_pos if _expanded else _collapsed_pos
	if _expanded:
		panel.visible = true
	if immediate:
		panel.position = final_panel_pos
		toggle_button.position = final_toggle_pos
		if not _expanded:
			panel.visible = false
		return
	var tween := create_tween()
	tween.tween_property(panel, "position", final_panel_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(toggle_button, "position", final_toggle_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if not _expanded:
		tween.tween_callback(func() -> void: panel.visible = false)

func _on_toggle_pressed() -> void:
	_set_expanded(not _expanded, false)

func _on_menu_pressed() -> void:
	if _menu_hud != null and _menu_hud.has_method("toggle_menu"):
		_menu_hud.call("toggle_menu")

func _on_inventory_pressed() -> void:
	if _inventory_hud != null and _inventory_hud.has_method("toggle_inventory"):
		_inventory_hud.call("toggle_inventory")

func _on_character_pressed() -> void:
	if _character_hud != null and _character_hud.has_method("toggle_character"):
		_character_hud.call("toggle_character")

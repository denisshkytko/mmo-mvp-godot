extends Control
class_name QuickMenuHUD

@onready var panel: Panel = $Panel
@onready var button_stack: VBoxContainer = $Panel/ButtonStack
@onready var menu_button: Button = $Panel/ButtonStack/MenuButton
@onready var inventory_button: Button = $Panel/ButtonStack/InventoryButton
@onready var character_button: Button = $Panel/ButtonStack/CharacterButton
@onready var toggle_button: Button = $Panel/ButtonStack/ToggleButton

var _expanded: bool = false
var _expanded_height: float = 0.0
var _collapsed_height: float = 0.0
var _bottom_offset: float = 0.0
var _menu_hud: Node = null
var _inventory_hud: Node = null
var _character_hud: Node = null

func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	character_button.pressed.connect(_on_character_pressed)
	toggle_button.pressed.connect(_on_toggle_pressed)
	_resolve_targets()
	_bottom_offset = offset_bottom
	await get_tree().process_frame
	_cache_sizes()
	_set_expanded(false, true)

func _resolve_targets() -> void:
	_menu_hud = get_tree().get_first_node_in_group("menu_hud")
	_inventory_hud = get_tree().get_first_node_in_group("inventory_ui")
	_character_hud = get_tree().get_first_node_in_group("character_hud")

func _cache_sizes() -> void:
	_expanded_height = button_stack.size.y
	_collapsed_height = toggle_button.size.y

func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	var target_height := _expanded_height if _expanded else _collapsed_height
	menu_button.visible = _expanded
	inventory_button.visible = _expanded
	character_button.visible = _expanded
	toggle_button.text = "▲" if _expanded else "▼"
	if immediate:
		offset_top = _bottom_offset - target_height
		return
	var tween := create_tween()
	tween.tween_property(self, "offset_top", _bottom_offset - target_height, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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

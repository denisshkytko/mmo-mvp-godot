extends CanvasLayer
class_name QuickMenuHUD

@onready var panel: Panel = $Root/Panel
@onready var button_stack: VBoxContainer = $Root/Panel/ButtonStack
@onready var menu_button: Button = $Root/Panel/ButtonStack/MenuButton
@onready var inventory_button: Button = $Root/Panel/ButtonStack/InventoryButton
@onready var character_button: Button = $Root/Panel/ButtonStack/CharacterButton
@onready var profiler_button: Button = $Root/Panel/ButtonStack/ProfilerButton
@onready var toggle_button: Button = $Root/ToggleButton
const PERFORMANCE_PROFILER_WINDOW := preload("res://ui/game/hud/windows/PerformanceProfilerWindow.tscn")

var _expanded: bool = false
var _menu_hud: Node = null
var _inventory_hud: Node = null
var _character_hud: Node = null
var _collapsed_toggle_pos: Vector2 = Vector2.ZERO
var _collapsed_panel_pos: Vector2 = Vector2.ZERO
var _performance_window: Control = null
var _hidden_ui_nodes: Array[CanvasItem] = []

func _ready() -> void:
	menu_button.pressed.connect(_on_menu_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	character_button.pressed.connect(_on_character_pressed)
	profiler_button.pressed.connect(_on_profiler_pressed)
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
	panel.size = panel.size
	_collapsed_toggle_pos = toggle_button.position
	_collapsed_panel_pos = panel.position


func _set_expanded(is_expanded: bool, immediate: bool) -> void:
	_expanded = is_expanded
	toggle_button.text = "▲" if _expanded else "▼"
	var target_panel_pos := _collapsed_panel_pos
	var target_toggle_pos := _collapsed_toggle_pos + Vector2(0.0, panel.size.y + 8.0)
	var final_panel_pos := target_panel_pos if _expanded else _collapsed_panel_pos
	var final_toggle_pos := target_toggle_pos if _expanded else _collapsed_toggle_pos
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


func _on_profiler_pressed() -> void:
	if _performance_window == null or not is_instance_valid(_performance_window):
		_performance_window = PERFORMANCE_PROFILER_WINDOW.instantiate() as Control
		get_parent().get_parent().add_child(_performance_window)
		if _performance_window.has_signal("closed"):
			_performance_window.closed.connect(_on_profiler_closed)
	_show_profiler_window(true)


func _on_profiler_closed() -> void:
	_show_profiler_window(false)


func _show_profiler_window(is_visible: bool) -> void:
	if _performance_window == null or not is_instance_valid(_performance_window):
		return
	if is_visible:
		_hidden_ui_nodes.clear()
		var ui_container := get_parent().get_parent()
		for child in ui_container.get_children():
			if child == _performance_window:
				continue
			if child is CanvasItem and (child as CanvasItem).visible:
				_hidden_ui_nodes.append(child as CanvasItem)
				(child as CanvasItem).visible = false
		_performance_window.visible = true
	else:
		_performance_window.visible = false
		for node in _hidden_ui_nodes:
			if node != null and is_instance_valid(node):
				node.visible = true
		_hidden_ui_nodes.clear()

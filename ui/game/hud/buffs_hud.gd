extends CanvasLayer
class_name BuffsHUD

@export var buff_icon_scene: PackedScene
@export var buffs_per_row: int = 7
@export var newest_on_right: bool = true  # если RTL недоступен, это всё равно даст правильный визуал
@onready var panel: Panel = $Root/Panel
@onready var grid: GridContainer = $Root/Panel/Grid

var _player: Node = null
var _icons: Dictionary = {} # buff_id:String -> BuffIcon (Node)
var _panel_fixed_top_right: Vector2 = Vector2.ZERO
var _has_fixed_corner: bool = false
var _realign_requested: bool = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_apply_grid_settings()
	visible = false
	if panel != null and not panel.resized.is_connected(_on_panel_resized):
		panel.resized.connect(_on_panel_resized)
	await get_tree().process_frame
	_capture_panel_top_right_from_scene()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return

	if not _player.has_method("get_buffs_snapshot"):
		return

	var snap: Array = _player.call("get_buffs_snapshot")
	_sync_icons(snap)

func _apply_grid_settings() -> void:
	if grid == null:
		return
	grid.columns = max(1, buffs_per_row)

func _sync_icons(snap: Array) -> void:
	var seen: Dictionary = {} # buff_id -> true

	# 1) create/update icons
	for entry in snap:
		var data: Dictionary = entry as Dictionary
		var id: String = String(data.get("id", ""))
		if id == "":
			continue

		seen[id] = true
		var left: float = float(data.get("time_left", 0.0))

		if _icons.has(id):
			var icon_node: BuffIcon = _icons[id] as BuffIcon
			if icon_node != null and is_instance_valid(icon_node):
				icon_node.update_time(left)
				icon_node.update_data(data)
		else:
			if buff_icon_scene == null:
				continue

			var inst: Node = buff_icon_scene.instantiate()
			if newest_on_right:
				grid.add_child(inst)
			else:
				grid.add_child(inst, true)

			var bicon: BuffIcon = inst as BuffIcon
			if bicon != null:
				bicon.setup(_player, data)
				_icons[id] = bicon

	# 2) remove missing buffs
	var to_remove: Array[String] = []
	for k in _icons.keys():
		if not seen.has(k):
			to_remove.append(k)

	for k in to_remove:
		var icon_node2: BuffIcon = _icons[k] as BuffIcon
		if icon_node2 != null and is_instance_valid(icon_node2):
			icon_node2.queue_free()
		_icons.erase(k)

	visible = (_icons.size() > 0)
	_request_panel_realign()

func _capture_panel_top_right_from_scene() -> void:
	if panel == null:
		return
	_panel_fixed_top_right = panel.global_position + Vector2(panel.size.x, 0.0)
	_has_fixed_corner = true
	_request_panel_realign()

func _request_panel_realign() -> void:
	if not _has_fixed_corner or panel == null:
		return
	if _realign_requested:
		return
	_realign_requested = true
	call_deferred("_apply_panel_fixed_top_right")

func _apply_panel_fixed_top_right() -> void:
	_realign_requested = false
	if not _has_fixed_corner or panel == null:
		return
	var target_pos := _panel_fixed_top_right - Vector2(panel.size.x, 0.0)
	panel.global_position = target_pos

func _on_panel_resized() -> void:
	_request_panel_realign()

extends CanvasLayer
class_name BuffsHUD

@export var buff_icon_scene: PackedScene
@export var buffs_per_row: int = 7
@export var newest_on_right: bool = false  # false => newest on left
@onready var panel: Panel = $Root/Panel
@onready var grid: GridContainer = $Root/Panel/Grid

var _player: Node = null
var _icons: Dictionary = {} # buff_id:String -> BuffIcon (Node)
var _fixed_offset_right: float = 0.0
var _fixed_offset_top: float = 0.0
var _has_fixed_corner: bool = false
var _realign_requested: bool = false

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_apply_grid_settings()
	visible = false
	if panel != null and not panel.resized.is_connected(_on_panel_resized):
		panel.resized.connect(_on_panel_resized)
	await get_tree().process_frame
	_capture_panel_corner_from_scene()

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
	var max_cols := _get_max_columns_that_fit()
	grid.columns = max(1, min(buffs_per_row, max_cols))

func _sync_icons(snap: Array) -> void:
	var seen: Dictionary = {} # buff_id -> true

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
			grid.add_child(inst)
			if not newest_on_right:
				grid.move_child(inst, 0)

			var bicon: BuffIcon = inst as BuffIcon
			if bicon != null:
				bicon.setup(_player, data)
				_icons[id] = bicon

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
	_apply_grid_settings()
	_request_panel_realign()

func _capture_panel_corner_from_scene() -> void:
	if panel == null:
		return
	_fixed_offset_right = panel.offset_right
	_fixed_offset_top = panel.offset_top
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
	panel.offset_right = _fixed_offset_right
	panel.offset_top = _fixed_offset_top
	panel.offset_left = panel.offset_right - panel.size.x
	panel.offset_bottom = panel.offset_top + panel.size.y

func _on_panel_resized() -> void:
	_apply_grid_settings()
	_request_panel_realign()

func _get_max_columns_that_fit() -> int:
	if panel == null or grid == null:
		return max(1, buffs_per_row)
	var icon_w := _get_icon_width()
	var sep := float(grid.get_theme_constant("h_separation"))
	if icon_w <= 0.0:
		return max(1, buffs_per_row)
	var fit := int(floor((panel.size.x + sep) / (icon_w + sep)))
	return max(1, fit)

func _get_icon_width() -> float:
	for child in grid.get_children():
		var c := child as Control
		if c != null:
			var w := c.custom_minimum_size.x
			if w <= 0.0:
				w = c.size.x
			if w > 0.0:
				return w
	if buff_icon_scene != null:
		var inst := buff_icon_scene.instantiate() as Control
		if inst != null:
			var w2 := inst.custom_minimum_size.x
			inst.queue_free()
			if w2 > 0.0:
				return w2
	return 40.0

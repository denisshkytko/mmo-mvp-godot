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
var _target_panel_size: Vector2 = Vector2.ZERO

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
	grid.columns = max(1, buffs_per_row)

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
	_update_panel_size_for_icon_count(_icons.size())
	_request_panel_realign()

func _update_panel_size_for_icon_count(icon_count: int) -> void:
	if panel == null or grid == null:
		return
	var icon_size := _get_icon_size()
	var used_cols := clampi(icon_count, 1, max(1, buffs_per_row))
	var rows := maxi(1, int(ceil(float(icon_count) / float(max(1, buffs_per_row)))))
	var h_sep := float(grid.get_theme_constant("h_separation"))
	var v_sep := float(grid.get_theme_constant("v_separation"))
	_target_panel_size = Vector2(
		float(used_cols) * icon_size.x + float(maxi(0, used_cols - 1)) * h_sep,
		float(rows) * icon_size.y + float(maxi(0, rows - 1)) * v_sep
	)

func _capture_panel_corner_from_scene() -> void:
	if panel == null:
		return
	_fixed_offset_right = panel.offset_right
	_fixed_offset_top = panel.offset_top
	_target_panel_size = panel.size
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
	var width := _target_panel_size.x
	var height := _target_panel_size.y
	if width <= 0.0:
		width = panel.size.x
	if height <= 0.0:
		height = panel.size.y
	panel.offset_right = _fixed_offset_right
	panel.offset_top = _fixed_offset_top
	panel.offset_left = panel.offset_right - width
	panel.offset_bottom = panel.offset_top + height

func _on_panel_resized() -> void:
	_apply_grid_settings()
	_request_panel_realign()

func _get_icon_size() -> Vector2:
	for child in grid.get_children():
		var c := child as Control
		if c != null:
			var s := c.custom_minimum_size
			if s.x <= 0.0:
				s.x = c.size.x
			if s.y <= 0.0:
				s.y = c.size.y
			if s.x > 0.0 and s.y > 0.0:
				return s
	if buff_icon_scene != null:
		var inst := buff_icon_scene.instantiate() as Control
		if inst != null:
			var s2 := inst.custom_minimum_size
			inst.queue_free()
			if s2.x > 0.0 and s2.y > 0.0:
				return s2
	return Vector2(40.0, 40.0)

extends CanvasLayer
class_name BuffsHUD

@export var buff_icon_scene: PackedScene
@export var buffs_per_row: int = 7
@onready var panel: Panel = $Root/Panel
@onready var buff_grid: GridContainer = $Root/Panel/VBox/BuffGrid
@onready var debuff_grid: GridContainer = $Root/Panel/VBox/DebuffGrid

var _player: Node = null
var _buff_icons: Dictionary = {}
var _debuff_icons: Dictionary = {}
var _fixed_offset_right: float = 0.0
var _fixed_offset_top: float = 0.0

const FALLBACK_ICON_SIZE: Vector2 = Vector2(40.0, 40.0)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	visible = false
	_apply_columns()
	_capture_panel_anchor()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	if not _player.has_method("get_buffs_snapshot"):
		return
	_sync_icons(_player.call("get_buffs_snapshot") as Array)

func _apply_columns() -> void:
	var cols: int = maxi(1, buffs_per_row)
	buff_grid.columns = cols
	debuff_grid.columns = cols

func _sync_icons(snap: Array) -> void:
	var seen_buffs: Dictionary = {}
	var seen_debuffs: Dictionary = {}
	for entry in snap:
		var data: Dictionary = entry as Dictionary
		var id: String = String(data.get("id", ""))
		if id == "":
			continue
		var is_debuff: bool = _is_debuff_entry(data)
		if is_debuff:
			seen_debuffs[id] = true
			_sync_single(_debuff_icons, debuff_grid, id, data)
		else:
			seen_buffs[id] = true
			_sync_single(_buff_icons, buff_grid, id, data)
	_prune(_buff_icons, seen_buffs)
	_prune(_debuff_icons, seen_debuffs)
	buff_grid.visible = _buff_icons.size() > 0
	debuff_grid.visible = _debuff_icons.size() > 0
	_relayout_panel()
	visible = buff_grid.visible or debuff_grid.visible

func _capture_panel_anchor() -> void:
	if panel == null:
		return
	_fixed_offset_right = panel.offset_right
	_fixed_offset_top = panel.offset_top

func _relayout_panel() -> void:
	if panel == null:
		return

	var cols_limit: int = maxi(1, buffs_per_row)
	var icon_size: Vector2 = _get_icon_size()
	var h_sep_buff: int = buff_grid.get_theme_constant("h_separation")
	var v_sep_buff: int = buff_grid.get_theme_constant("v_separation")
	var h_sep_debuff: int = debuff_grid.get_theme_constant("h_separation")
	var v_sep_debuff: int = debuff_grid.get_theme_constant("v_separation")
	var section_sep: int = 2

	var buff_count: int = _buff_icons.size()
	var debuff_count: int = _debuff_icons.size()

	var buff_cols_used: int = mini(buff_count, cols_limit) if buff_count > 0 else 0
	var debuff_cols_used: int = mini(debuff_count, cols_limit) if debuff_count > 0 else 0
	var max_cols_used: int = maxi(buff_cols_used, debuff_cols_used)
	if max_cols_used <= 0:
		max_cols_used = 1

	var width: float = float(max_cols_used) * icon_size.x
	if buff_cols_used > 1:
		width = max(width, float(buff_cols_used) * icon_size.x + float(buff_cols_used - 1) * float(h_sep_buff))
	if debuff_cols_used > 1:
		width = max(width, float(debuff_cols_used) * icon_size.x + float(debuff_cols_used - 1) * float(h_sep_debuff))

	var buff_rows: int = int(ceil(float(buff_count) / float(cols_limit))) if buff_count > 0 else 0
	var debuff_rows: int = int(ceil(float(debuff_count) / float(cols_limit))) if debuff_count > 0 else 0

	var height: float = 0.0
	if buff_rows > 0:
		height += float(buff_rows) * icon_size.y
		height += float(maxi(0, buff_rows - 1)) * float(v_sep_buff)
	if debuff_rows > 0:
		if height > 0.0:
			height += float(section_sep)
		height += float(debuff_rows) * icon_size.y
		height += float(maxi(0, debuff_rows - 1)) * float(v_sep_debuff)

	if height <= 0.0:
		height = icon_size.y

	panel.offset_right = _fixed_offset_right
	panel.offset_top = _fixed_offset_top
	panel.offset_left = panel.offset_right - width
	panel.offset_bottom = panel.offset_top + height

func _get_icon_size() -> Vector2:
	if buff_icon_scene != null:
		var inst: Control = buff_icon_scene.instantiate() as Control
		if inst != null:
			var size: Vector2 = inst.custom_minimum_size
			inst.queue_free()
			if size.x > 0.0 and size.y > 0.0:
				return size
	return FALLBACK_ICON_SIZE

func _sync_single(store: Dictionary, grid: GridContainer, id: String, data: Dictionary) -> void:
	if store.has(id):
		var icon: BuffIcon = store[id] as BuffIcon
		if icon != null and is_instance_valid(icon):
			icon.update_data(data)
			icon.update_time(float(data.get("time_left", 0.0)))
			return
	if buff_icon_scene == null:
		return
	var inst: BuffIcon = buff_icon_scene.instantiate() as BuffIcon
	if inst == null:
		return
	grid.add_child(inst)
	inst.setup(_player, data)
	store[id] = inst

func _prune(store: Dictionary, seen: Dictionary) -> void:
	for k in store.keys():
		if seen.has(k):
			continue
		var icon: Node = store[k] as Node
		if icon != null and is_instance_valid(icon):
			icon.queue_free()
		store.erase(k)

func _is_debuff_entry(data: Dictionary) -> bool:
	if bool(data.get("is_debuff", false)):
		return true
	if data.has("data") and data.get("data") is Dictionary:
		var inner: Dictionary = data.get("data", {}) as Dictionary
		if bool(inner.get("is_debuff", false)):
			return true
		return String(inner.get("source", "")) == "debuff"
	return String(data.get("source", "")) == "debuff"

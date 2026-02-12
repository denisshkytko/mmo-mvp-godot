extends CanvasLayer
class_name BuffsHUD

@export var buff_icon_scene: PackedScene
@export var buffs_per_row: int = 7
@export var newest_on_right: bool = true  # если RTL недоступен, это всё равно даст правильный визуал
@onready var panel: Panel = $Root/Panel
@onready var grid: GridContainer = $Root/Panel/Grid

var _player: Node = null
var _icons: Dictionary = {} # buff_id:String -> BuffIcon (Node)

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_apply_grid_settings()
	visible = false

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
			# Если хотим “новые справа”, то:
			# - при RTL контейнере можно просто add_child
			# - если RTL нет, добавляем в начало (index 0), тогда новые будут “с правого края” при правильной настройке UI
			if newest_on_right:
				grid.add_child(inst)
			else:
				grid.add_child(inst, true) # обычное добавление

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

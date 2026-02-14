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

func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	visible = false
	_apply_columns()

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
	visible = buff_grid.visible or debuff_grid.visible

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

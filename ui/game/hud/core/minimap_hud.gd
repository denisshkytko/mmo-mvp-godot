extends Control

@export var zoom_levels: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.25])
@export var follow_player: bool = true
@export var zone_refresh_sec: float = 0.4

@onready var map_mask: Control = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask
@onready var map_stack: Control = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask/MapStack
@onready var tap_zone: Button = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask/TapZone

var _zoom_index: int = 0
var _current_zone_path: String = ""
var _zone_refresh_timer: float = 0.0
var _active_map: TextureRect = null
var _active_world_min: Vector2 = Vector2.ZERO
var _active_world_size: Vector2 = Vector2.ONE
var _player: Node2D = null


func _ready() -> void:
	tap_zone.pressed.connect(_on_tap_pressed)
	_select_map_for_zone(_get_current_zone_path())
	_apply_zoom_and_focus()


func _process(delta: float) -> void:
	_zone_refresh_timer = max(0.0, _zone_refresh_timer - max(0.0, delta))
	if _zone_refresh_timer <= 0.0:
		_zone_refresh_timer = zone_refresh_sec
		var zone_path := _get_current_zone_path()
		if zone_path != _current_zone_path:
			_select_map_for_zone(zone_path)
	_apply_zoom_and_focus()


func _on_tap_pressed() -> void:
	if zoom_levels.is_empty():
		return
	_zoom_index = (_zoom_index + 1) % zoom_levels.size()
	_apply_zoom_and_focus()


func _select_map_for_zone(zone_path: String) -> void:
	_current_zone_path = zone_path
	var zone_file := zone_path.get_file()
	var selected: TextureRect = null
	for child in map_stack.get_children():
		if not (child is TextureRect):
			continue
		var tex := child as TextureRect
		tex.visible = false
		var map_zone_path := String(tex.get_meta("zone_path", ""))
		if map_zone_path == "":
			continue
		if map_zone_path == zone_path or map_zone_path.get_file() == zone_file:
			selected = tex
	if selected == null:
		for child in map_stack.get_children():
			if child is TextureRect:
				selected = child as TextureRect
				break
	if selected == null:
		_active_map = null
		return
	selected.visible = true
	_active_map = selected
	_active_world_min = selected.get_meta("world_min", Vector2.ZERO) as Vector2
	var world_size_v: Variant = selected.get_meta("world_size", Vector2.ONE)
	_active_world_size = world_size_v as Vector2
	if _active_world_size.x <= 0.0:
		_active_world_size.x = 1.0
	if _active_world_size.y <= 0.0:
		_active_world_size.y = 1.0


func _apply_zoom_and_focus() -> void:
	if _active_map == null or not is_instance_valid(_active_map):
		return
	var mask_size := map_mask.size
	if mask_size.x <= 1.0 or mask_size.y <= 1.0:
		return
	var zoom_value: float = 1.0
	if not zoom_levels.is_empty():
		zoom_value = zoom_levels[clamp(_zoom_index, 0, zoom_levels.size() - 1)]
	zoom_value = clampf(zoom_value, 0.05, 4.0)

	var uv := Vector2(0.5, 0.5)
	if follow_player:
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player != null and is_instance_valid(_player):
			uv.x = (_player.global_position.x - _active_world_min.x) / _active_world_size.x
			uv.y = (_player.global_position.y - _active_world_min.y) / _active_world_size.y
	uv.x = clampf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)

	var content_size := mask_size * zoom_value
	_active_map.custom_minimum_size = content_size
	_active_map.size = content_size
	_active_map.position = (mask_size * 0.5) - (content_size * uv)


func _get_current_zone_path() -> String:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and is_instance_valid(gm):
		return String(gm.get("current_zone_path"))
	return ""

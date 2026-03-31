extends Control

const MINIMAP_BUILDER := preload("res://ui/game/hud/core/minimap_builder.gd")

@export var zoom_levels: PackedFloat32Array = PackedFloat32Array([1.0, 0.5, 0.25])
@export var follow_player: bool = true
@export var zone_refresh_sec: float = 0.4
@export var default_world_rect: Rect2 = Rect2(Vector2(-2000, -1200), Vector2(4000, 2400))

@onready var map_mask: Control = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask
@onready var map_stack: Control = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask/MapStack
@onready var tap_zone: Button = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask/TapZone
@onready var player_marker: Control = $TopRightAnchor/MapPanel/Padding/MapAspect/MapMask/PlayerMarker

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
	_apply_zone_texture_and_bounds(selected, zone_path)


func _apply_zone_texture_and_bounds(target: TextureRect, zone_path: String) -> void:
	var map_zone_path := zone_path if zone_path != "" else String(target.get_meta("zone_path", ""))
	var build_cfg := _build_config_for_zone(map_zone_path)
	var built: Dictionary = MINIMAP_BUILDER.build_zone_minimap(map_zone_path, build_cfg)
	if built.has("texture"):
		target.texture = built.get("texture") as Texture2D
	if built.has("world_rect"):
		var wr: Rect2 = built.get("world_rect") as Rect2
		_active_world_min = wr.position
		_active_world_size = wr.size
	else:
		_active_world_min = target.get_meta("world_min", default_world_rect.position) as Vector2
		_active_world_size = target.get_meta("world_size", default_world_rect.size) as Vector2
	if _active_world_size.x <= 0.0:
		_active_world_size.x = 1.0
	if _active_world_size.y <= 0.0:
		_active_world_size.y = 1.0


func _build_config_for_zone(_zone_path: String) -> Dictionary:
	# Конфиг сделан отдельной структурой, чтобы его можно было легко править вручную.
	# Сейчас заполнен первичный пресет под сцену "1".
	return {
		"root_node_path": "World/z-level = 0, y-sort = false",
		"pixels_per_tile": 2,
		"default_color": Color(0.24, 0.36, 0.22, 1.0),
		"exclude_name_prefixes": ["fire"],
		"layer_rules": {
			"ground": {
				"enabled": true,
				"color": Color(0.22, 0.34, 0.20, 1.0),
			},
			"mountain": {
				"enabled": true,
				"color": Color(0.42, 0.42, 0.44, 1.0),
			},
			"pit": {
				"enabled": true,
				"color": Color(0.10, 0.10, 0.12, 1.0),
			},
			"decor 0.5x": {
				"enabled": true,
				"allow_source_ids": [0, 3],
				"color": Color(0.30, 0.45, 0.30, 1.0),
			},
			"decor 0.75x": {
				"enabled": true,
				"allow_source_ids": [0, 1, 2, 3],
				"color": Color(0.35, 0.50, 0.35, 1.0),
			},
			"decor 1x": {
				"enabled": true,
				"color": Color(0.38, 0.56, 0.38, 1.0),
			},
			"decor 1.5x": {
				"enabled": true,
				"color": Color(0.42, 0.62, 0.42, 1.0),
			},
		},
	}


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

	if player_marker != null and is_instance_valid(player_marker):
		if follow_player:
			player_marker.position = (mask_size * 0.5) - (player_marker.size * 0.5)
		else:
			player_marker.position = Vector2(mask_size.x * uv.x, mask_size.y * uv.y) - (player_marker.size * 0.5)


func _get_current_zone_path() -> String:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and is_instance_valid(gm):
		return String(gm.get("current_zone_path"))
	return ""

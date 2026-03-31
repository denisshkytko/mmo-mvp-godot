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
var _snapshot_cache: Dictionary = {}
var _snapshot_inflight: Dictionary = {}


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
	_ensure_zone_snapshot_if_needed(selected, zone_path)
	_active_world_min = selected.get_meta("world_min", Vector2.ZERO) as Vector2
	var world_size_v: Variant = selected.get_meta("world_size", Vector2.ONE)
	_active_world_size = world_size_v as Vector2
	if _active_world_size.x <= 0.0:
		_active_world_size.x = 1.0
	if _active_world_size.y <= 0.0:
		_active_world_size.y = 1.0


func _ensure_zone_snapshot_if_needed(target: TextureRect, zone_path: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var use_snapshot: bool = bool(target.get_meta("use_zone_snapshot", false))
	if not use_snapshot:
		return
	var key := zone_path if zone_path != "" else String(target.get_meta("zone_path", ""))
	if key == "":
		return
	if _snapshot_cache.has(key):
		target.texture = _snapshot_cache[key] as Texture2D
		return
	if _snapshot_inflight.has(key):
		return
	_snapshot_inflight[key] = true
	call_deferred("_generate_zone_snapshot_texture", key)


func _generate_zone_snapshot_texture(zone_path: String) -> void:
	var packed: PackedScene = load(zone_path) as PackedScene
	if packed == null:
		_snapshot_inflight.erase(zone_path)
		return
	var zone_root := packed.instantiate() as Node
	if zone_root == null:
		_snapshot_inflight.erase(zone_path)
		return
	var capture_root := Node2D.new()
	var collect_result: Dictionary = _collect_tile_layers_for_snapshot(zone_root, capture_root)
	var bounds: Rect2 = collect_result.get("bounds", Rect2()) as Rect2
	var has_bounds: bool = bool(collect_result.get("has_bounds", false))
	zone_root.queue_free()
	if capture_root.get_child_count() == 0 or not has_bounds:
		_snapshot_inflight.erase(zone_path)
		capture_root.queue_free()
		return

	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.size = Vector2i(1024, 576)
	add_child(vp)
	vp.add_child(capture_root)
	var cam := Camera2D.new()
	cam.enabled = true
	capture_root.add_child(cam)
	cam.global_position = bounds.get_center()
	var fit_x: float = bounds.size.x / max(1.0, float(vp.size.x))
	var fit_y: float = bounds.size.y / max(1.0, float(vp.size.y))
	var fit_zoom: float = max(0.001, max(fit_x, fit_y))
	cam.zoom = Vector2(fit_zoom, fit_zoom)

	await get_tree().process_frame
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()

	if img == null or img.is_empty():
		_snapshot_inflight.erase(zone_path)
		return
	var texture := ImageTexture.create_from_image(img)
	_snapshot_cache[zone_path] = texture
	_snapshot_inflight.erase(zone_path)
	_apply_snapshot_texture(zone_path, texture)


func _apply_snapshot_texture(zone_path: String, texture: Texture2D) -> void:
	for child in map_stack.get_children():
		if not (child is TextureRect):
			continue
		var tex := child as TextureRect
		var map_zone_path := String(tex.get_meta("zone_path", ""))
		if map_zone_path == zone_path or map_zone_path.get_file() == zone_path.get_file():
			tex.texture = texture


func _collect_tile_layers_for_snapshot(node: Node, capture_root: Node2D) -> Dictionary:
	var out_bounds := Rect2()
	var out_has_bounds := false
	if node is TileMapLayer:
		var src := node as TileMapLayer
		var copied := src.duplicate() as TileMapLayer
		if copied != null:
			capture_root.add_child(copied)
			copied.global_transform = src.global_transform
			var used: Rect2i = src.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				var a: Vector2 = src.to_global(src.map_to_local(used.position))
				var b: Vector2 = src.to_global(src.map_to_local(used.position + used.size))
				var min_x := minf(a.x, b.x)
				var min_y := minf(a.y, b.y)
				var max_x := maxf(a.x, b.x)
				var max_y := maxf(a.y, b.y)
				var r := Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))
				if out_has_bounds:
					out_bounds = out_bounds.merge(r)
				else:
					out_bounds = r
					out_has_bounds = true
	for child in node.get_children():
		if child is Node:
			var child_result: Dictionary = _collect_tile_layers_for_snapshot(child as Node, capture_root)
			var child_has: bool = bool(child_result.get("has_bounds", false))
			if child_has:
				var child_bounds: Rect2 = child_result.get("bounds", Rect2()) as Rect2
				if out_has_bounds:
					out_bounds = out_bounds.merge(child_bounds)
				else:
					out_bounds = child_bounds
					out_has_bounds = true
	return {
		"bounds": out_bounds,
		"has_bounds": out_has_bounds,
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


func _get_current_zone_path() -> String:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and is_instance_valid(gm):
		return String(gm.get("current_zone_path"))
	return ""

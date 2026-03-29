extends Node2D

var manager: Node = null

const ENTITY_COLOR := Color(1.0, 0.2, 0.2, 0.95)
const TILE_COLOR := Color(0.2, 0.9, 1.0, 0.85)
const LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const MAX_TILE_MARKERS := 512


func _ready() -> void:
	y_sort_enabled = false


func _process(_delta: float) -> void:
	if manager == null or not is_instance_valid(manager):
		visible = false
		return
	var enabled := bool(manager.get("debug_draw_y_sort_markers"))
	visible = enabled
	if not enabled:
		return
	queue_redraw()


func _draw() -> void:
	if manager == null or not is_instance_valid(manager):
		return
	_draw_entity_markers()
	_draw_tile_markers()


func _draw_entity_markers() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var entities := tree.get_nodes_in_group("y_sort_entities")
	for e in entities:
		if not (e is Node2D):
			continue
		var n := e as Node2D
		if n == null or not is_instance_valid(n):
			continue
		var p := _resolve_node_sort_origin_global(n)
		_draw_cross_marker(p, ENTITY_COLOR, 5.0)
		var label_pos := _world_to_overlay_pos(p) + Vector2(6, -6)
		draw_string(ThemeDB.fallback_font, label_pos, String(n.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, LABEL_COLOR)


func _draw_tile_markers() -> void:
	if not bool(manager.get("debug_draw_tilemap_y_sort_markers")):
		return
	var zone_container := manager.get("zone_container") as Node
	if zone_container == null or zone_container.get_child_count() == 0:
		return
	var zone_root := zone_container.get_child(0)
	if zone_root == null:
		return

	var layers: Array[TileMapLayer] = []
	var stack: Array[Node] = [zone_root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back() as Node
		if cur is TileMapLayer:
			var layer := cur as TileMapLayer
			if layer.y_sort_enabled:
				layers.append(layer)
		for c in cur.get_children():
			if c is Node:
				stack.append(c)

	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	var center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var half := (vp.get_visible_rect().size * 0.5 * cam.zoom) if cam != null else Vector2(1200, 800)
	var world_rect := Rect2(center - half, half * 2.0).grow(96.0)

	var drawn := 0
	for layer in layers:
		if drawn >= MAX_TILE_MARKERS:
			break
		var local_from := layer.to_local(world_rect.position)
		var local_to := layer.to_local(world_rect.position + world_rect.size)
		var a := layer.local_to_map(local_from)
		var b := layer.local_to_map(local_to)
		var min_x := mini(a.x, b.x)
		var max_x := maxi(a.x, b.x)
		var min_y := mini(a.y, b.y)
		var max_y := maxi(a.y, b.y)
		for y in range(min_y, max_y + 1):
			if drawn >= MAX_TILE_MARKERS:
				break
			for x in range(min_x, max_x + 1):
				if drawn >= MAX_TILE_MARKERS:
					break
				var cell := Vector2i(x, y)
				if layer.get_cell_source_id(cell) == -1:
					continue
				var tile_data := layer.get_cell_tile_data(cell)
				var y_sort_origin := 0.0
				if tile_data != null and tile_data.has_method("get_y_sort_origin"):
					y_sort_origin = float(tile_data.call("get_y_sort_origin"))
				var world_anchor := layer.to_global(layer.map_to_local(cell) + Vector2(0.0, y_sort_origin))
				_draw_cross_marker(world_anchor, TILE_COLOR, 3.0)
				drawn += 1


func _draw_cross_marker(world_pos: Vector2, color: Color, half_size: float) -> void:
	var local := _world_to_overlay_pos(world_pos)
	var outline := Color(0.0, 0.0, 0.0, color.a)
	draw_line(local + Vector2(-half_size - 1.0, 0), local + Vector2(half_size + 1.0, 0), outline, 3.0)
	draw_line(local + Vector2(0, -half_size - 1.0), local + Vector2(0, half_size + 1.0), outline, 3.0)
	draw_line(local + Vector2(-half_size, 0), local + Vector2(half_size, 0), color, 1.5)
	draw_line(local + Vector2(0, -half_size), local + Vector2(0, half_size), color, 1.5)
	draw_arc(local, 4.0, 0.0, TAU, 20, outline, 2.0)
	draw_arc(local, 3.0, 0.0, TAU, 20, color, 1.5)


func _resolve_node_sort_origin_global(node: Node2D) -> Vector2:
	if node == null or not is_instance_valid(node):
		return Vector2.ZERO
	var y_origin := 0.0
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			y_origin = float(node.get("y_sort_origin"))
			break
	return node.global_position + Vector2(0.0, y_origin)


func _world_to_overlay_pos(world_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return world_pos
	return vp.get_canvas_transform() * world_pos

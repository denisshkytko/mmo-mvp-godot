extends RefCounted
class_name MinimapBuilder

static var _zone_cache: Dictionary = {}

static func clear_cache() -> void:
	_zone_cache.clear()


static func build_zone_minimap(zone_path: String, config: Dictionary) -> Dictionary:
	if zone_path == "":
		return {}
	if _zone_cache.has(zone_path):
		return _zone_cache[zone_path] as Dictionary

	var packed: PackedScene = load(zone_path) as PackedScene
	if packed == null:
		return {}
	var zone_root := packed.instantiate() as Node
	if zone_root == null:
		return {}

	var tile_layers: Array[TileMapLayer] = []
	var root_paths: Array = config.get("root_node_paths", []) as Array
	if root_paths.is_empty():
		var root_path := String(config.get("root_node_path", ""))
		if root_path != "":
			root_paths.append(root_path)
	if root_paths.is_empty():
		_collect_tile_layers(zone_root, tile_layers)
	else:
		for path_v in root_paths:
			var path_s := String(path_v)
			if path_s == "":
				continue
			var found := zone_root.get_node_or_null(path_s)
			if found != null:
				_collect_tile_layers(found, tile_layers)
	if tile_layers.is_empty():
		_collect_tile_layers(zone_root, tile_layers)
	if tile_layers.is_empty():
		zone_root.queue_free()
		return {}

	var included_cells: Array[Dictionary] = []
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	var world_min := Vector2(1e20, 1e20)
	var world_max := Vector2(-1e20, -1e20)
	var has_world_bounds := false

	for layer in tile_layers:
		var layer_name := String(layer.name)
		var rule := _pick_layer_rule(layer_name, config)
		if not bool(rule.get("enabled", true)):
			continue
		var layer_color: Color = rule.get("color", config.get("default_color", Color(0.25, 0.45, 0.25, 1.0))) as Color
		for cell in layer.get_used_cells():
			var source_id: int = layer.get_cell_source_id(cell)
			var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
			if not _passes_filters(source_id, atlas, rule):
				continue
			included_cells.append({
				"cell": cell,
				"color": layer_color,
			})
			min_cell.x = mini(min_cell.x, cell.x)
			min_cell.y = mini(min_cell.y, cell.y)
			max_cell.x = maxi(max_cell.x, cell.x)
			max_cell.y = maxi(max_cell.y, cell.y)

			var world_p := layer.to_global(layer.map_to_local(cell))
			if not has_world_bounds:
				world_min = world_p
				world_max = world_p
				has_world_bounds = true
			else:
				world_min.x = minf(world_min.x, world_p.x)
				world_min.y = minf(world_min.y, world_p.y)
				world_max.x = maxf(world_max.x, world_p.x)
				world_max.y = maxf(world_max.y, world_p.y)

	zone_root.queue_free()
	if included_cells.is_empty():
		return {}

	var px_per_tile: int = int(config.get("pixels_per_tile", 2))
	px_per_tile = maxi(1, px_per_tile)
	var width_tiles: int = (max_cell.x - min_cell.x) + 1
	var height_tiles: int = (max_cell.y - min_cell.y) + 1
	var img_w := maxi(1, width_tiles * px_per_tile)
	var img_h := maxi(1, height_tiles * px_per_tile)

	var image := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0.0))

	for item in included_cells:
		var c: Vector2i = item["cell"] as Vector2i
		var col: Color = item["color"] as Color
		var px := (c.x - min_cell.x) * px_per_tile
		var py := (c.y - min_cell.y) * px_per_tile
		for yy in range(py, py + px_per_tile):
			for xx in range(px, px + px_per_tile):
				image.set_pixel(xx, yy, col)

	var tex := ImageTexture.create_from_image(image)
	var world_rect := Rect2(world_min, world_max - world_min)
	if world_rect.size.x <= 0.0:
		world_rect.size.x = 1.0
	if world_rect.size.y <= 0.0:
		world_rect.size.y = 1.0
	var result := {
		"texture": tex,
		"world_rect": world_rect,
		"tile_min": min_cell,
		"tile_max": max_cell,
	}
	_zone_cache[zone_path] = result
	return result


static func _collect_tile_layers(root: Node, out_layers: Array[TileMapLayer]) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is TileMapLayer:
			out_layers.append(child as TileMapLayer)
		if child is Node:
			_collect_tile_layers(child as Node, out_layers)


static func _pick_layer_rule(layer_name: String, config: Dictionary) -> Dictionary:
	var lower := layer_name.to_lower().replace(",", ".")
	var excluded_prefixes: Array = config.get("exclude_name_prefixes", []) as Array
	for raw in excluded_prefixes:
		var prefix := String(raw).to_lower()
		if prefix != "" and lower.begins_with(prefix):
			return {"enabled": false}

	var rules: Dictionary = config.get("layer_rules", {}) as Dictionary
	for key_v in rules.keys():
		var pattern := String(key_v).to_lower().replace(",", ".")
		if pattern != "" and lower.find(pattern) != -1:
			var rv: Variant = rules.get(key_v, {})
			if rv is Dictionary:
				return rv as Dictionary
	return {"enabled": true}


static func _passes_filters(source_id: int, atlas: Vector2i, rule: Dictionary) -> bool:
	var allow_sources: Array = rule.get("allow_source_ids", []) as Array
	if not allow_sources.is_empty() and not allow_sources.has(source_id):
		return false
	var deny_sources: Array = rule.get("ignore_source_ids", []) as Array
	if deny_sources.has(source_id):
		return false

	var atlas_key := "%d:%d" % [atlas.x, atlas.y]
	var allow_atlas: Array = rule.get("allow_atlas_coords", []) as Array
	if not allow_atlas.is_empty() and not allow_atlas.has(atlas_key):
		return false
	var deny_atlas: Array = rule.get("ignore_atlas_coords", []) as Array
	if deny_atlas.has(atlas_key):
		return false

	return true

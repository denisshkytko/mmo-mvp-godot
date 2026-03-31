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
	var world_min := Vector2(1e20, 1e20)
	var world_max := Vector2(-1e20, -1e20)
	var has_world_bounds := false
	var min_world_step := 1e20

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
			var world_p := layer.to_global(layer.map_to_local(cell))
			var world_px := layer.to_global(layer.map_to_local(cell + Vector2i(1, 0)))
			var world_py := layer.to_global(layer.map_to_local(cell + Vector2i(0, 1)))
			var step_x := maxf(0.001, (world_px - world_p).length())
			var step_y := maxf(0.001, (world_py - world_p).length())
			var world_step := maxf(0.001, minf(step_x, step_y))
			var half_step := world_step * 0.5

			included_cells.append({
				"world_pos": world_p,
				"world_step": world_step,
				"color": layer_color,
				"layer": layer,
				"source_id": source_id,
				"atlas": atlas,
				"alternative": layer.get_cell_alternative_tile(cell),
			})
			min_world_step = minf(min_world_step, world_step)

			if not has_world_bounds:
				world_min = Vector2(world_p.x - half_step, world_p.y - half_step)
				world_max = Vector2(world_p.x + half_step, world_p.y + half_step)
				has_world_bounds = true
			else:
				world_min.x = minf(world_min.x, world_p.x - half_step)
				world_min.y = minf(world_min.y, world_p.y - half_step)
				world_max.x = maxf(world_max.x, world_p.x + half_step)
				world_max.y = maxf(world_max.y, world_p.y + half_step)

	zone_root.queue_free()
	if included_cells.is_empty():
		return {}

	var px_per_tile: int = int(config.get("pixels_per_tile", 2))
	px_per_tile = maxi(1, px_per_tile)
	if min_world_step >= 1e19:
		min_world_step = 1.0
	var world_size := world_max - world_min
	world_size.x = maxf(1.0, world_size.x)
	world_size.y = maxf(1.0, world_size.y)
	var px_per_world := float(px_per_tile) / maxf(0.001, min_world_step)
	var img_w := maxi(1, int(ceil(world_size.x * px_per_world)))
	var img_h := maxi(1, int(ceil(world_size.y * px_per_world)))

	var image := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0.0))

	var draw_real_tiles := bool(config.get("draw_tile_textures", true))
	var atlas_image_cache: Dictionary = {}
	var tile_stamp_cache: Dictionary = {}
	for item in included_cells:
		var world_p: Vector2 = item["world_pos"] as Vector2
		var world_step: float = float(item["world_step"])
		var col: Color = item["color"] as Color
		var px := int(floor((world_p.x - world_min.x) * px_per_world))
		var py := int(floor((world_p.y - world_min.y) * px_per_world))
		var step_px := maxi(1, int(round(world_step * px_per_world)))
		if draw_real_tiles:
			var layer_ref: TileMapLayer = item["layer"] as TileMapLayer
			var source_id_ref := int(item["source_id"])
			var atlas_ref: Vector2i = item["atlas"] as Vector2i
			var alt_ref := int(item["alternative"])
			if _blit_tile_texture(image, px, py, step_px, layer_ref, source_id_ref, atlas_ref, alt_ref, atlas_image_cache, tile_stamp_cache):
				continue
		_fill_rect(image, px, py, step_px, img_w, img_h, col)

	var tex := ImageTexture.create_from_image(image)
	var world_rect := Rect2(world_min, world_max - world_min)
	if world_rect.size.x <= 0.0:
		world_rect.size.x = 1.0
	if world_rect.size.y <= 0.0:
		world_rect.size.y = 1.0
	var result := {
		"texture": tex,
		"world_rect": world_rect,
		"tile_min": Vector2i.ZERO,
		"tile_max": Vector2i.ZERO,
	}
	_zone_cache[zone_path] = result
	return result


static func _fill_rect(image: Image, px: int, py: int, step_px: int, img_w: int, img_h: int, col: Color) -> void:
	for yy in range(py, py + step_px):
		if yy < 0 or yy >= img_h:
			continue
		for xx in range(px, px + step_px):
			if xx < 0 or xx >= img_w:
				continue
			image.set_pixel(xx, yy, col)


static func _blit_tile_texture(
		image: Image,
		px: int,
		py: int,
		step_px: int,
		layer: TileMapLayer,
		source_id: int,
		atlas: Vector2i,
		alternative: int,
		atlas_image_cache: Dictionary,
		tile_stamp_cache: Dictionary
	) -> bool:
	if layer == null or source_id < 0:
		return false
	var tile_set := layer.tile_set
	if tile_set == null:
		return false
	var tile_set_id := str(tile_set.get_instance_id())
	var stamp_key := "%s|%d|%d:%d|%d|%d" % [tile_set_id, source_id, atlas.x, atlas.y, alternative, step_px]
	if tile_stamp_cache.has(stamp_key):
		var cached_item: Dictionary = tile_stamp_cache[stamp_key] as Dictionary
		var cached_stamp: Image = cached_item.get("image", null) as Image
		var cached_offset: Vector2i = cached_item.get("offset", Vector2i.ZERO) as Vector2i
		if cached_stamp != null and not cached_stamp.is_empty():
			_blend_stamp(image, cached_stamp, Vector2i(px, py) + cached_offset)
			return true

	var src := tile_set.get_source(source_id)
	if src == null or not (src is TileSetAtlasSource):
		return false
	var atlas_src := src as TileSetAtlasSource
	var tex := atlas_src.texture
	if tex == null:
		return false

	var atlas_img_key := "%s|%d" % [tile_set_id, source_id]
	var tex_img: Image = atlas_image_cache.get(atlas_img_key, null) as Image
	if tex_img == null:
		tex_img = tex.get_image()
		if tex_img == null or tex_img.is_empty():
			return false
		atlas_image_cache[atlas_img_key] = tex_img

	var region := Rect2i()
	if atlas_src.has_method("get_tile_texture_region"):
		var rr: Variant = atlas_src.call("get_tile_texture_region", atlas)
		if rr is Rect2i:
			region = rr as Rect2i
	if region.size.x <= 0 or region.size.y <= 0:
		return false

	var tile_data := atlas_src.get_tile_data(atlas, alternative)
	var tile_origin := Vector2i.ZERO
	if tile_data != null:
		tile_origin = tile_data.texture_origin

	var tile_size := tile_set.tile_size
	var scale_x := float(step_px) / maxf(1.0, float(tile_size.x))
	var scale_y := float(step_px) / maxf(1.0, float(tile_size.y))
	var stamp_w := maxi(1, int(round(float(region.size.x) * scale_x)))
	var stamp_h := maxi(1, int(round(float(region.size.y) * scale_y)))
	# Place sprite center into tile center and then apply texture_origin as center shift.
	# (tile center) = (sprite center) + texture_origin_scaled
	# => top-left = tile_center - sprite_half_size - texture_origin_scaled
	var draw_offset := Vector2i(
		-int(round(float(stamp_w) * 0.5)) - int(round(float(tile_origin.x) * scale_x)),
		-int(round(float(stamp_h) * 0.5)) - int(round(float(tile_origin.y) * scale_y))
	)

	var stamp := tex_img.get_region(region)
	stamp.resize(stamp_w, stamp_h, Image.INTERPOLATE_LANCZOS)

	tile_stamp_cache[stamp_key] = {"image": stamp, "offset": draw_offset}
	_blend_stamp(image, stamp, Vector2i(px, py) + draw_offset)
	return true


static func _blend_stamp(dst: Image, stamp: Image, pos: Vector2i) -> void:
	var w := dst.get_width()
	var h := dst.get_height()
	for sy in range(stamp.get_height()):
		var dy := pos.y + sy
		if dy < 0 or dy >= h:
			continue
		for sx in range(stamp.get_width()):
			var dx := pos.x + sx
			if dx < 0 or dx >= w:
				continue
			var src_col := stamp.get_pixel(sx, sy)
			if src_col.a <= 0.001:
				continue
			var base_col := dst.get_pixel(dx, dy)
			dst.set_pixel(dx, dy, base_col.blend(src_col))


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

extends Node

const FIRST_ENTRY_SPAWN_POINT := preload("res://game/world/spawn/first_entry_spawn_point.gd")
const Y_SORTING := preload("res://core/render/y_sorting.gd")
const Y_SORT_DEBUG_OVERLAY := preload("res://core/render/y_sort_debug_overlay.gd")

@onready var zone_container: Node = $"../ZoneContainer"
@onready var world_root: Node = $".."

var player: Node2D
var current_target: Node = null

@export var use_cam_screen_center_for_world_math: bool = true
@export var debug_targeting_clicks: bool = false
@export var allow_corpse_targeting: bool = true
@export var debug_world_probe_under_mouse: bool = true
@export var debug_draw_y_sort_markers: bool = true
@export var debug_draw_tilemap_y_sort_markers: bool = true

# --- Save/Load runtime ---
var current_zone_path: String = ""
var _pending_override_pos: Vector2 = Vector2.ZERO
var _has_override_pos: bool = false

var _save_debounce: Timer
var _autosave: Timer
var _save_pending: bool = false
var _has_loaded_character: bool = false
var _active_y_sort_host: Node2D = null
var _tree_node_added_connected: bool = false
var _y_sort_debug_overlay: Node2D = null
var _y_sort_debug_canvas: CanvasLayer = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		push_error("Player not found in group 'player'.")
		return

	# --- save timers ---
	_save_debounce = Timer.new()
	_save_debounce.one_shot = true
	_save_debounce.wait_time = 0.6
	add_child(_save_debounce)
	_save_debounce.timeout.connect(_flush_save)

	_autosave = Timer.new()
	_autosave.one_shot = false
	_autosave.wait_time = 20.0
	add_child(_autosave)
	_autosave.timeout.connect(_autosave_tick)
	_autosave.start()

	# --- load character state into world ---
	_load_character_into_world()
	if _has_loaded_character:
		call_deferred("_emit_player_spawned")
	call_deferred("_ensure_y_sort_debug_overlay")

func _get_world_screen_center(cam: Camera2D) -> Vector2:
	if cam == null:
		return Vector2.ZERO
	if use_cam_screen_center_for_world_math:
		return cam.get_screen_center_position()
	return cam.global_position


func _ensure_y_sort_debug_overlay() -> void:
	if world_root == null:
		return
	if _y_sort_debug_overlay != null and is_instance_valid(_y_sort_debug_overlay):
		return
	if _y_sort_debug_canvas == null or not is_instance_valid(_y_sort_debug_canvas):
		_y_sort_debug_canvas = CanvasLayer.new()
		_y_sort_debug_canvas.name = "__y_sort_debug_canvas"
		_y_sort_debug_canvas.layer = 100
		world_root.add_child.call_deferred(_y_sort_debug_canvas)
	_y_sort_debug_overlay = Y_SORT_DEBUG_OVERLAY.new()
	_y_sort_debug_overlay.name = "__y_sort_debug_overlay"
	_y_sort_debug_overlay.set("manager", self)
	_y_sort_debug_canvas.add_child.call_deferred(_y_sort_debug_overlay)



func _exit_tree() -> void:
	# Ensure we don't lose the last known zone/position/stats when leaving the world scene.
	# This is especially important when the player exits to menu or the window closes.
	save_now()


func _notification(what: int) -> void:
	# Catch OS-level close requests (Alt+F4 / window close button)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


# Godot can store scene references as uid://... in some situations (or old saves).
# We keep saves stable by converting unknown UIDs back to a real path.
func _sanitize_zone_path(zone_scene_path: String) -> String:
	if zone_scene_path == null:
		return "res://game/world/zones/Zone_01.tscn"
	var p: String = String(zone_scene_path)
	if p.begins_with("uid://"):
		# If .godot cache was deleted (recommended), UID mapping may be missing.
		# Fall back to default zone instead of crashing.
		return "res://game/world/zones/Zone_01.tscn"
	return p


func _load_character_into_world() -> void:
	if not has_node("/root/AppState"):
		return

	var data: Dictionary = AppState.selected_character_data
	if data.is_empty():
		# Защиты ты просил отложить — просто ничего не делаем.
		return
	_has_loaded_character = true

	# 1) Зона + точка входа
	var zone_path: String = String(data.get("zone", "res://game/world/zones/Zone_01.tscn"))
	zone_path = _sanitize_zone_path(zone_path)
	if zone_path == "":
		zone_path = "res://game/world/zones/Zone_01.tscn"

	var spawn_name: String = "SpawnPoint"

	# 2) Позиция: если позиции нет, пробуем last_world_pos; первый вход определяем
	# по признакам сохранения, а не только по (0,0), чтобы при сбое не телепортировать
	# уже существующего персонажа в точку первого входа.
	var pos_v: Variant = data.get("pos", null)
	if not (pos_v is Dictionary):
		pos_v = data.get("last_world_pos", null)
	_has_override_pos = false
	_pending_override_pos = Vector2.ZERO
	var is_first_entry: bool = _is_first_world_entry(data)
	var restored_pos: Vector2 = _extract_non_zero_pos(pos_v)
	if restored_pos != Vector2.ZERO:
		is_first_entry = false
		_has_override_pos = true
		_pending_override_pos = restored_pos

	if is_first_entry:
		var faction_id := String(data.get("faction", "blue")).to_lower()
		var first_spawn: Dictionary = _find_first_entry_spawn_for_faction(faction_id)
		if not first_spawn.is_empty():
			zone_path = String(first_spawn.get("zone_path", zone_path))
			spawn_name = String(first_spawn.get("spawn_name", spawn_name))

	current_zone_path = zone_path

	# 3) Загружаем зону
	load_zone(zone_path, spawn_name)

	# 4) Применяем статы/инвентарь
	if player.has_method("apply_character_data"):
		player.call("apply_character_data", data)

	# 5) Сохраним состояние входа (debounce)
	request_save("enter_world")


func _extract_non_zero_pos(pos_v: Variant) -> Vector2:
	if pos_v is Dictionary:
		var pos_d: Dictionary = pos_v as Dictionary
		var x: float = float(pos_d.get("x", 0.0))
		var y: float = float(pos_d.get("y", 0.0))
		if not (is_zero_approx(x) and is_zero_approx(y)):
			return Vector2(x, y)
	return Vector2.ZERO


func _is_first_world_entry(data: Dictionary) -> bool:
	# Жесткий флаг: если уже входил в мир, повторно first-entry не запускаем.
	if bool(data.get("world_entered_once", false)):
		return false

	# Надежные признаки прогресса. Не учитываем equipment/spellbook,
	# т.к. стартовый персонаж может иметь их с момента создания.
	if int(data.get("level", 1)) > 1:
		return false
	if int(data.get("xp", 0)) > 0:
		return false

	var inventory_v: Variant = data.get("inventory", null)
	if inventory_v is Dictionary:
		var inventory: Dictionary = inventory_v as Dictionary
		if int(inventory.get("gold", 0)) > 0:
			return false
		var slots_v: Variant = inventory.get("slots", [])
		if slots_v is Array:
			for slot_v in (slots_v as Array):
				if slot_v is Dictionary and not (slot_v as Dictionary).is_empty():
					return false

	return true


func _emit_player_spawned() -> void:
	if player == null or not is_instance_valid(player):
		return
	var flow_router := get_node_or_null("/root/FlowRouter")
	if flow_router != null and flow_router.has_method("notify_player_spawned"):
		flow_router.call("notify_player_spawned", player, self)
		if OS.is_debug_build():
			print("[FLOW] player_spawned emitted. player=", player, " class=", player.get("class_id"))


func _find_first_entry_spawn_for_faction(faction_id: String) -> Dictionary:
	var normalized := faction_id.strip_edges().to_lower()
	if normalized != "red":
		normalized = "blue"
	var zones_dir := DirAccess.open("res://game/world/zones")
	if zones_dir == null:
		push_error("[FirstEntry] Cannot open zones directory")
		return {}
	zones_dir.list_dir_begin()
	var file_name := zones_dir.get_next()
	while file_name != "":
		if not zones_dir.current_is_dir() and file_name.ends_with(".tscn"):
			var zone_path := "res://game/world/zones/" + file_name
			var zone_scene := load(zone_path) as PackedScene
			if zone_scene != null:
				var root := zone_scene.instantiate()
				var marker := _find_first_entry_marker_in_tree(root, normalized)
				if marker != null:
					var result := {"zone_path": zone_path, "spawn_name": String(marker.name)}
					root.free()
					zones_dir.list_dir_end()
					return result
				root.free()
		file_name = zones_dir.get_next()
	zones_dir.list_dir_end()
	push_error("[FirstEntry] Spawn marker for faction '%s' not found" % normalized)
	return {}

func _find_first_entry_marker_in_tree(root: Node, faction_id: String) -> Marker2D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D and current.get_script() == FIRST_ENTRY_SPAWN_POINT:
			if current.has_method("get_faction_id") and String(current.call("get_faction_id")).to_lower() == faction_id:
				return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


# ---------------------------
# Save API (debounced)
# ---------------------------
func request_save(_reason: String) -> void:
	_save_pending = true
	_save_debounce.start()

func _flush_save() -> void:
	if not _save_pending:
		return
	_save_pending = false
	_do_save_now()

func _autosave_tick() -> void:
	request_save("autosave")

func _do_save_now() -> void:
	if not has_node("/root/AppState"):
		return
	if AppState.selected_character_id == "":
		return
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("export_character_data"):
		return

	var data: Dictionary = player.call("export_character_data")

	# зона
	if current_zone_path != "":
		data["zone"] = current_zone_path
	data["world_entered_once"] = true
	data["last_world_zone"] = current_zone_path
	data["last_world_pos"] = {"x": float(player.global_position.x), "y": float(player.global_position.y)}

	AppState.save_selected_character(data)


# ---------------------------
# Zone loading
# ---------------------------
func load_zone(zone_scene_path: String, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene_path == "" or zone_scene_path == null:
		push_error("Zone path is empty.")
		return

	current_zone_path = zone_scene_path
	request_save("zone_change")

	# Wait a frame so physics flushing doesn't explode
	call_deferred("_load_zone_deferred", zone_scene_path, spawn_name)


func _load_zone_deferred(zone_scene_path: String, spawn_name: String) -> void:
	var zone_scene: PackedScene = load(zone_scene_path)
	if zone_scene == null:
		push_error("Failed to load zone: " + zone_scene_path)
		return

	# Clear previous zone
	_detach_player_from_zone_for_reload()
	for child in zone_container.get_children():
		child.queue_free()

	# Instantiate new zone
	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	# Move player to spawn
	var resolved_spawn: Marker2D = _resolve_spawn_marker(new_zone, spawn_name)
	if resolved_spawn != null:
		player.global_position = resolved_spawn.global_position
	else:
		push_error("Zone '%s' has no valid spawn marker. Keeping current player position." % zone_scene_path)

	# Override position if saved (not first entry)
	if _has_override_pos:
		player.global_position = _pending_override_pos
		_has_override_pos = false

	# Sync camera limits with the loaded zone so large maps keep player visible.
	_apply_camera_limits_from_zone(new_zone)
	_attach_player_to_zone_sort_host(new_zone)

	# Optional: target becomes invalid when changing zones
	clear_target()




func _detach_player_from_zone_for_reload() -> void:
	if player == null or not is_instance_valid(player):
		return
	if world_root == null:
		return
	if player.get_parent() == world_root:
		return
	player.reparent(world_root, true)


func _attach_player_to_zone_sort_host(zone_root: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	if zone_root == null:
		return
	var host: Node2D = _find_zone_sort_host(zone_root)
	if host == null:
		return
	host.y_sort_enabled = true
	var entity_host := _ensure_y_sort_runtime_layer(host)
	if player.get_parent() != entity_host:
		player.reparent(entity_host, true)
	player.top_level = false
	player.y_sort_enabled = true
	player.z_as_relative = true
	player.z_index = int(entity_host.z_index)


func _ensure_y_sort_runtime_layer(host: Node2D) -> Node2D:
	var runtime := host.get_node_or_null("__y_sort_runtime") as Node2D
	if runtime == null:
		runtime = Node2D.new()
		runtime.name = "__y_sort_runtime"
		runtime.y_sort_enabled = true
		runtime.z_index = int(host.z_index)
		host.add_child(runtime)
	if not bool(host.get_meta("__y_sort_runtime_flattened", false)):
		var tile_layers: Array[TileMapLayer] = []
		_collect_tile_layers_for_runtime(host, runtime, tile_layers)
		for layer in tile_layers:
			if layer.get_parent() != runtime:
				layer.reparent(runtime, true)
		var sortable_nodes: Array[Node2D] = []
		_collect_sortable_nodes_for_runtime(host, runtime, sortable_nodes)
		for sortable in sortable_nodes:
			_maybe_promote_node_to_runtime(sortable, runtime)
		host.set_meta("__y_sort_runtime_flattened", true)
	_active_y_sort_host = host
	if not _tree_node_added_connected:
		var cb := Callable(self, "_on_tree_node_added")
		if not get_tree().node_added.is_connected(cb):
			get_tree().node_added.connect(cb)
		_tree_node_added_connected = true
	return runtime


func _collect_tile_layers_for_runtime(node: Node, runtime: Node2D, out_layers: Array[TileMapLayer]) -> void:
	if node == runtime:
		return
	for child in node.get_children():
		if child == runtime:
			continue
		if child is TileMapLayer:
			out_layers.append(child as TileMapLayer)
		elif child is Node:
			_collect_tile_layers_for_runtime(child as Node, runtime, out_layers)


func _collect_sortable_nodes_for_runtime(node: Node, runtime: Node2D, out_nodes: Array[Node2D]) -> void:
	if node == runtime:
		return
	for child in node.get_children():
		if child == runtime:
			continue
		if child is Node2D:
			out_nodes.append(child as Node2D)
		if child is Node:
			_collect_sortable_nodes_for_runtime(child as Node, runtime, out_nodes)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _active_y_sort_host == null or not is_instance_valid(_active_y_sort_host):
		return
	if not _active_y_sort_host.is_ancestor_of(node):
		return
	# Godot can emit node_added while the parent is still mutating children.
	# Deferring avoids "parent is busy adding/removing children" reparent errors.
	call_deferred("_promote_node_to_runtime_deferred", node)


func _promote_node_to_runtime_deferred(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _active_y_sort_host == null or not is_instance_valid(_active_y_sort_host):
		return
	if not _active_y_sort_host.is_ancestor_of(node):
		return
	var runtime := _active_y_sort_host.get_node_or_null("__y_sort_runtime") as Node2D
	if runtime == null:
		return
	_maybe_promote_node_to_runtime(node, runtime)


func _maybe_promote_node_to_runtime(node: Node, runtime: Node2D) -> void:
	if node == runtime:
		return
	if node is TileMapLayer:
		if node.get_parent() != runtime:
			(node as TileMapLayer).reparent(runtime, true)
		return
	if not (node is Node2D):
		return
	var n2d := node as Node2D
	if _has_y_sort_entity_ancestor(n2d):
		return
	if _should_skip_nested_runtime_promotion(n2d):
		return
	var node_name := String(n2d.name).to_lower()
	if node_name == "decor" or node_name == "spawner groups" or node_name == "__y_sort_runtime":
		return
	var should_promote: bool = false
	should_promote = _is_runtime_promotion_candidate(n2d)
	if should_promote and n2d.get_parent() != runtime:
		n2d.reparent(runtime, true)
	_try_sync_node_y_sort_origin_from_world_collider(n2d)


func _has_y_sort_entity_ancestor(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var parent := node.get_parent()
	while parent != null:
		if parent.is_in_group("y_sort_entities"):
			return true
		parent = parent.get_parent()
	return false


func _is_runtime_promotion_candidate(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var node_name := String(node.name).to_lower()
	if node.has_method("get_sort_anchor_global"):
		return true
	if node.is_in_group("y_sort_entities"):
		return true
	if node_name == "player":
		return true
	if node.get_node_or_null("CollisionProfile/WorldCollider") != null:
		return true
	if node.get_node_or_null("WorldCollider") != null:
		return true
	return false


func _should_skip_nested_runtime_promotion(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return true
	var parent := node.get_parent()
	while parent != null:
		if parent is Node2D and _is_runtime_promotion_candidate(parent as Node2D):
			return true
		if parent == _active_y_sort_host:
			break
		parent = parent.get_parent()
	return false


func _try_sync_node_y_sort_origin_from_world_collider(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var world_collider := node.get_node_or_null("WorldCollider") as CollisionShape2D
	if world_collider == null:
		world_collider = node.get_node_or_null("CollisionProfile/WorldCollider") as CollisionShape2D
	if world_collider == null:
		return
	var origin_y := _compute_world_collider_sort_origin_y(node, world_collider)
	_apply_node_y_sort_origin(node, origin_y)


func _compute_world_collider_sort_origin_y(owner: Node2D, collider: CollisionShape2D) -> float:
	# Match debug green-diamond logic: collider center in global space, converted to owner local.
	if owner == null or not is_instance_valid(owner):
		return float(collider.position.y)
	return float(owner.to_local(collider.global_position).y)


func _apply_node_y_sort_origin(node: Node2D, origin_y: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var origin_i := int(round(origin_y))
	if node.has_method("set_y_sort_origin"):
		node.call("set_y_sort_origin", origin_i)
		return
	if node.has_method("get_y_sort_origin"):
		node.set("y_sort_origin", origin_i)
		return
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			node.set("y_sort_origin", origin_i)
			return
	node.set_meta("__debug_y_sort_origin_local", origin_i)


func _read_node_y_sort_origin_local(node: Node2D) -> Dictionary:
	var result := {
		"has_origin": false,
		"origin": 0.0,
		"source": "none",
	}
	if node == null or not is_instance_valid(node):
		return result
	if node.has_method("get_y_sort_origin"):
		result["has_origin"] = true
		result["origin"] = float(node.call("get_y_sort_origin"))
		result["source"] = "getter"
		return result
	for prop in node.get_property_list():
		if String(prop.get("name", "")) == "y_sort_origin":
			result["has_origin"] = true
			result["origin"] = float(node.get("y_sort_origin"))
			result["source"] = "property"
			return result
	if node.has_meta("__debug_y_sort_origin_local"):
		# Debug-only fallback: not guaranteed to be used by renderer sorting.
		result["has_origin"] = false
		result["origin"] = float(node.get_meta("__debug_y_sort_origin_local"))
		result["source"] = "meta"
	return result


func _find_zone_sort_host(zone_root: Node) -> Node2D:
	if zone_root == null:
		return null
	var stack: Array[Node] = [zone_root]
	var fallback_z50: Node2D = null
	var fallback_ysort: Node2D = null
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Node2D:
			var node2d := current as Node2D
			var node_name := String(current.name)
			if node_name == "z-level = 50, y-sort = true":
				return node2d
			if fallback_z50 == null and int(node2d.z_index) == 50:
				fallback_z50 = node2d
			if fallback_ysort == null and node2d.y_sort_enabled:
				fallback_ysort = node2d
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	if fallback_z50 != null:
		return fallback_z50
	return fallback_ysort


func _apply_camera_limits_from_zone(zone_root: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var camera := player.get_node_or_null("Camera") as Camera2D
	if camera == null:
		return
	var bounds: Rect2 = _collect_zone_world_bounds(zone_root)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var sort_bounds: Rect2 = _collect_zone_world_bounds(zone_root, true)
	if sort_bounds.size.x <= 0.0 or sort_bounds.size.y <= 0.0:
		sort_bounds = bounds
	var sort_origin_y: float = sort_bounds.position.y + (sort_bounds.size.y * 0.5)
	var sort_factor: float = 1.0
	if sort_bounds.size.y > 1.0:
		sort_factor = min(1.0, 3000.0 / sort_bounds.size.y)
	Y_SORTING.configure_world_y_mapping(sort_origin_y, sort_factor)
	camera.limit_left = int(floor(bounds.position.x))
	camera.limit_top = int(floor(bounds.position.y))
	camera.limit_right = int(ceil(bounds.position.x + bounds.size.x))
	camera.limit_bottom = int(ceil(bounds.position.y + bounds.size.y))


func _collect_zone_world_bounds(zone_root: Node, only_y_sorted_layers: bool = false) -> Rect2:
	if zone_root == null:
		return Rect2()
	var has_bounds := false
	var min_pos := Vector2.ZERO
	var max_pos := Vector2.ZERO
	var stack: Array[Node] = [zone_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is TileMapLayer:
			var tile_layer := current as TileMapLayer
			if only_y_sorted_layers and not tile_layer.y_sort_enabled:
				for child in current.get_children():
					if child is Node:
						stack.append(child)
				continue
			var used: Rect2i = tile_layer.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				var start_local: Vector2 = tile_layer.map_to_local(used.position)
				var end_local: Vector2 = tile_layer.map_to_local(used.position + used.size)
				var top_left: Vector2 = tile_layer.to_global(start_local)
				var bottom_right: Vector2 = tile_layer.to_global(end_local)
				if not has_bounds:
					min_pos = Vector2(min(top_left.x, bottom_right.x), min(top_left.y, bottom_right.y))
					max_pos = Vector2(max(top_left.x, bottom_right.x), max(top_left.y, bottom_right.y))
					has_bounds = true
				else:
					min_pos.x = min(min_pos.x, top_left.x, bottom_right.x)
					min_pos.y = min(min_pos.y, top_left.y, bottom_right.y)
					max_pos.x = max(max_pos.x, top_left.x, bottom_right.x)
					max_pos.y = max(max_pos.y, top_left.y, bottom_right.y)
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	if not has_bounds:
		return Rect2()
	return Rect2(min_pos, max_pos - min_pos).grow(256.0)

func _resolve_spawn_marker(zone_root: Node, requested_spawn_name: String) -> Marker2D:
	if zone_root == null:
		return null

	# 1) Explicit spawn name from portal/flow.
	var requested: Node = zone_root.get_node_or_null(requested_spawn_name)
	if requested is Marker2D:
		return requested as Marker2D

	# 2) Conventional name used by existing zones.
	var default_spawn: Node = zone_root.get_node_or_null("SpawnPoint")
	if default_spawn is Marker2D:
		return default_spawn as Marker2D

	# 3) First-entry markers can act as normal fallback if no SpawnPoint exists.
	var first_entry_marker: Marker2D = _find_first_marker_with_script(zone_root, FIRST_ENTRY_SPAWN_POINT)
	if first_entry_marker != null:
		return first_entry_marker

	# 4) Last resort: any marker in the zone.
	return _find_first_marker_in_tree(zone_root)


func _find_first_marker_with_script(root: Node, script_ref: Script) -> Marker2D:
	if root == null or script_ref == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D and current.get_script() == script_ref:
			return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


func _find_first_marker_in_tree(root: Node) -> Marker2D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is Marker2D:
			return current as Marker2D
		for child in current.get_children():
			if child is Node:
				stack.append(child)
	return null


# ---------------------------
# Target API
# ---------------------------
func set_target(mob: Node) -> void:
	if mob == null or not is_instance_valid(mob):
		current_target = null
		return
	current_target = mob


func get_target() -> Node:
	if current_target == null or not is_instance_valid(current_target):
		current_target = null
		return null

	# Сброс, если цель вне видимости камеры
	if current_target is Node2D:
		var t := current_target as Node2D
		if not _is_world_pos_visible(t.global_position):
			current_target = null
			return null

	return current_target


func clear_target() -> void:
	current_target = null


# ---------------------------
# Input: click/tap to select target
# ---------------------------
func _input(event: InputEvent) -> void:
	var screen_pos: Vector2
	var pressed: bool = false

	# Mouse click
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			if debug_world_probe_under_mouse:
				_debug_probe_under_mouse(mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			screen_pos = mb.position
			pressed = true

	# Touch
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			screen_pos = st.position
			pressed = true

	if not pressed:
		return

	if debug_targeting_clicks:
		print("[TargetingDebug] click screen=", screen_pos)

	if _is_ui_press_event(screen_pos):
		if debug_targeting_clicks:
			var hit := _get_ui_control_at_screen_pos(screen_pos)
			var hit_name := "<null>"
			var hit_type := "<null>"
			if hit != null:
				hit_name = String((hit as Node).name)
				hit_type = hit.get_class()
			print("[TargetingDebug] blocked by UI control=", hit_name, " type=", hit_type)
		return


	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var mob: Node = _pick_mob_at_world_pos(world_pos)
	if debug_targeting_clicks:
		print("[TargetingDebug] world=", world_pos, " mob=", mob)

	if mob != null:
		set_target(mob)
		if debug_targeting_clicks:
			print("[TargetingDebug] set_target -> ", mob)
	else:
		clear_target()
		if debug_targeting_clicks:
			print("[TargetingDebug] clear_target (no mob under click)")


func _is_ui_press_event(screen_pos: Vector2) -> bool:
	var hit := _get_ui_control_at_screen_pos(screen_pos)
	if hit == null:
		return false

	var node: Control = hit
	while node != null:
		if node.visible and node.mouse_filter == Control.MOUSE_FILTER_STOP and _should_block_world_targeting(node):
			return true
		node = node.get_parent() as Control
	return false


func _should_block_world_targeting(c: Control) -> bool:
	if c == null:
		return false
	# Built-in interactive widgets.
	if _is_interactive_ui_control(c):
		return true
	# Custom scripted controls (e.g. mobile joystick/pads).
	if c.get_script() != null:
		return true
	# Labels/panels with explicitly connected gui_input handlers.
	if c.gui_input.get_connections().size() > 0:
		return true
	return false


func _get_ui_control_at_screen_pos(screen_pos: Vector2) -> Control:
	var vp: Viewport = get_viewport()
	if vp == null:
		return null
	# Prefer hover on desktop (cheap and reliable for mouse).
	var hovered: Control = vp.gui_get_hovered_control()
	if hovered != null and hovered.get_global_rect().has_point(screen_pos):
		return hovered

	# Godot version in this project doesn't expose `gui_pick` on Window/Viewport,
	# so we resolve topmost control manually for touch/click position.
	var root: Node = get_tree().root
	if root == null:
		return null
	return _find_top_control_at_pos(root, screen_pos)


func _find_top_control_at_pos(node: Node, screen_pos: Vector2) -> Control:
	if node == null:
		return null

	if node is Control:
		var ctrl := node as Control
		if not ctrl.visible:
			return null
		if ctrl.clip_contents and not ctrl.get_global_rect().has_point(screen_pos):
			return null

	# Traverse children in reverse order to match draw/input priority.
	for i in range(node.get_child_count() - 1, -1, -1):
		var child: Node = node.get_child(i)
		var hit := _find_top_control_at_pos(child, screen_pos)
		if hit != null:
			return hit

	if node is Control:
		var ctrl2 := node as Control
		if ctrl2.mouse_filter != Control.MOUSE_FILTER_IGNORE and ctrl2.get_global_rect().has_point(screen_pos):
			return ctrl2
	return null


func _is_interactive_ui_control(c: Control) -> bool:
	if c == null:
		return false
	# Реально кликабельные/вводные контролы.
	return (
		c is BaseButton
		or c is LineEdit
		or c is TextEdit
		or c is ItemList
		or c is Tree
		or c is OptionButton
		or c is SpinBox
		or c is Slider
		or c is ScrollBar
	)



func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	var cam := vp.get_camera_2d()
	if cam == null:
		return vp.get_canvas_transform().affine_inverse() * screen_pos
	if not use_cam_screen_center_for_world_math:
		return vp.get_canvas_transform().affine_inverse() * screen_pos
	var center_world := _get_world_screen_center(cam)
	var screen_size := vp.get_visible_rect().size
	var screen_center := screen_size * 0.5
	var delta_screen := screen_pos - screen_center
	var zoom := cam.zoom
	var delta_world := Vector2(delta_screen.x * zoom.x, delta_screen.y * zoom.y)
	return center_world + delta_world


func _pick_mob_at_world_pos(world_pos: Vector2) -> Node:
	var vp: Viewport = get_viewport()
	var space_state: PhysicsDirectSpaceState2D = vp.world_2d.direct_space_state

	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = 0xFFFFFFFF

	var hits: Array[Dictionary] = space_state.intersect_point(params, 32)
	if hits.is_empty():
		return null

	for hit: Dictionary in hits:
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == null:
			continue

		var node: Node = collider_obj as Node
		while node != null:
			if node.is_in_group("mobs"):
				return node
			if allow_corpse_targeting and node is Corpse:
				return node
			node = node.get_parent()

	return null


func _debug_probe_under_mouse(screen_pos: Vector2) -> void:
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	print("[SortProbe] screen=", screen_pos, " world=", world_pos)
	if player != null and is_instance_valid(player):
		var p_z: int = int((player as CanvasItem).z_index) if player is CanvasItem else 0
		var root_y := float(player.global_position.y)
		var root_pos := player.global_position
		var anchor_global := root_pos
		if player.has_method("get_sort_anchor_global"):
			var anchor_v: Variant = player.call("get_sort_anchor_global")
			if anchor_v is Vector2:
				anchor_global = anchor_v as Vector2
		var wc_global := root_pos
		if player.has_method("get_world_collider_center_global"):
			var wc_v: Variant = player.call("get_world_collider_center_global")
			if wc_v is Vector2:
				wc_global = wc_v as Vector2
		var has_y_sort_origin := false
		var y_sort_origin_v: Variant = null
		var player_origin_info := _read_node_y_sort_origin_local(player)
		has_y_sort_origin = bool(player_origin_info.get("has_origin", false))
		y_sort_origin_v = player_origin_info.get("origin", 0.0)
		var origin_source := String(player_origin_info.get("source", "none"))
		var parent_path: String = str(player.get_parent().get_path()) if player.get_parent() != null else "<null>"
		print("[SortProbe][Player] root_pos=", root_pos, " root_y=", root_y, " z=", p_z, " parent=", parent_path)
		print("[SortProbe][Player] anchor_global=", anchor_global, " anchor_y=", float(anchor_global.y), " wc_global=", wc_global, " wc_y=", float(wc_global.y))
		if has_y_sort_origin:
			var computed_y := root_y + float(y_sort_origin_v)
			print("[SortProbe][Player] y_sort_origin(local)=", y_sort_origin_v, " source=", origin_source, " computed_global_y=", computed_y, " anchor_delta=", float(anchor_global.y) - computed_y)
		else:
			if origin_source == "meta":
				print("[SortProbe][Player] y_sort_origin(local)=<meta-only ", y_sort_origin_v, " renderer_uses_origin=false>")
			else:
				print("[SortProbe][Player] y_sort_origin(local)=<missing on Player node>")
	var y_map: Dictionary = Y_SORTING.get_world_y_mapping_debug()
	print("[SortProbe] y_map origin=", float(y_map.get("origin_y", 0.0)), " factor=", float(y_map.get("factor", 0.0)))

	var zone_root: Node = null
	if zone_container != null and zone_container.get_child_count() > 0:
		zone_root = zone_container.get_child(0)
	if zone_root == null:
		print("[SortProbe] no zone root in ZoneContainer")
		return

	var layers: Array[TileMapLayer] = []
	var stack: Array[Node] = [zone_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back() as Node
		if current is TileMapLayer:
			layers.append(current as TileMapLayer)
		for child in current.get_children():
			if child is Node:
				stack.append(child)

	for layer in layers:
		var cell: Vector2i = layer.local_to_map(layer.to_local(world_pos))
		var source_id: int = layer.get_cell_source_id(cell)
		if source_id == -1:
			continue
		var tile_data := layer.get_cell_tile_data(cell)
		var tile_y_sort_origin := 0.0
		var tile_texture_origin_y := 0.0
		if tile_data != null and tile_data.has_method("get_y_sort_origin"):
			tile_y_sort_origin = float(tile_data.call("get_y_sort_origin"))
		if tile_data != null and tile_data.has_method("get_texture_origin"):
			var tex_origin_v: Variant = tile_data.call("get_texture_origin")
			if tex_origin_v is Vector2i:
				tile_texture_origin_y = float((tex_origin_v as Vector2i).y)
			elif tex_origin_v is Vector2:
				tile_texture_origin_y = float((tex_origin_v as Vector2).y)
		var tile_anchor_world := layer.to_global(layer.map_to_local(cell) + Vector2(0.0, tile_y_sort_origin))
		print("[SortProbe][Tile] layer=", layer.get_path(), " y_sort=", layer.y_sort_enabled, " z=", layer.z_index, " scale=", layer.scale, " cell=", cell, " source=", source_id, " texture_origin_y=", tile_texture_origin_y, " y_sort_origin=", tile_y_sort_origin, " anchor_y=", float(tile_anchor_world.y))

	var entities := get_tree().get_nodes_in_group("y_sort_entities")
	for e in entities:
		if not (e is Node2D):
			continue
		var n := e as Node2D
		if not is_instance_valid(n):
			continue
		if n.global_position.distance_to(world_pos) > 260.0:
			continue
		var ez: int = int((n as CanvasItem).z_index) if n is CanvasItem else 0
		var origin_info := _read_node_y_sort_origin_local(n)
		var has_origin := bool(origin_info.get("has_origin", false))
		var local_origin_y := float(origin_info.get("origin", 0.0))
		var origin_source := String(origin_info.get("source", "none"))
		var effective_sort_y := float(n.global_position.y) + local_origin_y if has_origin else float(n.global_position.y)
		var origin_print: Variant = local_origin_y if has_origin else "<none>"
		if origin_source == "meta" and not has_origin:
			origin_print = "<meta-only %s>" % String(local_origin_y)
		print("[SortProbe][Entity] node=", n.get_path(), " root_y=", n.global_position.y, " sort_y=", effective_sort_y, " local_origin=", origin_print, " source=", origin_source, " z=", ez, " pos=", n.global_position)


func _is_world_pos_visible(world_pos: Vector2) -> bool:
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return true

	var center := _get_world_screen_center(cam)
	var half_size: Vector2 = vp.get_visible_rect().size * 0.5 * cam.zoom
	var rect := Rect2(center - half_size, half_size * 2.0)
	return rect.has_point(world_pos)


func get_nearest_graveyard_position(from_world_pos: Vector2) -> Vector2:
	var graveyards := get_tree().get_nodes_in_group("graveyards")

	var best_pos: Vector2 = from_world_pos
	var best_dist: float = INF

	for g in graveyards:
		if g == null:
			continue

		if g.has_method("get_spawn_position"):
			var p: Vector2 = g.call("get_spawn_position")
			var d: float = from_world_pos.distance_to(p)
			if d < best_dist:
				best_dist = d
				best_pos = p
		elif g is Node2D:
			var p2: Vector2 = (g as Node2D).global_position
			var d2: float = from_world_pos.distance_to(p2)
			if d2 < best_dist:
				best_dist = d2
				best_pos = p2

	return best_pos


# Preferred API: accept PackedScene directly (safer than string paths).
func load_zone_scene(zone_scene: PackedScene, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene == null:
		push_error("Zone scene is null.")
		return
	call_deferred("_load_zone_scene_deferred", zone_scene, spawn_name)


func _load_zone_scene_deferred(zone_scene: PackedScene, spawn_name: String) -> void:
	for child in zone_container.get_children():
		child.queue_free()

	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	var spawn: Node = new_zone.get_node_or_null(spawn_name)
	if spawn is Marker2D:
		player.global_position = (spawn as Marker2D).global_position
	else:
		var default_spawn: Node = new_zone.get_node_or_null("SpawnPoint")
		if default_spawn is Marker2D:
			player.global_position = (default_spawn as Marker2D).global_position
		else:
			player.global_position = new_zone.global_position

	clear_target()


func save_now() -> void:
	if has_method("_do_save_now"):
		call("_do_save_now")
		return
	if has_method("_flush_save"):
		call("_flush_save")
		return
	if has_method("request_save"):
		request_save("save_now")

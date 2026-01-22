extends Node

@onready var zone_container: Node = $"../ZoneContainer"

var player: Node2D
var current_target: Node = null

# --- Debug click marker ---
@export var debug_show_click_world_marker: bool = true
@export var debug_marker_lifetime_sec: float = 1.5
@export var debug_marker_radius_px: float = 6.0
@export var debug_click_log_v1: bool = true
@export var debug_cam_center_log_v2: bool = true
@export var debug_target_visibility_log_v2: bool = true
var _debug_marker: Node2D = null
var _debug_marker_timer: float = 0.0
const DBG_V1 := "[DBG_CLICK_V1]"
const DBG_V2 := "[DBG_CAM_V2]"
const DBG_V2_VIS := "[DBG_VIS_V2]"

# --- Save/Load runtime ---
var current_zone_path: String = ""
var _pending_override_pos: Vector2 = Vector2.ZERO
var _has_override_pos: bool = false

var _save_debounce: Timer
var _autosave: Timer
var _save_pending: bool = false


func _ready() -> void:
	set_process(true)
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


func _process(delta: float) -> void:
	if not OS.is_debug_build():
		return
	if not debug_show_click_world_marker:
		return
	if _debug_marker == null or not is_instance_valid(_debug_marker):
		return
	if _debug_marker_timer <= 0.0:
		return
	_debug_marker_timer = max(0.0, _debug_marker_timer - delta)
	if _debug_marker_timer <= 0.0:
		_debug_marker.visible = false


func _ensure_debug_marker() -> void:
	if _debug_marker != null and is_instance_valid(_debug_marker):
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var marker := Node2D.new()
	marker.name = "__DebugClickMarker"
	marker.visible = false
	root.add_child(marker)

	var radius: float = max(2.0, debug_marker_radius_px)
	var horiz := Line2D.new()
	horiz.name = "CrossH"
	horiz.width = 2.0
	horiz.default_color = Color(1.0, 0.2, 0.2, 1.0)
	horiz.points = PackedVector2Array([Vector2(-radius, 0.0), Vector2(radius, 0.0)])
	marker.add_child(horiz)

	var vert := Line2D.new()
	vert.name = "CrossV"
	vert.width = 2.0
	vert.default_color = Color(1.0, 0.2, 0.2, 1.0)
	vert.points = PackedVector2Array([Vector2(0.0, -radius), Vector2(0.0, radius)])
	marker.add_child(vert)

	_debug_marker = marker


func _show_debug_marker_at(world_pos: Vector2) -> void:
	_ensure_debug_marker()
	if _debug_marker == null or not is_instance_valid(_debug_marker):
		return
	_debug_marker.global_position = world_pos
	_debug_marker.visible = true
	_debug_marker_timer = debug_marker_lifetime_sec

func _dbg_compute_visible_world_rect(center_world: Vector2) -> Rect2:
	var vp := get_viewport()
	var cam := vp.get_camera_2d()
	if cam == null:
		return Rect2(center_world, Vector2.ZERO)
	var size := vp.get_visible_rect().size
	var half := size * 0.5
	var zoom := cam.zoom
	var top_left := center_world - Vector2(half.x * zoom.x, half.y * zoom.y)
	var world_size := Vector2(size.x * zoom.x, size.y * zoom.y)
	return Rect2(top_left, world_size)


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

	# 1) Зона: всегда берём из data["zone"], по умолчанию Zone_01 (у тебя это уже записывается при создании)
	var zone_path: String = String(data.get("zone", "res://game/world/zones/Zone_01.tscn"))
	zone_path = _sanitize_zone_path(zone_path)
	if zone_path == "":
		zone_path = "res://game/world/zones/Zone_01.tscn"

	current_zone_path = zone_path

	# 2) Позиция: применяем ТОЛЬКО если она не (0,0) — иначе это “первый вход”
	var pos_v: Variant = data.get("pos", null)
	_has_override_pos = false
	_pending_override_pos = Vector2.ZERO
	if pos_v is Dictionary:
		var pos_d: Dictionary = pos_v as Dictionary
		var x: float = float(pos_d.get("x", 0.0))
		var y: float = float(pos_d.get("y", 0.0))
		if not (is_zero_approx(x) and is_zero_approx(y)):
			_has_override_pos = true
			_pending_override_pos = Vector2(x, y)

	# 3) Загружаем зону
	load_zone(zone_path, "SpawnPoint")

	# 4) Применяем статы/инвентарь
	if player.has_method("apply_character_data"):
		player.call("apply_character_data", data)

	# 5) Сохраним состояние входа (debounce)
	request_save("enter_world")


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
	for child in zone_container.get_children():
		child.queue_free()

	# Instantiate new zone
	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	# Move player to spawn
	var spawn: Node = new_zone.get_node_or_null(spawn_name)
	if spawn is Marker2D:
		player.global_position = (spawn as Marker2D).global_position
	else:
		var default_spawn: Node = new_zone.get_node_or_null("SpawnPoint")
		if default_spawn is Marker2D:
			player.global_position = (default_spawn as Marker2D).global_position
		else:
			player.global_position = new_zone.global_position

	# Override position if saved (not first entry)
	if _has_override_pos:
		player.global_position = _pending_override_pos
		_has_override_pos = false

	# Optional: target becomes invalid when changing zones
	clear_target()


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
			if OS.is_debug_build() and debug_target_visibility_log_v2:
				var cam := get_viewport().get_camera_2d()
				var cam_node := cam.global_position if cam != null else Vector2.ZERO
				var cam_center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
				print(DBG_V2_VIS, " CLEAR_TARGET reason=not_visible", " target_pos=", t.global_position, " cam_node=", cam_node, " cam_center=", cam_center)
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

	var world_pos: Vector2 = _screen_to_world(screen_pos)
	if OS.is_debug_build() and debug_show_click_world_marker:
		_show_debug_marker_at(world_pos)
		var cam := get_viewport().get_camera_2d()
		var cam_node := Vector2.ZERO
		var cam_center := Vector2.ZERO
		if cam != null:
			cam_node = cam.global_position
			cam_center = cam.get_screen_center_position()
		if debug_click_log_v1:
			print(DBG_V1, " screen=", screen_pos, " world=", world_pos, " cam_node=", cam_node, " cam_center=", cam_center, " zoom=", cam.zoom if cam != null else Vector2.ONE, " vp_size=", get_viewport().get_visible_rect().size)
		if debug_cam_center_log_v2 and cam != null:
			var delta := cam_center - cam_node
			print(DBG_V2, " cam_node=", cam_node, " cam_center=", cam_center, " delta(center-node)=", delta, " zoom=", cam.zoom)
		if debug_target_visibility_log_v2 and cam != null:
			var rect_node := _dbg_compute_visible_world_rect(cam_node)
			var rect_center := _dbg_compute_visible_world_rect(cam_center)
			print(DBG_V2_VIS, " click_world=", world_pos, " contains_node_rect=", rect_node.has_point(world_pos), " contains_center_rect=", rect_center.has_point(world_pos), " rect_node=", rect_node, " rect_center=", rect_center)
	var mob: Node = _pick_mob_at_world_pos(world_pos)

	if mob != null:
		set_target(mob)
	else:
		clear_target()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp: Viewport = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * screen_pos


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
			node = node.get_parent()

	return null


func _is_world_pos_visible(world_pos: Vector2) -> bool:
	var vp: Viewport = get_viewport()
	var cam: Camera2D = vp.get_camera_2d()
	if cam == null:
		return true

	var half_size: Vector2 = vp.get_visible_rect().size * 0.5 * cam.zoom
	var rect := Rect2(cam.global_position - half_size, half_size * 2.0)
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

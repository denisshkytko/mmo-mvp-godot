extends Node

@onready var zone_container: Node = $"../ZoneContainer"

var player: Node2D
var current_target: Node = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		push_error("Player not found in group 'player'.")
		return


# ---------------------------
# Zone loading
# ---------------------------
func load_zone(zone_scene_path: String, spawn_name: String = "SpawnPoint") -> void:
	if zone_scene_path == "" or zone_scene_path == null:
		push_error("Zone path is empty.")
		return

	# Wait a frame so physics flushing doesn't explode (we already use this pattern)
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

	# Touch (Emulate Touch From Mouse or mobile)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			screen_pos = st.position
			pressed = true

	if not pressed:
		return

	var world_pos: Vector2 = _screen_to_world(screen_pos)
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

	# Typed array to avoid "cannot infer type" issues when warnings are errors
	var hits: Array[Dictionary] = space_state.intersect_point(params, 32)
	if hits.is_empty():
		return null

	for hit: Dictionary in hits:
		var collider_obj: Object = hit.get("collider") as Object
		if collider_obj == null:
			continue

		# Если клик попал в Area2D, она может быть TargetHitbox
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

		# Если это наша сцена Graveyard с методом
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
	# Удаляем текущую зону
	for child in zone_container.get_children():
		child.queue_free()

	# Создаём новую
	var new_zone: Node2D = zone_scene.instantiate() as Node2D
	zone_container.add_child(new_zone)

	# Спавним игрока
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

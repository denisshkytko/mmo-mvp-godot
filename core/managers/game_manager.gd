extends Node

const FIRST_ENTRY_SPAWN_POINT := preload("res://game/world/spawn/first_entry_spawn_point.gd")

@onready var zone_container: Node = $"../ZoneContainer"

var player: Node2D
var current_target: Node = null

@export var use_cam_screen_center_for_world_math: bool = true
@export var debug_targeting_clicks: bool = false
@export var allow_corpse_targeting: bool = true

# --- Save/Load runtime ---
var current_zone_path: String = ""
var _pending_override_pos: Vector2 = Vector2.ZERO
var _has_override_pos: bool = false

var _save_debounce: Timer
var _autosave: Timer
var _save_pending: bool = false
var _has_loaded_character: bool = false


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

func _get_world_screen_center(cam: Camera2D) -> Vector2:
	if cam == null:
		return Vector2.ZERO
	if use_cam_screen_center_for_world_math:
		return cam.get_screen_center_position()
	return cam.global_position



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

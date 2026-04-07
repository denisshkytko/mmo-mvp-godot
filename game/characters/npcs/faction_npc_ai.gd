extends Node
class_name FactionNPCAI

enum Behavior { GUARD, PATROL }
enum State { IDLE, CHASE, RETURN }

signal leash_return_started
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const COMBAT_SPACING_BUFFER: float = 32.0
const PATROL_SEPARATION_DISTANCE: float = 28.0
const PATROL_SEPARATION_REFRESH_SEC: float = 0.30
const OBSTACLE_AVOID_LOOKAHEAD: float = 18.0
const OBSTACLE_AVOID_ANGLES := [0.35, -0.35, 0.7, -0.7, 1.2, -1.2]
const PATROL_SOFT_STUCK_SEC: float = 0.8
const PATROL_HARD_STUCK_SEC: float = 1.6
const CHASE_SOFT_STUCK_SEC: float = 0.8
const CHASE_HARD_STUCK_SEC: float = 1.4
const PATROL_UNSTUCK_STEP_OPTIONS := [16.0, 24.0, 32.0]
const NAV_REPATH_PATROL_SEC: float = 0.65
const NAV_REPATH_CHASE_SEC: float = 0.20
const NAV_REPATH_RETURN_SEC: float = 0.25
const NAV_POINT_REACHED_DISTANCE: float = 8.0
const SEPARATION_CRITICAL_DISTANCE: float = 12.0
const DETOUR_SCAN_ANGLES := [-1.8, -1.4, -1.0, -0.7, -0.45, 0.45, 0.7, 1.0, 1.4, 1.8]
const DETOUR_SCAN_DISTANCES := [48.0, 80.0, 120.0, 160.0]
const DETOUR_REACHED_DISTANCE: float = 10.0
const LOCAL_FALLBACK_GRID_STEP: float = 32.0
const LOCAL_FALLBACK_GRID_MARGIN: float = 128.0
const LOCAL_FALLBACK_GRID_MAX_CELLS: int = 36
const LOCAL_FALLBACK_REPATH_SEC: float = 0.45
const LOCAL_FALLBACK_POINT_REACHED_DISTANCE: float = 10.0
const LOCAL_FALLBACK_MAX_EXPANSIONS: int = 24
const LOCAL_FALLBACK_MARGIN_GROWTH_MULT: float = 4.0
const LOCAL_FALLBACK_MAX_STEP: float = 96.0

var behavior: int = Behavior.GUARD
var state: int = State.IDLE

var speed: float = MOVE_SPEED.MOB_BASE
var patrol_speed: float = MOVE_SPEED.MOB_PATROL
var aggro_radius: float = COMBAT_RANGES.AGGRO_RADIUS
var leash_distance: float = COMBAT_RANGES.LEASH_DISTANCE
var patrol_radius: float = COMBAT_RANGES.PATROL_RADIUS
var patrol_pause_seconds: float = 1.5

var home_position: Vector2 = Vector2.ZERO

var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _wait: float = 0.0
var _patrol_last_position: Vector2 = Vector2.ZERO
var _patrol_has_last_position: bool = false
var _patrol_stuck_time: float = 0.0
var _patrol_separation_refresh: float = 0.0
var _patrol_separation_vector: Vector2 = Vector2.ZERO
var _chase_last_position: Vector2 = Vector2.ZERO
var _chase_has_last_position: bool = false
var _chase_stuck_time: float = 0.0
var _activity_tier: int = 0
var _nav_path: Array[Vector2] = []
var _nav_path_index: int = 0
var _nav_repath_timer: float = 0.0
var _nav_allow_direct_fallback: bool = true
var _has_detour_point: bool = false
var _detour_point: Vector2 = Vector2.ZERO
var _fallback_path: Array[Vector2] = []
var _fallback_path_index: int = 0
var _fallback_repath_timer: float = 0.0

func set_activity_tier(value: int) -> void:
	_activity_tier = value

func reset_to_idle() -> void:
	state = State.IDLE
	_has_patrol_target = false
	_wait = 0.0
	_patrol_has_last_position = false
	_patrol_stuck_time = 0.0
	_patrol_separation_refresh = 0.0
	_patrol_separation_vector = Vector2.ZERO
	_chase_has_last_position = false
	_chase_stuck_time = 0.0
	_clear_nav_path()

func on_took_damage(attacker: Node2D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if state == State.RETURN:
		var dist_home: float = attacker.global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			state = State.CHASE
		return
	state = State.CHASE

func tick(delta: float, actor: CharacterBody2D, target: Node2D, combat: FactionNPCCombat, proactive: bool) -> void:
	_nav_repath_timer = max(0.0, _nav_repath_timer - delta)
	_fallback_repath_timer = max(0.0, _fallback_repath_timer - delta)
	var t_leash := Time.get_ticks_usec()
	var dist_home: float = actor.global_position.distance_to(home_position)
	if state == State.CHASE and dist_home > leash_distance:
		state = State.RETURN
		emit_signal("leash_return_started")
	FRAME_PROFILER.add_usec("npc.ai.leash_check", Time.get_ticks_usec() - t_leash)

	if state == State.RETURN:
		var t_return := Time.get_ticks_usec()
		_do_return(delta, actor)
		FRAME_PROFILER.add_usec("npc.ai.return", Time.get_ticks_usec() - t_return)
		return

	var t_proactive_gate := Time.get_ticks_usec()
	if proactive:
		if state != State.CHASE and target != null and is_instance_valid(target):
			var d: float = actor.global_position.distance_to(target.global_position)
			if d <= aggro_radius:
				state = State.CHASE
	FRAME_PROFILER.add_usec("npc.ai.proactive_gate", Time.get_ticks_usec() - t_proactive_gate)

	if state == State.CHASE:
		var t_chase := Time.get_ticks_usec()
		_do_chase(delta, actor, target, combat)
		FRAME_PROFILER.add_usec("npc.ai.chase", Time.get_ticks_usec() - t_chase)
		return

	var t_idle := Time.get_ticks_usec()
	_do_idle(delta, actor)
	FRAME_PROFILER.add_usec("npc.ai.idle", Time.get_ticks_usec() - t_idle)

func _do_idle(delta: float, actor: CharacterBody2D) -> void:
	if behavior == Behavior.PATROL:
		var t_idle_patrol := Time.get_ticks_usec()
		_do_patrol(delta, actor)
		FRAME_PROFILER.add_usec("npc.ai.idle_patrol", Time.get_ticks_usec() - t_idle_patrol)
	else:
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		return

func _pick_patrol_target() -> void:
	_has_patrol_target = true
	var a: float = randf() * TAU
	var r: float = lerp(max(10.0, patrol_radius * 0.3), patrol_radius, randf())
	_patrol_target = home_position + Vector2(cos(a), sin(a)) * r

func _do_patrol(delta: float, actor: CharacterBody2D) -> void:
	if _wait > 0.0:
		_wait -= delta
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		var t_patrol_wait_move := Time.get_ticks_usec()
		actor.move_and_slide()
		FRAME_PROFILER.add_usec("npc.ai.patrol_move", Time.get_ticks_usec() - t_patrol_wait_move)
		return

	if not _has_patrol_target:
		_pick_patrol_target()

	var d: float = actor.global_position.distance_to(_patrol_target)
	if d <= 6.0:
		_wait = patrol_pause_seconds
		_pick_patrol_target()
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		return

	if _patrol_has_last_position:
		var patrol_progress: float = actor.global_position.distance_to(_patrol_last_position)
		if patrol_progress < 0.5 and d > 12.0:
			_patrol_stuck_time += delta
			if _patrol_stuck_time >= PATROL_HARD_STUCK_SEC:
				_force_unstuck_position(actor)
				_pick_patrol_target()
				_patrol_stuck_time = 0.0
				_patrol_has_last_position = false
			elif _patrol_stuck_time >= PATROL_SOFT_STUCK_SEC:
				_pick_patrol_target()
				_patrol_stuck_time = PATROL_SOFT_STUCK_SEC
				_patrol_has_last_position = false
		else:
			_patrol_stuck_time = 0.0
	_patrol_last_position = actor.global_position
	_patrol_has_last_position = true

	var patrol_dir: Vector2 = _next_path_direction(actor, _patrol_target, NAV_REPATH_PATROL_SEC)
	var t_patrol_separation := Time.get_ticks_usec()
	var separation_dir: Vector2 = _get_patrol_separation_vector(delta, actor)
	FRAME_PROFILER.add_usec("npc.ai.patrol_separation", Time.get_ticks_usec() - t_patrol_separation)
	var final_dir: Vector2 = patrol_dir + separation_dir
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()
	else:
		final_dir = patrol_dir
	var t_patrol_steer := Time.get_ticks_usec()
	final_dir = _steer_around_obstacles(actor, final_dir)
	FRAME_PROFILER.add_usec("npc.ai.patrol_steer", Time.get_ticks_usec() - t_patrol_steer)
	if final_dir.length_squared() <= 0.0001:
		actor.velocity = Vector2.ZERO
		return
	else:
		actor.velocity = final_dir * patrol_speed
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, true)
	var t_patrol_move := Time.get_ticks_usec()
	actor.move_and_slide()
	FRAME_PROFILER.add_usec("npc.ai.patrol_move", Time.get_ticks_usec() - t_patrol_move)

func _get_patrol_separation_vector(delta: float, actor: CharacterBody2D) -> Vector2:
	_patrol_separation_refresh -= delta
	if _patrol_separation_refresh > 0.0:
		return _patrol_separation_vector
	_patrol_separation_refresh = PATROL_SEPARATION_REFRESH_SEC
	_patrol_separation_vector = _compute_patrol_separation(actor)
	return _patrol_separation_vector

func _compute_patrol_separation(actor: CharacterBody2D) -> Vector2:
	var cache := _get_proximity_cache(actor)
	if cache != null and cache.has_method("get_nearby_faction_units"):
		return _compute_patrol_separation_cached(actor, cache)
	if actor == null or not is_instance_valid(actor):
		return Vector2.ZERO
	var tree := actor.get_tree()
	if tree == null:
		return Vector2.ZERO
	var repel := Vector2.ZERO
	var nearby_count: int = 0
	for n in tree.get_nodes_in_group("faction_units"):
		if not (n is Node2D):
			continue
		var other := n as Node2D
		if other == actor or not is_instance_valid(other):
			continue
		if not _is_patrol_friendly(actor, other):
			continue
		var offset: Vector2 = actor.global_position - other.global_position
		var dist: float = offset.length()
		if dist <= 0.001 or dist >= PATROL_SEPARATION_DISTANCE:
			continue
		if dist < SEPARATION_CRITICAL_DISTANCE:
			repel += (offset / max(0.001, dist)) * 2.0
			nearby_count += 1
			continue
		var strength: float = (PATROL_SEPARATION_DISTANCE - dist) / PATROL_SEPARATION_DISTANCE
		repel += (offset / dist) * strength
		nearby_count += 1
		if nearby_count >= 6:
			break
	if repel.length_squared() <= 0.0001:
		return Vector2.ZERO
	if nearby_count > 3:
		repel *= 1.5
	return repel.normalized() * min(2.0, repel.length())

func _compute_patrol_separation_cached(actor: CharacterBody2D, cache: Node) -> Vector2:
	var nearby_v: Variant = cache.call("get_nearby_faction_units", actor, PATROL_SEPARATION_DISTANCE, "faction_units")
	if not (nearby_v is Array):
		return Vector2.ZERO
	var nearby: Array = nearby_v as Array
	var repel := Vector2.ZERO
	var nearby_count: int = 0
	for other in nearby:
		if other == actor or not is_instance_valid(other):
			continue
		if not _is_patrol_friendly(actor, other):
			continue
		var offset: Vector2 = actor.global_position - other.global_position
		var dist: float = offset.length()
		if dist <= 0.001 or dist >= PATROL_SEPARATION_DISTANCE:
			continue
		if dist < SEPARATION_CRITICAL_DISTANCE:
			repel += (offset / max(0.001, dist)) * 2.0
			nearby_count += 1
			continue
		var strength: float = (PATROL_SEPARATION_DISTANCE - dist) / PATROL_SEPARATION_DISTANCE
		repel += (offset / dist) * strength
		nearby_count += 1
		if nearby_count >= 6:
			break
	if repel.length_squared() <= 0.0001:
		return Vector2.ZERO
	if nearby_count > 3:
		repel *= 1.5
	return repel.normalized() * min(2.0, repel.length())

func _get_proximity_cache(actor: CharacterBody2D) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	var root := actor.get_tree().root
	if root == null:
		return null
	return root.get_node_or_null("MobProximityCache")

func _should_play_animation() -> bool:
	return _activity_tier == EntityActivityManager.ActivityTier.FULL

func _build_path(actor: CharacterBody2D, destination: Vector2, repath_sec: float) -> void:
	if _nav_repath_timer > 0.0 and _nav_path_index < _nav_path.size():
		return
	_nav_repath_timer = repath_sec
	if actor == null or not is_instance_valid(actor):
		_clear_nav_path()
		return
	var world := actor.get_world_2d()
	if world == null:
		_nav_path = [destination]
		_nav_path_index = 0
		_nav_allow_direct_fallback = true
		return
	var map := world.navigation_map
	var points := NavPathManager.request_path(map, actor.global_position, destination, true)
	_nav_path.clear()
	for p in points:
		if p is Vector2:
			_nav_path.append(p as Vector2)
	_nav_allow_direct_fallback = _nav_path.is_empty()
	if not _nav_path.is_empty() and _nav_path[_nav_path.size() - 1].distance_to(destination) > NAV_POINT_REACHED_DISTANCE:
		_nav_path.append(destination)
	_nav_path_index = 0
	_advance_path_index(actor.global_position)

func _advance_path_index(current_pos: Vector2) -> void:
	while _nav_path_index < _nav_path.size():
		if current_pos.distance_to(_nav_path[_nav_path_index]) > NAV_POINT_REACHED_DISTANCE:
			return
		_nav_path_index += 1

func _next_path_direction(actor: CharacterBody2D, destination: Vector2, repath_sec: float) -> Vector2:
	_build_path(actor, destination, repath_sec)
	if _nav_path_index >= _nav_path.size():
		if _nav_allow_direct_fallback:
			return _next_fallback_direction(actor, destination)
		return Vector2.ZERO
	_has_detour_point = false
	var waypoint := _nav_path[_nav_path_index]
	var to_waypoint := waypoint - actor.global_position
	if to_waypoint.length_squared() <= 0.0001:
		_nav_path_index += 1
		return _next_path_direction(actor, destination, repath_sec)
	return to_waypoint.normalized()

func _clear_nav_path() -> void:
	_nav_path.clear()
	_nav_path_index = 0
	_nav_repath_timer = 0.0
	_nav_allow_direct_fallback = true
	_has_detour_point = false
	_clear_fallback_path()

func _next_fallback_direction(actor: CharacterBody2D, destination: Vector2) -> Vector2:
	if actor == null or not is_instance_valid(actor):
		return Vector2.ZERO
	if not _is_segment_blocked(actor, actor.global_position, destination):
		_clear_fallback_path()
		var to_direct := destination - actor.global_position
		return to_direct.normalized() if to_direct.length_squared() > 0.0001 else Vector2.ZERO
	var fallback_dir := _follow_fallback_path(actor)
	if fallback_dir != Vector2.ZERO:
		return fallback_dir
	if _fallback_repath_timer <= 0.0:
		_build_local_fallback_path(actor, destination)
	_fallback_repath_timer = LOCAL_FALLBACK_REPATH_SEC if not _fallback_path.is_empty() else 0.05
	fallback_dir = _follow_fallback_path(actor)
	if fallback_dir != Vector2.ZERO:
		return fallback_dir
	var to_direct := destination - actor.global_position
	return _steer_around_obstacles(actor, to_direct.normalized() if to_direct.length_squared() > 0.0001 else Vector2.ZERO)

func _clear_fallback_path() -> void:
	_fallback_path.clear()
	_fallback_path_index = 0
	_fallback_repath_timer = 0.0

func _follow_fallback_path(actor: CharacterBody2D) -> Vector2:
	while _fallback_path_index < _fallback_path.size():
		var waypoint := _fallback_path[_fallback_path_index]
		if _is_segment_blocked(actor, actor.global_position, waypoint):
			_clear_fallback_path()
			return Vector2.ZERO
		if actor.global_position.distance_to(waypoint) > LOCAL_FALLBACK_POINT_REACHED_DISTANCE:
			var to_waypoint := waypoint - actor.global_position
			return _steer_around_obstacles(actor, to_waypoint.normalized() if to_waypoint.length_squared() > 0.0001 else Vector2.ZERO)
		_fallback_path_index += 1
	return Vector2.ZERO

func _build_local_fallback_path(actor: CharacterBody2D, destination: Vector2) -> void:
	_fallback_path.clear()
	_fallback_path_index = 0
	var step: float = LOCAL_FALLBACK_GRID_STEP
	var margin: float = LOCAL_FALLBACK_GRID_MARGIN
	var attempts: int = 0
	while attempts < LOCAL_FALLBACK_MAX_EXPANSIONS:
		if _try_build_local_fallback_path(actor, destination, step, margin):
			return
		margin += step * LOCAL_FALLBACK_MARGIN_GROWTH_MULT
		if attempts % 2 == 1:
			step = minf(LOCAL_FALLBACK_MAX_STEP, step + 8.0)
		attempts += 1

func _try_build_local_fallback_path(actor: CharacterBody2D, destination: Vector2, step: float, margin: float) -> bool:
	var start: Vector2 = actor.global_position
	var min_x: float = minf(start.x, destination.x) - margin
	var min_y: float = minf(start.y, destination.y) - margin
	var max_x: float = maxf(start.x, destination.x) + margin
	var max_y: float = maxf(start.y, destination.y) + margin
	var max_span := float(LOCAL_FALLBACK_GRID_MAX_CELLS - 1) * step
	if max_x - min_x > max_span:
		var cx := (start.x + destination.x) * 0.5
		min_x = cx - max_span * 0.5
		max_x = cx + max_span * 0.5
	if max_y - min_y > max_span:
		var cy := (start.y + destination.y) * 0.5
		min_y = cy - max_span * 0.5
		max_y = cy + max_span * 0.5
	var cols := maxi(2, int(ceil((max_x - min_x) / step)) + 1)
	var rows := maxi(2, int(ceil((max_y - min_y) / step)) + 1)
	var astar := AStar2D.new()
	for gy in range(rows):
		for gx in range(cols):
			var point := Vector2(min_x + float(gx) * step, min_y + float(gy) * step)
			if not _is_probe_walkable(actor, point):
				continue
			var id := gy * cols + gx
			astar.add_point(id, point)
	for gy in range(rows):
		for gx in range(cols):
			var id := gy * cols + gx
			if not astar.has_point(id):
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := gx + ox
					var ny := gy + oy
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
						continue
					var nid := ny * cols + nx
					if not astar.has_point(nid):
						continue
					if not _is_probe_segment_walkable(actor, astar.get_point_position(id), astar.get_point_position(nid)):
						continue
					if not astar.are_points_connected(id, nid):
						astar.connect_points(id, nid, false)
	if astar.get_point_count() <= 1:
		return false
	var start_id := astar.get_closest_point(start)
	var goal_id := astar.get_closest_point(destination)
	if start_id < 0 or goal_id < 0:
		return false
	var id_path := astar.get_id_path(start_id, goal_id)
	if id_path.is_empty():
		return false
	for id_v in id_path:
		var pid := int(id_v)
		if not astar.has_point(pid):
			continue
		var p := astar.get_point_position(pid)
		if p.distance_to(start) <= LOCAL_FALLBACK_POINT_REACHED_DISTANCE:
			continue
		_fallback_path.append(p)
	if _fallback_path.is_empty():
		return false
	if _fallback_path[_fallback_path.size() - 1].distance_to(destination) > LOCAL_FALLBACK_POINT_REACHED_DISTANCE:
		_fallback_path.append(destination)
	return true

func _is_probe_walkable(actor: CharacterBody2D, point: Vector2) -> bool:
	var world := actor.get_world_2d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var probe := CircleShape2D.new()
	probe.radius = max(6.0, OBSTACLE_AVOID_LOOKAHEAD * 0.6)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, point)
	query.exclude = [actor.get_rid()]
	query.collision_mask = actor.collision_mask
	return space.intersect_shape(query, 1).is_empty()

func _is_probe_segment_walkable(actor: CharacterBody2D, from_pos: Vector2, to_pos: Vector2) -> bool:
	var world := actor.get_world_2d()
	if world == null:
		return false
	var space := world.direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.exclude = [actor.get_rid()]
	query.collision_mask = actor.collision_mask
	return space.intersect_ray(query).is_empty()

func _pick_detour_point(actor: CharacterBody2D, destination: Vector2) -> Vector2:
	var base := (destination - actor.global_position).normalized()
	if base.length_squared() <= 0.0001:
		return Vector2.ZERO
	var best: Vector2 = Vector2.ZERO
	var best_score: float = INF
	for distance_v in DETOUR_SCAN_DISTANCES:
		var distance := float(distance_v)
		for angle_v in DETOUR_SCAN_ANGLES:
			var dir := base.rotated(float(angle_v))
			var candidate := actor.global_position + dir * distance
			if _is_segment_blocked(actor, actor.global_position, candidate):
				continue
			var score := candidate.distance_to(destination) + actor.global_position.distance_to(candidate) * 0.2
			if score < best_score:
				best_score = score
				best = candidate
	return best

func _is_segment_blocked(actor: CharacterBody2D, from_pos: Vector2, to_pos: Vector2) -> bool:
	var segment := to_pos - from_pos
	var length := segment.length()
	if length <= 0.001:
		return false
	var dir := segment / length
	var step := OBSTACLE_AVOID_LOOKAHEAD
	var probe := step
	while probe < length:
		if actor.test_move(actor.global_transform, dir * probe):
			return true
		probe += step
	return actor.test_move(actor.global_transform, segment)

func _is_patrol_friendly(actor: CharacterBody2D, other: Node2D) -> bool:
	if actor.has_method("get_faction_id") and other.has_method("get_faction_id"):
		return String(actor.call("get_faction_id")) == String(other.call("get_faction_id"))
	return true

func _steer_around_obstacles(actor: CharacterBody2D, desired_dir: Vector2) -> Vector2:
	if actor == null or not is_instance_valid(actor):
		return Vector2.ZERO
	if desired_dir.length_squared() <= 0.0001:
		return Vector2.ZERO
	var base_dir: Vector2 = desired_dir.normalized()
	if not _is_motion_blocked(actor, base_dir):
		return base_dir
	for angle in OBSTACLE_AVOID_ANGLES:
		var candidate := base_dir.rotated(float(angle))
		if not _is_motion_blocked(actor, candidate):
			return candidate
	return Vector2.ZERO

func _is_motion_blocked(actor: CharacterBody2D, direction: Vector2) -> bool:
	if direction.length_squared() <= 0.0001:
		return false
	var motion: Vector2 = direction.normalized() * OBSTACLE_AVOID_LOOKAHEAD
	return actor.test_move(actor.global_transform, motion)

func _force_unstuck_position(actor: CharacterBody2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	for step_v in PATROL_UNSTUCK_STEP_OPTIONS:
		var step_len := float(step_v)
		for angle in OBSTACLE_AVOID_ANGLES:
			var dir := Vector2.RIGHT.rotated(float(angle))
			var motion := dir * step_len
			if actor.test_move(actor.global_transform, motion):
				continue
			actor.global_position += motion
			return

func _do_chase(delta: float, actor: CharacterBody2D, target: Node2D, combat: FactionNPCCombat) -> void:
	if target == null or not is_instance_valid(target):
		state = State.RETURN
		emit_signal("leash_return_started")
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		_chase_has_last_position = false
		_chase_stuck_time = 0.0
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	var to: Vector2 = target.global_position - actor.global_position
	var dist: float = to.length()
	var stop: float = max(0.0, combat.stop_distance())
	var spacing_distance: float = max(0.0, stop - COMBAT_SPACING_BUFFER)

	if dist > stop:
		var chase_dir := _next_path_direction(actor, target.global_position, NAV_REPATH_CHASE_SEC)
		actor.velocity = chase_dir * speed if chase_dir.length_squared() > 0.0001 else Vector2.ZERO
	elif dist < spacing_distance:
		_clear_nav_path()
		if _should_backstep_from_target(target):
			var backstep_dir := _steer_around_obstacles(actor, (-to).normalized())
			actor.velocity = backstep_dir * (speed * 0.5) if backstep_dir.length_squared() > 0.0001 else Vector2.ZERO
		else:
			actor.velocity = Vector2.ZERO
	else:
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, false)
	actor.move_and_slide()
	_track_chase_stuck(actor, dist, stop, delta)

func _should_backstep_from_target(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_in_group("player"):
		return true
	return false

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	var to: Vector2 = home_position - actor.global_position
	var dist_home: float = to.length()
	if dist_home <= 6.0:
		state = State.IDLE
		_clear_nav_path()
		_has_patrol_target = false
		_wait = patrol_pause_seconds
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		_chase_has_last_position = false
		_chase_stuck_time = 0.0
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	var return_dir := _next_path_direction(actor, home_position, NAV_REPATH_RETURN_SEC)
	actor.velocity = return_dir * speed if return_dir.length_squared() > 0.0001 else Vector2.ZERO
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, false)
	actor.move_and_slide()
	_track_chase_stuck(actor, dist_home, 6.0, _delta)

func _track_chase_stuck(actor: CharacterBody2D, distance_to_goal: float, stop_distance: float, delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.velocity.length_squared() <= 0.001:
		_chase_has_last_position = false
		_chase_stuck_time = 0.0
		return
	if distance_to_goal <= stop_distance + 2.0:
		_chase_has_last_position = false
		_chase_stuck_time = 0.0
		return
	if _chase_has_last_position:
		var progress := actor.global_position.distance_to(_chase_last_position)
		if progress < 0.45:
			_chase_stuck_time += delta
			if _chase_stuck_time >= CHASE_HARD_STUCK_SEC:
				_force_unstuck_position(actor)
				_chase_stuck_time = 0.0
				_chase_has_last_position = false
			elif _chase_stuck_time >= CHASE_SOFT_STUCK_SEC:
				_chase_stuck_time = CHASE_SOFT_STUCK_SEC
		else:
			_chase_stuck_time = 0.0
	_chase_last_position = actor.global_position
	_chase_has_last_position = true

extends Node
class_name NormalAggresiveMobAI

signal leash_return_started
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const PROFILER_UTILS := preload("res://core/debug/profiler_utils.gd")
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
const IDLE_STAGGER_DIVISOR: int = 3
const NAV_REPATH_PATROL_SEC: float = 0.65
const NAV_REPATH_CHASE_SEC: float = 0.20
const NAV_REPATH_RETURN_SEC: float = 0.25
const NAV_POINT_REACHED_DISTANCE: float = 8.0

enum AIState { IDLE, CHASE, RETURN }
enum Behavior { GUARD, PATROL }

var behavior: int = Behavior.GUARD
var speed: float = MOVE_SPEED.MOB_BASE
var patrol_speed: float = MOVE_SPEED.MOB_PATROL
var aggro_radius: float = COMBAT_RANGES.AGGRO_RADIUS
var leash_distance: float = COMBAT_RANGES.LEASH_DISTANCE
var patrol_radius: float = COMBAT_RANGES.PATROL_RADIUS
var patrol_pause_seconds: float = 1.5

var home_position: Vector2 = Vector2.ZERO

var _state: int = AIState.IDLE
var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0
var _patrol_last_position: Vector2 = Vector2.ZERO
var _patrol_has_last_position: bool = false
var _patrol_stuck_time: float = 0.0
var _patrol_separation_refresh: float = 0.0
var _patrol_separation_vector: Vector2 = Vector2.ZERO
var _idle_tick_counter: int = 0
var _idle_stagger_offset: int = -1
var _current_lod_level: int = 0
var _chase_last_position: Vector2 = Vector2.ZERO
var _chase_has_last_position: bool = false
var _chase_stuck_time: float = 0.0
var _activity_tier: int = 0
var _nav_path: Array[Vector2] = []
var _nav_path_index: int = 0
var _nav_repath_timer: float = 0.0
var _nav_allow_direct_fallback: bool = true

func set_activity_tier(value: int) -> void:
	_activity_tier = value

func reset_to_idle() -> void:
	_state = AIState.IDLE
	_has_patrol_target = false
	_patrol_wait = 0.0
	_patrol_has_last_position = false
	_patrol_stuck_time = 0.0
	_patrol_separation_refresh = 0.0
	_patrol_separation_vector = Vector2.ZERO
	_chase_has_last_position = false
	_chase_stuck_time = 0.0
	_clear_nav_path()

func force_return() -> void:
	_state = AIState.RETURN
	emit_signal("leash_return_started")

func is_returning() -> bool:
	return _state == AIState.RETURN

func tick(delta: float, actor: CharacterBody2D, target: Node2D, combat: NormalAggresiveMobCombat) -> void:
	var t_tick_total := Time.get_ticks_usec()
	_nav_repath_timer = max(0.0, _nav_repath_timer - delta)
	_current_lod_level = _resolve_lod_level(actor, target)
	# выключение CHASE по leash_distance
	var t_leash := Time.get_ticks_usec()
	var dist_to_home: float = actor.global_position.distance_to(home_position)
	if _state == AIState.CHASE and dist_to_home > leash_distance:
		_state = AIState.RETURN
		emit_signal("leash_return_started")
	FRAME_PROFILER.add_usec("mob_aggressive.ai.leash_check", Time.get_ticks_usec() - t_leash)

	# RETURN
	if _state == AIState.RETURN:
		var t_return := Time.get_ticks_usec()
		_do_return(delta, actor)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.return", Time.get_ticks_usec() - t_return)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.tick_total", Time.get_ticks_usec() - t_tick_total)
		return

	# включаем CHASE только если цель вошла в агро-радиус
	var t_aggro_gate := Time.get_ticks_usec()
	if _state != AIState.CHASE and target != null and is_instance_valid(target):
		var dist_to_target: float = actor.global_position.distance_to(target.global_position)
		if dist_to_target <= aggro_radius:
			_state = AIState.CHASE
	FRAME_PROFILER.add_usec("mob_aggressive.ai.aggro_gate", Time.get_ticks_usec() - t_aggro_gate)

	# CHASE
	if _state == AIState.CHASE:
		var t_chase := Time.get_ticks_usec()
		_do_chase(delta, actor, target, combat)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.chase", Time.get_ticks_usec() - t_chase)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.tick_total", Time.get_ticks_usec() - t_tick_total)
		return

	# IDLE
	if not _should_run_idle_patrol_tick(actor):
		_idle_tick_counter += 1
		_idle_noop(actor)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.tick_total", Time.get_ticks_usec() - t_tick_total)
		return
	_idle_tick_counter += 1
	var t_idle := Time.get_ticks_usec()
	_do_idle(delta, actor)
	FRAME_PROFILER.add_usec("mob_aggressive.ai.idle", Time.get_ticks_usec() - t_idle)
	FRAME_PROFILER.add_usec("mob_aggressive.ai.tick_total", Time.get_ticks_usec() - t_tick_total)

func on_took_damage(attacker: Node2D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if _state == AIState.RETURN:
		var dist_home: float = attacker.global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_state = AIState.CHASE
		return
	_state = AIState.CHASE

func _do_idle(delta: float, actor: CharacterBody2D) -> void:
	if behavior == Behavior.PATROL:
		var t_idle_patrol := Time.get_ticks_usec()
		_do_patrol(delta, actor)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.idle_patrol", Time.get_ticks_usec() - t_idle_patrol)
	else:
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)

func _pick_new_patrol_target() -> void:
	_has_patrol_target = true
	var min_r: float = max(10.0, patrol_radius * 0.30)
	var angle: float = randf() * TAU
	var r: float = lerp(min_r, patrol_radius, randf())
	_patrol_target = home_position + Vector2(cos(angle), sin(angle)) * r

func _do_patrol(delta: float, actor: CharacterBody2D) -> void:
	if _current_lod_level >= 2:
		actor.velocity = Vector2.ZERO
		_clear_nav_path()
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		return

	if not _has_patrol_target:
		_pick_new_patrol_target()

	var d: float = actor.global_position.distance_to(_patrol_target)
	if d <= 6.0:
		_patrol_wait = patrol_pause_seconds
		_pick_new_patrol_target()
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		return

	if _patrol_has_last_position:
		var patrol_progress: float = actor.global_position.distance_to(_patrol_last_position)
		if patrol_progress < 0.5 and d > 12.0:
			_patrol_stuck_time += delta
			if _patrol_stuck_time >= PATROL_HARD_STUCK_SEC:
				_force_unstuck_position(actor)
				_pick_new_patrol_target()
				_patrol_stuck_time = 0.0
				_patrol_has_last_position = false
			elif _patrol_stuck_time >= PATROL_SOFT_STUCK_SEC:
				_pick_new_patrol_target()
				_patrol_stuck_time = PATROL_SOFT_STUCK_SEC
				_patrol_has_last_position = false
		else:
			_patrol_stuck_time = 0.0
	_patrol_last_position = actor.global_position
	_patrol_has_last_position = true

	var patrol_dir: Vector2 = _next_path_direction(actor, _patrol_target, NAV_REPATH_PATROL_SEC)
	var separation_dir: Vector2 = Vector2.ZERO
	if _current_lod_level == 0:
		var t_patrol_separation := Time.get_ticks_usec()
		separation_dir = _get_patrol_separation_vector(delta, actor)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.patrol_separation", Time.get_ticks_usec() - t_patrol_separation)
	var final_dir: Vector2 = patrol_dir + separation_dir
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()
	else:
		final_dir = patrol_dir
	if _current_lod_level == 0:
		var t_patrol_steer := Time.get_ticks_usec()
		final_dir = _steer_around_obstacles(actor, final_dir)
		FRAME_PROFILER.add_usec("mob_aggressive.ai.patrol_steer", Time.get_ticks_usec() - t_patrol_steer)
	if final_dir.length_squared() <= 0.0001:
		actor.velocity = Vector2.ZERO
		return
	else:
		actor.velocity = final_dir * patrol_speed
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, true)
	var t_patrol_move := Time.get_ticks_usec()
	actor.move_and_slide()
	FRAME_PROFILER.add_usec("mob_aggressive.ai.patrol_move", Time.get_ticks_usec() - t_patrol_move)

func _get_patrol_separation_vector(delta: float, actor: CharacterBody2D) -> Vector2:
	_patrol_separation_refresh -= delta
	if _patrol_separation_refresh > 0.0:
		return _patrol_separation_vector
	_patrol_separation_refresh = PATROL_SEPARATION_REFRESH_SEC
	_patrol_separation_vector = _compute_patrol_separation(actor)
	return _patrol_separation_vector

func _compute_patrol_separation(actor: CharacterBody2D) -> Vector2:
	var cache := _get_proximity_cache(actor)
	if cache != null and cache.has_method("get_nearby_mobs"):
		return _compute_patrol_separation_cached(actor, cache)
	return _compute_patrol_separation_legacy(actor)


func _compute_patrol_separation_cached(actor: CharacterBody2D, cache: Node) -> Vector2:
	var nearby_v: Variant
	if cache.has_method("get_nearby_faction_units"):
		nearby_v = cache.call("get_nearby_faction_units", actor, PATROL_SEPARATION_DISTANCE, "faction_units")
	else:
		nearby_v = cache.call("get_nearby_mobs", actor, PATROL_SEPARATION_DISTANCE, "mobs")
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
		var strength: float = (PATROL_SEPARATION_DISTANCE - dist) / PATROL_SEPARATION_DISTANCE
		repel += (offset / dist) * strength
		nearby_count += 1
		if nearby_count >= 6:
			break
	if repel.length_squared() <= 0.0001:
		return Vector2.ZERO
	return repel.normalized() * min(1.0, repel.length())


func _compute_patrol_separation_legacy(actor: CharacterBody2D) -> Vector2:
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
		var strength: float = (PATROL_SEPARATION_DISTANCE - dist) / PATROL_SEPARATION_DISTANCE
		repel += (offset / dist) * strength
		nearby_count += 1
		if nearby_count >= 6:
			break
	if repel.length_squared() <= 0.0001:
		return Vector2.ZERO
	return repel.normalized() * min(1.0, repel.length())


func _get_proximity_cache(actor: CharacterBody2D) -> Node:
	if actor == null or not is_instance_valid(actor):
		return null
	var root := actor.get_tree().root
	if root == null:
		return null
	return root.get_node_or_null("MobProximityCache")


func _resolve_lod_level(actor: CharacterBody2D, target: Node2D) -> int:
	if _activity_tier == EntityActivityManager.ActivityTier.FULL:
		return 0
	if _activity_tier == EntityActivityManager.ActivityTier.SIM:
		return 1
	return 2

func _should_play_animation() -> bool:
	return _activity_tier == EntityActivityManager.ActivityTier.FULL

func _build_path(actor: CharacterBody2D, destination: Vector2, repath_sec: float) -> void:
	if _nav_repath_timer > 0.0 and _nav_path_index < _nav_path.size():
		return
	_nav_repath_timer = repath_sec
	if actor == null or not is_instance_valid(actor):
		_nav_path.clear()
		_nav_path_index = 0
		_nav_allow_direct_fallback = true
		return
	var world := actor.get_world_2d()
	if world == null:
		_nav_path = [destination]
		_nav_path_index = 0
		_nav_allow_direct_fallback = true
		return
	var map := world.navigation_map
	if not NavigationServer2D.map_is_active(map):
		_nav_path = [destination]
		_nav_path_index = 0
		_nav_allow_direct_fallback = true
		return
	if NavigationServer2D.map_get_iteration_id(map) <= 0:
		_nav_path.clear()
		_nav_path_index = 0
		_nav_allow_direct_fallback = true
		return
	var start := NavigationServer2D.map_get_closest_point(map, actor.global_position)
	var goal := NavigationServer2D.map_get_closest_point(map, destination)
	var points := NavigationServer2D.map_get_path(map, start, goal, true)
	_nav_allow_direct_fallback = false
	_nav_path.clear()
	for p in points:
		if p is Vector2:
			_nav_path.append(p as Vector2)
	if not _nav_path.is_empty() and goal.distance_to(destination) > NAV_POINT_REACHED_DISTANCE:
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
		var to_direct := destination - actor.global_position
		if _nav_allow_direct_fallback:
			var direct_dir := to_direct.normalized() if to_direct.length_squared() > 0.0001 else Vector2.ZERO
			return _steer_around_obstacles(actor, direct_dir)
		return Vector2.ZERO
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

func _should_run_idle_patrol_tick(actor: CharacterBody2D) -> bool:
	if _state != AIState.IDLE:
		return true
	if behavior != Behavior.PATROL:
		return true
	# Keep nearby/on-camera mobs visually smooth; stagger only at minimal LOD.
	if _current_lod_level <= 1:
		return true
	if _idle_stagger_offset < 0:
		_idle_stagger_offset = int(abs(actor.get_instance_id())) % IDLE_STAGGER_DIVISOR
	return (_idle_tick_counter % IDLE_STAGGER_DIVISOR) == _idle_stagger_offset


func _idle_noop(actor: CharacterBody2D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.velocity.length_squared() > 0.0001:
		actor.velocity = Vector2.ZERO
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)

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
	PROFILER_UTILS.track_count("mob_aggressive.ai.obstacle_checks")
	if not _is_motion_blocked(actor, base_dir):
		return base_dir
	for angle in OBSTACLE_AVOID_ANGLES:
		var candidate := base_dir.rotated(float(angle))
		PROFILER_UTILS.track_count("mob_aggressive.ai.obstacle_checks")
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

func _do_chase(delta: float, actor: CharacterBody2D, target: Node2D, combat: NormalAggresiveMobCombat) -> void:
	if target == null or not is_instance_valid(target):
		_state = AIState.IDLE
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

	var to_target: Vector2 = target.global_position - actor.global_position
	var dist: float = to_target.length()

	var stop_distance: float = max(0.0, combat.get_stop_distance())
	var spacing_distance: float = max(0.0, stop_distance - COMBAT_SPACING_BUFFER)
	if dist > stop_distance:
		var chase_dir := _next_path_direction(actor, target.global_position, NAV_REPATH_CHASE_SEC)
		actor.velocity = chase_dir * speed if chase_dir.length_squared() > 0.0001 else Vector2.ZERO
	elif dist < spacing_distance:
		_clear_nav_path()
		var backstep_dir := _steer_around_obstacles(actor, (-to_target).normalized())
		actor.velocity = backstep_dir * (speed * 0.5) if backstep_dir.length_squared() > 0.0001 else Vector2.ZERO
	else:
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, false)
	actor.move_and_slide()
	_track_chase_stuck(delta, actor, dist, stop_distance)

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	var to_home: Vector2 = home_position - actor.global_position
	var dist: float = to_home.length()

	if dist <= 6.0:
		_state = AIState.IDLE
		_clear_nav_path()
		_has_patrol_target = false
		_patrol_wait = patrol_pause_seconds
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
	_track_chase_stuck(_delta, actor, dist, 6.0)

func _track_chase_stuck(delta: float, actor: CharacterBody2D, distance_to_goal: float, stop_distance: float) -> void:
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

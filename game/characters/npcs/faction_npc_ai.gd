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
const PATROL_SOFT_STUCK_SEC: float = 0.8
const PATROL_HARD_STUCK_SEC: float = 1.6
const NAV_REPATH_PATROL_SEC: float = 0.65
const NAV_REPATH_CHASE_SEC: float = 0.20
const NAV_REPATH_RETURN_SEC: float = 0.25
const NAV_POINT_REACHED_DISTANCE: float = 12.0
const NAV_MOVE_EPSILON: float = 0.05
const NAV_TARGET_UPDATE_DISTANCE: float = 6.0
const SEPARATION_CRITICAL_DISTANCE: float = 12.0

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
var _nav_agent: NavigationAgent2D = null
var _nav_target: Vector2 = Vector2.INF
var _has_detour_point: bool = false
var _detour_point: Vector2 = Vector2.ZERO

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
	var final_dir: Vector2 = patrol_dir
	if final_dir.length_squared() <= 0.0001:
		actor.velocity = Vector2.ZERO
		if _should_play_animation() and actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		return
	else:
		actor.velocity = final_dir * patrol_speed
	var t_patrol_move := Time.get_ticks_usec()
	_move_with_animation(actor, true)
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
	var agent := _ensure_nav_agent(actor)
	if agent == null:
		return
	var should_update: bool = _nav_repath_timer <= 0.0
	if _nav_target == Vector2.INF or _nav_target.distance_to(destination) > NAV_TARGET_UPDATE_DISTANCE:
		should_update = true
	elif agent.is_navigation_finished() and actor.global_position.distance_to(destination) > NAV_POINT_REACHED_DISTANCE:
		should_update = true
	if not should_update:
		return
	_nav_repath_timer = repath_sec
	_nav_target = destination
	agent.target_position = destination

func _advance_path_index(current_pos: Vector2) -> void:
	while _nav_path_index < _nav_path.size():
		var waypoint := _nav_path[_nav_path_index]
		if current_pos.distance_to(waypoint) <= NAV_POINT_REACHED_DISTANCE:
			_nav_path_index += 1
			continue
		if _nav_path_index + 1 < _nav_path.size():
			var next_waypoint := _nav_path[_nav_path_index + 1]
			var segment := next_waypoint - waypoint
			if segment.length_squared() > 0.0001:
				var passed: bool = (current_pos - waypoint).dot(segment) > 0.0
				if passed and current_pos.distance_to(next_waypoint) < current_pos.distance_to(waypoint):
					_nav_path_index += 1
					continue
		return

func _next_path_direction(actor: CharacterBody2D, destination: Vector2, repath_sec: float) -> Vector2:
	_build_path(actor, destination, repath_sec)
	var agent := _ensure_nav_agent(actor)
	if agent == null:
		return Vector2.ZERO
	if agent.is_navigation_finished():
		if actor.global_position.distance_to(destination) > NAV_POINT_REACHED_DISTANCE:
			_nav_repath_timer = 0.0
			_build_path(actor, destination, repath_sec)
			if not agent.is_navigation_finished():
				var retry_waypoint := agent.get_next_path_position()
				var retry_vec := retry_waypoint - actor.global_position
				return retry_vec.normalized() if retry_vec.length_squared() > 0.0001 else Vector2.ZERO
		return Vector2.ZERO
	var waypoint := agent.get_next_path_position()
	var to_waypoint := waypoint - actor.global_position
	if to_waypoint.length_squared() <= 0.0001:
		return Vector2.ZERO
	return to_waypoint.normalized()

func _clear_nav_path() -> void:
	_nav_path.clear()
	_nav_path_index = 0
	_nav_repath_timer = 0.0
	_nav_target = Vector2.INF
	_has_detour_point = false

func _ensure_nav_agent(actor: CharacterBody2D) -> NavigationAgent2D:
	if actor == null or not is_instance_valid(actor):
		return null
	if _nav_agent != null and is_instance_valid(_nav_agent):
		return _nav_agent
	_nav_agent = actor.get_node_or_null("NavAgent") as NavigationAgent2D
	if _nav_agent == null:
		return null
	_nav_agent.path_desired_distance = 8.0
	_nav_agent.target_desired_distance = 4.0
	_nav_agent.avoidance_enabled = false
	var world := actor.get_world_2d()
	if world != null:
		_nav_agent.set_navigation_map(world.navigation_map)
	return _nav_agent

func _is_patrol_friendly(actor: CharacterBody2D, other: Node2D) -> bool:
	if actor.has_method("get_faction_id") and other.has_method("get_faction_id"):
		return String(actor.call("get_faction_id")) == String(other.call("get_faction_id"))
	return true

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
		actor.velocity = Vector2.ZERO
	else:
		_clear_nav_path()
		actor.velocity = Vector2.ZERO
	_move_with_animation(actor, false)
	_chase_has_last_position = false
	_chase_stuck_time = 0.0

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
	_move_with_animation(actor, false)
	_chase_has_last_position = false
	_chase_stuck_time = 0.0

func _move_with_animation(actor: CharacterBody2D, moving_animation: bool) -> bool:
	var before := actor.global_position
	actor.move_and_slide()
	var moved: bool = actor.global_position.distance_to(before) > NAV_MOVE_EPSILON
	if not moved:
		actor.velocity = Vector2.ZERO
	if _should_play_animation() and actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity if moved else Vector2.ZERO, moving_animation and moved)
	return moved

extends Node
class_name NormalNeutralMobAI

signal leash_return_started
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const FRAME_PROFILER := preload("res://core/debug/frame_profiler.gd")
const COMBAT_SPACING_BUFFER: float = 32.0
const PATROL_SEPARATION_DISTANCE: float = 28.0
const PATROL_SEPARATION_REFRESH_SEC: float = 0.15
const OBSTACLE_AVOID_LOOKAHEAD: float = 18.0
const OBSTACLE_AVOID_ANGLES := [0.35, -0.35, 0.7, -0.7, 1.2, -1.2]
const PATROL_SOFT_STUCK_SEC: float = 0.8
const PATROL_HARD_STUCK_SEC: float = 1.6
const PATROL_UNSTUCK_STEP_OPTIONS := [16.0, 24.0, 32.0]

enum AIState { IDLE, CHASE, RETURN }
enum Behavior { GUARD, PATROL }

var behavior: int = Behavior.GUARD
var speed: float = MOVE_SPEED.MOB_BASE
var patrol_speed: float = MOVE_SPEED.MOB_PATROL
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

func reset_to_idle() -> void:
	_state = AIState.IDLE
	_has_patrol_target = false
	_patrol_wait = 0.0
	_patrol_has_last_position = false
	_patrol_stuck_time = 0.0
	_patrol_separation_refresh = 0.0
	_patrol_separation_vector = Vector2.ZERO

func is_chasing() -> bool:
	return _state == AIState.CHASE

func is_returning() -> bool:
	return _state == AIState.RETURN

# aggressive = true только если моб «разозлён» (его ударили)
func tick(delta: float, actor: CharacterBody2D, target: Node2D, combat: NormalNeutralMobCombat, aggressive: bool) -> void:
	# нейтрал не агрессивен → живёт как guard/patrol, но если RETURN — возвращается домой
	if not aggressive:
		if _state == AIState.RETURN:
			var t_passive_return := Time.get_ticks_usec()
			_do_return(delta, actor)
			FRAME_PROFILER.add_usec("mob_neutral.ai.passive_return", Time.get_ticks_usec() - t_passive_return)
			return
		var t_passive_idle := Time.get_ticks_usec()
		_do_idle(delta, actor)
		FRAME_PROFILER.add_usec("mob_neutral.ai.passive_idle", Time.get_ticks_usec() - t_passive_idle)
		return

	# aggressive = true → CHASE/RETURN логика как у агрессивного
	var t_leash := Time.get_ticks_usec()
	var dist_to_home: float = actor.global_position.distance_to(home_position)
	if _state == AIState.CHASE and dist_to_home > leash_distance:
		_state = AIState.RETURN
		emit_signal("leash_return_started")
	FRAME_PROFILER.add_usec("mob_neutral.ai.leash_check", Time.get_ticks_usec() - t_leash)

	if _state == AIState.RETURN:
		var t_return := Time.get_ticks_usec()
		_do_return(delta, actor)
		FRAME_PROFILER.add_usec("mob_neutral.ai.return", Time.get_ticks_usec() - t_return)
		return

	_state = AIState.CHASE
	var t_chase := Time.get_ticks_usec()
	_do_chase(actor, target, combat)
	FRAME_PROFILER.add_usec("mob_neutral.ai.chase", Time.get_ticks_usec() - t_chase)

func on_took_damage(attacker: Node2D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if _state == AIState.RETURN:
		var dist_home: float = attacker.global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_state = AIState.CHASE
		return
	_state = AIState.CHASE

func force_return() -> void:
	_state = AIState.RETURN
	emit_signal("leash_return_started")

func _do_idle(delta: float, actor: CharacterBody2D) -> void:
	if behavior == Behavior.PATROL:
		var t_idle_patrol := Time.get_ticks_usec()
		_do_patrol(delta, actor)
		FRAME_PROFILER.add_usec("mob_neutral.ai.idle_patrol", Time.get_ticks_usec() - t_idle_patrol)
	else:
		actor.velocity = Vector2.ZERO
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		var t_idle_guard_move := Time.get_ticks_usec()
		actor.move_and_slide()
		FRAME_PROFILER.add_usec("mob_neutral.ai.idle_guard_move", Time.get_ticks_usec() - t_idle_guard_move)

func _pick_new_patrol_target() -> void:
	_has_patrol_target = true
	var min_r: float = max(10.0, patrol_radius * 0.30)
	var angle: float = randf() * TAU
	var r: float = lerp(min_r, patrol_radius, randf())
	_patrol_target = home_position + Vector2(cos(angle), sin(angle)) * r

func _do_patrol(delta: float, actor: CharacterBody2D) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		var t_patrol_wait_move := Time.get_ticks_usec()
		actor.move_and_slide()
		FRAME_PROFILER.add_usec("mob_neutral.ai.patrol_move", Time.get_ticks_usec() - t_patrol_wait_move)
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
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		var t_patrol_reached_move := Time.get_ticks_usec()
		actor.move_and_slide()
		FRAME_PROFILER.add_usec("mob_neutral.ai.patrol_move", Time.get_ticks_usec() - t_patrol_reached_move)
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

	var patrol_dir: Vector2 = (_patrol_target - actor.global_position).normalized()
	var t_patrol_separation := Time.get_ticks_usec()
	var separation_dir: Vector2 = _get_patrol_separation_vector(delta, actor)
	FRAME_PROFILER.add_usec("mob_neutral.ai.patrol_separation", Time.get_ticks_usec() - t_patrol_separation)
	var final_dir: Vector2 = patrol_dir + separation_dir
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()
	else:
		final_dir = patrol_dir
	var t_patrol_steer := Time.get_ticks_usec()
	final_dir = _steer_around_obstacles(actor, final_dir)
	FRAME_PROFILER.add_usec("mob_neutral.ai.patrol_steer", Time.get_ticks_usec() - t_patrol_steer)
	if final_dir.length_squared() <= 0.0001:
		actor.velocity = Vector2.ZERO
	else:
		actor.velocity = final_dir * patrol_speed
	if actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, true)
	var t_patrol_move := Time.get_ticks_usec()
	actor.move_and_slide()
	FRAME_PROFILER.add_usec("mob_neutral.ai.patrol_move", Time.get_ticks_usec() - t_patrol_move)

func _get_patrol_separation_vector(delta: float, actor: CharacterBody2D) -> Vector2:
	_patrol_separation_refresh -= delta
	if _patrol_separation_refresh > 0.0:
		return _patrol_separation_vector
	_patrol_separation_refresh = PATROL_SEPARATION_REFRESH_SEC
	_patrol_separation_vector = _compute_patrol_separation(actor)
	return _patrol_separation_vector

func _compute_patrol_separation(actor: CharacterBody2D) -> Vector2:
	if actor == null or not is_instance_valid(actor):
		return Vector2.ZERO
	var tree := actor.get_tree()
	if tree == null:
		return Vector2.ZERO
	var repel := Vector2.ZERO
	var nearby_count: int = 0
	for n in tree.get_nodes_in_group("mobs"):
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

func _do_chase(actor: CharacterBody2D, target: Node2D, combat: NormalNeutralMobCombat) -> void:
	if target == null or not is_instance_valid(target):
		_state = AIState.RETURN
		emit_signal("leash_return_started")
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	var to_target: Vector2 = target.global_position - actor.global_position
	var dist: float = to_target.length()

	var stop_distance: float = max(0.0, combat.get_stop_distance())
	var spacing_distance: float = max(0.0, stop_distance - COMBAT_SPACING_BUFFER)
	if dist > stop_distance:
		var chase_dir := _steer_around_obstacles(actor, to_target.normalized())
		actor.velocity = chase_dir * speed if chase_dir.length_squared() > 0.0001 else Vector2.ZERO
	elif dist < spacing_distance:
		var backstep_dir := _steer_around_obstacles(actor, (-to_target).normalized())
		actor.velocity = backstep_dir * (speed * 0.5) if backstep_dir.length_squared() > 0.0001 else Vector2.ZERO
	else:
		actor.velocity = Vector2.ZERO
	if actor.has_method("update_movement_animation"):
		var anim_dir: Vector2 = actor.velocity
		if anim_dir.length_squared() <= 0.0001 and dist > 0.001:
			anim_dir = to_target.normalized() * 0.02
		actor.call("update_movement_animation", anim_dir, false)
	actor.move_and_slide()

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	var to_home: Vector2 = home_position - actor.global_position
	var dist: float = to_home.length()

	if dist <= 6.0:
		_state = AIState.IDLE
		_has_patrol_target = false
		_patrol_wait = patrol_pause_seconds
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	var return_dir := _steer_around_obstacles(actor, to_home.normalized())
	actor.velocity = return_dir * speed if return_dir.length_squared() > 0.0001 else Vector2.ZERO
	if actor.has_method("update_movement_animation"):
		var anim_dir: Vector2 = actor.velocity
		if anim_dir.length_squared() <= 0.0001 and dist > 0.001:
			anim_dir = to_home.normalized() * 0.02
		actor.call("update_movement_animation", anim_dir, false)
	actor.move_and_slide()

extends Node
class_name FactionNPCAI

enum Behavior { GUARD, PATROL }
enum State { IDLE, CHASE, RETURN }

signal leash_return_started
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")
const COMBAT_SPACING_BUFFER: float = 20.0
const PATROL_SEPARATION_DISTANCE: float = 28.0
const PATROL_SEPARATION_REFRESH_SEC: float = 0.15

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

func reset_to_idle() -> void:
	state = State.IDLE
	_has_patrol_target = false
	_wait = 0.0
	_patrol_has_last_position = false
	_patrol_stuck_time = 0.0
	_patrol_separation_refresh = 0.0
	_patrol_separation_vector = Vector2.ZERO

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
	var dist_home: float = actor.global_position.distance_to(home_position)
	if state == State.CHASE and dist_home > leash_distance:
		state = State.RETURN
		emit_signal("leash_return_started")

	if state == State.RETURN:
		_do_return(delta, actor)
		return

	if proactive:
		if state != State.CHASE and target != null and is_instance_valid(target):
			var d: float = actor.global_position.distance_to(target.global_position)
			if d <= aggro_radius:
				state = State.CHASE

	if state == State.CHASE:
		_do_chase(actor, target, combat)
		return

	_do_idle(delta, actor)

func _do_idle(delta: float, actor: CharacterBody2D) -> void:
	if behavior == Behavior.PATROL:
		_do_patrol(delta, actor)
	else:
		actor.velocity = Vector2.ZERO
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()

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
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
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
			if _patrol_stuck_time >= 0.8:
				_pick_patrol_target()
				_patrol_stuck_time = 0.0
				_patrol_has_last_position = false
		else:
			_patrol_stuck_time = 0.0
	_patrol_last_position = actor.global_position
	_patrol_has_last_position = true

	var patrol_dir: Vector2 = (_patrol_target - actor.global_position).normalized()
	var separation_dir: Vector2 = _get_patrol_separation_vector(delta, actor)
	var final_dir: Vector2 = patrol_dir + separation_dir
	if final_dir.length_squared() > 0.0001:
		final_dir = final_dir.normalized()
	else:
		final_dir = patrol_dir
	actor.velocity = final_dir * patrol_speed
	if actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, true)
	actor.move_and_slide()

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

func _do_chase(actor: CharacterBody2D, target: Node2D, combat: FactionNPCCombat) -> void:
	if target == null or not is_instance_valid(target):
		state = State.RETURN
		emit_signal("leash_return_started")
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	var to: Vector2 = target.global_position - actor.global_position
	var dist: float = to.length()
	var stop: float = max(0.0, combat.stop_distance())
	var spacing_distance: float = max(0.0, stop - COMBAT_SPACING_BUFFER)

	if dist > stop:
		actor.velocity = to.normalized() * speed
	elif dist < spacing_distance:
		actor.velocity = (-to).normalized() * (speed * 0.5)
	else:
		actor.velocity = Vector2.ZERO
	if actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, false)
	actor.move_and_slide()

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	var to: Vector2 = home_position - actor.global_position
	if to.length() <= 6.0:
		state = State.IDLE
		_has_patrol_target = false
		_wait = patrol_pause_seconds
		actor.velocity = Vector2.ZERO
		_patrol_has_last_position = false
		_patrol_stuck_time = 0.0
		if actor.has_method("update_movement_animation"):
			actor.call("update_movement_animation", Vector2.ZERO, false)
		actor.move_and_slide()
		return

	actor.velocity = to.normalized() * speed
	if actor.has_method("update_movement_animation"):
		actor.call("update_movement_animation", actor.velocity, false)
	actor.move_and_slide()

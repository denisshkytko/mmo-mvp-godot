extends Node
class_name NormalAggresiveMobAI

signal leash_return_started

enum AIState { IDLE, CHASE, RETURN }
enum Behavior { GUARD, PATROL }

var behavior: int = Behavior.GUARD
var speed: float = 120.0
var aggro_radius: float = 260.0
var leash_distance: float = 420.0
var patrol_radius: float = 140.0
var patrol_pause_seconds: float = 1.5

var home_position: Vector2 = Vector2.ZERO

var _state: int = AIState.IDLE
var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _patrol_wait: float = 0.0

# RETURN → re-aggro if damaged
var _force_chase_timer: float = 0.0
var force_chase_seconds: float = 0.6

func reset_to_idle() -> void:
	_state = AIState.IDLE
	_has_patrol_target = false
	_patrol_wait = 0.0
	_force_chase_timer = 0.0

func force_return() -> void:
	_state = AIState.RETURN
	_force_chase_timer = 0.0
	emit_signal("leash_return_started")

func tick(delta: float, actor: CharacterBody2D, target: Node2D, combat: NormalAggresiveMobCombat) -> void:
	_force_chase_timer = max(0.0, _force_chase_timer - delta)

	# выключение CHASE по leash_distance
	var dist_to_home: float = actor.global_position.distance_to(home_position)
	if _state == AIState.CHASE and dist_to_home > leash_distance:
		_state = AIState.RETURN
		emit_signal("leash_return_started")

	# RETURN
	if _state == AIState.RETURN:
		_do_return(delta, actor)
		return

	# включаем CHASE только если цель вошла в агро-радиус
	if _state != AIState.CHASE and target != null and is_instance_valid(target):
		var dist_to_target: float = actor.global_position.distance_to(target.global_position)
		if dist_to_target <= aggro_radius:
			_state = AIState.CHASE

	# CHASE
	if _state == AIState.CHASE:
		_do_chase(actor, target, combat)
		return

	# IDLE
	_do_idle(delta, actor)

func on_took_damage(actor: CharacterBody2D) -> void:
	# ре-агро во время RETURN, но только если ещё в leash
	if _state == AIState.RETURN:
		var dist_home: float = actor.global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_force_chase_timer = force_chase_seconds
			_state = AIState.CHASE
	else:
		_state = AIState.CHASE

func _do_idle(delta: float, actor: CharacterBody2D) -> void:
	if behavior == Behavior.PATROL:
		_do_patrol(delta, actor)
	else:
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()

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
		actor.move_and_slide()
		return

	if not _has_patrol_target:
		_pick_new_patrol_target()

	var d: float = actor.global_position.distance_to(_patrol_target)
	if d <= 6.0:
		_patrol_wait = patrol_pause_seconds
		_pick_new_patrol_target()
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()
		return

	actor.velocity = (_patrol_target - actor.global_position).normalized() * speed
	actor.move_and_slide()

func _do_chase(actor: CharacterBody2D, target: Node2D, combat: NormalAggresiveMobCombat) -> void:
	if target == null or not is_instance_valid(target):
		_state = AIState.IDLE
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()
		return

	var to_target: Vector2 = target.global_position - actor.global_position
	var dist: float = to_target.length()

	var stop_distance: float = combat.get_stop_distance()
	if dist > stop_distance:
		actor.velocity = to_target.normalized() * speed
		actor.move_and_slide()
		return

	actor.velocity = Vector2.ZERO
	actor.move_and_slide()

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	# если во время RETURN получили урон и всё ещё в leash — снова CHASE
	if _force_chase_timer > 0.0:
		var dist_home: float = actor.global_position.distance_to(home_position)
		if dist_home <= leash_distance:
			_state = AIState.CHASE
			return

	var to_home: Vector2 = home_position - actor.global_position
	var dist: float = to_home.length()

	if dist <= 6.0:
		_state = AIState.IDLE
		_has_patrol_target = false
		_patrol_wait = patrol_pause_seconds
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()
		return

	actor.velocity = to_home.normalized() * speed
	actor.move_and_slide()

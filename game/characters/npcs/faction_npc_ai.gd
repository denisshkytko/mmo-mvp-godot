extends Node
class_name FactionNPCAI

enum Behavior { GUARD, PATROL }
enum State { IDLE, CHASE, RETURN }

signal leash_return_started
const MOVE_SPEED := preload("res://core/movement/move_speed.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

var behavior: int = Behavior.GUARD
var state: int = State.IDLE

var speed: float = MOVE_SPEED.MOB_BASE
var aggro_radius: float = COMBAT_RANGES.AGGRO_RADIUS
var leash_distance: float = COMBAT_RANGES.LEASH_DISTANCE
var patrol_radius: float = COMBAT_RANGES.PATROL_RADIUS
var patrol_pause_seconds: float = 1.5

var home_position: Vector2 = Vector2.ZERO

var _patrol_target: Vector2 = Vector2.ZERO
var _has_patrol_target: bool = false
var _wait: float = 0.0

func reset_to_idle() -> void:
	state = State.IDLE
	_has_patrol_target = false
	_wait = 0.0

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
		actor.move_and_slide()
		return

	if not _has_patrol_target:
		_pick_patrol_target()

	var d: float = actor.global_position.distance_to(_patrol_target)
	if d <= 6.0:
		_wait = patrol_pause_seconds
		_pick_patrol_target()
		return

	actor.velocity = (_patrol_target - actor.global_position).normalized() * speed
	actor.move_and_slide()

func _do_chase(actor: CharacterBody2D, target: Node2D, combat: FactionNPCCombat) -> void:
	if target == null or not is_instance_valid(target):
		state = State.RETURN
		emit_signal("leash_return_started")
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()
		return

	var to: Vector2 = target.global_position - actor.global_position
	var dist: float = to.length()
	var stop: float = combat.stop_distance()

	if dist > stop:
		actor.velocity = to.normalized() * speed
		actor.move_and_slide()
	else:
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()

func _do_return(_delta: float, actor: CharacterBody2D) -> void:
	var to: Vector2 = home_position - actor.global_position
	if to.length() <= 6.0:
		state = State.IDLE
		_has_patrol_target = false
		_wait = patrol_pause_seconds
		actor.velocity = Vector2.ZERO
		actor.move_and_slide()
		return

	actor.velocity = to.normalized() * speed
	actor.move_and_slide()

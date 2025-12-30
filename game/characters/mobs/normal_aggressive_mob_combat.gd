extends Node
class_name NormalAggresiveMobCombat

const STAT_CONST := preload("res://core/stats/stat_constants.gd")

enum AttackMode { MELEE, RANGED }

var attack_mode: int = AttackMode.MELEE

# melee params
var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

# ranged params
var ranged_attack_range: float = 220.0
var ranged_cooldown: float = 1.5
var ranged_projectile_scene: PackedScene = null

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, attack_power: int, attack_speed_pct: float = 0.0) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = actor.global_position.distance_to(target.global_position)
	# unified physical damage
	var dmg: int = int(round(float(attack_power) * STAT_CONST.AP_DAMAGE_SCALAR))
	if dmg < 1:
		dmg = 1

	var speed_mult: float = 1.0 + max(0.0, attack_speed_pct) / 100.0
	if speed_mult < 0.1:
		speed_mult = 0.1

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _attack_timer <= 0.0:
			target.call("take_damage", dmg)
			_attack_timer = melee_cooldown / speed_mult
		return

	# RANGED
	if dist <= ranged_attack_range and _attack_timer <= 0.0:
		_fire_ranged(actor, target, dmg)
		_attack_timer = ranged_cooldown / speed_mult

func _fire_ranged(actor: Node2D, target: Node2D, damage: int) -> void:
	if ranged_projectile_scene == null:
		target.call("take_damage", damage)
		return

	var inst: Node = ranged_projectile_scene.instantiate()
	var proj: Node2D = inst as Node2D
	if proj == null:
		target.call("take_damage", damage)
		return

	var parent: Node = actor.get_parent()
	if parent == null:
		target.call("take_damage", damage)
		return

	parent.add_child(proj)
	proj.global_position = actor.global_position

	if proj.has_method("setup"):
		proj.call("setup", target, damage, actor)

func get_stop_distance() -> float:
	return melee_stop_distance if attack_mode == AttackMode.MELEE else ranged_attack_range

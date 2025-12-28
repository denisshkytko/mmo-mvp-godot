extends Node
class_name FactionNPCCombat

enum AttackMode { MELEE, RANGED }

var attack_mode: int = AttackMode.MELEE

var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

var ranged_attack_range: float = 220.0
var ranged_cooldown: float = 1.5
var ranged_projectile_scene: PackedScene = null

var _t: float = 0.0

func reset() -> void:
	_t = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, dmg: int) -> void:
	_t = max(0.0, _t - delta)

	if target == null or not is_instance_valid(target):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = actor.global_position.distance_to(target.global_position)

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _t <= 0.0:
			if target.has_method("take_damage_from"):
				target.call("take_damage_from", dmg, actor)
			elif target.has_method("take_damage"):
				target.call("take_damage", dmg)
			_t = melee_cooldown
		return

	# RANGED
	if dist <= ranged_attack_range and _t <= 0.0:
		if ranged_projectile_scene != null:
			var inst: Node = ranged_projectile_scene.instantiate()
			var proj: Node2D = inst as Node2D
			if proj != null:
				var parent: Node = actor.get_parent()
				if parent != null:
					parent.add_child(proj)
					proj.global_position = actor.global_position
					if proj.has_method("setup"):
						proj.call("setup", target, dmg, actor)
		_t = ranged_cooldown

func stop_distance() -> float:
	return melee_stop_distance if attack_mode == AttackMode.MELEE else ranged_attack_range

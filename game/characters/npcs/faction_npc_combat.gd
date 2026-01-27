extends Node
class_name FactionNPCCombat

const STAT_CONST := preload("res://core/stats/stat_constants.gd")

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

func tick(delta: float, actor: Node2D, target: Node2D, snap: Dictionary) -> void:
	_t = max(0.0, _t - delta)

	if target == null or not is_instance_valid(target):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = actor.global_position.distance_to(target.global_position)
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var dmg: int = max(1, int(round(ap * STAT_CONST.MOB_UNARMED_AP_MULT)))
	var crit_chance_pct: float = float(snap.get("crit_chance_pct", 0.0))
	var crit_mult: float = float(snap.get("crit_multiplier", 2.0))
	if randf() * 100.0 < crit_chance_pct:
		dmg = int(round(float(dmg) * crit_mult))
	dmg = max(1, dmg)

	var aspct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + max(0.0, aspct) / 100.0
	if speed_mult < 0.1:
		speed_mult = 0.1

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _t <= 0.0:
			if target.has_method("take_damage_from"):
				target.call("take_damage_from", dmg, actor)
			elif target.has_method("take_damage"):
				target.call("take_damage", dmg)
			if "c_resource" in actor and actor.c_resource != null:
				actor.c_resource.on_damage_dealt()
			_t = melee_cooldown / speed_mult
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
		_t = ranged_cooldown / speed_mult

func stop_distance() -> float:
	return melee_stop_distance if attack_mode == AttackMode.MELEE else ranged_attack_range

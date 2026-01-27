extends Node
class_name NormalNeutralMobCombat

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")

var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, snap: Dictionary) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	if target == null or not is_instance_valid(target):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = actor.global_position.distance_to(target.global_position)
	if dist > melee_attack_range:
		return
	if _attack_timer > 0.0:
		return

	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var raw: int = STAT_CALC.compute_mob_unarmed_hit(ap)
	var dmg: int = STAT_CALC.apply_crit_to_damage(raw, snap)

	var aspct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + max(0.0, aspct) / 100.0
	if speed_mult < 0.1:
		speed_mult = 0.1

	if target.has_method("take_damage"):
		target.call("take_damage", dmg)
		if "c_resource" in actor and actor.c_resource != null:
			actor.c_resource.on_damage_dealt()

	_attack_timer = melee_cooldown / speed_mult

func get_stop_distance() -> float:
	return melee_stop_distance

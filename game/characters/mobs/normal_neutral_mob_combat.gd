extends Node
class_name NormalNeutralMobCombat

const STAT_CONST := preload("res://core/stats/stat_constants.gd")

var melee_stop_distance: float = 45.0
var melee_attack_range: float = 55.0
var melee_cooldown: float = 1.2

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, attack_power: int, attack_speed_pct: float = 0.0) -> void:
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

	var speed_mult: float = 1.0 + max(0.0, attack_speed_pct) / 100.0
	if speed_mult < 0.1:
		speed_mult = 0.1

	# Mobs deal physical damage using the same formula as the Player:
	# final_damage ~= AttackPower * AP_DAMAGE_SCALAR
	var dmg: int = int(round(float(attack_power) * STAT_CONST.AP_DAMAGE_SCALAR))
	if dmg < 1:
		dmg = 1
	if target.has_method("take_damage"):
		target.call("take_damage", dmg)
		if "c_resource" in actor and actor.c_resource != null:
			actor.c_resource.on_damage_dealt()

	_attack_timer = melee_cooldown / speed_mult

func get_stop_distance() -> float:
	return melee_stop_distance

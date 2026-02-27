extends Node
class_name NormalAggresiveMobCombat

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

enum AttackMode { MELEE, RANGED }

var attack_mode: int = AttackMode.MELEE

# melee params
var melee_stop_distance: float = 45.0
var melee_attack_range: float = COMBAT_RANGES.MELEE_ATTACK_RANGE
var melee_cooldown: float = 1.2

# ranged params
var ranged_attack_range: float = COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
var ranged_cooldown: float = 1.5
var ranged_projectile_scene: PackedScene = null

var _attack_timer: float = 0.0

func reset_combat() -> void:
	_attack_timer = 0.0

func tick(delta: float, actor: Node2D, target: Node2D, snap: Dictionary) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)

	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	if "is_dead" in target and bool(target.get("is_dead")):
		return

	var dist: float = actor.global_position.distance_to(target.global_position)
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var raw: int = STAT_CALC.compute_mob_unarmed_hit(ap)
	var dmg: int = STAT_CALC.apply_crit_to_damage(raw, snap)

	var aspct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + max(0.0, aspct) / 100.0
	if "c_stats" in actor and actor.c_stats != null and actor.c_stats.has_method("get_attack_speed_multiplier"):
		speed_mult *= float(actor.c_stats.call("get_attack_speed_multiplier"))
	if speed_mult < 0.1:
		speed_mult = 0.1

	if attack_mode == AttackMode.MELEE:
		if dist <= melee_attack_range and _attack_timer <= 0.0:
			DAMAGE_HELPER.apply_damage(actor, target, dmg)
			_attack_timer = melee_cooldown / speed_mult
		return

	# RANGED
	if dist <= ranged_attack_range and _attack_timer <= 0.0:
		_fire_ranged(actor, target, dmg)
		_attack_timer = ranged_cooldown / speed_mult

func _fire_ranged(actor: Node2D, target: Node2D, damage: int) -> void:
	if ranged_projectile_scene == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		return

	var inst: Node = ranged_projectile_scene.instantiate()
	var proj: Node2D = inst as Node2D
	if proj == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		return

	var parent: Node = actor.get_parent()
	if parent == null:
		DAMAGE_HELPER.apply_damage(actor, target, damage)
		return

	parent.add_child(proj)
	proj.global_position = actor.global_position

	if proj.has_method("setup"):
		proj.call("setup", target, damage, actor)

func get_stop_distance() -> float:
	return melee_stop_distance if attack_mode == AttackMode.MELEE else ranged_attack_range

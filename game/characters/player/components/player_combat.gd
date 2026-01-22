extends Node
class_name PlayerCombat

## NodeCache is a global helper (class_name). Avoid shadowing.
const STAT_CONST := preload("res://core/stats/stat_constants.gd")

var p: Player = null
var _attack_timer: float = 0.0

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if p == null:
		return

	_attack_timer = max(0.0, _attack_timer - delta)

	# Auto-attack only if target exists and is in range
	if _attack_timer > 0.0:
		return

	var target: Node2D = _get_current_target()
	if target == null:
		return

	var dist: float = p.global_position.distance_to(target.global_position)
	if dist > p.attack_range:
		return

	_apply_damage_to_target(target, get_attack_damage())
	_attack_timer = _get_effective_attack_cooldown()


func get_attack_damage() -> int:
	# Stage 1: physical damage = weapon_damage (0 for now) + AttackPower * scalar
	# Crit chance/crit multiplier are read from stats snapshot.
	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary

	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var weapon_damage: float = 0.0
	var base_damage: float = weapon_damage + ap * STAT_CONST.AP_DAMAGE_SCALAR

	# Crit
	var crit_chance_pct: float = float(snap.get("crit_chance_pct", 0.0))
	var crit_mult: float = float(snap.get("crit_multiplier", 2.0))
	var is_crit: bool = (randf() * 100.0) < crit_chance_pct
	var final: float = base_damage
	if is_crit:
		final *= crit_mult

	return max(1, int(round(final)))


func _get_effective_attack_cooldown() -> float:
	# Base cooldown comes from Player (and later from weapon)
	var base_cd: float = p.attack_cooldown
	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary
	var atk_speed_pct: float = float(snap.get("attack_speed_pct", 0.0))
	# Example: +15% attack speed => cooldown / 1.15
	var mult: float = 1.0 + (atk_speed_pct / 100.0)
	if mult <= 0.01:
		mult = 0.01
	return base_cd / mult


func _apply_damage_to_target(target: Node2D, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return

	# faction gate
	var attacker_faction := "blue"
	if p != null and p.has_method("get_faction_id"):
		attacker_faction = String(p.call("get_faction_id"))

	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))

	if not FactionRules.can_attack(attacker_faction, target_faction, true):
		return

	# Mark combat so HP regen pauses
	if p != null and p.has_method("mark_in_combat"):
		p.call("mark_in_combat")

	# apply damage (prefer take_damage_from for loot rights)
	if target.has_method("take_damage_from"):
		target.call("take_damage_from", dmg, p)
	elif target.has_method("take_damage"):
		target.call("take_damage", dmg)
	if p != null and "c_resource" in p and p.c_resource != null:
		p.c_resource.on_damage_dealt()


func _get_current_target() -> Node2D:
	var gm: Node = NodeCache.get_game_manager(p.get_tree())
	if gm == null or not gm.has_method("get_target"):
		return null

	var t = gm.call("get_target")
	if t != null and t is Node2D and is_instance_valid(t):
		return t as Node2D
	return null

extends Node
class_name PlayerCombat

## NodeCache is a global helper (class_name). Avoid shadowing.
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const PROG := preload("res://core/stats/progression.gd")

var p: Player = null
var _t_r: float = 0.0
var _t_l: float = 0.0

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if p == null:
		return

	var target: Node2D = _get_current_target()
	if target == null:
		_t_r = 0.0
		_t_l = 0.0
		return

	var dist: float = p.global_position.distance_to(target.global_position)
	if dist > p.attack_range:
		return

	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var atk_speed_pct: float = float(snap.get("attack_speed_pct", 0.0))
	var speed_mult: float = 1.0 + (atk_speed_pct / 100.0)
	if speed_mult <= 0.01:
		speed_mult = 0.01

	var base_interval_r: float = _get_base_interval_right()
	var base_interval_l: float = _get_base_interval_left()
	var eff_interval_r: float = base_interval_r / speed_mult
	var eff_interval_l: float = base_interval_l / speed_mult if base_interval_l > 0.0 else 0.0

	var hits := _get_hit_values(ap)

	_t_r = max(0.0, _t_r - delta)
	_t_l = max(0.0, _t_l - delta)

	if hits.has("right") and _t_r <= 0.0:
		var dmg_r: int = _apply_crit(int(hits.get("right", 0)), snap)
		_apply_damage_to_target(target, dmg_r)
		_t_r = eff_interval_r

	if hits.has("left") and _t_l <= 0.0:
		var dmg_l: int = _apply_crit(int(hits.get("left", 0)), snap)
		_apply_damage_to_target(target, dmg_l)
		_t_l = eff_interval_l

func _get_hit_values(ap: float) -> Dictionary:
	var right_weapon_damage: int = 0
	var left_weapon_damage: int = 0
	var has_right_weapon := false
	var has_left_weapon := false
	var is_two_handed := false

	if p != null and p.c_equip != null:
		right_weapon_damage = p.c_equip.get_weapon_damage_right()
		left_weapon_damage = p.c_equip.get_weapon_damage_left()
		has_left_weapon = p.c_equip.has_left_weapon()
		is_two_handed = p.c_equip.is_two_handed_equipped()
		has_right_weapon = p.c_equip.get_weapon_attack_interval_right() > 0.0

	if not has_right_weapon:
		var dmg_unarmed: int = max(1, int(round(ap * 1.5)))
		return {"right": dmg_unarmed}

	if is_two_handed:
		var dmg_2h: int = max(1, int(round(float(right_weapon_damage) + ap * 1.5)))
		return {"right": dmg_2h}

	if has_left_weapon:
		var dmg_r: int = max(1, int(round(float(right_weapon_damage) + ap)))
		var dmg_l: int = max(1, int(round((float(left_weapon_damage) + ap) * STAT_CONST.OFFHAND_MULT)))
		return {"right": dmg_r, "left": dmg_l}

	var dmg_1h: int = max(1, int(round(float(right_weapon_damage) + ap)))
	return {"right": dmg_1h}

func _get_base_interval_right() -> float:
	if p == null or p.c_equip == null:
		return _get_class_base_interval()
	var r: float = p.c_equip.get_weapon_attack_interval_right()
	if r <= 0.0:
		return _get_class_base_interval()
	return r

func _get_base_interval_left() -> float:
	if p == null or p.c_equip == null:
		return 0.0
	if not p.c_equip.has_left_weapon():
		return 0.0
	var l: float = p.c_equip.get_weapon_attack_interval_left()
	return l

func _get_class_base_interval() -> float:
	if p == null:
		return 1.0
	return float(PROG.get_base_melee_attack_interval_for_class(p.class_id))

func _apply_crit(base_damage: int, snap: Dictionary) -> int:
	if base_damage <= 0:
		return 1
	var crit_chance_pct: float = float(snap.get("crit_chance_pct", 0.0))
	var crit_mult: float = float(snap.get("crit_multiplier", 2.0))
	var final: float = float(base_damage)
	if (randf() * 100.0) < crit_chance_pct:
		final *= crit_mult
	return max(1, int(round(final)))


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

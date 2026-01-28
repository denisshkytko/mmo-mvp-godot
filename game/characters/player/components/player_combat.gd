extends Node
class_name PlayerCombat

## NodeCache is a global helper (class_name). Avoid shadowing.
const STAT_CONST := preload("res://core/stats/stat_constants.gd")
const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const PROG := preload("res://core/stats/progression.gd")
const RANGED_PROJECTILE_SCENE := preload("res://game/characters/mobs/projectiles/HomingProjectile.tscn")

const MELEE_ATTACK_RANGE: float = 66.0
const RANGED_ATTACK_RANGE: float = 264.0
const RANGED_WEAPON_SUBTYPES: Array[String] = [
	"staff",
	"staff_2h",
	"bow",
	"bow_2h",
	"crossbow",
	"crossbow_2h",
	"wand",
	"wand_1h",
]

enum AttackMode { MELEE, RANGED }

var p: Player = null
var _t_r: float = 0.0
var _t_l: float = 0.0
var _attack_mode: int = AttackMode.MELEE

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

	_attack_mode = _get_attack_mode()
	var dist: float = p.global_position.distance_to(target.global_position)
	var attack_range := _get_attack_range()
	if dist > attack_range:
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
		var dmg_r: int = STAT_CALC.apply_crit_to_damage(int(hits.get("right", 0)), snap)
		if _attack_mode == AttackMode.RANGED:
			_fire_ranged(target, dmg_r)
		else:
			_apply_damage_to_target(target, dmg_r)
		_t_r = eff_interval_r

	if hits.has("left") and _t_l <= 0.0:
		var dmg_l: int = STAT_CALC.apply_crit_to_damage(int(hits.get("left", 0)), snap)
		if _attack_mode == AttackMode.RANGED:
			_fire_ranged(target, dmg_l)
		else:
			_apply_damage_to_target(target, dmg_l)
		_t_l = eff_interval_l

func get_attack_damage() -> int:
	if p == null:
		return 0
	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var ap: float = float(derived.get("attack_power", 0.0))
	var hits := _get_hit_values(ap)
	if hits.has("right"):
		return int(hits.get("right", 0))
	if hits.has("left"):
		return int(hits.get("left", 0))
	return 0

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

func _apply_damage_to_target(target: Node2D, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _can_attack_target(target):
		return

	DAMAGE_HELPER.apply_damage(p, target, dmg)

func _fire_ranged(target: Node2D, dmg: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not _can_attack_target(target):
		return
	if RANGED_PROJECTILE_SCENE == null:
		_apply_damage_to_target(target, dmg)
		return

	var inst: Node = RANGED_PROJECTILE_SCENE.instantiate()
	var proj: Node2D = inst as Node2D
	if proj == null:
		_apply_damage_to_target(target, dmg)
		return

	var parent: Node = p.get_parent()
	if parent == null:
		_apply_damage_to_target(target, dmg)
		return

	parent.add_child(proj)
	proj.global_position = p.global_position
	if proj.has_method("setup"):
		proj.call("setup", target, dmg, p)


func _get_current_target() -> Node2D:
	var gm: Node = NodeCache.get_game_manager(p.get_tree())
	if gm == null or not gm.has_method("get_target"):
		return null

	var t = gm.call("get_target")
	if t != null and t is Node2D and is_instance_valid(t):
		return t as Node2D
	return null

func _can_attack_target(target: Node2D) -> bool:
	var attacker_faction := "blue"
	if p != null and p.has_method("get_faction_id"):
		attacker_faction = String(p.call("get_faction_id"))

	var target_faction := ""
	if target != null and target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))

	return FactionRules.can_attack(attacker_faction, target_faction, true)

func _get_attack_mode() -> int:
	if p == null or p.c_equip == null:
		return AttackMode.MELEE
	var subtype := p.c_equip.get_right_weapon_subtype()
	if subtype != "" and RANGED_WEAPON_SUBTYPES.has(subtype):
		return AttackMode.RANGED
	return AttackMode.MELEE

func _get_attack_range() -> float:
	return RANGED_ATTACK_RANGE if _attack_mode == AttackMode.RANGED else MELEE_ATTACK_RANGE

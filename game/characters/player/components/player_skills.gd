extends Node
class_name PlayerSkills

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

var p: Player = null

var _skill_1_timer: float = 0.0
var _skill_2_timer: float = 0.0
var _skill_3_timer: float = 0.0

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if p == null:
		return

	_skill_1_timer = max(0.0, _skill_1_timer - delta)
	_skill_2_timer = max(0.0, _skill_2_timer - delta)
	_skill_3_timer = max(0.0, _skill_3_timer - delta)

	# хоткеи (оставляем как было)
	if Input.is_action_just_pressed("skill_1"):
		try_cast_skill_1()
	if Input.is_action_just_pressed("skill_2"):
		try_cast_skill_2()
	if Input.is_action_just_pressed("skill_3"):
		try_cast_skill_3()

func get_skill_1_cooldown_left() -> float:
	return _skill_1_timer

func get_skill_2_cooldown_left() -> float:
	return _skill_2_timer

func get_skill_3_cooldown_left() -> float:
	return _skill_3_timer


func try_cast_skill_1() -> void:
	if _skill_1_timer > 0.0:
		return
	if p.mana < p.skill_1_mana_cost:
		return

	var target: Node2D = _get_skill_1_target_in_range()
	if target == null:
		return

	var dmg: int = int(round(float(p.get_attack_damage()) * p.skill_1_damage_multiplier))
	var attacker_faction := "blue"
	if p != null and p.has_method("get_faction_id"):
		attacker_faction = String(p.call("get_faction_id"))

	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))

	if not FactionRules.can_attack(attacker_faction, target_faction, true):
		return

	DAMAGE_HELPER.apply_damage(p, target, dmg)

	p.mana = max(0, p.mana - p.skill_1_mana_cost)
	_skill_1_timer = _get_effective_skill_cooldown(p.skill_1_cooldown)


func try_cast_skill_2() -> void:
	if _skill_2_timer > 0.0:
		return
	if p.mana < p.skill_2_mana_cost:
		return
	if p.current_hp >= p.max_hp:
		return

	p.current_hp = min(p.max_hp, p.current_hp + p.skill_2_heal_amount)
	p.mana = max(0, p.mana - p.skill_2_mana_cost)
	_skill_2_timer = _get_effective_skill_cooldown(p.skill_2_cooldown)


func try_cast_skill_3() -> void:
	if _skill_3_timer > 0.0:
		return
	if p.mana < p.skill_3_mana_cost:
		return

	# баф атаки
	var buffs: PlayerBuffs = p.c_buffs
	if buffs != null:
		buffs.add_or_refresh_buff(
			"atk_buff_1",
			p.skill_3_duration_sec,
			{"attack_bonus": p.skill_3_attack_bonus}
		)

	p.mana = max(0, p.mana - p.skill_3_mana_cost)
	_skill_3_timer = _get_effective_skill_cooldown(p.skill_3_cooldown)


func _get_effective_skill_cooldown(base_cd: float) -> float:
	# Skill cooldowns are reduced ONLY by SpeedRating (secondary).
	# Formula: final_cd = base_cd / (1 + cooldown_reduction_pct/100)
	if p == null:
		return base_cd
	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary
	var cd_red_pct: float = float(snap.get("cooldown_reduction_pct", 0.0))
	var mult: float = 1.0 + (cd_red_pct / 100.0)
	if mult <= 0.01:
		mult = 0.01
	return base_cd / mult


func _get_skill_1_target_in_range() -> Node2D:
	var gm: Node = p.get_tree().get_first_node_in_group("game_manager")

	# 1) текущий таргет (если в радиусе)
	if gm != null and gm.has_method("get_target"):
		var t = gm.call("get_target")
		if t != null and t is Node2D and is_instance_valid(t):
			var tn: Node2D = t as Node2D
			var dist: float = p.global_position.distance_to(tn.global_position)
			if dist <= p.skill_1_range:
				return tn

	# 2) иначе ближайший моб в радиусе
	var mobs: Array = p.get_tree().get_nodes_in_group("mobs")
	var best: Node2D = null
	var best_dist: float = p.skill_1_range

	for mob in mobs:
		if mob is Node2D:
			var m: Node2D = mob as Node2D
			var d: float = p.global_position.distance_to(m.global_position)
			if d <= best_dist:
				best_dist = d
				best = m

	# 3) если нашли — ставим в таргет
	if best != null and gm != null and gm.has_method("set_target"):
		gm.call("set_target", best)

	return best

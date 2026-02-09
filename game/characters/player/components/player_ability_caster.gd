extends Node
class_name PlayerAbilityCaster

const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const STAT_CONST := preload("res://core/stats/stat_constants.gd")

var p: Player = null
var _cooldowns: Dictionary = {} # ability_id -> time_left
var _active_aura_buff_id: String = ""
var _active_stance_buff_id: String = ""
var _cast_time_left: float = 0.0
var _cast_payload: Dictionary = {}

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if _cast_time_left > 0.0:
		_cast_time_left = max(0.0, _cast_time_left - delta)
		if _cast_time_left <= 0.0 and not _cast_payload.is_empty():
			_finish_cast(_cast_payload)
			_cast_payload = {}

	if _cooldowns.is_empty():
		return
	for k in _cooldowns.keys():
		var ability_id: String = String(k)
		var left: float = max(0.0, float(_cooldowns.get(ability_id, 0.0)) - delta)
		if left <= 0.0:
			_cooldowns.erase(ability_id)
		else:
			_cooldowns[ability_id] = left

func try_cast(ability_id: String, target: Node) -> Dictionary:
	if ability_id == "":
		return {"ok": false, "reason": "empty"}
	if p == null or p.c_spellbook == null:
		return {"ok": false, "reason": "no_spellbook"}
	if _cast_time_left > 0.0:
		return {"ok": false, "reason": "casting"}
	var rank := int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	if rank <= 0:
		return {"ok": false, "reason": "not_learned"}

	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return {"ok": false, "reason": "no_db"}
	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def == null:
		return {"ok": false, "reason": "no_def"}
	if def.ability_type == "aura" or def.ability_type == "stance":
		return {"ok": false, "reason": "passive"}

	var rank_data: RankData = null
	if db.has_method("get_rank_data"):
		rank_data = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return {"ok": false, "reason": "no_rank"}

	if get_cooldown_left(ability_id) > 0.0:
		return {"ok": false, "reason": "cooldown"}

	var actual_target: Node = target
	if def.target_type == "self":
		actual_target = p
	elif actual_target == null:
		actual_target = p

	if actual_target == null and def.target_type != "self":
		return {"ok": false, "reason": "no_target"}

	if def.target_type == "enemy" and actual_target == p:
		return {"ok": false, "reason": "no_target"}

	var range_mode := def.range_mode
	if range_mode != "self" and actual_target is Node2D:
		var range: float = PlayerCombat.RANGED_ATTACK_RANGE
		if range_mode == "melee":
			range = PlayerCombat.MELEE_ATTACK_RANGE
		var dist: float = p.global_position.distance_to((actual_target as Node2D).global_position)
		if dist > range:
			return {"ok": false, "reason": "out_of_range"}

	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary

	var cost: int = int(ceil(float(p.max_mana) * float(rank_data.resource_cost) / 100.0))
	if cost > 0:
		if p.mana < cost:
			return {"ok": false, "reason": "no_mana"}
		p.mana -= cost

	var cdr_pct: float = float(snap.get("cooldown_reduction_pct", 0.0))
	var cd_eff: float = max(0.0, rank_data.cooldown_sec * (1.0 - cdr_pct / 100.0))
	if cd_eff > 0.0:
		_cooldowns[ability_id] = cd_eff

	var cast_speed_pct: float = float(snap.get("cast_speed_pct", 0.0))
	var cast_mult: float = 1.0 / (1.0 + cast_speed_pct / 100.0)
	var cast_time_eff: float = rank_data.cast_time_sec * cast_mult
	if cast_time_eff > 0.0:
		_cast_time_left = cast_time_eff
		_cast_payload = {
			"ability_id": ability_id,
			"target": actual_target,
			"def": def,
			"rank_data": rank_data
		}
		return {"ok": true, "reason": "casting", "target": actual_target}

	_apply_ability_effect(ability_id, def, rank_data, actual_target)
	return {"ok": true, "reason": "", "target": actual_target}

func get_cooldown_left(ability_id: String) -> float:
	return float(_cooldowns.get(ability_id, 0.0))

func get_cooldown_pct(ability_id: String) -> float:
	if ability_id == "":
		return 0.0
	var left := get_cooldown_left(ability_id)
	if left <= 0.0:
		return 0.0
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_rank_data") or p == null or p.c_spellbook == null:
		return 0.0
	var rank := int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return 0.0
	if rank_data.cooldown_sec <= 0.0:
		return 0.0
	return clamp(left / rank_data.cooldown_sec, 0.0, 1.0)

func apply_active_aura(ability_id: String) -> void:
	if p == null or p.c_buffs == null:
		return
	var new_buff_id := ""
	if ability_id != "":
		new_buff_id = "aura:%s" % ability_id
	if _active_aura_buff_id != "" and _active_aura_buff_id != new_buff_id:
		p.c_buffs.remove_buff(_active_aura_buff_id)
	_active_aura_buff_id = new_buff_id
	if ability_id == "":
		return
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_rank_data"):
		return
	var rank := 0
	if p.c_spellbook != null:
		rank = int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	if rank <= 0 and db.has_method("get_rank_for_level"):
		rank = int(db.call("get_rank_for_level", ability_id, p.level))
	if rank <= 0:
		return
	var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return

	var secondary := {}
	match ability_id:
		"aura_of_light_protection":
			secondary["defense"] = rank_data.value
			secondary["magic_resist"] = rank_data.value2
		"concentration_aura":
			secondary["cast_speed_rating"] = int(round(float(rank_data.value) * STAT_CONST.CS_RATING_PER_1PCT))
		"aura_of_tempering":
			secondary["flat_physical_bonus"] = rank_data.value

	var data := {
		"source_ability": ability_id,
		"ability_id": ability_id,
		"kind": "aura",
		"secondary": secondary
	}
	p.c_buffs.add_or_refresh_buff(new_buff_id, 999999.0, data)

func apply_active_stance(ability_id: String) -> void:
	if p == null or p.c_buffs == null:
		return
	var new_buff_id := ""
	if ability_id != "":
		new_buff_id = "stance:%s" % ability_id
	if _active_stance_buff_id != "" and _active_stance_buff_id != new_buff_id:
		p.c_buffs.remove_buff(_active_stance_buff_id)
	_active_stance_buff_id = new_buff_id
	if ability_id == "":
		return
	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_rank_data"):
		return
	var rank := 0
	if p.c_spellbook != null:
		rank = int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	if rank <= 0 and db.has_method("get_rank_for_level"):
		rank = int(db.call("get_rank_for_level", ability_id, p.level))
	if rank <= 0:
		return
	var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return

	var data := {
		"source_ability": ability_id,
		"ability_id": ability_id,
		"kind": "stance"
	}
	match ability_id:
		"path_of_righteousness":
			data["on_hit_magic_bonus"] = rank_data.value
		"path_of_light":
			data["lifesteal_pct"] = rank_data.value
		"path_of_righteous_fury":
			data["mana_on_hit_pct"] = rank_data.value
	p.c_buffs.add_or_refresh_buff(new_buff_id, 999999.0, data)

func _finish_cast(payload: Dictionary) -> void:
	var ability_id := String(payload.get("ability_id", ""))
	var def: AbilityDefinition = payload.get("def") as AbilityDefinition
	var rank_data: RankData = payload.get("rank_data") as RankData
	var actual_target: Node = payload.get("target")

	if def == null or rank_data == null:
		return

	if def.target_type == "self":
		actual_target = p
	elif actual_target != null and not is_instance_valid(actual_target):
		actual_target = null
	elif actual_target == null and def.target_type == "ally":
		actual_target = p

	if actual_target == null and def.ability_type != "aoe_damage":
		return

	_apply_ability_effect(ability_id, def, rank_data, actual_target)

func _apply_ability_effect(ability_id: String, def: AbilityDefinition, rank_data: RankData, actual_target: Node) -> void:
	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))

	match def.ability_type:
		"buff":
			var secondary := {}
			var percent := {}
			var primary := {}
			match ability_id:
				"lightbound_might":
					secondary["attack_power"] = rank_data.value
				"lights_guidance":
					secondary["mana_regen"] = rank_data.value
				"royal_oath":
					percent["attack_power"] = 0.10
					percent["spell_power"] = 0.10
					percent["defense"] = 0.10
					percent["magic_resist"] = 0.10
			var data := {
				"source_ability": ability_id,
				"ability_id": ability_id,
				"kind": "buff",
				"secondary": secondary,
				"percent": percent,
				"primary": primary
			}
			var buff_target: Node = actual_target
			if buff_target == null or not buff_target.has_method("add_or_refresh_buff"):
				buff_target = p
			buff_target.call("add_or_refresh_buff", "buff:%s" % ability_id, rank_data.duration_sec, data)
		"heal":
			var raw_heal: int = rank_data.value + int(round(spell_power * STAT_CONST.SP_DAMAGE_SCALAR))
			var final_heal: int = STAT_CALC.apply_crit_to_heal(raw_heal, snap)
			_apply_heal_to_target(actual_target, final_heal)
		"damage":
			if ability_id == "strike_of_light":
				var base_phys: int = 0
				if p.c_combat != null:
					base_phys = p.c_combat.get_attack_damage()
				var phys: int = int(round(float(base_phys) * float(rank_data.value) / 100.0))
				phys = STAT_CALC.apply_crit_to_damage(phys, snap)
				DAMAGE_HELPER.apply_damage_typed(p, actual_target, phys, "physical")

				var mag_raw: int = rank_data.value2 + int(round(spell_power * STAT_CONST.SP_DAMAGE_SCALAR))
				var mag: int = STAT_CALC.apply_crit_to_damage(mag_raw, snap)
				DAMAGE_HELPER.apply_damage_typed(p, actual_target, mag, "magic")
			else:
				var raw: int = rank_data.value + int(round(spell_power * STAT_CONST.SP_DAMAGE_SCALAR))
				var final: int = STAT_CALC.apply_crit_to_damage(raw, snap)
				DAMAGE_HELPER.apply_damage_typed(p, actual_target, final, "magic")
		"aoe_damage":
			var radius: float = PlayerCombat.MELEE_ATTACK_RANGE
			var base_phys2: int = 0
			if p.c_combat != null:
				base_phys2 = p.c_combat.get_attack_damage()
			var nodes := get_tree().get_nodes_in_group("faction_units")
			for node in nodes:
				if not (node is Node2D):
					continue
				var target: Node2D = node as Node2D
				if target == null or not is_instance_valid(target):
					continue
				if target == p:
					continue
				var target_faction := ""
				if target.has_method("get_faction_id"):
					target_faction = String(target.call("get_faction_id"))
				if not FactionRules.can_attack(p.faction_id, target_faction, true):
					continue
				if p.global_position.distance_to(target.global_position) > radius:
					continue

				var phys_raw: int = int(round(float(base_phys2) * float(rank_data.value) / 100.0))
				var phys_final: int = STAT_CALC.apply_crit_to_damage(phys_raw, snap)
				DAMAGE_HELPER.apply_damage_typed(p, target, phys_final, "physical")

				var mag_raw2: int = rank_data.value2 + int(round(spell_power * STAT_CONST.SP_DAMAGE_SCALAR))
				var mag_final2: int = STAT_CALC.apply_crit_to_damage(mag_raw2, snap)
				DAMAGE_HELPER.apply_damage_typed(p, target, mag_final2, "magic")
		"active":
			match ability_id:
				"prayer_to_the_light":
					var mana_gain: int = int(ceil(float(p.max_mana) * float(rank_data.value) / 100.0))
					if mana_gain > 0:
						p.mana = min(p.max_mana, p.mana + mana_gain)
				"sacred_barrier":
					var data := {
						"source_ability": ability_id,
						"ability_id": ability_id,
						"kind": "buff",
						"invulnerable": true
					}
					p.add_or_refresh_buff("buff:%s" % ability_id, rank_data.duration_sec, data)
		_:
			pass

func _apply_heal_to_target(target: Node, heal_amount: int) -> void:
	if target == null or heal_amount <= 0:
		return
	if "current_hp" in target and "max_hp" in target:
		target.current_hp = min(target.max_hp, target.current_hp + heal_amount)
		return
	if "c_stats" in target and target.c_stats != null:
		var stats = target.c_stats
		if "current_hp" in stats and "max_hp" in stats:
			stats.current_hp = min(stats.max_hp, stats.current_hp + heal_amount)
			if target.has_method("_update_hp"):
				target.call("_update_hp")
			elif "hp_fill" in target and target.hp_fill != null and stats.has_method("update_hp_bar"):
				stats.update_hp_bar(target.hp_fill)

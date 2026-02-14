extends Node
class_name PlayerAbilityCaster

var p: Player = null
var _cooldowns: Dictionary = {} # ability_id -> time_left
var _cast_time_left: float = 0.0
var _cast_total_time: float = 0.0
var _cast_payload: Dictionary = {}

func setup(player: Player) -> void:
	p = player

func tick(delta: float) -> void:
	if _cast_time_left > 0.0:
		_cast_time_left = max(0.0, _cast_time_left - delta)
		if _cast_time_left <= 0.0 and not _cast_payload.is_empty():
			_finish_cast(_cast_payload)
			_cast_payload = {}
			_cast_total_time = 0.0

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
		interrupt_cast("ability_input")
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
	if def.ability_type == "aura" or def.ability_type == "stance" or def.ability_type == "hidden_passive":
		return {"ok": false, "reason": "passive"}

	var rank_data: RankData = null
	if db.has_method("get_rank_data"):
		rank_data = db.call("get_rank_data", ability_id, rank)
	if rank_data == null:
		return {"ok": false, "reason": "no_rank"}

	if def.effect == null:
		return {"ok": false, "reason": "no_effect"}

	if get_cooldown_left(ability_id) > 0.0:
		return {"ok": false, "reason": "cooldown"}

	var target_result := _resolve_cast_target(def, target)
	if not bool(target_result.get("ok", false)):
		return {"ok": false, "reason": String(target_result.get("reason", "invalid_target"))}
	var actual_target: Node = target_result.get("target") as Node

	if def.target_type == "corpse_player" and p != null and p.has_method("is_in_combat") and bool(p.call("is_in_combat")):
		return {"ok": false, "reason": "in_combat"}

	if ability_id == "light_execution":
		var hp_threshold: float = float(rank_data.value_pct)
		if actual_target == null or not _is_execute_target_valid(actual_target, hp_threshold):
			return {"ok": false, "reason": "invalid_execute_target"}

	var snap: Dictionary = {}
	if p.has_method("get_stats_snapshot"):
		snap = p.call("get_stats_snapshot") as Dictionary

	var cost: int = int(ceil(float(p.max_mana) * float(rank_data.resource_cost) / 100.0))
	if cost > 0 and p.mana < cost:
		return {"ok": false, "reason": "no_mana"}

	var cdr_pct: float = float(snap.get("cooldown_reduction_pct", 0.0))
	var cd_eff: float = max(0.0, rank_data.cooldown_sec * (1.0 - cdr_pct / 100.0))

	var cast_speed_pct: float = float(snap.get("cast_speed_pct", 0.0))
	var cast_mult: float = 1.0 / (1.0 + cast_speed_pct / 100.0)
	var cast_time_eff: float = rank_data.cast_time_sec * cast_mult
	if cast_time_eff > 0.0:
		_cast_time_left = cast_time_eff
		_cast_total_time = cast_time_eff
		_cast_payload = {
			"ability_id": ability_id,
			"target": actual_target,
			"def": def,
			"rank_data": rank_data,
			"cost": cost,
			"cooldown": cd_eff,
		}
		return {"ok": true, "reason": "casting", "target": actual_target}

	if cost > 0:
		p.mana -= cost
	_apply_ability_effect(ability_id, def, rank_data, actual_target)
	_start_cooldown(ability_id, cd_eff)
	return {"ok": true, "reason": "", "target": actual_target}

func get_targeting_preview(ability_id: String, target: Node) -> Dictionary:
	if ability_id == "":
		return {"ok": false, "reason": "empty"}
	if p == null or p.c_spellbook == null:
		return {"ok": false, "reason": "no_spellbook"}
	var rank := int(p.c_spellbook.learned_ranks.get(ability_id, 0))
	if rank <= 0:
		return {"ok": false, "reason": "not_learned"}

	var db := get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return {"ok": false, "reason": "no_db"}
	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def == null:
		return {"ok": false, "reason": "no_def"}
	if def.ability_type == "aura" or def.ability_type == "stance" or def.ability_type == "hidden_passive":
		return {"ok": false, "reason": "passive"}

	var target_result := _resolve_cast_target(def, target)
	if not bool(target_result.get("ok", false)):
		return {"ok": false, "reason": String(target_result.get("reason", "invalid_target"))}
	return {"ok": true, "target": target_result.get("target")}

func interrupt_cast(_reason: String = "interrupted") -> void:
	if _cast_time_left <= 0.0:
		return
	_cast_time_left = 0.0
	_cast_total_time = 0.0
	_cast_payload = {}

func is_casting() -> bool:
	return _cast_time_left > 0.0

func get_cast_progress() -> float:
	if _cast_total_time <= 0.0:
		return 0.0
	return clamp(1.0 - (_cast_time_left / _cast_total_time), 0.0, 1.0)

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
	if ability_id == "":
		p.c_buffs.remove_buff("active_aura")
		return
	p.c_buffs.remove_buffs_with_prefix("aura:")
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

	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def == null or def.effect == null:
		return
	def.effect.apply(p, p, rank_data, _build_context(ability_id, def, {}))

func apply_active_stance(ability_id: String) -> void:
	if p == null or p.c_buffs == null:
		return
	if ability_id == "":
		p.c_buffs.remove_buff("active_stance")
		return
	p.c_buffs.remove_buffs_with_prefix("stance:")
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

	var def: AbilityDefinition = db.call("get_ability", ability_id)
	if def == null or def.effect == null:
		return
	def.effect.apply(p, p, rank_data, _build_context(ability_id, def, {}))

func _finish_cast(payload: Dictionary) -> void:
	var ability_id := String(payload.get("ability_id", ""))
	var def: AbilityDefinition = payload.get("def") as AbilityDefinition
	var rank_data: RankData = payload.get("rank_data") as RankData
	var actual_target: Node = payload.get("target")
	var cost: int = int(payload.get("cost", 0))
	var cooldown: float = float(payload.get("cooldown", 0.0))

	if def == null or rank_data == null:
		return
	if def.effect == null:
		return

	if actual_target != null and not is_instance_valid(actual_target):
		actual_target = null
	var target_result := _normalize_target(def, actual_target)
	if not bool(target_result.get("ok", false)):
		return
	actual_target = target_result.get("target") as Node

	if cost > 0:
		if p == null or p.mana < cost:
			return
		p.mana -= cost

	_apply_ability_effect(ability_id, def, rank_data, actual_target)
	_start_cooldown(ability_id, cooldown)

func _start_cooldown(ability_id: String, duration: float) -> void:
	if ability_id == "" or duration <= 0.0:
		return
	_cooldowns[ability_id] = duration

func _apply_ability_effect(ability_id: String, def: AbilityDefinition, rank_data: RankData, actual_target: Node) -> void:
	if def == null or def.effect == null:
		return
	var context := _build_context(ability_id, def, {})
	if actual_target != null and actual_target.has_method("get_stats_snapshot"):
		context["target_snapshot"] = actual_target.call("get_stats_snapshot") as Dictionary
	def.effect.apply(p, actual_target, rank_data, context)

func _build_context(ability_id: String, def: AbilityDefinition, extra: Dictionary) -> Dictionary:
	var context := {
		"ability_id": ability_id,
		"ability_def": def,
	}
	if p != null and p.has_method("get_stats_snapshot"):
		context["caster_snapshot"] = p.call("get_stats_snapshot") as Dictionary
	for k in extra.keys():
		context[k] = extra[k]
	return context

func _resolve_cast_target(def: AbilityDefinition, target: Node) -> Dictionary:
	var target_result := _normalize_target(def, target)
	if not bool(target_result.get("ok", false)):
		return target_result
	var actual_target: Node = target_result.get("target") as Node

	var range_mode := def.range_mode
	if range_mode != "self" and actual_target is Node2D:
		var range: float = PlayerCombat.RANGED_ATTACK_RANGE
		if range_mode == "melee":
			range = PlayerCombat.MELEE_ATTACK_RANGE
		var dist: float = p.global_position.distance_to((actual_target as Node2D).global_position)
		if dist > range:
			return {"ok": false, "reason": "out_of_range"}
	elif range_mode != "self" and not (actual_target is Node2D):
		return {"ok": false, "reason": "no_target"}

	return {"ok": true, "target": actual_target}

func _normalize_target(def: AbilityDefinition, target: Node) -> Dictionary:
	if def == null or p == null:
		return {"ok": false, "reason": "invalid"}
	var actual_target: Node = target
	match def.target_type:
		"self":
			actual_target = p
		"ally":
			if actual_target == null or _is_hostile_target(actual_target):
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "invalid_target"}
		"enemy":
			if actual_target == null:
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "no_target"}
			if actual_target == p:
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "no_target"}
			if not _is_hostile_target(actual_target):
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "invalid_target"}
		"ally_or_enemy":
			if actual_target == null:
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "no_target"}
			if actual_target != p and not _is_hostile_target(actual_target) and not _is_friendly_target(actual_target):
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "invalid_target"}
		"corpse_player":
			if actual_target == null or not (actual_target is Corpse):
				return {"ok": false, "reason": "invalid_target"}
			var corpse := actual_target as Corpse
			if corpse == null or not corpse.owner_is_player:
				return {"ok": false, "reason": "invalid_target"}
			if corpse.owner_entity_id == 0:
				return {"ok": false, "reason": "invalid_target"}
		"any":
			if actual_target == null:
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "no_target"}
		_:
			if actual_target == null:
				if _can_fallback_to_self(def):
					actual_target = p
				else:
					return {"ok": false, "reason": "no_target"}
	return {"ok": true, "target": actual_target}

func _is_execute_target_valid(target: Node, threshold_pct: float) -> bool:
	if target == null:
		return false
	var current_hp: float = 0.0
	var max_hp: float = 0.0
	if "current_hp" in target and "max_hp" in target:
		current_hp = float(target.current_hp)
		max_hp = float(target.max_hp)
	elif target.has_method("get_current_hp") and target.has_method("get_max_hp"):
		current_hp = float(target.call("get_current_hp"))
		max_hp = float(target.call("get_max_hp"))
	if max_hp <= 0.0:
		return false
	var hp_pct: float = (current_hp / max_hp) * 100.0
	return hp_pct < threshold_pct

func _can_fallback_to_self(def: AbilityDefinition) -> bool:
	if def == null:
		return false
	# Ally spells are expected to be self-castable by default.
	if def.target_type == "ally" or def.target_type == "self":
		return true
	return bool(def.self_cast_fallback)

func _is_hostile_target(target: Node) -> bool:
	var caster_faction := ""
	if p != null and p.has_method("get_faction_id"):
		caster_faction = String(p.call("get_faction_id"))
	var target_faction := ""
	if target != null and target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	return FactionRules.relation(caster_faction, target_faction) == FactionRules.Relation.HOSTILE

func _is_friendly_target(target: Node) -> bool:
	var caster_faction := ""
	if p != null and p.has_method("get_faction_id"):
		caster_faction = String(p.call("get_faction_id"))
	var target_faction := ""
	if target != null and target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	return FactionRules.relation(caster_faction, target_faction) == FactionRules.Relation.FRIENDLY

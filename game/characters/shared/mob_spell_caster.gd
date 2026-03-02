extends RefCounted
class_name MobSpellCaster

const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

var _owner: Node = null
var _ability_ids: Array[String] = []
var _ability_ranks: Dictionary = {}
var _cooldowns: Dictionary = {}
var _next_index: int = 0

func setup(owner: Node) -> void:
	_owner = owner

func configure(ability_ids: Array[String], actor_level: int) -> void:
	_ability_ids = ability_ids.duplicate()
	_ability_ranks.clear()
	_cooldowns.clear()
	_next_index = 0
	var db: Node = _owner.get_node_or_null("/root/AbilityDB") if _owner != null else null
	if db == null:
		return
	for ability_id in _ability_ids:
		var rank := int(db.call("get_rank_for_level", ability_id, actor_level)) if db.has_method("get_rank_for_level") else 0
		if rank > 0:
			_ability_ranks[ability_id] = rank

func tick(delta: float, preferred_target: Node) -> void:
	if _owner == null:
		return
	for k in _cooldowns.keys():
		var ability_id: String = String(k)
		var left: float = max(0.0, float(_cooldowns.get(ability_id, 0.0)) - delta)
		if left <= 0.0:
			_cooldowns.erase(ability_id)
		else:
			_cooldowns[ability_id] = left
	if _ability_ids.is_empty() or _ability_ranks.is_empty():
		return

	var db: Node = _owner.get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability") or not db.has_method("get_rank_data"):
		return

	for i in range(_ability_ids.size()):
		var idx := (_next_index + i) % _ability_ids.size()
		var ability_id: String = _ability_ids[idx]
		if float(_cooldowns.get(ability_id, 0.0)) > 0.0:
			continue
		var rank := int(_ability_ranks.get(ability_id, 0))
		if rank <= 0:
			continue
		var def: AbilityDefinition = db.call("get_ability", ability_id)
		if def == null or def.effect == null:
			continue
		var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
		if rank_data == null:
			continue
		if not _has_enough_resource(int(rank_data.resource_cost)):
			continue
		var target := _resolve_target(def, preferred_target)
		if target == null:
			continue
		if not _is_in_range(target, String(def.range_mode)):
			continue
		_apply_ability(ability_id, def, rank_data, target)
		_next_index = (idx + 1) % _ability_ids.size()
		return

func _has_enough_resource(cost: int) -> bool:
	if cost <= 0:
		return true
	if _owner == null or not ("c_resource" in _owner):
		return true
	var rc: ResourceComponent = _owner.c_resource
	if rc == null:
		return true
	return int(rc.resource) >= cost

func _spend_resource(cost: int) -> void:
	if cost <= 0:
		return
	if _owner == null or not ("c_resource" in _owner):
		return
	var rc: ResourceComponent = _owner.c_resource
	if rc == null:
		return
	rc.add(-cost)

func _resolve_target(def: AbilityDefinition, preferred_target: Node) -> Node:
	if _owner == null:
		return null
	match String(def.target_type):
		"self":
			return _owner
		"ally":
			return _owner
		"enemy":
			return preferred_target
		"ally_or_enemy":
			if preferred_target != null and _is_friendly(preferred_target):
				return preferred_target
			if preferred_target != null:
				return preferred_target
			return _owner
		_:
			return preferred_target if preferred_target != null else _owner

func _is_friendly(target: Node) -> bool:
	if _owner == null or target == null:
		return false
	if not _owner.has_method("get_faction_id") or not target.has_method("get_faction_id"):
		return false
	var a := String(_owner.call("get_faction_id"))
	var b := String(target.call("get_faction_id"))
	return FactionRules.relation(a, b) == FactionRules.Relation.FRIENDLY

func _is_in_range(target: Node, range_mode: String) -> bool:
	if _owner == null:
		return false
	if range_mode == "self":
		return true
	if not (_owner is Node2D) or not (target is Node2D):
		return false
	var max_range := COMBAT_RANGES.RANGED_ATTACK_RANGE_BASE
	var rm := range_mode.strip_edges().to_lower()
	if rm == "melee":
		max_range = COMBAT_RANGES.MELEE_ATTACK_RANGE
	var dist := (_owner as Node2D).global_position.distance_to((target as Node2D).global_position)
	return dist <= max_range

func _apply_ability(ability_id: String, def: AbilityDefinition, rank_data: RankData, target: Node) -> void:
	if _owner == null:
		return
	_spend_resource(int(rank_data.resource_cost))
	var context := {
		"ability_id": ability_id,
		"ability_def": def,
		"caster_snapshot": _get_stats_snapshot(_owner),
		"caster_attack_damage": _get_attack_damage(),
	}
	if target != null:
		context["target_snapshot"] = _get_stats_snapshot(target)
	def.effect.apply(_owner, target, rank_data, context)
	var cd := float(rank_data.cooldown_sec)
	if cd > 0.0:
		_cooldowns[ability_id] = cd

func _get_stats_snapshot(node: Node) -> Dictionary:
	if node == null:
		return {}
	if node.has_method("get_stats_snapshot"):
		return node.call("get_stats_snapshot") as Dictionary
	if "c_stats" in node and node.c_stats != null and node.c_stats.has_method("get_stats_snapshot"):
		return node.c_stats.call("get_stats_snapshot") as Dictionary
	return {}

func _get_attack_damage() -> int:
	if _owner == null or not ("c_combat" in _owner) or _owner.c_combat == null:
		return 0
	if _owner.c_combat.has_method("get_attack_damage"):
		return int(_owner.c_combat.call("get_attack_damage"))
	return 0

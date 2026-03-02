extends RefCounted
class_name MobSpellCaster

const COMBAT_RANGES := preload("res://core/combat/combat_ranges.gd")

var _owner: Node = null
var _ability_ids: Array[String] = []
var _ability_ranks: Dictionary = {}
var _cooldowns: Dictionary = {}
var _next_index: int = 0

var _cast_time_left: float = 0.0
var _cast_total_time: float = 0.0
var _cast_payload: Dictionary = {}

var _heal_lock: bool = false
var _mana_lock: bool = false
var _stationary_cooldown_left: float = 0.0

func setup(owner: Node) -> void:
	_owner = owner

func configure(ability_ids: Array[String], actor_level: int) -> void:
	_ability_ids.clear()
	_ability_ranks.clear()
	_cooldowns.clear()
	_next_index = 0
	_cast_time_left = 0.0
	_cast_total_time = 0.0
	_cast_payload = {}
	_heal_lock = false
	_mana_lock = false
	_stationary_cooldown_left = 0.0

	var db: Node = _owner.get_node_or_null("/root/AbilityDB") if _owner != null else null
	if db == null or not db.has_method("get_ability") or not db.has_method("get_rank_for_level") or not db.has_method("get_rank_data"):
		return

	for ability_id in ability_ids:
		var rank := int(db.call("get_rank_for_level", ability_id, actor_level))
		if rank <= 0:
			continue
		var def: AbilityDefinition = db.call("get_ability", ability_id)
		if def == null or def.effect == null:
			continue
		var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
		if rank_data == null:
			continue

		# Aura/Stance/Passive are applied immediately and excluded from rotation.
		var t := String(def.ability_type).to_lower()
		if t == "aura" or t == "stance" or t == "passive":
			_apply_ability_instant(ability_id, def, rank_data, _owner, false)
			continue

		_ability_ids.append(ability_id)
		_ability_ranks[ability_id] = rank

func tick(delta: float, preferred_target: Node) -> void:
	if _owner == null:
		return
	_tick_cooldowns(delta)
	_update_state_locks()
	if _owner_is_stunned():
		interrupt_cast("stunned")
		return
	if _owner_is_moving():
		_stationary_cooldown_left = 0.2
		if _cast_time_left > 0.0:
			interrupt_cast("movement")
		return
	if _stationary_cooldown_left > 0.0:
		_stationary_cooldown_left = max(0.0, _stationary_cooldown_left - delta)
		if _stationary_cooldown_left > 0.0:
			return

	if _cast_time_left > 0.0:
		_cast_time_left = max(0.0, _cast_time_left - delta)
		if _cast_time_left <= 0.0 and not _cast_payload.is_empty():
			_finish_cast()
		return

	if _ability_ids.is_empty() or _ability_ranks.is_empty():
		return
	if _mana_lock:
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
		if _heal_lock and not _is_heal_ability(def):
			continue
		if not _heal_lock and _is_heal_ability(def):
			continue

		var rank_data: RankData = db.call("get_rank_data", ability_id, rank)
		if rank_data == null:
			continue
		if not _has_enough_resource(int(rank_data.resource_cost)):
			continue

		if String(def.ability_type).to_lower() == "buff" and _has_active_own_buff(ability_id):
			continue

		var target := _resolve_target(def, preferred_target)
		if target == null:
			continue
		if not _is_in_range(target, String(def.range_mode)):
			continue

		if float(rank_data.cast_time_sec) > 0.0:
			_start_cast(ability_id, def, rank_data, target)
		else:
			_apply_ability_instant(ability_id, def, rank_data, target, true)
		_next_index = (idx + 1) % _ability_ids.size()
		return

func should_block_auto_attack() -> bool:
	if _cast_time_left > 0.0:
		return true
	if _heal_lock:
		return true
	return false


func interrupt_cast(_reason: String = "interrupted") -> void:
	if _cast_time_left <= 0.0 and _cast_payload.is_empty():
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

func get_cast_icon() -> Texture2D:
	if _cast_payload.is_empty():
		return null
	var def: AbilityDefinition = _cast_payload.get("def") as AbilityDefinition
	if def == null:
		return null
	return def.icon

func _start_cast(ability_id: String, def: AbilityDefinition, rank_data: RankData, target: Node) -> void:
	_cast_time_left = max(0.0, float(rank_data.cast_time_sec))
	_cast_total_time = _cast_time_left
	_cast_payload = {
		"ability_id": ability_id,
		"def": def,
		"rank_data": rank_data,
		"target": target,
		"cost": int(rank_data.resource_cost),
	}

func _finish_cast() -> void:
	if _cast_payload.is_empty():
		return
	var ability_id := String(_cast_payload.get("ability_id", ""))
	var def: AbilityDefinition = _cast_payload.get("def") as AbilityDefinition
	var rank_data: RankData = _cast_payload.get("rank_data") as RankData
	var target: Node = _cast_payload.get("target") as Node
	if ability_id != "" and def != null and rank_data != null:
		if target == null:
			target = _owner
		if _has_enough_resource(int(_cast_payload.get("cost", 0))):
			_apply_ability_instant(ability_id, def, rank_data, target, true)
	_cast_payload = {}
	_cast_total_time = 0.0
	_cast_time_left = 0.0

func _tick_cooldowns(delta: float) -> void:
	for k in _cooldowns.keys():
		var ability_id: String = String(k)
		var left: float = max(0.0, float(_cooldowns.get(ability_id, 0.0)) - delta)
		if left <= 0.0:
			_cooldowns.erase(ability_id)
		else:
			_cooldowns[ability_id] = left

func _update_state_locks() -> void:
	var hp_pct := _owner_health_pct()
	if _has_heal_abilities() and hp_pct <= 0.5:
		_heal_lock = true
	elif _heal_lock and hp_pct >= 0.9:
		_heal_lock = false

	var mana_ratio := _owner_mana_ratio()
	if _mana_lock:
		if mana_ratio >= 0.15:
			_mana_lock = false
	else:
		if _owner_current_mana() <= 0:
			_mana_lock = true


func _owner_is_moving() -> bool:
	if _owner == null:
		return false
	if "velocity" in _owner:
		var v: Variant = _owner.get("velocity")
		if v is Vector2:
			return (v as Vector2).length_squared() > 0.0001
	return false

func _owner_is_stunned() -> bool:
	if _owner == null:
		return false
	if "c_buffs" in _owner and _owner.c_buffs != null and _owner.c_buffs.has_method("is_stunned"):
		return bool(_owner.c_buffs.call("is_stunned"))
	if "c_stats" in _owner and _owner.c_stats != null and _owner.c_stats.has_method("is_stunned"):
		return bool(_owner.c_stats.call("is_stunned"))
	return false

func _owner_health_pct() -> float:
	var stats := _owner_stats_node()
	if stats == null:
		return 1.0
	if not ("current_hp" in stats) or not ("max_hp" in stats):
		return 1.0
	var mx: float = max(1.0, float(stats.max_hp))
	return clamp(float(stats.current_hp) / mx, 0.0, 1.0)

func _owner_current_mana() -> int:
	if _owner == null or not ("c_resource" in _owner):
		return 1
	var rc: ResourceComponent = _owner.c_resource
	if rc == null or rc.resource_type != "mana":
		return 1
	return int(rc.resource)

func _owner_mana_ratio() -> float:
	if _owner == null or not ("c_resource" in _owner):
		return 1.0
	var rc: ResourceComponent = _owner.c_resource
	if rc == null or rc.resource_type != "mana":
		return 1.0
	if rc.max_resource <= 0:
		return 0.0
	return clamp(float(rc.resource) / float(rc.max_resource), 0.0, 1.0)

func _has_heal_abilities() -> bool:
	var db: Node = _owner.get_node_or_null("/root/AbilityDB")
	if db == null or not db.has_method("get_ability"):
		return false
	for ability_id in _ability_ids:
		var def: AbilityDefinition = db.call("get_ability", ability_id)
		if def != null and _is_heal_ability(def):
			return true
	return false

func _is_heal_ability(def: AbilityDefinition) -> bool:
	if def == null or def.effect == null:
		return false
	var c := String(def.effect.get_class()).to_lower()
	return c.find("heal") != -1

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
	if _heal_lock and _is_heal_ability(def):
		return _owner
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

func _apply_ability_instant(ability_id: String, def: AbilityDefinition, rank_data: RankData, target: Node, start_cd: bool) -> void:
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
	if start_cd:
		var cd := float(rank_data.cooldown_sec)
		if cd > 0.0:
			_cooldowns[ability_id] = cd

func _has_active_own_buff(ability_id: String) -> bool:
	var buffs := _get_buffs_snapshot(_owner)
	var owner_id := _owner.get_instance_id() if _owner != null else 0
	for e in buffs:
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		if String(d.get("source", "")) != "buff":
			continue
		if String(d.get("ability_id", "")) != ability_id:
			continue
		var data: Dictionary = d.get("data", {}) as Dictionary
		if int(data.get("caster_owner_id", 0)) == owner_id:
			return true
	return false

func _owner_stats_node() -> Node:
	if _owner == null:
		return null
	if "c_stats" in _owner and _owner.c_stats != null:
		return _owner.c_stats
	return null

func _get_buffs_snapshot(node: Node) -> Array:
	if node == null:
		return []
	if node.has_method("get_buffs_snapshot"):
		return node.call("get_buffs_snapshot") as Array
	if "c_buffs" in node and node.c_buffs != null and node.c_buffs.has_method("get_buffs_snapshot"):
		return node.c_buffs.call("get_buffs_snapshot") as Array
	if "c_stats" in node and node.c_stats != null and node.c_stats.has_method("get_buffs_snapshot"):
		return node.c_stats.call("get_buffs_snapshot") as Array
	return []

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

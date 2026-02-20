extends AbilityEffect
class_name EffectMultiShotDamage

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const PLAYER_COMBAT := preload("res://game/characters/player/components/player_combat.gd")

@export var school: String = "physical" # physical | magic
@export var scaling_mode: String = "phys_base_pct" # flat | phys_base_pct | spell_power_flat | attack_power_pct
@export var max_targets: int = 3

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or rank_data == null:
		return
	if caster.get_tree() == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base_damage: int = _compute_base_damage(caster, rank_data, snap)
	if base_damage <= 0:
		return

	var limit: int = int(rank_data.flags.get("max_targets", max_targets))
	if limit <= 0:
		return

	var primary_target: Node2D = null
	if target is Node2D and is_instance_valid(target):
		primary_target = target as Node2D

	var cast_range: float = _resolve_cast_range(context)
	var targets: Array[Node2D] = _collect_targets(caster, primary_target, cast_range, limit)
	for t in targets:
		var final_damage: int = STAT_CALC.apply_crit_to_damage_typed(base_damage, snap, school)
		DAMAGE_HELPER.apply_damage_typed(caster, t, final_damage, school)

func _compute_base_damage(caster: Node, rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	var attack_power: float = float(derived.get("attack_power", 0.0))

	match scaling_mode:
		"flat":
			return int(rank_data.value_flat)
		"phys_base_pct":
			var base_phys: int = 0
			if "c_combat" in caster and caster.c_combat != null:
				base_phys = caster.c_combat.get_attack_damage()
			return int(round(float(base_phys) * float(rank_data.value_pct) / 100.0))
		"spell_power_flat":
			return int(rank_data.value_flat) + int(round(spell_power))
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat)

func _collect_targets(caster: Node, primary_target: Node2D, cast_range: float, limit: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if caster == null or caster.get_tree() == null:
		return out

	if primary_target != null and _is_valid_enemy_target(caster, primary_target):
		var primary_dist: float = caster.global_position.distance_to(primary_target.global_position)
		if primary_dist <= cast_range:
			out.append(primary_target)

	var candidates: Array[Dictionary] = []
	var nodes := caster.get_tree().get_nodes_in_group("faction_units")
	for node in nodes:
		if not (node is Node2D):
			continue
		var unit := node as Node2D
		if unit == null or not is_instance_valid(unit):
			continue
		if unit == caster:
			continue
		if out.has(unit):
			continue
		if not _is_valid_enemy_target(caster, unit):
			continue
		var dist: float = caster.global_position.distance_to(unit.global_position)
		if dist > cast_range:
			continue
		candidates.append({"node": unit, "dist": dist})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("dist", INF)) < float(b.get("dist", INF))
	)

	for item in candidates:
		if out.size() >= limit:
			break
		out.append(item.get("node") as Node2D)

	return out

func _resolve_cast_range(context: Dictionary) -> float:
	var def: AbilityDefinition = context.get("ability_def") as AbilityDefinition
	if def == null:
		return PLAYER_COMBAT.RANGED_ATTACK_RANGE
	var rm := String(def.range_mode).strip_edges().to_lower()
	if rm == "melee":
		return PLAYER_COMBAT.MELEE_ATTACK_RANGE
	if rm == "self":
		return PLAYER_COMBAT.MELEE_ATTACK_RANGE
	if rm == "ranged" or rm == "":
		return PLAYER_COMBAT.RANGED_ATTACK_RANGE
	if rm.begins_with("ranged"):
		var cleaned := rm.replace(" ", "")
		if cleaned.begins_with("ranged+") and cleaned.ends_with("%"):
			var pct_str := cleaned.substr(7, cleaned.length() - 8)
			var pct := float(pct_str)
			return PLAYER_COMBAT.RANGED_ATTACK_RANGE * (1.0 + pct / 100.0)
	return PLAYER_COMBAT.RANGED_ATTACK_RANGE

func _is_valid_enemy_target(caster: Node, target: Node) -> bool:
	if caster == null or target == null:
		return false
	var caster_faction := ""
	if caster.has_method("get_faction_id"):
		caster_faction = String(caster.call("get_faction_id"))
	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	var rel := FactionRules.relation(caster_faction, target_faction)
	if rel == FactionRules.Relation.HOSTILE:
		return true
	if rel != FactionRules.Relation.NEUTRAL:
		return false
	if "current_target" in target and target.current_target == caster:
		return true
	if "aggressor" in target and target.aggressor == caster:
		return true
	return false

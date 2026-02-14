extends AbilityEffect
class_name EffectChainDamage

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const PLAYER_COMBAT := preload("res://game/characters/player/components/player_combat.gd")

@export var school: String = "magic" # physical | magic
@export var scaling_mode: String = "spell_power_flat" # flat | phys_base_pct | spell_power_flat
@export var jump_count: int = 2 # number of additional jumps after primary target
@export var jump_damage_decay_pct: float = 30.0 # each next hit deals this percent less than previous
@export var jump_radius_factor: float = 0.5 # jump radius = cast_range * factor

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (target is Node2D):
		return
	if caster.get_tree() == null:
		return
	if not _is_hostile_target(caster, target):
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base_damage: int = _compute_base_damage(caster, rank_data, snap)
	if base_damage <= 0:
		return

	var remaining_jumps: int = max(0, int(rank_data.flags.get("jump_count", jump_count)))
	var decay_pct: float = float(rank_data.flags.get("jump_damage_decay_pct", jump_damage_decay_pct))
	var decay_mult: float = clamp(1.0 - decay_pct / 100.0, 0.0, 1.0)
	var radius_factor: float = float(rank_data.flags.get("jump_radius_factor", jump_radius_factor))
	if radius_factor <= 0.0:
		radius_factor = 0.5
	var jump_radius: float = _get_cast_range(context) * radius_factor

	var hit_targets: Array[Node2D] = []
	var current_target: Node2D = target as Node2D
	var hit_index: int = 0

	while current_target != null and is_instance_valid(current_target):
		hit_targets.append(current_target)
		_apply_single_hit(caster, current_target, base_damage, decay_mult, hit_index, snap)
		if remaining_jumps <= 0:
			break
		var next_target := _find_next_target(caster, current_target, hit_targets, jump_radius)
		if next_target == null:
			break
		current_target = next_target
		hit_index += 1
		remaining_jumps -= 1

func _compute_base_damage(caster: Node, rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))

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
		_:
			return int(rank_data.value_flat)

func _apply_single_hit(caster: Node, target: Node2D, base_damage: int, decay_mult: float, hit_index: int, snap: Dictionary) -> void:
	var scaled: int = int(round(float(base_damage) * pow(decay_mult, float(hit_index))))
	if scaled <= 0:
		return
	var final_damage: int = STAT_CALC.apply_crit_to_damage_typed(scaled, snap, school)
	DAMAGE_HELPER.apply_damage_typed(caster, target, final_damage, school)

func _find_next_target(caster: Node, from_target: Node2D, hit_targets: Array[Node2D], jump_radius: float) -> Node2D:
	if caster == null or from_target == null or caster.get_tree() == null:
		return null
	var nodes := caster.get_tree().get_nodes_in_group("faction_units")
	var best: Node2D = null
	var best_dist: float = INF

	for node in nodes:
		if not (node is Node2D):
			continue
		var candidate := node as Node2D
		if candidate == null or not is_instance_valid(candidate):
			continue
		if candidate == caster:
			continue
		if hit_targets.has(candidate):
			continue
		if not _is_hostile_target(caster, candidate):
			continue
		var dist: float = from_target.global_position.distance_to(candidate.global_position)
		if dist > jump_radius:
			continue
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best

func _get_cast_range(context: Dictionary) -> float:
	var def: AbilityDefinition = context.get("ability_def") as AbilityDefinition
	if def == null:
		return PLAYER_COMBAT.RANGED_ATTACK_RANGE
	match def.range_mode:
		"melee":
			return PLAYER_COMBAT.MELEE_ATTACK_RANGE
		"self":
			return PLAYER_COMBAT.MELEE_ATTACK_RANGE
		_:
			return PLAYER_COMBAT.RANGED_ATTACK_RANGE

func _is_hostile_target(caster: Node, target: Node) -> bool:
	if caster == null or target == null:
		return false
	var caster_faction := ""
	if caster.has_method("get_faction_id"):
		caster_faction = String(caster.call("get_faction_id"))
	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	return FactionRules.relation(caster_faction, target_faction) == FactionRules.Relation.HOSTILE

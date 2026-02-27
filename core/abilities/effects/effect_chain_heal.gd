extends AbilityEffect
class_name EffectChainHeal

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")
const PLAYER_COMBAT := preload("res://game/characters/player/components/player_combat.gd")

@export var scaling_mode: String = "spell_power_flat" # flat | spell_power_flat
@export var jump_count: int = 2 # number of additional jumps after primary target
@export var jump_heal_decay_pct: float = 30.0 # each next jump heals this percent less than previous
@export var jump_radius_factor: float = 0.5 # jump radius = cast_range * factor

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	if not (target is Node2D):
		return
	if caster.get_tree() == null:
		return
	if not _is_valid_heal_target(caster, target):
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base_heal: int = _compute_base_heal(rank_data, snap)
	if base_heal <= 0:
		return

	var remaining_jumps: int = max(0, int(rank_data.flags.get("jump_count", jump_count)))
	var decay_pct: float = float(rank_data.flags.get("jump_heal_decay_pct", jump_heal_decay_pct))
	var decay_mult: float = clamp(1.0 - decay_pct / 100.0, 0.0, 1.0)
	var radius_factor: float = float(rank_data.flags.get("jump_radius_factor", jump_radius_factor))
	if radius_factor <= 0.0:
		radius_factor = 0.5
	var jump_radius: float = _get_cast_range(context) * radius_factor

	var healed_targets: Array[Node2D] = []
	var current_target: Node2D = target as Node2D
	var jump_index: int = 0

	while current_target != null and is_instance_valid(current_target):
		healed_targets.append(current_target)
		_apply_single_heal(caster, current_target, base_heal, decay_mult, jump_index, snap)
		if remaining_jumps <= 0:
			break
		var next_target := _find_next_target(caster, current_target, healed_targets, jump_radius)
		if next_target == null:
			break
		current_target = next_target
		jump_index += 1
		remaining_jumps -= 1

func _compute_base_heal(rank_data: RankData, snap: Dictionary) -> int:
	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	match scaling_mode:
		"flat":
			return int(rank_data.value_flat)
		"spell_power_flat":
			return int(rank_data.value_flat) + int(round(spell_power))
		_:
			return int(rank_data.value_flat)

func _apply_single_heal(caster: Node, target: Node2D, base_heal: int, decay_mult: float, jump_index: int, snap: Dictionary) -> void:
	var scaled: int = int(round(float(base_heal) * pow(decay_mult, float(jump_index))))
	if scaled <= 0:
		return
	var final_heal: int = STAT_CALC.apply_crit_to_heal(scaled, snap)
	_apply_heal_to_target(caster, target, final_heal)

func _apply_heal_to_target(source: Node, target: Node, heal_amount: int) -> void:
	if target == null or heal_amount <= 0:
		return
	if "current_hp" in target and "max_hp" in target:
		var before: int = int(target.current_hp)
		target.current_hp = min(target.max_hp, target.current_hp + heal_amount)
		var actual_heal: int = max(0, int(target.current_hp) - before)
		if actual_heal > 0:
			DAMAGE_HELPER.show_heal(target, actual_heal, source)
		return
	if "c_stats" in target and target.c_stats != null:
		var stats = target.c_stats
		if "current_hp" in stats and "max_hp" in stats:
			var before2: int = int(stats.current_hp)
			stats.current_hp = min(stats.max_hp, stats.current_hp + heal_amount)
			var actual_heal2: int = max(0, int(stats.current_hp) - before2)
			if actual_heal2 > 0:
				DAMAGE_HELPER.show_heal(target, actual_heal2, source)
			if target.has_method("_update_hp"):
				target.call("_update_hp")
			elif "hp_fill" in target and target.hp_fill != null and stats.has_method("update_hp_bar"):
				stats.update_hp_bar(target.hp_fill)

func _find_next_target(caster: Node, from_target: Node2D, healed_targets: Array[Node2D], jump_radius: float) -> Node2D:
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
		if healed_targets.has(candidate):
			continue
		if not _is_valid_heal_target(caster, candidate):
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

func _is_valid_heal_target(caster: Node, target: Node) -> bool:
	if caster == null or target == null:
		return false
	if target is Corpse:
		return false
	if "is_dead" in target and bool(target.is_dead):
		return false
	if "current_hp" in target and int(target.current_hp) <= 0:
		return false
	var caster_faction := ""
	if caster.has_method("get_faction_id"):
		caster_faction = String(caster.call("get_faction_id"))
	var target_faction := ""
	if target.has_method("get_faction_id"):
		target_faction = String(target.call("get_faction_id"))
	return FactionRules.relation(caster_faction, target_faction) != FactionRules.Relation.HOSTILE

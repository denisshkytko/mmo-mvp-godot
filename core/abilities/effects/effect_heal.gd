extends AbilityEffect
class_name EffectHeal

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return
	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	var raw: int = int(rank_data.value_flat) + int(round(spell_power))
	if raw <= 0:
		return
	var final: int = STAT_CALC.apply_crit_to_heal(raw, snap)
	_apply_heal_to_target(target, final)

func _apply_heal_to_target(target: Node, heal_amount: int) -> void:
	if target == null or heal_amount <= 0:
		return
	if "current_hp" in target and "max_hp" in target:
		var before: int = int(target.current_hp)
		target.current_hp = min(target.max_hp, target.current_hp + heal_amount)
		var actual_heal: int = max(0, int(target.current_hp) - before)
		if actual_heal > 0:
			DAMAGE_HELPER.show_heal(target, actual_heal)
		return
	if "c_stats" in target and target.c_stats != null:
		var stats = target.c_stats
		if "current_hp" in stats and "max_hp" in stats:
			var before2: int = int(stats.current_hp)
			stats.current_hp = min(stats.max_hp, stats.current_hp + heal_amount)
			var actual_heal2: int = max(0, int(stats.current_hp) - before2)
			if actual_heal2 > 0:
				DAMAGE_HELPER.show_heal(target, actual_heal2)
			if target.has_method("_update_hp"):
				target.call("_update_hp")
			elif "hp_fill" in target and target.hp_fill != null and stats.has_method("update_hp_bar"):
				stats.update_hp_bar(target.hp_fill)

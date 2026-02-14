extends AbilityEffect
class_name EffectDamage

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var school: String = "magic" # physical | magic
@export var scaling_mode: String = "spell_power_flat" # flat | phys_base_pct | spell_power_flat

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var derived: Dictionary = snap.get("derived", {}) as Dictionary
	var spell_power: float = float(derived.get("spell_power", 0.0))
	var base: int = 0

	match scaling_mode:
		"flat":
			base = int(rank_data.value_flat)
		"phys_base_pct":
			var base_phys: int = 0
			if "c_combat" in caster and caster.c_combat != null:
				base_phys = caster.c_combat.get_attack_damage()
			base = int(round(float(base_phys) * float(rank_data.value_pct) / 100.0))
		"spell_power_flat":
			base = int(rank_data.value_flat) + int(round(spell_power))
		_:
			base = int(rank_data.value_flat)

	if base <= 0:
		return

	var final: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	DAMAGE_HELPER.apply_damage_typed(caster, target, final, school)

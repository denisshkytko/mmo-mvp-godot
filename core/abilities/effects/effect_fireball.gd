extends AbilityEffect
class_name EffectFireball

const STAT_CALC := preload("res://core/stats/stat_calculator.gd")
const DAMAGE_HELPER := preload("res://game/characters/shared/damage_helper.gd")

@export var school: String = "magic"
@export var scaling_mode: String = "spell_power_flat"
@export var burn_tick_interval_sec: float = 1.0
@export var burn_debuff_suffix: String = "burn"

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if caster == null or target == null or rank_data == null:
		return

	var snap: Dictionary = context.get("caster_snapshot", {}) as Dictionary
	if snap.is_empty() and caster.has_method("get_stats_snapshot"):
		snap = caster.call("get_stats_snapshot") as Dictionary

	var base: int = _compute_base_damage(caster, rank_data, snap)
	if base <= 0:
		return

	var final: int = STAT_CALC.apply_crit_to_damage_typed(base, snap, school)
	var dealt: int = DAMAGE_HELPER.apply_damage_typed_with_result(caster, target, final, school)
	if dealt <= 0:
		return

	var burn_total: int = int(round(float(dealt) * float(rank_data.value_pct) / 100.0))
	if burn_total <= 0:
		return

	var ability_id: String = String(context.get("ability_id", ""))
	var duration_sec: float = max(0.01, float(rank_data.duration_sec))
	var entry_id: String = "debuff:%s:%s" % [ability_id, burn_debuff_suffix] if ability_id != "" else "debuff:%s" % burn_debuff_suffix
	var data := {
		"ability_id": ability_id,
		"source": "debuff",
		"is_debuff": true,
		"duration_sec": duration_sec,
		"caster_ref": caster,
		"flags": {
			"dot_total_damage_flat": burn_total,
			"dot_damage_school": school,
			"dot_tick_interval_sec": burn_tick_interval_sec,
		},
	}
	_apply_debuff_to_target(target, entry_id, duration_sec, data)


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
		"attack_power_pct":
			return int(round(attack_power * float(rank_data.value_pct) / 100.0))
		_:
			return int(rank_data.value_flat) + int(round(spell_power))


func _apply_debuff_to_target(target: Node, entry_id: String, duration_sec: float, data: Dictionary) -> void:
	if target == null:
		return
	if target.has_method("add_or_refresh_buff"):
		target.call("add_or_refresh_buff", entry_id, duration_sec, data)
		return
	if "c_buffs" in target and target.c_buffs != null:
		target.c_buffs.add_or_refresh_buff(entry_id, duration_sec, data)
		return
	if "c_stats" in target and target.c_stats != null and target.c_stats.has_method("add_or_refresh_buff"):
		target.c_stats.call("add_or_refresh_buff", entry_id, duration_sec, data)

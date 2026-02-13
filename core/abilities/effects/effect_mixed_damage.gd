extends AbilityEffect
class_name EffectMixedDamage

@export var physical_effect: AbilityEffect
@export var magic_effect: AbilityEffect

func apply(caster: Node, target: Node, rank_data: RankData, context: Dictionary) -> void:
	if rank_data == null:
		return
	if physical_effect != null:
		var rank_phys := RankData.new()
		rank_phys.value_pct = rank_data.value_pct
		rank_phys.value_flat = 0
		physical_effect.apply(caster, target, rank_phys, context)
	if magic_effect != null:
		var rank_magic := RankData.new()
		rank_magic.value_flat = rank_data.value_flat_2
		rank_magic.value_pct = 0.0
		magic_effect.apply(caster, target, rank_magic, context)
